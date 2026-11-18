import 'dart:async';
import 'dart:typed_data';

import '../../models/category.dart';
import '../device/trash_store.dart';
import '../device/device_capture_service.dart';
import '../device/gallery_reader.dart';
import '../device/own_capture.dart';
import '../device/privacy/local_verdict_store.dart';
import '../device/privacy/privacy_filter.dart';
import '../device/settings_store.dart';
import 'api_client.dart';
import 'image_prep.dart';
import 'push.dart';
import 'remote_state_store.dart';
import 'sync_plan.dart';
import 'sync_status.dart';

/// 기기 판정을 통과한 캡처만 서버 analyze로 보내고, 결과를 로컬 상태에 반영한다.
///
/// 흐름: 갤러리(최신 [DeviceCaptureService.maxPhotos]장 + 기기 등록 뒤에 생긴 것 전부) → 이미 보낸 것 제외(증분) →
/// `maxBatchSize`장씩 OCR·판정 → [planFor]가 정한 것만 전송 → 배치가 끝날 때마다 [onBatchDone](홈 갱신).
/// 그다음 같은 실행 안에서 2단계로 예전 스크린샷을 오늘 남은 몫만큼 이어서 보낸다([_older]).
/// 동기화는 한 번에 하나만 돈다([run]을 겹쳐 부르면 진행 중인 실행을 그대로 돌려준다).
/// 서버가 기기를 잊으면(DB 초기화) [RemineApi]가 [_recoverDevice]를 불러 재등록하고, 전송 기록을 비운 뒤
/// 이번 실행이 끝나면 한 번 더 돌아 전체를 다시 보낸다.
///
/// 개인정보: 예외는 [SyncIssue]로만 바뀌어 화면에 나가고 내용은 버린다(디버그 [log]에는 종류만).
class SyncService {
  SyncService({
    required this.api,
    required this.reader,
    required this.capture,
    required this.settings,
    required this.state,
    required this.images,
    required this.status,
    this.photoLimit = 0,
    this.batchSize = defaultBatchSize,
    this.onBatchDone,
    this.push,
    this.log,
    this.autoSync = true,
    this.trash,
    this.olderRange = '',
    Future<bool> Function()? isWifi,
    Future<bool> Function()? isCharging,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _isWifi = isWifi ?? _yes,
       _isCharging = isCharging ?? _yes {
    api.recoverDevice = _recoverDevice;
  }

  final RemineApi api;
  final GalleryReader reader;
  final DeviceCaptureService capture;
  final SettingsStore settings;
  final RemoteStateStore state;
  final ImagePreparer images;
  final SyncStatus status;

  /// 디버그용 장수 제한(`--dart-define=SYNC_LIMIT=15`). 0이면 제한 없음. 실기기 첫 확인을 소량으로 하려는 용도다.
  final int photoLimit;

  /// 앱이 한 번에 보내는 장수. 기본은 서버 상한(`maxBatchSize`, 20)과 같다: 서버가 요청 안의 캡처를
  /// 여러 장씩 한 LLM 호출로 묶으므로(텍스트 10·이미지 5장) 많이 담을수록 호출이 준다(20장 ≈ 6호출, 2분 타임아웃 안쪽).
  /// 서버 상한이 이보다 작으면 서버 상한을 따른다. 디버그에서는 `--dart-define=SYNC_BATCH_SIZE`로 바꿀 수 있다.
  final int batchSize;
  static const defaultBatchSize = 20;

  /// 배치 하나가 끝날 때마다(홈이 새로 불러오게).
  void Function()? onBatchDone;

  /// FCM 토큰을 주는 곳. 없으면(Firebase 초기화 실패 등) 토큰 없이 등록한다.
  final PushClient? push;

  /// 디버그 빌드에서만(main.dart). 동기화가 멈춘 이유를 예외 **종류**로만 남긴다(메시지에 OCR이 섞일 수 있어 안 찍음).
  final void Function(String line)? log;
  final DateTime Function() _now;

  /// 앱이 열리거나 앞으로 올 때·재등록 뒤에 저절로 동기화할지. 디버그의 `--dart-define=AUTO_SYNC=false`만 끈다
  /// (main.dart, 릴리스는 항상 켜짐). 꺼져도 서버 조회·토큰·기기 재등록은 그대로이고 [run]으로 수동 실행한다.
  final bool autoSync;

  /// 앱 휴지통. 서버에 아직 못 알린 일을 [flushTrash]가 보낸다.
  final TrashStore? trash;

  /// 디버그 전용 예전 스크린샷 범위(`--dart-define=OLDER_RANGE=1y`, [olderRangeFromDefine]). 범위를 아직 안 골랐을 때만 쓴다.
  /// 비어 있으면(릴리스·기본) 범위를 고르기 전까지 예전 스크린샷을 읽지 않는다.
  final String olderRange;

  /// Wi-Fi 연결·충전 중인지(예전 스크린샷 조건). 크롬·테스트는 늘 true.
  final Future<bool> Function() _isWifi;
  final Future<bool> Function() _isCharging;
  static Future<bool> _yes() async => true;

  Future<void>? _inFlight;
  StreamSubscription<String>? _tokenSub;
  bool _again = false; // 재등록으로 전송 기록을 비웠다 → 이번 실행 뒤 한 번 더
  Future<int>? _reregistering;

  /// 동기화를 시작한다. 이미 돌고 있으면 새로 시작하지 않고 진행 중인 것을 기다린다.
  Future<void> run() =>
      _inFlight ??= _runUntilSettled().whenComplete(() => _inFlight = null);

  /// 저절로 도는 자리(앱 시작·복귀)에서 부른다. [autoSync]가 꺼져 있으면 아무것도 하지 않는다.
  Future<void> runAuto() => autoSync ? run() : Future.value();

  Future<void> _runUntilSettled() async {
    // ponytail: 재등록이 연달아 나도 최대 3번까지만 돈다(서버가 계속 기기를 잊는 경우의 무한 반복 방지).
    for (var i = 0; i < 3; i++) {
      _again = false;
      await _run();
      if (!_again) return;
    }
  }

  /// 서버가 이 기기를 모를 때 [RemineApi]가 부른다(동시 요청이 여럿이어도 한 번).
  /// 새로 등록하고, 서버에 있다고 믿던 전송 기록을 버린 뒤 전체 재전송을 예약한다.
  Future<int> _recoverDevice() async {
    log?.call('[sync] 서버가 기기를 모름 → 재등록');
    final id = await (_reregistering = () async {
      final id = await api.registerDevice(await _tokenForRegister());
      await state.clear();
      await state.setDeviceId(id);
      await settings.setOlderCursor(null); // 전송 기록을 비웠으니 예전 스크린샷도 처음부터 다시 본다
      await trash?.resendAll(); // 새 기기에는 휴지통 표시가 없다. 이번 실행의 재전송 뒤에 다시 알린다
      return id;
    }().whenComplete(() => _reregistering = null));
    if (_inFlight != null) {
      _again = true; // 돌고 있던 실행(수동이어도)이 끝나면 한 번 더
    } else if (autoSync) {
      unawaited(run());
    }
    return id;
  }

  bool get isRunning => _inFlight != null;

  Future<void> _run() async {
    var failed = 0;
    try {
      final (:albumId, :all, :mine, :own, :ownBy) = await _photos();
      final config = await api.config();
      final deviceId = await _ensureDevice();
      // 이 시각 뒤에 찍은 캡처는 다음부터 300장을 넘어도 모두 읽는다(이미 등록된 기기는 이 버전의 첫 동기화 시각).
      if (await state.registeredAt() == null) {
        await state.setRegisteredAt(_now());
      }
      await _forgetOwn(deviceId, own);
      await flushTrash(); // 지난번에 못 알린 휴지통
      final waiting = <GalleryPhoto>[];
      for (final photo in mine) {
        if (!await _upToDate(photo)) waiting.add(photo);
      }
      // SYNC_LIMIT는 실제로 보낼 후보(자기 캡처·이미 보낸 것을 뺀 나머지)의 최신 N장에 건다.
      final pending = photoLimit > 0
          ? waiting.take(photoLimit).toList()
          : waiting;
      log?.call(
        '[sync] 대상 갤러리 $all → 자기 캡처 ${own.length}'
        '(이름 ${ownBy[OwnReason.name]} · 앞에 있던 구간 ${ownBy[OwnReason.interval]} · '
        '1회 정리 기간 ${ownBy[OwnReason.backfill]}) → 이미 보냄 ${mine.length - waiting.length}'
        ' → 보낼 후보 ${waiting.length} → SYNC_LIMIT 후 ${pending.length}',
      );
      final tally = _Tally();
      status.begin(pending.length);
      var deviceIdNow = deviceId;
      final size = batchSize < config.maxBatchSize
          ? batchSize
          : config.maxBatchSize;
      for (var i = 0; i < pending.length; i += size) {
        final chunk = pending.sublist(i, (i + size).clamp(0, pending.length));
        final r = await _batch(chunk, config, deviceIdNow, tally);
        deviceIdNow = r.deviceId;
        failed += r.failed;
        status.advance(chunk.length);
        onBatchDone?.call();
      }
      log?.call(
        '[sync] 결과 보냄 ${tally.sent} · 기기에서 끝남(앱·민감) ${tally.deviceOnly}'
        ' · 글자 없음 ETC ${tally.noTextEtc} · 건너뜀(판정 없음 등) ${tally.skipped} · 실패 $failed',
      );
      await state.setFirstSyncDone();
      await flushTrash(); // 재등록으로 다시 보낸 캡처까지 표시되도록 끝에서 한 번 더
      failed = await state.failedCount();
      status.finish(
        issue: failed > 0 ? SyncIssue.partial : SyncIssue.none,
        failedCount: failed,
      );
      if (albumId != null) await _olderQuietly(albumId, config);
    } on ApiException catch (e) {
      log?.call('[sync] 중단: $e'); // ApiException(실패 종류, 상태 코드)뿐
      status.finish(
        issue: SyncIssue.of(e.failure),
        failedCount: await _safeFailedCount(),
      );
    } catch (e) {
      // 어떤 예외든 앱이 죽지 않게 한다. 서버 문제가 아니라 앱 안의 오류로 따로 분류한다.
      // 내용(OCR 원문이 섞일 수 있음)은 남기지 않고 종류만.
      log?.call('[sync] 중단: ${e.runtimeType}');
      status.finish(
        issue: SyncIssue.internal,
        failedCount: await _safeFailedCount(),
      );
    }
    onBatchDone?.call();
  }

  /// 이미 보냈거나 기기에서 끝난 캡처인지(바뀌면 다시 판정). 실패 기록은 다시 보낸다.
  Future<bool> _upToDate(GalleryPhoto photo) async {
    final e = await state.entry(photo.id);
    return e != null &&
        e.status != SyncStatusCode.failed &&
        e.modifiedAt == photo.modifiedAt;
  }

  /// [_older]의 실패는 이번 동기화 결과(이미 끝남)를 바꾸지 않는다. 다음 실행에 같은 자리부터 다시.
  Future<void> _olderQuietly(String albumId, ApiConfig config) async {
    try {
      await _older(albumId, config);
    } on ApiException catch (e) {
      log?.call('[older] 중단: $e');
    } catch (e) {
      log?.call('[older] 중단: ${e.runtimeType}'); // 내용은 남기지 않는다
    }
  }

  /// 예전 스크린샷(최신 300장보다 오래된 것)을 오늘 남은 몫만큼 최신 → 오래된 순으로 이어서 보낸다.
  ///
  /// 범위를 고르지 않았거나(기본) 꺼져 있거나 Wi-Fi·충전 조건이 안 맞으면 읽지 않는다. 남은 몫은 서버 값이 기준이다
  /// ([ApiConfig.olderRemainingToday], 분석 응답마다 갱신). 커서([SettingsStore.olderCursor])는 서버가 처리한 장과
  /// 제외된 장(자기 캡처·기기에서 끝난 민감·글자 없음)까지만 앞으로 간다. 한도에 걸리거나 실패한 장에서 멈추고,
  /// 다음 날 그 장부터 다시 본다(그 뒤에 이미 보낸 장은 기록이 있어 건너뛴다).
  Future<void> _older(String albumId, ApiConfig config) async {
    final range = olderRangeStart(
      await settings.olderRangeFrom() ??
          olderRangeFromDefine(olderRange, _now()),
    );
    if (!range.enabled || !await settings.olderEnabled()) return;
    if (await settings.olderWifiOnly() && !await _isWifi()) {
      log?.call('[older] Wi-Fi 아님 → 건너뜀');
      return;
    }
    if (await settings.olderChargingOnly() && !await _isCharging()) {
      log?.call('[older] 충전 중 아님 → 건너뜀');
      return;
    }
    final from = range.from;
    var cursor = PhotoPosition.decode(await settings.olderCursor());
    if (cursor != null && from != null && cursor.time.isBefore(from)) {
      return; // 범위를 줄여 시작보다 오래된 곳까지 이미 봤다 → 완료
    }
    final quota = await api.config(deviceId: await _ensureDevice());
    var left = quota.olderRemainingToday ?? 0;
    await settings.setOlderQuota(left, quota.olderResetsAt);
    if (left <= 0) return;

    final rule = await capture.ownRule();
    final size = batchSize < config.maxBatchSize
        ? batchSize
        : config.maxBatchSize;
    final tally = _Tally();
    var readFrom = cursor;
    var blocked = false; // 커서는 처리하지 못한 첫 장 앞에서 멈춘다
    var read = 0;
    while (left > 0) {
      final page = await reader.olderThan(
        albumId,
        readFrom,
        notBefore: from,
        limit: size,
      );
      if (page.isEmpty) break;
      read += page.length;
      final (:mine, :own, ownBy: _) = capture.split(page, rule);
      final waiting = <GalleryPhoto>[];
      for (final p in mine) {
        if (!await _upToDate(p)) waiting.add(p);
      }
      final chunk = waiting.take(left).toList();
      var limitHit = false;
      if (chunk.isNotEmpty) {
        final sentBefore = tally.sent;
        final r = await _batch(
          chunk,
          config,
          await _ensureDevice(),
          tally,
          quiet: true,
        );
        limitHit = r.limitHit;
        left = r.olderRemaining ?? left - (tally.sent - sentBefore);
        onBatchDone?.call();
      }
      final ownIds = {for (final p in own) p.id};
      for (final p in page) {
        if (blocked) break;
        if (ownIds.contains(p.id) || await _upToDate(p)) {
          cursor = p.position;
        } else {
          blocked = true;
        }
      }
      if (cursor != null) await settings.setOlderCursor(cursor.encode());
      if (limitHit) left = 0;
      if (page.length < size || chunk.length < waiting.length) break;
      readFrom = page.last.position;
    }
    await settings.setOlderQuota(left < 0 ? 0 : left, quota.olderResetsAt);
    log?.call(
      '[older] 읽음 $read · 보냄 ${tally.sent}'
      ' · 기기에서 끝남 ${tally.deviceOnly + tally.noTextEtc} · 오늘 남은 몫 $left',
    );
  }

  Future<int> _safeFailedCount() async {
    try {
      return await state.failedCount();
    } catch (_) {
      return 0;
    }
  }

  /// 갤러리 최신 [DeviceCaptureService.maxPhotos]장 + 기기 등록 뒤에 생긴 것을 (분류할 것, 자기 캡처)로 나눈다.
  /// [all]은 읽은 장수, [albumId]는 Screenshots 앨범(없으면 null).
  Future<
    ({
      String? albumId,
      int all,
      List<GalleryPhoto> mine,
      List<GalleryPhoto> own,
      Map<OwnReason, int> ownBy,
    })
  >
  _photos() async {
    final albums = await reader.albums();
    final shots = albums.where((a) => a.isScreenshots).toList();
    if (shots.isEmpty) {
      return (
        albumId: null,
        all: 0,
        mine: <GalleryPhoto>[],
        own: <GalleryPhoto>[],
        ownBy: <OwnReason, int>{for (final r in OwnReason.values) r: 0},
      );
    }
    final albumId = shots.first.id;
    final (:mine, :own, :ownBy) = await capture.recentSplit(
      albumId,
      since: await state.registeredAt(),
    );
    return (
      albumId: albumId,
      all: mine.length + own.length,
      mine: mine,
      own: own,
      ownBy: ownBy,
    );
  }

  /// 예전에 보냈던 캡처가 지금 보니 Remine 자기 캡처면(판정 규칙이 생기기 전에 보낸 것) 서버에서 지운다.
  /// 지운 뒤 전송 기록을 없애서 다음 실행에는 다시 보내지 않는다. 실패하면 다음 실행에서 다시(분석은 계속).
  Future<void> _forgetOwn(int deviceId, List<GalleryPhoto> own) async {
    // 서버에 보낸 적 있는 것만. 기기에서 끝난 캡처(deviceOnly)의 id는 서버에 알리지 않는다.
    final sent = <String>[];
    for (final p in own) {
      final e = await state.entry(p.id);
      if (e != null && e.status != SyncStatusCode.deviceOnly) sent.add(p.id);
    }
    if (sent.isEmpty) return;
    try {
      for (var i = 0; i < sent.length; i += _forgetChunk) {
        final ids = sent.sublist(i, (i + _forgetChunk).clamp(0, sent.length));
        await api.forget(deviceId, ids);
        await state.removeEntries(ids);
      }
      log?.call('[sync] 자기 캡처 ${sent.length}장 서버에서 지움');
    } on ApiException catch (e) {
      log?.call('[sync] 자기 캡처 지우기 실패: $e');
    }
  }

  static const _forgetChunk = 500; // 서버 forget·trash·restore 상한

  Future<void>? _flushing;
  bool _flushAgain = false;

  /// 휴지통 대기열을 서버에 보낸다. 실패는 삼킨다(대기열에 남아 다음 동기화 때 다시). 겹쳐 돌지 않고, 도는 중에 또 불리면 끝나고 한 번 더.
  Future<void> flushTrash() {
    if (_flushing != null) {
      _flushAgain = true;
      return _flushing!;
    }
    return _flushing = _flushLoop().whenComplete(() => _flushing = null);
  }

  Future<void> _flushLoop() async {
    final store = trash;
    if (store == null) return;
    do {
      _flushAgain = false;
      try {
        final id = await state.deviceId();
        if (id == null) return; // 등록 전: 서버에 그 캡처가 아직 없다
        final o = await store.outbox();
        await _sendTrash(o.trash, (ids) => api.trash(id, ids), store.trashSent);
        await _sendTrash(
          o.restore,
          (ids) => api.restore(id, ids),
          store.restoreSent,
        );
        await _sendTrash(
          o.forget,
          (ids) => api.forget(id, ids),
          store.forgetSent,
        );
      } on ApiException catch (e) {
        log?.call('[sync] 휴지통 반영 실패: $e');
        return;
      } catch (e) {
        log?.call('[sync] 휴지통 반영 실패: ${e.runtimeType}'); // 내용은 남기지 않는다
        return;
      }
    } while (_flushAgain);
  }

  Future<void> _sendTrash(
    List<String> ids,
    Future<void> Function(List<String> ids) send,
    Future<void> Function(List<String> ids) done,
  ) async {
    for (var i = 0; i < ids.length; i += _forgetChunk) {
      final part = ids.sublist(i, (i + _forgetChunk).clamp(0, ids.length));
      await send(part);
      await done(part);
    }
  }

  /// 앱 시작 때 한 번 서버의 토큰을 알림 설정에 맞춘다. **서버에 토큰이 있는 건 알림을 켰을 때뿐이다.**
  /// 켜짐 → 지금 토큰을 올리고 FCM이 바꿀 때마다 다시 올림 / 꺼짐 → 지움(지난번 실패분도 여기서 다시) /
  /// 아직 안 고름 → 그대로. 아직 등록 전이면 건너뛴다(등록 요청이 켜짐일 때만 토큰을 싣는다). 실패는 무시한다.
  Future<void> startTokenSync() async {
    final p = push;
    if (p == null) return;
    _tokenSub ??= p.tokenRefresh.listen((t) async {
      if (await settings.notificationsEnabled() == true) await _uploadToken(t);
    });
    await _applyToServer(await settings.notificationsEnabled());
  }

  /// 설정·첫 안내 화면에서 고른 값을 저장하고 서버 토큰을 맞춘다(켜면 올림, 끄면 지움).
  Future<void> setNotifications(bool on) async {
    await settings.setNotificationsEnabled(on);
    await _applyToServer(on);
  }

  Future<void> _applyToServer(bool? on) async {
    if (on == true) {
      await _uploadToken(await push?.token());
    } else if (on == false) {
      await _quietly((id) => api.deleteFcmToken(id));
    }
  }

  Future<void> _uploadToken(String? token) async {
    if (token != null) await _quietly((id) => api.updateFcmToken(id, token));
  }

  /// 등록된 기기에만 부르고 실패는 삼킨다. 서버에 닿지 못했거나 기기를 모름(404)
  /// → 다음 시작의 [startTokenSync]나 재등록이 설정에 맞게 다시 한다.
  Future<void> _quietly(Future<void> Function(int deviceId) call) async {
    try {
      final id = await state.deviceId();
      if (id != null) await call(id);
    } catch (_) {}
  }

  /// [개발용] 서버(dev 프로필)가 이 기기에 테스트 알림 1건을 바로 보내게 한다. 실패는 [ApiException].
  /// 서버가 [delaySeconds] 기다렸다 보내고 발송 결과를 돌려준다.
  Future<String> sendTestPush({int delaySeconds = 0}) async {
    final id = await state.deviceId();
    if (id == null) throw const ApiException(ApiFailure.rejected); // 아직 등록 전
    return api.sendTestPush(id, delaySeconds: delaySeconds);
  }

  /// 알림을 켰을 때만 등록 요청에 토큰을 싣는다.
  Future<String?> _tokenForRegister() async =>
      await settings.notificationsEnabled() == true
      ? await push?.token()
      : null;

  Future<int> _ensureDevice() async {
    // 재등록 중이면(기기 id를 비우고 새로 받는 사이) 따로 등록하지 않고 그 결과를 쓴다.
    final pending = _reregistering;
    if (pending != null) return pending;
    final saved = await state.deviceId();
    if (saved != null) return saved;
    final id = await api.registerDevice(await _tokenForRegister());
    await state.setDeviceId(id);
    return id;
  }

  /// [quiet]면 진행 화면([status])에 알리지 않는다(첫 분석이 끝난 뒤 조용히 도는 예전 스크린샷).
  /// [limitHit]: 서버가 예전 스크린샷 하루 한도로 돌려보낸 장이 있었다. [olderRemaining]: 마지막 응답의 남은 몫.
  Future<({int deviceId, int failed, bool limitHit, int? olderRemaining})>
  _batch(
    List<GalleryPhoto> chunk,
    ApiConfig config,
    int deviceId,
    _Tally tally, {
    bool quiet = false,
  }) async {
    await capture.run(chunk); // OCR·판정(이미 한 것은 건너뛴다). 실패한 장은 기록이 없어 아래에서 걸러진다.
    final consent = await settings.imageConsent() == true;
    final photoById = {for (final p in chunk) p.id: p};
    final send = <String, _Outgoing>{};
    var failed = 0;
    var limitHit = false;
    int? olderRemaining;
    void count(Category c, {String? assetId}) {
      if (!quiet) status.count(c, assetId: assetId);
    }

    for (final photo in chunk) {
      final verdict = await capture.verdicts.find(photo.id);
      final record = await capture.store.find(photo.id);
      if (verdict?.route == LocalRoute.deviceOnly) {
        tally.deviceOnly++;
        await state.putEntry(_entry(photo, SyncStatusCode.deviceOnly));
      }
      if (verdict?.route == LocalRoute.deviceOnly &&
          verdict!.category != null) {
        count(
          verdict.category!,
          assetId: verdict.hidden
              ? null
              : photo.id, // 숨김(민감·금융) 캡처는 화면에 올리지 않는다
        );
      }
      if (record == null && verdict?.route != LocalRoute.deviceOnly) {
        failed++; // OCR 실패 등 → 다음 실행에서 다시 시도
        await state.putEntry(_entry(photo, SyncStatusCode.failed));
        continue;
      }
      final entry = planFor(
        PlanInput(
          assetId: photo.id,
          takenAt: photo.takenAt,
          fileName: photo.fileName,
          text: record?.text ?? '',
          charCount: record?.charCount ?? 0,
          verdict: verdict,
        ),
        imageConsent: consent,
        thresholdChars: config.imageThresholdChars,
      );
      switch (entry.action) {
        case PlanAction.skip:
          if (verdict?.route != LocalRoute.deviceOnly) tally.skipped++;
        case PlanAction.deviceEtc:
          await _classifyOnDevice(photo, Category.etc, quiet: quiet);
          tally.noTextEtc++;
        case PlanAction.sendText:
          send[photo.id] = _Outgoing(entry);
        case PlanAction.sendWithImage:
          final image = await images.prepare(
            photo.id,
            maxLongSide: config.imageMaxLongSide,
            maxBytes: config.imageMaxBytes,
          );
          if (image != null) {
            send[photo.id] = _Outgoing(entry, image: image);
          } else if (entry.fallback == ImageFallback.sendText) {
            send[photo.id] = _Outgoing(entry);
          } else {
            await _classifyOnDevice(photo, Category.etc, quiet: quiet);
          }
      }
    }

    // 서버가 일부를 되돌려 보내면(이미지가 크다/잘못됐다) 고쳐서 같은 배치 안에서 최대 3번 더 보낸다.
    var round = 0;
    final currentDevice = deviceId; // 재등록되면 api가 새 id로 바꿔 보낸다
    while (send.isNotEmpty && round < 3) {
      round++;
      final AnalyzeResult result;
      try {
        // 화면이 "분류하는 중"과 이 묶음의 썸네일을 보여 준다(기기 안 표시일 뿐, 보내는 내용과 무관).
        if (!quiet) {
          status.setWaiting(send.length, assetIds: send.keys.toList());
        }
        result = await api.analyze(currentDevice, [
          for (final o in send.values) o.toItem(),
        ]);
      } finally {
        if (!quiet) status.setWaiting(0);
      }
      olderRemaining = result.olderRemainingToday ?? olderRemaining;

      for (final a in result.analyzed) {
        final photo = photoById[a.assetId];
        if (photo == null || !send.containsKey(a.assetId)) continue;
        await state.putEntry(_entry(photo, SyncStatusCode.synced));
        tally.sent++;
        count(a.category, assetId: a.assetId);
        send.remove(a.assetId);
      }
      for (final id in result.skipped) {
        final photo = photoById[id];
        if (photo == null || !send.containsKey(id)) continue;
        await state.putEntry(_entry(photo, SyncStatusCode.synced));
        tally.sent++;
        send.remove(id);
      }
      for (final f in result.failed) {
        final photo = photoById[f.assetId];
        final out = send[f.assetId];
        if (photo == null || out == null) continue;
        switch (f.reason) {
          case FailReason.imageTooLarge:
            final next = out.level + 1;
            final image = next <= ImagePreparer.lastLevel
                ? await images.prepare(
                    photo.id,
                    maxLongSide: config.imageMaxLongSide,
                    maxBytes: config.imageMaxBytes,
                    minLevel: next,
                  )
                : null;
            if (image != null) {
              send[f.assetId] = _Outgoing(out.entry, image: image, level: next);
            } else {
              await _dropImage(photo, out, send, quiet: quiet);
            }
          case FailReason.imageInvalid:
            // 같은 이미지를 다시 보내지 않는다
            await _dropImage(photo, out, send, quiet: quiet);
          case FailReason.inProgress:
          case FailReason.deadlineExceeded:
            // 서버가 아직 분석 중이거나(IN_PROGRESS) 요청 마감이 지나 손대지 않았다(DEADLINE_EXCEEDED).
            // 실패가 아니니 기록하지 않고 이번엔 빼 둔다. 기록이 없으면 다음 실행에서 다시 보낸다.
            send.remove(f.assetId);
          case FailReason.dailyLimitExceeded:
            // 예전 스크린샷 하루 한도. 서버가 손대지 않았으니 기록하지 않고(다음 날 다시) 오늘은 그만 보낸다.
            send.remove(f.assetId);
            limitHit = true;
          case FailReason.llmCallFailed:
          case FailReason.llmInvalidResponse:
          case FailReason.other:
            await state.putEntry(_entry(photo, SyncStatusCode.failed));
            send.remove(f.assetId);
            failed++;
        }
      }
    }
    // 끝까지 처리되지 않은 것은 다음 실행에서 다시 보낸다.
    for (final id in send.keys) {
      await state.putEntry(_entry(photoById[id]!, SyncStatusCode.failed));
      failed++;
    }
    return (
      deviceId: currentDevice,
      failed: failed,
      limitHit: limitHit,
      olderRemaining: olderRemaining,
    );
  }

  /// 이미지를 빼고 텍스트만으로 다시 보낸다(텍스트가 없으면 기기에서 ETC).
  Future<void> _dropImage(
    GalleryPhoto photo,
    _Outgoing out,
    Map<String, _Outgoing> send, {
    bool quiet = false,
  }) async {
    if (out.entry.text.trim().isEmpty) {
      send.remove(photo.id);
      await _classifyOnDevice(
        photo,
        Category.etc,
        quiet: quiet,
      ); // ponytail: 사유 로그에서는 세지 않는다(드묾)
    } else {
      send[photo.id] = _Outgoing(out.entry);
    }
  }

  Future<void> _classifyOnDevice(
    GalleryPhoto photo,
    Category category, {
    bool quiet = false,
  }) async {
    await capture.verdicts.save(
      StoredVerdict.of(
        LocalVerdict(
          route: LocalRoute.deviceOnly,
          category: category,
          reasons: const [ReasonCode.noText],
        ),
        assetId: photo.id,
        takenAt: photo.takenAt,
        modifiedAt: photo.modifiedAt,
        now: _now(),
      ),
    );
    await state.putEntry(_entry(photo, SyncStatusCode.deviceOnly));
    if (!quiet) status.count(category, assetId: photo.id);
  }

  SyncEntry _entry(GalleryPhoto photo, SyncStatusCode code) =>
      SyncEntry(assetId: photo.id, modifiedAt: photo.modifiedAt, status: code);
}

/// 한 번의 실행에서 캡처가 어디로 갔는지 센다(디버그 로그에 숫자만).
class _Tally {
  int sent = 0;
  int deviceOnly = 0;
  int noTextEtc = 0;
  int skipped = 0;
}

/// 보내려고 준비한 한 장. 이미지는 [level]단계로 줄인 것이다.
class _Outgoing {
  const _Outgoing(this.entry, {this.image, this.level = 0});

  final PlanEntry entry;
  final Uint8List? image;
  final int level;

  AnalyzeItem toItem() => AnalyzeItem(
    assetId: entry.assetId,
    takenAt: entry.takenAt,
    text: entry.text,
    image: image,
  );
}
