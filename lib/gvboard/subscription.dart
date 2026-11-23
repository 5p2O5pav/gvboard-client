class GvboardSubscription {
  const GvboardSubscription({
    required this.id,
    this.planId,
    this.planName,
    required this.name,
    required this.isPrimary,
    required this.transferEnable,
    required this.upload,
    required this.download,
    required this.deviceLimit,
    required this.speedLimit,
    required this.expiredAt,
    required this.aliveIp,
    required this.subscribeUrl,
    required this.banned,
    required this.allowNewPeriod,
  });

  final int id;
  final int? planId;
  final String? planName;
  final String name;
  final bool isPrimary;
  final int transferEnable;
  final int upload;
  final int download;
  final int? deviceLimit;
  final int? speedLimit;
  final int? expiredAt;
  final int aliveIp;
  final String subscribeUrl;
  final bool banned;
  final bool allowNewPeriod;

  bool get isExpired =>
      expiredAt != null &&
      DateTime.fromMillisecondsSinceEpoch(
        expiredAt! * 1000,
      ).isBefore(DateTime.now());

  factory GvboardSubscription.fromJson(Map<String, dynamic> json) {
    final plan = json['plan'];
    return GvboardSubscription(
      id: (json['id'] as num?)?.toInt() ?? 0,
      planId: ((json['plan'] as Map?)?['id'] as num?)?.toInt(),
      planName: (json['plan'] as Map?)?['name'] as String?,
      name:
          json['name'] as String? ??
          (plan is Map ? plan['name'] as String? : null) ??
          '订阅',
      isPrimary: json['is_primary'] == true,
      transferEnable: (json['transfer_enable'] as num?)?.toInt() ?? 0,
      upload: (json['u'] as num?)?.toInt() ?? 0,
      download: (json['d'] as num?)?.toInt() ?? 0,
      deviceLimit: (json['device_limit'] as num?)?.toInt(),
      speedLimit: (json['speed_limit'] as num?)?.toInt(),
      expiredAt: (json['expired_at'] as num?)?.toInt(),
      aliveIp: (json['alive_ip'] as num?)?.toInt() ?? 0,
      subscribeUrl: json['subscribe_url'] as String? ?? '',
      banned: json['banned'] == true,
      allowNewPeriod: json['allow_new_period'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'plan': planId == null ? null : {'id': planId, 'name': name},
    'name': name,
    'is_primary': isPrimary,
    'transfer_enable': transferEnable,
    'u': upload,
    'd': download,
    'device_limit': deviceLimit,
    'speed_limit': speedLimit,
    'expired_at': expiredAt,
    'alive_ip': aliveIp,
    'subscribe_url': subscribeUrl,
    'banned': banned,
    'allow_new_period': allowNewPeriod,
  };
}
