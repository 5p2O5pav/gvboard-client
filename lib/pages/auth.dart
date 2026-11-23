import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/constant.dart';
import '../account/account.dart';
import '../common/package.dart';
import '../common/l10n_labels.dart';
import '../gvboard/gvboard.dart';
import '../l10n/l10n.dart';
import '../oss/oss.dart';
import 'internal_browser.dart';
import '../state.dart';
import '../ui/icons/icons.dart';
import '../ui/ui.dart';
import '../providers/providers.dart';

enum _AuthMode { login, register, reset }

class AuthGate extends ConsumerWidget {
  const AuthGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.read(accountProvider);
    return ValueListenableBuilder<AccountState>(
      valueListenable: account,
      builder: (context, state, _) {
        if (state.isReady) {
          return Stack(
            children: [
              child,
              PositionedDirectional(
                top: 0,
                start: 12,
                end: 12,
                child: _UpdateBanner(config: state.oss),
              ),
              if (state.isOffline)
                const PositionedDirectional(
                  top: 8,
                  start: 12,
                  end: 12,
                  child: _OfflineBanner(),
                ),
            ],
          );
        }
        return AuthPage(state: state);
      },
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.config});

  final OssConfig? config;

  @override
  Widget build(BuildContext context) {
    final update = config?.clientUpdate;
    if (update == null ||
        update.latestVersion.isEmpty ||
        update.updateUrl.isEmpty) {
      return const SizedBox.shrink();
    }
    if (compareVersions(
          globalState.packageInfo.version,
          update.latestVersion,
        ) >=
        0) {
      return const SizedBox.shrink();
    }
    return MaterialBanner(
      content: Text('发现新版本 ${update.latestVersion}'),
      leading: const GlyphIcon(AppGlyphs.refresh),
      actions: [
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse(update.updateUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('打开更新地址'),
        ),
      ],
    );
  }
}

class _OfflineBanner extends StatefulWidget {
  const _OfflineBanner();

  @override
  State<_OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<_OfflineBanner> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return const MaterialBanner(
      content: Text('当前无法连接服务器，已进入离线模式。当前显示的是上次缓存的节点数据'),
      leading: GlyphIcon(AppGlyphs.warning),
      actions: [SizedBox.shrink()],
    );
  }
}

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({required this.state, super.key});

  final AccountState state;

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  _AuthMode _mode = _AuthMode.login;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _inviteCode = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _sending = false;
  bool _hidePassword = true;
  bool _settingsFailed = false;
  ({List<String> suffixes, bool emailCode, bool inviteRequired})? _settings;
  String? _suffix;

  String _t(String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  String get _address {
    final text = _email.text.trim();
    return text.isEmpty || text.contains('@') || _suffix == null
        ? text
        : '$text@$_suffix';
  }

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void didUpdateWidget(AuthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.state.oss, widget.state.oss)) _loadSettings();
  }

  Future<void> _loadSettings() async {
    final config = widget.state.oss;
    if (config == null || config.apis.isEmpty) return;
    setState(() {
      _settings = null;
      _settingsFailed = false;
      _suffix = null;
    });
    try {
      final settings = await GvboardApi(config).registrationOptions();
      if (!mounted || !identical(config, widget.state.oss)) return;
      setState(() {
        _settings = settings;
        _suffix = settings.suffixes.firstOrNull;
      });
    } on Exception {
      if (mounted && identical(config, widget.state.oss)) {
        setState(() => _settingsFailed = true);
      }
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    _inviteCode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_address.contains('@') || _password.text.isEmpty) {
      setState(
        () => _error = _t('请输入有效邮箱和密码', 'Enter a valid email and password'),
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final controller = ref.read(accountProvider);
      switch (_mode) {
        case _AuthMode.login:
          await controller.login(_address, _password.text);
        case _AuthMode.register:
          await controller.register(
            _address,
            _password.text,
            inviteCode: _inviteCode.text,
            emailCode: _settings?.emailCode == true ? _code.text.trim() : '',
          );
        case _AuthMode.reset:
          if (_code.text.trim().isEmpty) {
            throw const FormatException('请输入邮箱验证码');
          }
          await controller.resetPassword(
            email: _address,
            password: _password.text,
            code: _code.text,
          );
          if (mounted) setState(() => _mode = _AuthMode.login);
      }
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendCode() async {
    if (!_address.contains('@')) {
      setState(() => _error = '请输入邮箱');
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(accountProvider)
          .sendEmailCode(
            _address,
            _mode == _AuthMode.register ? 'register' : 'reset',
          );
      if (mounted) setState(() => _error = '验证码已发送');
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = widget.state.oss?.brand.name ?? 'FlClash';
    final restoring =
        widget.state.status == AccountStatus.authenticating &&
        widget.state.remainingSeconds != null;
    final colors = context.colorScheme;
    final login = _mode == _AuthMode.login;
    final register = _mode == _AuthMode.register;
    final title = login
        ? _t('登录', 'Sign in')
        : register
        ? _t('创建账号', 'Create account')
        : _t('找回密码', 'Recover password');
    final website = widget.state.oss?.officialWebsite ?? '';
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.45, -0.55),
            radius: 1.05,
            colors: [
              Color.alphaBlend(
                colors.primary.withValues(alpha: 0.30),
                colors.surface,
              ),
              colors.surfaceContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                          if (!login)
                            IconButton(
                              tooltip: _t('返回登录', 'Back to sign in'),
                              onPressed: _busy
                                  ? null
                                  : () => _changeMode(_AuthMode.login),
                              icon: const GlyphIcon(AppGlyphs.arrowBack),
                            ),
                          _AuthToolbarButton(
                            width: 128,
                            glyph: AppGlyphs.send,
                            label: _t('联系客服', 'Support'),
                            onPressed: _openCustomerService,
                          ),
                          _AuthToolbarButton(
                            width: 128,
                            glyph: AppGlyphs.language,
                            label: _t('访问官网', 'Website'),
                            onPressed: website.isEmpty
                                ? null
                                : () => InternalBrowserPage.open(
                                    context,
                                    website,
                                    title: _t('官网', 'Website'),
                                  ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: _t('选择语言', 'Language'),
                            onSelected: (locale) => ref
                                .read(appSettingProvider.notifier)
                                .update(
                                  (state) => state.copyWith(
                                    locale: locale.isEmpty ? null : locale,
                                  ),
                                ),
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: '',
                                child: Text(_t('跟随系统', 'System default')),
                              ),
                              for (final locale
                                  in AppLocalizations.delegate.supportedLocales)
                                PopupMenuItem(
                                  value: locale.toString(),
                                  child: Text(locale.label),
                                ),
                            ],
                            child: const _AuthToolbarSurface(
                              width: 48,
                              child: GlyphIcon(AppGlyphs.language, size: 18),
                            ),
                          ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (login) ...[
                              Center(
                                child: DecoratedBox(
                                  decoration: ShapeDecoration(
                                    color: colors.primary,
                                    shape: AppShape.circle,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: GlyphIcon(
                                      AppGlyphs.bolt,
                                      size: 36,
                                      fill: 1,
                                      color: colors.onPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                            ],
                            Text(
                              login ? brand : title,
                              textAlign: TextAlign.center,
                              style: AppTextStyle.title1
                                  .of(context, emphasized: true)
                                  .copyWith(color: colors.primary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              login
                                  ? _t('欢迎使用 $brand', 'Welcome to $brand')
                                  : register
                                  ? _t('加入我们，开始使用服务', 'Join us and get started')
                                  : _t(
                                      '重置您的账户密码',
                                      'Reset your account password',
                                    ),
                              textAlign: TextAlign.center,
                              style: context.listSubtitleStyle,
                            ),
                            const SizedBox(height: 28),
                            Material(
                              color: context.raisedSurfaceLevel.colorOf(colors),
                              shape: AppShape.xl,
                              elevation: 3,
                              child: Padding(
                                padding: const EdgeInsets.all(22),
                                child:
                                    restoring ||
                                        widget.state.status ==
                                            AccountStatus.loading
                                    ? Column(
                                        spacing: 12,
                                        children: [
                                          Text(
                                            _t(
                                              '正在恢复登录…',
                                              'Restoring your session…',
                                            ),
                                          ),
                                          const LinearProgressIndicator(),
                                        ],
                                      )
                                    : _form(title, login, register),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(String title, bool login, bool register) {
    final error = _error ?? widget.state.error;
    final canSubmit = !_busy && _addressAvailable(register);
    return AutofillGroup(
      child: Column(
        spacing: 14,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (login) ...[
            Text(
              title,
              style: AppTextStyle.title1
                  .of(context, emphasized: true)
                  .copyWith(color: context.colorScheme.primary),
            ),
            Text(
              _t('欢迎回来，请登录您的账号', 'Welcome back. Sign in to your account.'),
              style: context.listSubtitleStyle,
            ),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              prefixIcon: const GlyphIcon(AppGlyphs.account),
              labelText: _t('邮箱', 'Email'),
              suffixIcon: _suffix == null
                  ? null
                  : PopupMenuButton<String>(
                      tooltip: _t('选择邮箱后缀', 'Email domain'),
                      onSelected: (value) => setState(() => _suffix = value),
                      itemBuilder: (_) => [
                        for (final suffix in _settings!.suffixes.toSet())
                          PopupMenuItem(value: suffix, child: Text('@$suffix')),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '@$_suffix',
                              style: context.listCaptionStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const GlyphIcon(AppGlyphs.chevronDown, size: 14),
                          ],
                        ),
                      ),
                    ),
              suffixIconConstraints: const BoxConstraints(
                maxWidth: 135,
                minHeight: 44,
              ),
            ),
          ),
          TextField(
            controller: _password,
            obscureText: _hidePassword,
            autocorrect: false,
            autofillHints: login
                ? const [AutofillHints.password]
                : const [AutofillHints.newPassword],
            decoration: InputDecoration(
              prefixIcon: const GlyphIcon(AppGlyphs.lock),
              labelText: login || register
                  ? _t('密码', 'Password')
                  : _t('新密码', 'New password'),
              suffixIcon: IconButton(
                tooltip: _hidePassword
                    ? _t('显示密码', 'Show password')
                    : _t('隐藏密码', 'Hide password'),
                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                icon: GlyphIcon(
                  _hidePassword ? AppGlyphs.eye : AppGlyphs.eyeOff,
                ),
              ),
            ),
          ),
          if (register)
            TextField(
              controller: _inviteCode,
              decoration: InputDecoration(
                prefixIcon: const GlyphIcon(AppGlyphs.key),
                labelText: _settings?.inviteRequired == true
                    ? _t('邀请码', 'Invite code')
                    : _t('邀请码（可选）', 'Invite code (optional)'),
              ),
            ),
          if ((!login && !register) ||
              (register && _settings?.emailCode == true))
            TextField(
              controller: _code,
              decoration: InputDecoration(
                labelText: _t('邮箱验证码', 'Email code'),
                suffixIcon: TextButton(
                  onPressed: _sending || _busy ? null : _sendCode,
                  child: Text(_t('获取验证码', 'Send code')),
                ),
              ),
            ),
          if (register && _settings == null)
            if (_settingsFailed)
              TextButton(
                onPressed: _loadSettings,
                child: Text(
                  _t(
                    '注册设置加载失败，点击重试',
                    'Could not load registration settings. Retry',
                  ),
                ),
              )
            else
              const LinearProgressIndicator(),
          if (error != null)
            Text(
              error,
              style: context.listCaptionStyle.copyWith(
                color: context.colorScheme.error,
              ),
            ),
          FilledButton(
            onPressed: canSubmit ? _submit : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _busy
                    ? _t('处理中…', 'Working…')
                    : login
                    ? title
                    : register
                    ? _t('注册', 'Register')
                    : _t('重置密码', 'Reset password'),
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              if (login) ...[
                FilledButton.tonal(
                  onPressed: _busy
                      ? null
                      : () => _changeMode(_AuthMode.register),
                  child: Text(_t('注册账号', 'Create account')),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _changeMode(_AuthMode.reset),
                  child: Text(_t('忘记密码？', 'Forgot password?')),
                ),
              ] else
                TextButton(
                  onPressed: _busy ? null : () => _changeMode(_AuthMode.login),
                  child: Text(_t('返回登录', 'Back to sign in')),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _addressAvailable(bool register) => !register || _settings != null;

  void _changeMode(_AuthMode mode) => setState(() {
    _mode = mode;
    _error = null;
    _code.clear();
    _hidePassword = true;
  });

  Future<void> _openCustomerService() async {
    final configuredUrl = widget.state.oss?.customerService.url;
    final url = configuredUrl == null || configuredUrl.isEmpty
        ? defaultCustomerServiceUrl
        : configuredUrl;
    await InternalBrowserPage.open(context, url, title: _t('客服', 'Support'));
  }
}

class _AuthToolbarButton extends StatelessWidget {
  const _AuthToolbarButton({
    required this.width,
    required this.glyph,
    required this.label,
    required this.onPressed,
  });

  final double width;
  final Glyph glyph;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => _AuthToolbarSurface(
    width: width,
    onPressed: onPressed,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 6,
      children: [
        GlyphIcon(glyph, size: 18),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.listSubtitleStyle,
          ),
        ),
      ],
    ),
  );
}

class _AuthToolbarSurface extends StatelessWidget {
  const _AuthToolbarSurface({
    required this.width,
    required this.child,
    this.onPressed,
  });

  final double width;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final surface = Material(
      color: colors.secondaryContainer,
      shape: AppShape.md,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: 34,
        child: Center(child: child),
      ),
    );
    if (onPressed == null) return surface;
    return InkWell(
      customBorder: AppShape.md,
      onTap: onPressed,
      child: surface,
    );
  }
}
