import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/account/account.dart';
import 'package:fl_clash/gvboard/gvboard.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/window.dart';
import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:fl_clash/manager/manager.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/ui/ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/pages.dart';

Widget buildManagerStack({
  required bool isDesktop,
  required Future<void> Function(List<ConnectivityResult> results)
  onConnectivityChanged,
  Stream<ProcessSignal>? terminateSignals,
  required Widget child,
}) {
  final platformApp = isDesktop
      ? WindowHeaderContainer(child: child)
      : VpnManager(child: child);
  final state = AppStateManager(
    child: CoreManager(
      child: ConnectivityManager(
        onConnectivityChanged: onConnectivityChanged,
        child: platformApp,
      ),
    ),
  );
  final platformState = isDesktop
      ? WindowManager(
          terminateSignals: terminateSignals,
          child: TrayManager(
            child: HotKeyManager(child: ProxyManager(child: state)),
          ),
        )
      : AndroidManager(child: TileManager(child: state));
  return LocaleManager(
    child: StatusManager(child: ThemeManager(child: platformState)),
  );
}

class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => ApplicationState();
}

class ApplicationState extends ConsumerState<Application> {
  Timer? _autoUpdateProfilesTaskTimer;
  AccountController? _accountController;
  AccountState? _lastAccountState;
  GvboardApi? _syncedGvboardApi;
  int? _lastSelectedSubscriptionId;
  String _lastSubscriptionSignature = '';
  bool _syncingGvboardSubscriptions = false;
  bool _syncGvboardSubscriptionsAgain = false;
  bool _preHasVpn = false;
  // Windows can only watch SIGINT and SIGHUP.
  final _terminateSignals = system.isDesktop && !system.isWindows
      ? ProcessSignal.sigterm.watch()
      : null;

  @override
  void initState() {
    super.initState();
    SystemNavigator.setFrameworkHandlesBack(true);
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (globalState.navigatorKey.currentContext != null) {
        await bootstrap.attach();
        _watchGvboardAccount();
      } else {
        exit(0);
      }
      _autoUpdateProfilesTask();
      _initLink();
      if (!safeModeBuild) {
        unawaited(app?.initShortcuts());
      }
    });
  }

  void _watchGvboardAccount() {
    final account = ref.read(accountProvider);
    _accountController = account;
    _lastAccountState = account.state;
    _lastSelectedSubscriptionId = account.selectedSubscriptionId;
    _lastSubscriptionSignature = _subscriptionSignature(account);
    account.addListener(_onGvboardAccountChanged);
    unawaited(_syncGvboardSubscriptions());
  }

  void _onGvboardAccountChanged() {
    final account = _accountController;
    if (account == null) return;
    final selectionChanged =
        _lastSelectedSubscriptionId != account.selectedSubscriptionId;
    _lastSelectedSubscriptionId = account.selectedSubscriptionId;
    final subscriptionChanged =
        _lastSubscriptionSignature != _subscriptionSignature(account);
    _lastSubscriptionSignature = _subscriptionSignature(account);
    if (identical(_lastAccountState, account.state)) {
      if (selectionChanged || subscriptionChanged) {
        unawaited(_syncGvboardSubscriptions());
      }
      return;
    }
    _lastAccountState = account.state;
    if (account.state.status == AccountStatus.online &&
        !identical(_syncedGvboardApi, account.api)) {
      unawaited(_syncGvboardSubscriptions());
    }
  }

  String _subscriptionSignature(AccountController account) => account
      .subscriptions
      .map((item) => '${item.id}:${item.subscribeUrl}')
      .join('|');

  Future<void> _syncGvboardSubscriptions() async {
    if (_syncingGvboardSubscriptions) {
      _syncGvboardSubscriptionsAgain = true;
      return;
    }
    final account = ref.read(accountProvider);
    if (account.state.status != AccountStatus.online) return;
    final api = account.api;
    if (api == null) return;
    _syncingGvboardSubscriptions = true;
    _syncedGvboardApi = api;
    try {
      final subscriptions = await account.fetchSubscriptions();
      final selected = account.selectedSubscription;
      final ordered = [
        ...?(selected == null ? null : <GvboardSubscription>[selected]),
        ...subscriptions.where((item) => item.id != selected?.id),
      ];
      for (final item in ordered) {
        final url = item.subscribeUrl;
        if (url.isEmpty || item.banned || item.isExpired) continue;
        final label = 'GVBoard ${item.id}';
        Profile? existing;
        for (final candidate in ref.read(profilesProvider)) {
          if (candidate.label == label) {
            existing = candidate;
            break;
          }
        }
        final profile =
            existing?.copyWith(url: url, autoUpdate: true) ??
            Profile.normal(label: label, url: url);
        ref.read(profilesActionProvider.notifier).putProfile(profile);
        try {
          await ref
              .read(profilesActionProvider.notifier)
              .updateProfile(profile);
          await account.fetchSubscription(item.id);
          ref.read(currentProfileIdProvider.notifier).value = profile.id;
          ref
              .read(setupActionProvider.notifier)
              .applyProfileDebounce(silence: true);
          return;
        } on Object {
          continue;
        }
      }
    } on Object catch (error) {
      commonPrint.log(
        'GVBoard subscription sync failed: $error',
        logLevel: LogLevel.warning,
      );
    } finally {
      _syncingGvboardSubscriptions = false;
      if (_syncGvboardSubscriptionsAgain) {
        _syncGvboardSubscriptionsAgain = false;
        unawaited(_syncGvboardSubscriptions());
      }
    }
  }

  void _initLink() {
    linkManager.initAppLinksListen((url) async {
      if (dedicatedClientBuild) return;
      unawaited(window?.show());
      final message = currentAppLocalizations.createProfileFromUrlTip(url);
      final parts = message.split(url);
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.addProfile,
        message: TextSpan(
          children: [
            TextSpan(text: parts.first),
            TextSpan(
              text: url,
              style: TextStyle(
                color: context.colorScheme.primary,
                decoration: TextDecoration.underline,
                decorationColor: context.colorScheme.primary,
              ),
            ),
            if (parts.length > 1) TextSpan(text: parts.last),
          ],
        ),
      );
      if (res != true) return;
      unawaited(
        ref.read(profilesActionProvider.notifier).addProfileFromLink(url),
      );
    });
  }

  void _autoUpdateProfilesTask() {
    _autoUpdateProfilesTaskTimer = Timer(const Duration(minutes: 20), () async {
      await ref.read(profilesActionProvider.notifier).autoUpdateProfiles();
      await ref.read(resourcesActionProvider.notifier).autoUpdate();
      if (!mounted) {
        return;
      }
      _autoUpdateProfilesTask();
    });
  }

  Future<void> _handleConnectivityChanged(
    List<ConnectivityResult> results,
  ) async {
    commonPrint.log('connectivityChanged ${results.toString()}');
    unawaited(systemDnsCoordinator?.resync() ?? Future.value());
    unawaited(ref.read(systemActionProvider.notifier).updateLocalIp());
    final hasVpn = results.contains(ConnectivityResult.vpn);
    if (_preHasVpn == hasVpn) {
      ref.read(routeTrackerProvider.notifier).bumpHostEpoch();
      // Android's NetworkObserver tells the Core about a new network itself.
      if (system.isDesktop) {
        debouncer.call(
          FunctionTag.clearDnsCache,
          ref.read(coreActionProvider.notifier).clearDnsCacheOnNetworkChange,
          duration: const Duration(milliseconds: 200),
        );
      }
    }
    _preHasVpn = hasVpn;
    if (results.isNotEmpty) {
      unawaited(ref.read(accountProvider).trySilentRelogin());
    }
  }

  @override
  Widget build(context) {
    return Consumer(
      builder: (_, ref, child) {
        final locale = ref.watch(
          appSettingProvider.select((state) => state.locale),
        );
        final themeProps = ref.watch(themeSettingProvider);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: globalState.navigatorKey,
          onNavigationNotification: (_) => true,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            AppUiLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          builder: (context, child) {
            return ThemeCrossFade(
              child: buildManagerStack(
                isDesktop: system.isDesktop,
                onConnectivityChanged: _handleConnectivityChanged,
                terminateSignals: _terminateSignals,
                child: RemoteFocusAdapter(
                  enabled: system.isTV,
                  floatingKeyboard: app?.floatingKeyboard,
                  child: child!,
                ),
              ),
            );
          },
          scrollBehavior: const BaseScrollBehavior(),
          title: appName,
          locale: getLocaleForString(locale),
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          themeMode: themeProps.themeMode,
          theme: watchAppTheme(ref, Brightness.light),
          darkTheme: watchAppTheme(ref, Brightness.dark),
          themeAnimationStyle: AnimationStyle.noAnimation,
          home: KeyboardInsetHold(child: child!),
        );
      },
      child: const AuthGate(child: HomePage()),
    );
  }

  @override
  void dispose() {
    _accountController?.removeListener(_onGvboardAccountChanged);
    linkManager.destroy();
    _autoUpdateProfilesTaskTimer?.cancel();
    super.dispose();
  }
}
