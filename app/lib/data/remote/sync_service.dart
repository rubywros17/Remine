import 'dart:async';
import 'dart:typed_data';

import '../../models/category.dart';
import '../device/device_capture_service.dart';
import '../device/gallery_reader.dart';
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
///
/// 개인정보: 로그를 남기지 않는다. 예외는 [SyncIssue]로만 바뀌어 화면에 나가고 내용은 버린다.
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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

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
  final DateTime Function() _now;

  Future<void>? _inFlight;
  StreamSubscription<String>? _tokenSub;

  /// 동기화를 시작한다. 이미 돌고 있으면 새로 시작하지 않고 진행 중인 것을 기다린다.
  Future<void> run() =>
      _inFlight ??= _run().whenComplete(() => _inFlight = null);

  bool get isRunning => _inFlight != null;

  Future<void> _run() async {
    var failed = 0;
    try {
      final photos = await _photos();
      final config = await api.config();
      final deviceId = await _ensureDevice();
      final pending = <GalleryPhoto>[];
      for (final photo in photos) {
        final e = await state.entry(photo.id);
        final upToDate =
            e != null &&
            e.status == SyncStatusCode.synced &&
            e.modifiedAt == photo.modifiedAt;
        if (!upToDate) pending.add(photo);
      }
      status.begin(pending.length, intervalMs: config.classifyIntervalMs);
      var deviceIdNow = deviceId;
      final size = batchSize < config.maxBatchSize
          ? batchSize
          : config.maxBatchSize;
      for (var i = 0; i < pending.length; i += size) {
        final chunk = pending.sublist(i, (i + size).clamp(0, pending.length));
        final r = await _batch(chunk, config, deviceIdNow);
        deviceIdNow = r.deviceId;
        failed += r.failed;
        status.advance(chunk.length);
        onBatchDone?.call();
      }
      await state.setFirstSyncDone();
      failed = await state.failedCount();
      status.finish(
        issue: failed > 0 ? SyncIssue.partial : SyncIssue.none,
        failedCount: failed,
      );
    } on ApiException catch (e) {
      status.finish(
        issue: e.failure == ApiFailure.offline
            ? SyncIssue.offline
            : SyncIssue.server,
        failedCount: await _safeFailedCount(),
      );
    } catch (_) {
      // 어떤 예외든 앱이 죽지 않게 한다. 내용(OCR 원문이 섞일 수 있음)은 남기지 않는다.
      status.finish(
        issue: SyncIssue.server,
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

  Future<List<GalleryPhoto>> _photos() async {
    final albums = await reader.albums();
    final shots = albums.where((a) => a.isScreenshots).toList();
    if (shots.isEmpty) return const [];
    final all = await capture.recent(shots.first.id);
    return photoLimit > 0 ? all.take(photoLimit).toList() : all;
  }

  /// 앱 시작 때 한 번: 현재 토큰을 서버에 올리고, FCM이 토큰을 바꾸면 다시 올린다.
  /// 아직 등록 전이면 건너뛴다(등록 요청에 토큰이 실린다). 실패는 무시한다(다음 시작에 다시).
  Future<void> startTokenSync() async {
    final p = push;
    if (p == null) return;
    _tokenSub ??= p.tokenRefresh.listen(_uploadToken);
    await _uploadToken(await p.token());
  }

  Future<void> _uploadToken(String? token) async {
    if (token == null) return;
    try {
      final id = await state.deviceId();
      if (id != null) await api.updateFcmToken(id, token);
    } catch (_) {
      // 서버에 닿지 못했거나 기기를 모름(404) → 다음 동기화의 재등록이 새 토큰을 싣는다
    }
  }

  Future<int> _ensureDevice() async {
    final saved = await state.deviceId();
    if (saved != null) return saved;
    final id = await api.registerDevice(await push?.token());
    await state.setDeviceId(id);
    return id;
  }

  /// 서버가 기기를 모를 때(서버 DB가 초기화됨 등): 새로 등록하고, 서버에 있다고 믿던 동기화 기록을 버려 다시 보내게 한다.
  Future<int> _reregister() async {
    await state.clear();
    final id = await api.registerDevice(await push?.token());
    await state.setDeviceId(id);
    return id;
  }

  Future<({int deviceId, int failed})> _batch(
    List<GalleryPhoto> chunk,
    ApiConfig config,
    int deviceId,
  ) async {
    await capture.run(chunk); // OCR·판정(이미 한 것은 건너뛴다). 실패한 장은 기록이 없어 아래에서 걸러진다.
    final consent = await settings.imageConsent() == true;
    final photoById = {for (final p in chunk) p.id: p};
    final send = <String, _Outgoing>{};
    var failed = 0;

    for (final photo in chunk) {
      final verdict = await capture.verdicts.find(photo.id);
      final record = await capture.store.find(photo.id);
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
          break;
        case PlanAction.deviceEtc:
          await _classifyOnDevice(photo, Category.etc);
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
    var currentDevice = deviceId;
    var reregistered = false;
    while (send.isNotEmpty && round < 3) {
      round++;
      final AnalyzeResult result;
      try {
        status.setWaiting(send.length); // 화면이 "분류하는 중"을 보여 준다
        result = await api.analyze(currentDevice, [
          for (final o in send.values) o.toItem(),
        ]);
        status.setWaiting(0);
      } on ApiException catch (e) {
        status.setWaiting(0);
        if (e.failure == ApiFailure.rejected &&
            e.statusCode == 404 &&
            !reregistered) {
          reregistered = true;
          currentDevice = await _reregister();
          continue;
        }
        rethrow;
      }

      for (final a in result.analyzed) {
        final photo = photoById[a.assetId];
        if (photo == null || !send.containsKey(a.assetId)) continue;
        await state.putEntry(_entry(photo, SyncStatusCode.synced));
        status.count(a.category, assetId: a.assetId);
        send.remove(a.assetId);
      }
      for (final id in result.skipped) {
        final photo = photoById[id];
        if (photo == null || !send.containsKey(id)) continue;
        await state.putEntry(_entry(photo, SyncStatusCode.synced));
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
      await _classifyOnDevice(photo, Category.etc);
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
