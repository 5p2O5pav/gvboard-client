import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as html;
import 'package:html/parser.dart' as html;
import 'package:material_ui/material_ui.dart';

import '../account/account.dart';
import '../gvboard/gvboard.dart';
import '../pages/internal_browser.dart';
import '../providers/providers.dart';
import '../ui/icons/icons.dart';
import '../ui/ui.dart';
import 'store_orders.dart';

const _periods = {
  'month_price': '月付',
  'quarter_price': '季付',
  'half_year_price': '半年付',
  'year_price': '年付',
  'two_year_price': '两年付',
  'three_year_price': '三年付',
  'onetime_price': '一次性',
  'reset_price': '重置流量',
};

class StoreView extends ConsumerWidget {
  const StoreView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(accountProvider);
    return ValueListenableBuilder<AccountState>(
      valueListenable: account,
      builder: (context, state, _) {
        final api = account.api;
        if (state.status != AccountStatus.online || api == null) {
          return const CommonScaffold(
            title: '商店',
            body: NullStatus(label: '离线模式下暂时无法购买套餐'),
          );
        }
        return _OnlineStore(
          key: ObjectKey(api),
          api: api,
          subscriptionLimit: state.user?.subscriptionLimit,
        );
      },
    );
  }
}

class _OnlineStore extends StatefulWidget {
  const _OnlineStore({required this.api, this.subscriptionLimit, super.key});
  final GvboardApi api;
  final int? subscriptionLimit;

  @override
  State<_OnlineStore> createState() => _OnlineStoreState();
}

class _OnlineStoreState extends State<_OnlineStore> {
  late var _plans = widget.api.plans();

  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: '商店',
    iconActions: [
      IconButtonData(
        glyph: AppGlyphs.receipt,
        tooltip: '订单记录',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => StoreOrdersPage(api: widget.api),
          ),
        ),
      ),
    ],
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _plans,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CommonCircleLoading());
        if (snapshot.hasError)
          return NullStatus(
            label: '套餐加载失败',
            illustration: NullStatusIllustration.error,
            action: TextButton(
              onPressed: () => setState(() {
                _plans = widget.api.plans();
              }),
              child: const Text('重试'),
            ),
          );
        final plans = snapshot.data ?? const [];
        if (plans.isEmpty) return const NullStatus(label: '暂无可购买套餐');
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            16,
            context.contentTopPadding,
            16,
            16 + context.bottomInset,
          ),
          itemCount: plans.length,
          separatorBuilder: (_, _) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final plan = plans[index];
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _PlanCard(
                  plan: plan,
                  alternate: index.isOdd,
                  onBuy: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    showDragHandle: true,
                    builder: (_) => _PurchaseSheet(
                      api: widget.api,
                      plan: plan,
                      subscriptionLimit: widget.subscriptionLimit,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.alternate,
    required this.onBuy,
  });
  final Map<String, dynamic> plan;
  final bool alternate;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final accent = alternate ? colors.tertiary : colors.primary;
    final foreground = alternate ? colors.onTertiary : colors.onPrimary;
    final price = _periods.keys
        .where((key) => key != 'reset_price' && plan[key] is num)
        .firstOrNull;
    return Material(
      color: context.raisedSurfaceLevel.colorOf(colors),
      shape: AppShape.xl,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(
            color: accent,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    '${plan['name'] ?? '套餐'}',
                    style: AppTextStyle.headline
                        .of(context)
                        .copyWith(color: foreground),
                  ),
                  if (price != null)
                    Text(
                      '¥${storeMoney(plan[price] as num)} ${_periods[price]}',
                      style: AppTextStyle.headline
                          .of(context)
                          .copyWith(color: foreground),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 16,
                  runSpacing: 10,
                  children: [
                    _PlanFact(
                      glyph: AppGlyphs.speed,
                      label: '流量',
                      value: '${plan['transfer_enable'] ?? '—'} GB',
                    ),
                    _PlanFact(
                      glyph: AppGlyphs.devices,
                      label: '设备限制',
                      value:
                          plan['device_limit'] == null ||
                              plan['device_limit'] == 0
                          ? '不限'
                          : '${plan['device_limit']} 台设备',
                    ),
                  ],
                ),
                if ((plan['content'] as String? ?? '').trim().isNotEmpty)
                  DecoratedBox(
                    decoration: ShapeDecoration(
                      color: SurfaceLevel.block.colorOf(colors),
                      shape: AppShape.md,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: _PlanDescription(
                        source: plan['content'] as String,
                      ),
                    ),
                  ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: foreground,
                  ),
                  onPressed: _periods.keys.any((key) => plan[key] is num)
                      ? onBuy
                      : null,
                  child: const Text('购买'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanFact extends StatelessWidget {
  const _PlanFact({
    required this.glyph,
    required this.label,
    required this.value,
  });
  final Glyph glyph;
  final String label, value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 10,
    children: [
      DecoratedBox(
        decoration: ShapeDecoration(
          color: SurfaceLevel.inset.colorOf(context.colorScheme),
          shape: AppShape.sm,
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: GlyphIcon(glyph, color: context.colorScheme.primary, size: 20),
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.listCaptionStyle),
          Text(value, style: context.listTitleStyle),
        ],
      ),
    ],
  );
}

class _PlanDescription extends StatelessWidget {
  const _PlanDescription({required this.source});
  final String source;

  Iterable<InlineSpan> _spans(
    Iterable<html.Node> nodes,
    BuildContext context,
  ) sync* {
    for (final node in nodes) {
      if (node is html.Text) {
        yield TextSpan(text: node.text);
      } else if (node is html.Element) {
        final tag = node.localName;
        if (const {
          'script',
          'style',
          'iframe',
          'object',
          'template',
        }.contains(tag))
          continue;
        if (tag == 'br') {
          yield const TextSpan(text: '\n');
          continue;
        }
        if (tag == 'li') yield const TextSpan(text: '• ');
        yield TextSpan(
          style: switch (tag) {
            'b' ||
            'strong' ||
            'h1' ||
            'h2' ||
            'h3' => AppTextStyle.headline.of(context),
            'em' || 'i' => const TextStyle(fontStyle: FontStyle.italic),
            'a' || 'u' => const TextStyle(decoration: TextDecoration.underline),
            'del' ||
            's' => const TextStyle(decoration: TextDecoration.lineThrough),
            _ => null,
          },
          children: _spans(node.nodes, context).toList(),
        );
        if (const {'p', 'div', 'li', 'h1', 'h2', 'h3'}.contains(tag))
          yield const TextSpan(text: '\n');
      }
    }
  }

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(children: _spansWithContext(context)),
    style: context.listSubtitleStyle,
  );

  List<InlineSpan> _spansWithContext(BuildContext context) =>
      _spans(html.parseFragment(source).nodes, context).toList();
}

class _RenewModeInfoButton extends StatelessWidget {
  const _RenewModeInfoButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '查看说明',
    onPressed: onPressed,
    icon: Text(
      'ⓘ',
      style: AppTextStyle.custom(
        context,
        size: 24,
        leading: 24,
        weight: FontWeight.w700,
            ).copyWith(
              color: context.colorScheme.brightness == Brightness.dark
                  ? const Color(0xFFFBBF24)
                  : const Color(0xFFD97706),
            ),
    ),
  );
}

class _PurchaseSheet extends StatefulWidget {
  const _PurchaseSheet({
    required this.api,
    required this.plan,
    this.subscriptionLimit,
  });
  final GvboardApi api;
  final Map<String, dynamic> plan;
  final int? subscriptionLimit;

  @override
  State<_PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends State<_PurchaseSheet> {
  final _coupon = TextEditingController();
  late Future<List<GvboardSubscription>> _targets = widget.api
      .subscriptions()
      .then((subscriptions) {
        if (widget.subscriptionLimit == 1 &&
            subscriptions.isNotEmpty &&
            mounted) {
          setState(() => _target = subscriptions.first.id);
        }
        return subscriptions;
      });
  int _target = 0;
  String? _period;
  bool _immediate = false;
  String? _message;
  bool _busy = false;
  String? _tradeNo;

  String _targetLabel(GvboardSubscription subscription) =>
      subscription.planName == null || subscription.planName!.isEmpty
      ? subscription.name
      : '${subscription.planName} · ${subscription.name}';

  bool get _singleSubscription => widget.subscriptionLimit == 1;

  Future<void> _showRenewModeInfo(bool immediate) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(immediate ? '立刻生效' : '提前续费'),
        content: Text(
          immediate
              ? '新套餐会立即替换当前套餐，已使用流量会清零，新周期从现在开始计算，并按规则扣除当前周期剩余时间。'
              : '新周期会接在当前套餐到期时间之后，不会清零当前已使用流量，适合提前续费。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('我知道了'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _coupon.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy() => _run(() async {
    final period = _period;
    if (period == null) return;
    final input = <String, dynamic>{
      'plan_id': widget.plan['id'],
      'period': period,
      'subscription_id': _target,
      'immediate': _immediate,
      if (_coupon.text.trim().isNotEmpty) 'coupon_code': _coupon.text.trim(),
    };
    final api = widget.api;
    final quote = await api.orderPreview(input);
    final methods = (quote['total'] == 0)
        ? <Map<String, dynamic>>[]
        : await api.paymentMethods();
    if (!mounted) return;
    if (quote['total'] != 0 && methods.isEmpty)
      throw const GvboardApiException('当前没有可用支付方式');
    final method = await showDialog<int>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text('确认订单 · ${widget.plan['name'] ?? '套餐'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (key, label) in const [
              ('price', '原价'),
              ('coupon', '优惠券'),
              ('user_discount', '会员折扣'),
              ('surplus', '订阅折抵'),
              ('balance', '余额抵扣'),
            ])
              if (quote[key] case final num amount when amount != 0)
                Text('$label：¥${storeMoney(amount)}'),
            Text(
              '应付：¥${storeMoney(quote['total'] as num? ?? 0)}',
              style: AppTextStyle.headline.of(context, emphasized: true),
            ),
            if ((quote['type'] as num?)?.toInt() == 3)
              const Text('请注意，变更订阅会导致当前订阅被新订阅覆盖。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          if (methods.isEmpty)
            FilledButton(
              onPressed: () => Navigator.pop(context, 0),
              child: const Text('确认创建订单'),
            ),
          for (final method in methods)
            if (method['id'] case final num id)
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, id.toInt()),
                child: Text('${method['name'] ?? '继续支付'}'),
              ),
        ],
      ),
    );
    if (method == null || !mounted) return;
    final tradeNo = await api.createOrder(input);
    if (!mounted) return;
    setState(() => _tradeNo = tradeNo);
    final result = await api.checkout(tradeNo, method);
    if (!mounted) return;
    final link = result['data'];
    final uri = link is String ? Uri.tryParse(link) : null;
    if (result['type'] == 0 && link is String && link.isNotEmpty) {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('扫码支付'),
          content: QrCodeView(data: link, size: 200),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } else if (result['type'] == 1 &&
        uri != null &&
        ['http', 'https'].contains(uri.scheme)) {
      await InternalBrowserPage.open(context, link as String);
    } else if (result['type'] != -1 && result['type'] != 2) {
      throw const GvboardApiException('此支付方式未返回可用链接，请在订单记录查看');
    }
    if (mounted) {
      setState(
        () =>
            _message = result['type'] == -1 ? '订单已提交，可查看订单状态' : '请在订单详情查看最新状态',
      );
      unawaited(_watchOrder(tradeNo));
    }
  });

  Future<void> _watchOrder(String tradeNo) async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      try {
        final status = await widget.api.orderStatus(tradeNo);
        if (!mounted) return;
        if (status == 0) continue;
        setState(
          () => _message = switch (status) {
            1 => '支付已确认，正在开通',
            2 => '订单已取消',
            3 => '订单已完成',
            _ => '请在订单详情查看最新状态',
          },
        );
        return;
      } on Exception {
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: FutureBuilder<List<GvboardSubscription>>(
        future: _targets,
        builder: (context, snapshot) {
          final selectedSub = snapshot.data
              ?.where((item) => item.id == _target)
              .firstOrNull;
          final samePlan =
              selectedSub != null &&
              selectedSub.planId == (widget.plan['id'] as num?)?.toInt() &&
              !selectedSub.isExpired &&
              !selectedSub.banned;
          final changesPlan =
              selectedSub != null &&
              selectedSub.planId != (widget.plan['id'] as num?)?.toInt() &&
              !selectedSub.isExpired &&
              !selectedSub.banned;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: 14,
            children: [
              Text(
                '${widget.plan['name'] ?? '套餐'}',
                textAlign: TextAlign.center,
                style: AppTextStyle.title2.of(context, emphasized: true),
              ),
              if (snapshot.hasError)
                TextButton(
                  onPressed: () => setState(() {
                    _targets = widget.api.subscriptions();
                  }),
                  child: const Text('订阅目标加载失败，点击重试'),
                )
              else if (!snapshot.hasData)
                const LinearProgressIndicator()
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_singleSubscription) ...[
                      Text(
                        '作用于',
                        style: AppTextStyle.headline.of(
                          context,
                          emphasized: true,
                        ),
                      ),
                      Text(
                        '选择已有订阅时，同套餐为续费，不同套餐为更换套餐',
                        style: context.listSubtitleStyle,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: _target,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '订阅目标'),
                        items: [
                          const DropdownMenuItem(value: 0, child: Text('新开订阅')),
                          for (final sub in snapshot.data!)
                            DropdownMenuItem(
                              value: sub.id,
                              child: Text(
                                _targetLabel(sub),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: _busy || _tradeNo != null
                            ? null
                            : (value) => setState(() {
                                _target = value ?? 0;
                                if (_target == 0 && _period == 'reset_price') {
                                  _period = null;
                                }
                                final targetSub = snapshot.data
                                    ?.where((item) => item.id == _target)
                                    .firstOrNull;
                                if (targetSub?.planId !=
                                    (widget.plan['id'] as num?)?.toInt())
                                  _immediate = false;
                              }),
                      ),
                    ],
                    if (_target != 0 &&
                        samePlan &&
                        _period != 'reset_price' &&
                        _period != 'onetime_price') ...[
                      const SizedBox(height: 10),
                      Row(
                        spacing: 10,
                        children: [
                          Expanded(
                            child: CommonCard(
                              shape: AppShape.md,
                              isSelected: !_immediate,
                              inert: !samePlan || _busy || _tradeNo != null,
                              onPressed: !samePlan || _busy || _tradeNo != null
                                  ? null
                                  : () => setState(() => _immediate = false),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '提前续费',
                                      style: context.listTitleStyle,
                                    ),
                                  ),
                                  if (!_immediate) const SelectionCheck(),
                                  _RenewModeInfoButton(
                                    onPressed: () => _showRenewModeInfo(false),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: CommonCard(
                              shape: AppShape.md,
                              isSelected: _immediate,
                              inert: !samePlan || _busy || _tradeNo != null,
                              onPressed: !samePlan || _busy || _tradeNo != null
                                  ? null
                                  : () => setState(() => _immediate = true),
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      '立刻生效',
                                      style: context.listTitleStyle,
                                    ),
                                  ),
                                  if (_immediate) const SelectionCheck(),
                                  _RenewModeInfoButton(
                                    onPressed: () => _showRenewModeInfo(true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (changesPlan)
                      DecoratedBox(
                        decoration: ShapeDecoration(
                          color: context.colorScheme.warningContainer,
                          shape: AppShape.md,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('请注意，变更订阅会导致当前订阅被新订阅覆盖。'),
                        ),
                      ),
                    if (_target != 0 && selectedSub?.isExpired == true)
                      Text(
                        '此订阅已过期，本订单将新开订阅。',
                        style: context.listSubtitleStyle,
                      ),
                    if (_target != 0 && selectedSub?.banned == true)
                      Text('此订阅已停用，无法续费。', style: context.listSubtitleStyle),
                  ],
                ),
              Text('选择周期', style: AppTextStyle.headline.of(context)),
              SizedBox(
                height: 94,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final entry in _periods.entries)
                      if (widget.plan[entry.key] is num &&
                          (entry.key != 'reset_price' || _target != 0))
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: SizedBox(
                            width: 100,
                            child: CommonCard(
                              shape: AppShape.md,
                              isSelected: _period == entry.key,
                              onPressed: _busy || _tradeNo != null
                                  ? null
                                  : () => setState(() => _period = entry.key),
                              inert: _busy || _tradeNo != null,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                spacing: 4,
                                children: [
                                  Text(
                                    entry.value,
                                    style: context.listCaptionStyle,
                                  ),
                                  Text(
                                    '¥${storeMoney(widget.plan[entry.key] as num)}',
                                    style: AppTextStyle.headline
                                        .of(context)
                                        .copyWith(
                                          color: context.colorScheme.primary,
                                        ),
                                  ),
                                  if (_period == entry.key)
                                    const SelectionCheck(),
                                ],
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
              if (_tradeNo == null) ...[
                TextField(
                  controller: _coupon,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: '优惠券（可选）',
                    suffixIcon: TextButton(
                      onPressed: _busy || _period == null
                          ? null
                          : () => _run(() async {
                              final code = _coupon.text.trim();
                              if (code.isEmpty) return;
                              await widget.api.checkCoupon(
                                code: code,
                                planId: (widget.plan['id'] as num).toInt(),
                                period: _period!,
                              );
                              if (mounted) setState(() => _message = '优惠券有效');
                            }),
                      child: const Text('验证'),
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _busy || _period == null || !snapshot.hasData
                      ? null
                      : _buy,
                  child: Text(_busy ? '处理中…' : '创建订单'),
                ),
              ] else
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => StoreOrderDetail(
                              api: widget.api,
                              tradeNo: _tradeNo!,
                            ),
                          ),
                        ),
                  child: const Text('查看订单'),
                ),
              if (_message != null)
                Text(_message!, style: context.listSubtitleStyle),
            ],
          );
        },
      ),
    ),
  );
}
