import '../gvboard/gvboard.dart';
import '../oss/oss.dart';

enum AccountStatus {
  loading,
  unauthenticated,
  authenticating,
  online,
  offline,
  expired,
}

class AccountState {
  const AccountState({
    required this.status,
    this.oss,
    this.user,
    this.error,
    this.remainingSeconds,
  });

  final AccountStatus status;
  final OssConfig? oss;
  final GvboardUserInfo? user;
  final String? error;
  final int? remainingSeconds;

  bool get isReady =>
      status == AccountStatus.online || status == AccountStatus.offline;
  bool get isOffline => status == AccountStatus.offline;
}

class AccountSnapshot {
  const AccountSnapshot({required this.api, required this.credentials});

  final GvboardApi api;
  final ({
    String email,
    String password,
    String? token,
    String? ossId,
    String? apiId,
    int? lastOnlineAt,
  })
  credentials;
}
