import 'package:fl_clash/gvboard/subscription.dart';
import 'package:fl_clash/gvboard/user_center.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the native GVBoard subscription fields', () {
    final subscription = GvboardSubscription.fromJson({
      'id': 42,
      'name': 'Primary',
      'is_primary': true,
      'transfer_enable': 1024,
      'u': 100,
      'd': 200,
      'device_limit': 3,
      'speed_limit': 50,
      'expired_at': 4102444800,
      'alive_ip': 2,
      'subscribe_url': 'https://panel.example/sub',
      'banned': false,
      'allow_new_period': true,
    });

    expect(subscription.id, 42);
    expect(subscription.isPrimary, isTrue);
    expect(subscription.upload + subscription.download, 300);
    expect(subscription.deviceLimit, 3);
    expect(subscription.subscribeUrl, 'https://panel.example/sub');
    expect(subscription.isExpired, isFalse);
  });

  test('round trips cached subscription data', () {
    final subscription = GvboardSubscription.fromJson({
      'id': 7,
      'subscribe_url': 'https://panel.example/sub/7',
      'expired_at': 1,
      'banned': true,
    });

    final restored = GvboardSubscription.fromJson(subscription.toJson());

    expect(restored.id, subscription.id);
    expect(restored.subscribeUrl, subscription.subscribeUrl);
    expect(restored.isExpired, isTrue);
    expect(restored.banned, isTrue);
  });

  test('maps GVBoard account, session, invite, and commission fields', () {
    final user = GvboardUserInfo.fromJson({
      'id': 9,
      'email': 'user@example.com',
      'balance': 1250,
      'commission_balance': 300,
      'subscription_limit': 4,
      'created_at': 100,
    });
    final session = GvboardSession.fromJson({
      'id': 'session-id',
      'ip': '192.0.2.1',
      'ua': 'desktop',
      'login_at': 200,
      'current': true,
    });
    final invite = GvboardInviteOverview.fromJson({
      'codes': [
        {'code': 'ABCD1234', 'pv': 5},
      ],
      'stat': {
        'invitees': 2,
        'total_commission': 900,
        'pending_commission': 100,
        'commission_rate': 10,
        'commission_balance': 300,
      },
    });
    final entry = GvboardCommissionEntry.fromJson({
      'id': 1,
      'trade_no': 'T2026',
      'order_amount': 1000,
      'get_amount': 100,
      'created_at': 300,
    });

    expect(user.subscriptionLimit, 4);
    expect(session.current, isTrue);
    expect(invite.codes.single.views, 5);
    expect(invite.totalCommission, 900);
    expect(entry.amount, 100);
  });
}
