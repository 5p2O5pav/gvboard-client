import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../common/constant.dart';
import '../gvboard/gvboard.dart';
import '../account/account.dart';
import '../features/form/form_row.dart';
import '../providers/providers.dart';
import '../pages/internal_browser.dart';
import '../ui/icons/icons.dart';
import '../ui/ui.dart';

class AccountView extends ConsumerWidget {
  const AccountView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(accountProvider);
    return ValueListenableBuilder<AccountState>(
      valueListenable: controller,
      builder: (context, state, _) =>
          _buildPage(context, ref, controller, state),
    );
  }

  Widget _buildPage(
    BuildContext context,
    WidgetRef ref,
    AccountController controller,
    AccountState state,
  ) {
    final api = controller.api;
    final email = state.user?.email ?? '未获取账号信息';
    return CommonScaffold(
      title: '我的',
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [
          generateSection(
            title: '账号',
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.account),
                title: Text(email),
              ),
              ListItem(
                leading: GlyphIcon(
                  state.isOffline ? AppGlyphs.warning : AppGlyphs.vpn,
                ),
                title: Text(state.isOffline ? '离线模式' : '在线'),
              ),
              if (state.user != null)
                ListItem(
                  leading: const GlyphIcon(AppGlyphs.wallet),
                  title: Text('账户余额：${_money(state.user!.balance)}'),
                  subtitle: Text('可管理订阅数：${state.user!.subscriptionLimit}'),
                ),
              if (state.user != null && api != null && !state.isOffline)
                _UserStatSection(controller: controller),
            ],
          ),
          _DeferredSection(
            title: '套餐与订阅',
            glyph: AppGlyphs.profiles,
            child: _SubscriptionsSection(
              controller: controller,
              online: !state.isOffline,
            ),
          ),
          if (api != null && !state.isOffline)
            _DeferredSection(
              title: '订单记录',
              glyph: AppGlyphs.receipt,
              child: _OrdersSection(api: api),
            ),
          if (api != null && !state.isOffline) ...[
            _DeferredSection(
              title: '邀请与佣金',
              glyph: AppGlyphs.connections,
              child: _InviteSection(api: api),
            ),
          ],
          generateSection(
            title: '支持',
            items: [
              ListItem(
                leading: const GlyphIcon(AppGlyphs.language),
                title: const Text('访问官网'),
                onTap: () => InternalBrowserPage.open(
                  context,
                  state.oss?.officialWebsite.isNotEmpty == true
                      ? state.oss!.officialWebsite
                      : 'https://gvboard.161486.xyz',
                  title: '官网',
                ),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.send),
                title: const Text('联系客服'),
                onTap: () =>
                    _customerService(context, state.oss?.customerService.url),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.password),
                title: const Text('修改密码'),
                onTap: () => _changePassword(context, controller),
              ),
              ListItem(
                leading: const GlyphIcon(AppGlyphs.logout),
                title: const Text('退出登录'),
                onTap: () => _logout(ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _orderSummary(GvboardOrder order) {
    final status = switch (order.status) {
      0 => '待支付',
      1 => '处理中',
      2 => '已取消',
      3 => '已完成',
      _ => '未知状态',
    };
    return '$status  ·  金额：${_money(order.totalAmount)}';
  }

  static String _money(num amount) => (amount / 100).toStringAsFixed(2);

  static Future<void> _changePassword(
    BuildContext context,
    AccountController controller,
  ) async {
    final oldPassword = TextEditingController();
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    await showFormSheet<void>(
      context: context,
      builder: (sheetContext) => CommonScaffold(
        title: '修改密码',
        confirmationAction: IconButtonData(
          glyph: AppGlyphs.check,
          tooltip: '修改密码',
          onPressed: () async {
            if (oldPassword.text.isEmpty || newPassword.text.length < 8) {
              ScaffoldMessenger.of(sheetContext).showSnackBar(
                const SnackBar(content: Text('请填写当前密码，新密码至少 8 位')),
              );
              return;
            }
            if (newPassword.text != confirmPassword.text) {
              ScaffoldMessenger.of(
                sheetContext,
              ).showSnackBar(const SnackBar(content: Text('两次输入的新密码不一致')));
              return;
            }
            try {
              await controller.changePassword(
                oldPassword: oldPassword.text,
                newPassword: newPassword.text,
              );
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
            } on Object catch (error) {
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(
                  sheetContext,
                ).showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          },
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
            top: sheetContext.contentTopPadding,
            bottom: 16 + sheetContext.bottomInset,
          ),
          children: [
            generateSection(
              items: [
                FormRow(
                  title: '当前密码',
                  trailing: FormRowSecretTextField(controller: oldPassword),
                ),
                FormRow(
                  title: '新密码',
                  trailing: FormRowSecretTextField(controller: newPassword),
                ),
                FormRow(
                  title: '确认新密码',
                  trailing: FormRowSecretTextField(controller: confirmPassword),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    oldPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
  }

  static Future<void> _logout(WidgetRef ref) async {
    final profiles = ref.read(profilesProvider);
    for (final profile in profiles) {
      if (profile.label.startsWith('GVBoard ')) {
        await ref
            .read(profilesActionProvider.notifier)
            .deleteProfile(profile.id);
      }
    }
    await ref.read(accountProvider).logout();
  }

  static Future<void> _customerService(
    BuildContext context,
    String? url,
  ) async {
    final target = url == null || url.isEmpty ? defaultCustomerServiceUrl : url;
    await InternalBrowserPage.open(context, target, title: '客服');
  }
}

class _SubscriptionsSection extends StatefulWidget {
  const _SubscriptionsSection({required this.controller, required this.online});

  final AccountController controller;
  final bool online;

  @override
  State<_SubscriptionsSection> createState() => _SubscriptionsSectionState();
}

class _DeferredSection extends StatefulWidget {
  const _DeferredSection({
    required this.title,
    required this.glyph,
    required this.child,
  });

  final String title;
  final Glyph glyph;
  final Widget child;

  @override
  State<_DeferredSection> createState() => _DeferredSectionState();
}

class _DeferredSectionState extends State<_DeferredSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      generateSection(
        items: [
          ListItem(
            leading: GlyphIcon(widget.glyph),
            title: Text(widget.title),
            trailing: GlyphIcon(
              _expanded ? AppGlyphs.chevronUp : AppGlyphs.chevronDown,
            ),
            onTap: () => setState(() => _expanded = !_expanded),
          ),
        ],
      ),
      if (_expanded) widget.child,
    ],
  );
}

class _OrdersSection extends StatefulWidget {
  const _OrdersSection({required this.api});
  final GvboardApi api;

  @override
  State<_OrdersSection> createState() => _OrdersSectionState();
}

class _OrdersSectionState extends State<_OrdersSection> {
  late final Future<List<GvboardOrder>> _future = widget.api.orders();

  @override
  Widget build(BuildContext context) => FutureBuilder<List<GvboardOrder>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const ListItem(title: Text('正在加载订单…'));
      }
      if (snapshot.hasError) {
        return ListItem(title: Text('订单加载失败：${snapshot.error}'));
      }
      final orders = snapshot.data ?? const [];
      if (orders.isEmpty) return const ListItem(title: Text('暂无订单'));
      return generateGroup([
        for (final order in orders.take(10))
          ListItem(
            leading: const GlyphIcon(AppGlyphs.receipt),
            title: Text(order.tradeNo),
            subtitle: Text(AccountView._orderSummary(order)),
          ),
      ]);
    },
  );
}

class _UserStatSection extends StatefulWidget {
  const _UserStatSection({required this.controller});

  final AccountController controller;

  @override
  State<_UserStatSection> createState() => _UserStatSectionState();
}

class _UserStatSectionState extends State<_UserStatSection> {
  late Future<GvboardUserStat> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.dashboardStat();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GvboardUserStat>(
      future: _future,
      builder: (context, snapshot) {
        final stat = snapshot.data;
        if (stat == null) return const SizedBox.shrink();
        return ListItem(
          leading: const GlyphIcon(AppGlyphs.target),
          title: Text('邀请 ${stat.invitees} 人'),
          subtitle: Text(
            '待支付订单 ${stat.pendingOrders} · 未关闭工单 ${stat.openTickets}',
          ),
        );
      },
    );
  }
}

class _InviteSection extends StatefulWidget {
  const _InviteSection({required this.api});

  final GvboardApi api;

  @override
  State<_InviteSection> createState() => _InviteSectionState();
}

class _InviteSectionState extends State<_InviteSection> {
  late Future<GvboardInviteOverview> _overview;
  late Future<List<GvboardCommissionEntry>> _commissions;
  var _commissionPage = 1;
  var _loadingMoreCommissions = false;
  var _hasMoreCommissions = true;

  @override
  void initState() {
    super.initState();
    _overview = widget.api.invite();
    _commissions = widget.api.commissions().then((entries) {
      _hasMoreCommissions = entries.length == 20;
      return entries;
    });
  }

  Future<void> _generateCode() async {
    try {
      final result = await widget.api.generateInviteCode();
      final raw = result['url'] ?? result['link'] ?? result['code'];
      if (raw == null) throw const FormatException('邀请码数据为空');
      await Clipboard.setData(ClipboardData(text: '$raw'));
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('邀请码已复制')));
        setState(() {
          _overview = widget.api.invite();
        });
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _loadMoreCommissions() async {
    if (_loadingMoreCommissions || !_hasMoreCommissions) return;
    setState(() => _loadingMoreCommissions = true);
    try {
      final existing = await _commissions;
      final nextPage = _commissionPage + 1;
      final next = await widget.api.commissions(current: nextPage);
      _commissionPage = nextPage;
      _hasMoreCommissions = next.length == 20;
      if (mounted) {
        setState(() {
          _commissions = Future.value([...existing, ...next]);
        });
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _loadingMoreCommissions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        generateSection(
          title: '邀请与佣金',
          items: [
            FutureBuilder<GvboardInviteOverview>(
              future: _overview,
              builder: (context, snapshot) {
                final value = snapshot.data;
                if (value == null) {
                  return const ListItem(title: Text('正在加载邀请信息…'));
                }
                return ListItem(
                  leading: const GlyphIcon(AppGlyphs.connections),
                  title: Text('邀请人数：${value.invitees}'),
                  subtitle: Text(
                    '佣金比例：${value.commissionRate}% · 累计：${AccountView._money(value.totalCommission)} · 可用：${AccountView._money(value.commissionBalance)} · 待确认：${AccountView._money(value.pendingCommission)}',
                  ),
                );
              },
            ),
            FutureBuilder<GvboardInviteOverview>(
              future: _overview,
              builder: (context, snapshot) {
                final codes = snapshot.data?.codes ?? const [];
                return generateGroup([
                  for (final inviteCode in codes)
                    ListItem(
                      leading: const GlyphIcon(AppGlyphs.key),
                      title: Text(inviteCode.code),
                      subtitle: Text('访问 ${inviteCode.views} 次'),
                      trailing: IconButton(
                        tooltip: '复制邀请码',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: inviteCode.code),
                          );
                        },
                        icon: const GlyphIcon(AppGlyphs.copy),
                      ),
                    ),
                ]);
              },
            ),
            ListItem(
              leading: const GlyphIcon(AppGlyphs.add),
              title: const Text('生成并复制邀请码'),
              onTap: _generateCode,
            ),
          ],
        ),
        FutureBuilder<List<GvboardCommissionEntry>>(
          future: _commissions,
          builder: (context, snapshot) {
            final entries = snapshot.data ?? const [];
            return generateSection(
              title: '佣金明细（${entries.length}）',
              items: [
                for (final entry in entries)
                  ListItem(
                    title: Text(entry.tradeNo),
                    subtitle: Text(
                      '订单 ${AccountView._money(entry.orderAmount)} · ${DateTime.fromMillisecondsSinceEpoch(entry.createdAt * 1000)}',
                    ),
                    trailing: Text('+${AccountView._money(entry.amount)}'),
                  ),
                if (entries.isNotEmpty && _hasMoreCommissions)
                  ListItem(
                    title: Text(_loadingMoreCommissions ? '正在加载…' : '加载更多佣金明细'),
                    onTap: _loadingMoreCommissions
                        ? null
                        : _loadMoreCommissions,
                  ),
                if (snapshot.hasError)
                  ListItem(title: Text('佣金明细加载失败：${snapshot.error}')),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SubscriptionsSectionState extends State<_SubscriptionsSection> {
  late Future<List<GvboardSubscription>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.controller.fetchSubscriptions();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.controller.fetchSubscriptions();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AccountState>(
      valueListenable: widget.controller,
      builder: (context, _, _) => FutureBuilder<List<GvboardSubscription>>(
        future: _future,
        builder: (context, snapshot) {
          final subscriptions =
              snapshot.data ?? widget.controller.subscriptions;
          if (snapshot.connectionState != ConnectionState.done &&
              subscriptions.isEmpty) {
            return const ListItem(
              leading: GlyphIcon(AppGlyphs.profiles),
              title: Text('正在加载订阅…'),
            );
          }
          return generateGroup([
            if (subscriptions.isNotEmpty)
              ListItem(
                leading: const GlyphIcon(AppGlyphs.receipt),
                title: Text(
                  '当前：${widget.controller.selectedSubscription?.name ?? '未选择'}',
                ),
              ),
            if (subscriptions.isEmpty) const ListItem(title: Text('暂无订阅信息')),
            for (final subscription in subscriptions)
              ListItem(
                title: Text(subscription.name),
                subtitle: Text(_summary(subscription)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.controller.selectedSubscription?.id ==
                        subscription.id)
                      const SelectionBadge(),
                    IconButton(
                      tooltip: '订阅详情',
                      onPressed: () => _showDetails(subscription),
                      icon: const GlyphIcon(AppGlyphs.info),
                    ),
                    if (widget.online)
                      IconButton(
                        tooltip: '重置订阅链接',
                        onPressed: () => _reset(subscription),
                        icon: const GlyphIcon(AppGlyphs.reset),
                      ),
                  ],
                ),
                onTap: widget.online
                    ? () =>
                          widget.controller.selectSubscription(subscription.id)
                    : null,
              ),
            ListItem(
              leading: const GlyphIcon(AppGlyphs.refresh),
              title: const Text('刷新订阅'),
              onTap: widget.online ? _refresh : null,
            ),
          ]);
        },
      ),
    );
  }

  String _summary(GvboardSubscription item) {
    final status = item.banned
        ? '已停用'
        : item.isExpired
        ? '已过期'
        : item.expiredAt == null
        ? '长期有效'
        : '到期：${DateTime.fromMillisecondsSinceEpoch(item.expiredAt! * 1000)}';
    final used = item.upload + item.download;
    return '$status\n上行 ${_bytes(item.upload)} · 下行 ${_bytes(item.download)}\n已用 ${_bytes(used)} / ${_bytes(item.transferEnable)} · 在线设备 ${item.aliveIp}/${item.deviceLimit ?? '不限'}';
  }

  String _bytes(int value) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var amount = value.toDouble();
    var unit = 0;
    while (amount >= 1024 && unit < units.length - 1) {
      amount /= 1024;
      unit++;
    }
    return '${amount.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  Future<void> _showDetails(GvboardSubscription subscription) async {
    late final GvboardSubscription detail;
    try {
      detail = widget.online
          ? await widget.controller.fetchSubscription(subscription.id) ??
                subscription
          : subscription;
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(detail.name),
        content: Text(_summary(detail)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _reset(GvboardSubscription subscription) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置订阅链接？'),
        content: const Text('旧链接将失效，需要重新同步订阅。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.controller.resetSubscriptionSecurity(subscription.id);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('订阅链接已重置')));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}
