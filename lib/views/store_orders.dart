import 'package:material_ui/material_ui.dart';

import '../gvboard/gvboard.dart';
import '../ui/icons/icons.dart';
import '../ui/ui.dart';

String storeMoney(num cents) => (cents / 100).toStringAsFixed(2);

String _status(int status) => switch (status) {
  0 => '待支付',
  1 => '开通中',
  2 => '已取消',
  3 => '已完成',
  4 => '已折抵',
  _ => '未知状态',
};

String _date(BuildContext context, int seconds) {
  if (seconds <= 0) return '—';
  final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  final l10n = MaterialLocalizations.of(context);
  return '${l10n.formatCompactDate(date)} ${l10n.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}';
}

class StoreOrdersPage extends StatefulWidget {
  const StoreOrdersPage({required this.api, super.key});
  final GvboardApi api;

  @override
  State<StoreOrdersPage> createState() => _StoreOrdersPageState();
}

class _StoreOrdersPageState extends State<StoreOrdersPage> {
  late var _orders = widget.api.orders();
  void _refresh() => setState(() {
    _orders = widget.api.orders();
  });

  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: '订单记录',
    iconActions: [
      IconButtonData(
        glyph: AppGlyphs.refresh,
        tooltip: '刷新订单',
        onPressed: _refresh,
      ),
    ],
    body: FutureBuilder<List<GvboardOrder>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CommonCircleLoading());
        if (snapshot.hasError)
          return NullStatus(
            label: '订单加载失败',
            illustration: NullStatusIllustration.error,
            action: TextButton(onPressed: _refresh, child: const Text('重试')),
          );
        final orders = snapshot.data ?? const [];
        if (orders.isEmpty) return const NullStatus(label: '暂无订单');
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(
            16,
            context.contentTopPadding,
            16,
            16 + context.bottomInset,
          ),
          itemCount: orders.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final order = orders[index];
            return CommonCard(
              shape: AppShape.lg,
              padding: const EdgeInsets.all(14),
              onPressed: () async {
                await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => StoreOrderDetail(
                      api: widget.api,
                      tradeNo: order.tradeNo,
                    ),
                  ),
                );
                if (mounted) _refresh();
              },
              child: Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 4,
                      children: [
                        Text(
                          order.planName ?? order.tradeNo,
                          style: context.listTitleStyle,
                        ),
                        Text(
                          _date(context, order.createdAt),
                          style: context.listCaptionStyle,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    spacing: 4,
                    children: [
                      Text(
                        '¥${storeMoney(order.totalAmount)}',
                        style: AppTextStyle.headline
                            .of(context)
                            .copyWith(color: context.colorScheme.primary),
                      ),
                      Text(
                        _status(order.status),
                        style: context.listCaptionStyle.copyWith(
                          color: order.status == 3
                              ? context.colorScheme.success
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}

class StoreOrderDetail extends StatefulWidget {
  const StoreOrderDetail({required this.api, required this.tradeNo, super.key});
  final GvboardApi api;
  final String tradeNo;

  @override
  State<StoreOrderDetail> createState() => _StoreOrderDetailState();
}

class _StoreOrderDetailState extends State<StoreOrderDetail> {
  late var _order = widget.api.order(widget.tradeNo);
  bool _busy = false;
  bool _cancelled = false;

  void _refresh() => setState(() {
    _order = widget.api.order(widget.tradeNo);
  });

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        useRootNavigator: false,
        builder: (context) => AlertDialog(
          title: const Text('取消未支付订单？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保留订单'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认取消'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      await widget.api.cancelOrder(widget.tradeNo);
      if (!mounted) return;
      _cancelled = true;
      _refresh();
    } on Object catch (error) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => CommonScaffold(
    title: '订单详情',
    backAction: () => Navigator.pop(context, _cancelled),
    iconActions: [
      IconButtonData(
        glyph: AppGlyphs.refresh,
        tooltip: '刷新订单',
        onPressed: _busy ? null : _refresh,
      ),
    ],
    body: FutureBuilder<Map<String, dynamic>>(
      future: _order,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done)
          return const Center(child: CommonCircleLoading());
        if (snapshot.hasError)
          return NullStatus(
            label: '订单详情加载失败',
            illustration: NullStatusIllustration.error,
            action: TextButton(onPressed: _refresh, child: const Text('重试')),
          );
        final data = snapshot.data!;
        final order = GvboardOrder.fromJson(data);
        return ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            context.sectionsTopPadding,
            16,
            20 + context.bottomInset,
          ),
          children: [
            generateSection(
              title: order.planName ?? '订单',
              items: [
                ListItem(
                  title: const Text('订单号'),
                  subtitle: SelectableText(widget.tradeNo),
                ),
                ListItem(
                  title: const Text('状态'),
                  trailing: Text(_status(order.status)),
                ),
                ListItem(
                  title: const Text('创建时间'),
                  trailing: Text(_date(context, order.createdAt)),
                ),
                ListItem(
                  title: const Text('订单金额'),
                  trailing: Text('¥${storeMoney(order.totalAmount)}'),
                ),
                for (final (key, label) in const [
                  ('handling_amount', '手续费'),
                  ('discount_amount', '优惠'),
                  ('surplus_amount', '订阅折抵'),
                  ('refund_amount', '退款'),
                  ('balance_amount', '余额抵扣'),
                ])
                  if (data[key] case final num amount when amount != 0)
                    ListItem(
                      title: Text(label),
                      trailing: Text('¥${storeMoney(amount)}'),
                    ),
                if (order.status == 0 && !_cancelled)
                  ListItem(
                    leading: const GlyphIcon(AppGlyphs.close),
                    title: const Text('取消订单'),
                    onTap: _busy ? null : _cancel,
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );
}
