import 'package:fl_clash/account/account.dart';
import 'package:fl_clash/gvboard/gvboard.dart';
import 'package:fl_clash/providers/account.dart';
import 'package:fl_clash/pages/auth.dart';
import 'package:fl_clash/views/account.dart';
import 'package:fl_clash/views/store.dart';
import 'package:fl_clash/views/store_orders.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/test_app.dart';

class _Api extends Mock implements GvboardApi {}

class _Account extends AccountController {
  _Account(this.api) {
    value = const AccountState(status: AccountStatus.online);
  }

  @override
  final GvboardApi api;
}

Future<void> _pump(WidgetTester tester, _Account account, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(415, 680);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(account.dispose);
  await tester.pumpWidget(
    TestApp(
      overrides: [accountProvider.overrideWithValue(account)],
      child: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('auth toolbar and recovery form fit the reference phone width', (
    tester,
  ) async {
    await _pump(
      tester,
      _Account(_Api()),
      const AuthPage(
        state: AccountState(status: AccountStatus.unauthenticated),
      ),
    );
    expect(find.byTooltip('Language'), findsOneWidget);
    expect(find.text('Website'), findsOneWidget);
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Recover password'), findsOneWidget);
    expect(find.text('Email code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelling a pending order refreshes its detail', (
    tester,
  ) async {
    final api = _Api();
    var cancelled = false;
    when(() => api.order('demo')).thenAnswer(
      (_) async => {'trade_no': 'demo', 'status': cancelled ? 2 : 0},
    );
    when(() => api.cancelOrder('demo')).thenAnswer((_) async {
      cancelled = true;
    });
    await _pump(
      tester,
      _Account(api),
      StoreOrderDetail(api: api, tradeNo: 'demo'),
    );
    await tester.ensureVisible(find.text('取消订单'));
    await tester.tap(find.text('取消订单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认取消'));
    await tester.pumpAndSettle();
    expect(find.text('已取消'), findsOneWidget);
    expect(find.text('取消订单'), findsNothing);
    verify(() => api.cancelOrder('demo')).called(1);
  });
  testWidgets('plan card renders HTML and opens its own purchase sheet', (
    tester,
  ) async {
    final api = _Api();
    when(api.plans).thenAnswer(
      (_) async => [
        {
          'id': 1,
          'name': 'Demo',
          'month_price': 1200,
          'transfer_enable': 298,
          'content': '<strong>高速通道</strong><br>流畅播放',
        },
      ],
    );
    when(api.subscriptions).thenAnswer((_) async => []);
    await _pump(tester, _Account(api), const StoreView());
    expect(find.textContaining('高速通道', findRichText: true), findsOneWidget);
    verifyNever(api.subscriptions);
    await tester.tap(find.text('购买'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('订阅目标')).dy,
      lessThan(tester.getTopLeft(find.text('选择周期')).dy),
    );
    verify(api.subscriptions).called(1);
  });

  testWidgets(
    'account support keeps password change without security sections',
    (tester) async {
      final api = _Api();
      when(api.orders).thenAnswer((_) async => []);
      when(api.subscriptions).thenAnswer((_) async => []);
      when(
        api.invite,
      ).thenAnswer((_) async => GvboardInviteOverview.fromJson({}));
      when(() => api.commissions()).thenAnswer((_) async => []);
      await _pump(tester, _Account(api), const AccountView());
      verifyNever(api.orders);
      verifyNever(api.subscriptions);
      verifyNever(api.invite);
      verifyNever(api.commissions);
      final orderSection = find.text('订单记录');
      await tester.ensureVisible(orderSection);
      await tester.tap(orderSection);
      await tester.pumpAndSettle();
      verify(api.orders).called(1);
      expect(find.text('账号安全'), findsNothing);
      expect(find.text('登录记录'), findsNothing);
      expect(find.text('修改密码'), findsOneWidget);
    },
  );
}
