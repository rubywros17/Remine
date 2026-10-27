import 'dart:async';
import 'dart:typed_data';

import '../../models/category.dart';
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
/// 흐름: 갤러리(최신 [DeviceCaptureService.maxPhotos]장) → 이미 보낸 것 제외(증분) → `maxBatchSize`장씩
/// OCR·판정 → [planFor]가 정한 것만 전송 → 배치가 끝날 때마다 [onBatchDone](홈 갱신).
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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
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

  /// 앱이 한 번에 보내는 장수. 서버 상한(`maxBatchSize`, 20)보다 작게 잡아 묶음마다 숫자가 자주 오르게 한다.
  /// 서버 상한이 이보다 작으면 서버 상한을 따른다.
  final int batchSize;
  static const defaultBatchSize = 5;

  /// 배치 하나가 끝날 때마다(홈이 새로 불러오게).
  void Function()? onBatchDone;

  /// FCM 토큰을 주는 곳. 없으면(Firebase 초기화 실패 등) 토큰 없이 등록한다.
  final PushClient? push;

  /// 디버그 빌드에서만(main.dart). 동기화가 멈춘 이유를 예외 **종류**로만 남긴다(메시지에 OCR이 섞일 수 있어 안 찍음).
  final void Function(String line)? log;
  final DateTime Function() _now;

  Future<void>? _inFlight;
  StreamSubscription<String>? _tokenSub;
  bool _again = false; // 재등록으로 전송 기록을 비웠다 → 이번 실행 뒤 한 번 더
  Future<int>? _reregistering;

  /// 동기화를 시작한다. 이미 돌고 있으면 새로 시작하지 않고 진행 중인 것을 기다린다.
  Future<void> run() =>
      _inFlight ??= _runUntilSettled().whenComplete(() => _inFlight = null);

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
      return id;
    }().whenComplete(() => _reregistering = null));
    if (_inFlight != null) {
      _again = true;
    } else {
      unawaited(run());
    }
    return id;
  }

  bool get isRunning => _inFlight != null;

  Future<void> _run() async {
    var failed = 0;
    try {
      final (:all, :mine, :own, :ownBy) = await _photos();
      final config = await api.config();
      final deviceId = await _ensureDevice();
      await _forgetOwn(deviceId, own);
      final waiting = <GalleryPhoto>[];
      for (final photo in mine) {
        final e = await state.entry(photo.id);
        final upToDate =
            e != null &&
            e.status == SyncStatusCode.synced &&
            e.modifiedAt == photo.modifiedAt;
        if (!upToDate) waiting.add(photo);
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
      status.begin(pending.length, intervalMs: config.classifyIntervalMs);
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
      failed = await state.failedCount();
      status.finish(
        issue: failed > 0 ? SyncIssue.partial : SyncIssue.none,
        failedCount: failed,
      );
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

  Future<int> _safeFailedCount() async {
    try {
      return await state.failedCount();
    } catch (_) {
      return 0;
    }
  }

  /// 갤러리 최신 [DeviceCaptureService.maxPhotos]장을 (분류할 것, 자기 캡처)로 나눈다. [all]은 읽은 장수.
  Future<
    ({
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
        all: 0,
        mine: <GalleryPhoto>[],
        own: <GalleryPhoto>[],
        ownBy: <OwnReason, int>{for (final r in OwnReason.values) r: 0},
      );
    }
    final (:mine, :own, :ownBy) = await capture.recentSplit(shots.first.id);
    return (all: mine.length + own.length, mine: mine, own: own, ownBy: ownBy);
  }

  /// 예전에 보냈던 캡처가 지금 보니 Remine 자기 캡처면(판정 규칙이 생기기 전에 보낸 것) 서버에서 지운다.
  /// 지운 뒤 전송 기록을 없애서 다음 실행에는 다시 보내지 않는다. 실패하면 다음 실행에서 다시(분석은 계속).
  Future<void> _forgetOwn(int deviceId, List<GalleryPhoto> own) async {
    final sent = [
      for (final p in own)
        if (await state.entry(p.id) != null) p.id,
    ];
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

  static const _forgetChunk = 500; // 서버 forget 상한

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

  Future<({int deviceId, int failed})> _batch(
    List<GalleryPhoto> chunk,
    ApiConfig config,
    int deviceId,
    _Tally tally,
  ) async {
    await capture.run(chunk); // OCR·판정(이미 한 것은 건너뛴다). 실패한 장은 기록이 없어 아래에서 걸러진다.
    final consent = await settings.imageConsent() == true;
    final photoById = {for (final p in chunk) p.id: p};
    final send = <String, _Outgoing>{};
    var failed = 0;

    for (final photo in chunk) {
      final verdict = await capture.verdicts.find(photo.id);
      final record = await capture.store.find(photo.id);
      if (verdict?.route == LocalRoute.deviceOnly) tally.deviceOnly++;
      if (verdict?.route == LocalRoute.deviceOnly &&
          verdict!.category != null) {
        status.count(
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
          await _classifyOnDevice(photo, Category.etc);
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
            await _classifyOnDevice(photo, Category.etc);
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
        status.setWaiting(send.length); // 화면이 "분류하는 중"을 보여 준다
        result = await api.analyze(currentDevice, [
          for (final o in send.values) o.toItem(),
        ]);
        status.setWaiting(0);
      } finally {
        status.setWaiting(0);
      }

      for (final a in result.analyzed) {
        final photo = photoById[a.assetId];
        if (photo == null || !send.containsKey(a.assetId)) continue;
        await state.putEntry(_entry(photo, SyncStatusCode.synced));
        tally.sent++;
        status.count(a.category, assetId: a.assetId);
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
              await _dropImage(photo, out, send);
            }
          case FailReason.imageInvalid:
            await _dropImage(photo, out, send); // 같은 이미지를 다시 보내지 않는다
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
    return (deviceId: currentDevice, failed: failed);
  }

  /// 이미지를 빼고 텍스트만으로 다시 보낸다(텍스트가 없으면 기기에서 ETC).
  Future<void> _dropImage(
    GalleryPhoto photo,
    _Outgoing out,
    Map<String, _Outgoing> send,
  ) async {
    if (out.entry.text.trim().isEmpty) {
      send.remove(photo.id);
      await _classifyOnDevice(
        photo,
        Category.etc,
      ); // ponytail: 사유 로그에서는 세지 않는다(드묾)
    } else {
      send[photo.id] = _Outgoing(out.entry);
    }
  }

  Future<void> _classifyOnDevice(GalleryPhoto photo, Category category) async {
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
    status.count(category, assetId: photo.id);
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
