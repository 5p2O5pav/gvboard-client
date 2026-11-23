class GvboardUserInfo {
  const GvboardUserInfo({
    required this.id,
    required this.email,
    required this.balance,
    required this.commissionBalance,
    required this.subscriptionLimit,
    required this.createdAt,
  });

  final int id;
  final String email;
  final int balance;
  final int commissionBalance;
  final int subscriptionLimit;
  final int createdAt;

  factory GvboardUserInfo.fromJson(Map<String, dynamic> json) =>
      GvboardUserInfo(
        id: (json['id'] as num?)?.toInt() ?? 0,
        email: json['email'] as String? ?? '',
        balance: (json['balance'] as num?)?.toInt() ?? 0,
        commissionBalance: (json['commission_balance'] as num?)?.toInt() ?? 0,
        subscriptionLimit: (json['subscription_limit'] as num?)?.toInt() ?? 0,
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

class GvboardUserStat {
  const GvboardUserStat({
    required this.pendingOrders,
    required this.openTickets,
    required this.invitees,
  });

  final int pendingOrders;
  final int openTickets;
  final int invitees;

  factory GvboardUserStat.fromJson(Map<String, dynamic> json) =>
      GvboardUserStat(
        pendingOrders: (json['pending_orders'] as num?)?.toInt() ?? 0,
        openTickets: (json['open_tickets'] as num?)?.toInt() ?? 0,
        invitees: (json['invitees'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'pending_orders': pendingOrders,
    'open_tickets': openTickets,
    'invitees': invitees,
  };
}

class GvboardSession {
  const GvboardSession({
    required this.id,
    required this.ip,
    required this.userAgent,
    required this.loginAt,
    required this.current,
  });

  final String id;
  final String ip;
  final String userAgent;
  final int loginAt;
  final bool current;

  factory GvboardSession.fromJson(Map<String, dynamic> json) => GvboardSession(
    id: json['id'] as String? ?? '',
    ip: json['ip'] as String? ?? '',
    userAgent: json['ua'] as String? ?? '',
    loginAt: (json['login_at'] as num?)?.toInt() ?? 0,
    current: json['current'] == true,
  );
}

class GvboardInviteOverview {
  const GvboardInviteOverview({
    required this.codes,
    required this.invitees,
    required this.totalCommission,
    required this.pendingCommission,
    required this.commissionRate,
    required this.commissionBalance,
  });

  final List<GvboardInviteCode> codes;
  final int invitees;
  final int totalCommission;
  final num pendingCommission;
  final int commissionRate;
  final int commissionBalance;

  factory GvboardInviteOverview.fromJson(Map<String, dynamic> json) {
    final stat = (json['stat'] as Map?)?.cast<String, dynamic>() ?? const {};
    return GvboardInviteOverview(
      codes: [
        for (final code in (json['codes'] as List?) ?? const [])
          if (code is Map<String, dynamic>) GvboardInviteCode.fromJson(code),
      ],
      invitees: (stat['invitees'] as num?)?.toInt() ?? 0,
      totalCommission: (stat['total_commission'] as num?)?.toInt() ?? 0,
      pendingCommission: (stat['pending_commission'] as num?) ?? 0,
      commissionRate: (stat['commission_rate'] as num?)?.toInt() ?? 0,
      commissionBalance: (stat['commission_balance'] as num?)?.toInt() ?? 0,
    );
  }
}

class GvboardInviteCode {
  const GvboardInviteCode({required this.code, required this.views});

  final String code;
  final int views;

  factory GvboardInviteCode.fromJson(Map<String, dynamic> json) =>
      GvboardInviteCode(
        code: json['code'] as String? ?? '',
        views: (json['pv'] as num?)?.toInt() ?? 0,
      );
}

class GvboardCommissionEntry {
  const GvboardCommissionEntry({
    required this.id,
    required this.tradeNo,
    required this.orderAmount,
    required this.amount,
    required this.createdAt,
  });

  final int id;
  final String tradeNo;
  final int orderAmount;
  final int amount;
  final int createdAt;

  factory GvboardCommissionEntry.fromJson(Map<String, dynamic> json) =>
      GvboardCommissionEntry(
        id: (json['id'] as num?)?.toInt() ?? 0,
        tradeNo: json['trade_no'] as String? ?? '',
        orderAmount: (json['order_amount'] as num?)?.toInt() ?? 0,
        amount: (json['get_amount'] as num?)?.toInt() ?? 0,
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
      );
}

class GvboardOrder {
  const GvboardOrder({
    required this.tradeNo,
    required this.status,
    required this.totalAmount,
    required this.createdAt,
    this.planName,
  });

  final String tradeNo;
  final int status;
  final int totalAmount;
  final int createdAt;
  final String? planName;

  factory GvboardOrder.fromJson(Map<String, dynamic> json) => GvboardOrder(
    tradeNo: json['trade_no'] as String? ?? '',
    status: (json['status'] as num?)?.toInt() ?? -1,
    totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
    createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    planName: json['plan'] is Map
        ? (json['plan'] as Map)['name'] as String?
        : null,
  );
}
