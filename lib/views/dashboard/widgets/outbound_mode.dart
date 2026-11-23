import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/ui/icons/icons.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:fl_clash/views/dashboard/layout.dart';
import 'package:fl_clash/views/dashboard/style.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'card.dart';

Glyph _glyphOf(Mode mode) => switch (mode) {
  Mode.rule => AppGlyphs.rules,
  Mode.global => AppGlyphs.proxies,
  Mode.direct => AppGlyphs.target,
};

void _changeMode(WidgetRef ref, Mode mode) {
  if (ref.read(patchClashConfigProvider).mode == mode) return;
  ref.read(setupActionProvider.notifier).changeMode(mode);
}

Future<void> _showModeInfo(BuildContext context, bool global) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(global ? '全局模式' : '规则模式'),
      content: Text(
        global
            ? '所有对外访问全部使用vpn节点，确保国外网站和app一定会使用vpn节点进行访问。缺点是大概率导致 国内网站和app 网络异常或无网络。'
            : '使用客户端默认分流规则，访问国内网站和app时，自动使用国内网络；访问国外网站和app时，自动使用vpn节点。注意，默认分流规则不保证绝对准确。',
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

class _OutboundModeInfoButton extends StatelessWidget {
  const _OutboundModeInfoButton({required this.global});

  final bool global;

  @override
  Widget build(BuildContext context) => IconButton(
    constraints: const BoxConstraints.tightFor(width: 24, height: 24),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.standard,
    tooltip: global ? '全局模式说明' : '规则模式说明',
    onPressed: () => _showModeInfo(context, global),
    icon: Text(
      'ⓘ',
      style: AppTextStyle.custom(
        context,
        size: 19,
        leading: 19,
        weight: FontWeight.w700,
      ).copyWith(
        color: context.colorScheme.brightness == Brightness.dark
            ? const Color(0xFFFBBF24)
            : const Color(0xFFD97706),
      ),
    ),
  );
}

class OutboundModeCard extends ConsumerWidget {
  const OutboundModeCard({super.key});

  static const _outer = 26.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final tone = DashboardColors.of(context).tone;
    final style = AppTextStyle.footnote.of(context, emphasized: true);
    final modes = Mode.values.where((item) => item != Mode.direct).toList();
    return DashboardCard(
      semanticLabel: context.appLocalizations.outboundMode,
      child: Column(
        children: [
          DashboardCardHeader(
            glyph: AppGlyphs.split,
            title: context.appLocalizations.outboundMode,
            leading: [_OutboundModeInfoButton(global: mode == Mode.global)],
          ),
          const SizedBox(height: 12),
          DashboardConnectedGroup(
            children: [
              for (final (index, item) in modes.indexed)
                Expanded(
                  child: DashboardConnectedButton(
                    selected: item == mode,
                    first: index == 0,
                    last: index == modes.length - 1,
                    outer: _outer,
                    inner: 12,
                    background: tone,
                    semanticLabel: item.label,
                    onTap: () => _changeMode(ref, item),
                    builder: (foreground) => SizedBox(
                      height: 52,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 2,
                        children: [
                          GlyphIcon(
                            _glyphOf(item),
                            size: 18,
                            color: foreground,
                          ),
                          Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(color: foreground),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The desktop control row's mode switch; its buttons sit as far in from the
/// card's ends as from its edges so their corners stay concentric.
class OutboundModeBar extends ConsumerWidget {
  const OutboundModeBar({super.key});

  static const _inset = 8.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final density = DashboardDensityScope.of(context);
    final mode = ref.watch(
      patchClashConfigProvider.select((state) => state.mode),
    );
    final appLocalizations = context.appLocalizations;
    final outer = dashboardCardRadius(density) - _inset;
    final style = AppTextStyle.subheadline.of(context, emphasized: true);
    final modes = Mode.values.where((item) => item != Mode.direct).toList();
    return DashboardCard(
      semanticLabel: appLocalizations.outboundMode,
      padding: EdgeInsetsDirectional.fromSTEB(
        dashboardCardPadding(density).left,
        _inset,
        _inset,
        _inset,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          spacing: 16,
          children: [
            GlyphIcon(
              AppGlyphs.split,
              size: 18,
              color: context.colorScheme.onSurfaceVariant,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth / 4),
              child: Text(
                appLocalizations.outboundMode,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashboardText.cardTitle(context),
              ),
            ),
            _OutboundModeInfoButton(global: mode == Mode.global),
            Expanded(
              child: DashboardConnectedGroup(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, item) in modes.indexed)
                    Expanded(
                      child: DashboardConnectedButton(
                        selected: item == mode,
                        first: index == 0,
                        last: index == modes.length - 1,
                        outer: outer,
                        inner: 10,
                        background: DashboardColors.of(context).tone,
                        semanticLabel: item.label,
                        onTap: () => _changeMode(ref, item),
                        builder: (foreground) => Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          spacing: 6,
                          children: [
                            GlyphIcon(
                              _glyphOf(item),
                              size: 18,
                              color: foreground,
                            ),
                            Flexible(
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style.copyWith(color: foreground),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
