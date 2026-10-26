import 'push.dart';
import 'remote_repository.dart';
import 'remote_state_store.dart';
import 'sync_service.dart';
import 'sync_status.dart';

/// 서버 연동에 쓰는 객체 묶음. `--dart-define=API_BASE`가 있을 때만 만들어진다.
class RemoteServices {
  const RemoteServices({
    required this.repository,
    required this.sync,
    required this.status,
    required this.state,
    this.push,
  });

  final RemoteRepository repository;
  final SyncService sync;
  final SyncStatus status;
  final RemoteStateStore state;

  /// 푸시(관심사 알림). Firebase를 초기화하지 못했으면 null.
  final PushClient? push;
}
