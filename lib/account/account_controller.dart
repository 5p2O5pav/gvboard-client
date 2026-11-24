import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../gvboard/gvboard.dart';
import '../oss/oss.dart';
import 'account_state.dart';
import 'credential_store.dart';

class AccountController extends ValueNotifier<AccountState> {
  AccountController({
    CredentialStore? credentials,
    OssRepository? ossRepository,
  }) : _credentials = credentials ?? CredentialStore(),
       _ossRepository = ossRepository ?? OssRepository(),
       super(const AccountState(status: AccountStatus.loading));

  final CredentialStore _credentials;
  final OssRepository _ossRepository;
  List<OssConfig> _configs = const [];
  GvboardApi? _api;
  bool _initialized = false;
  bool _silentRetrying = false;
  bool _silentRetryExhausted = false;
  bool _onlineAttemptActive = false;
  List<GvboardSubscription> _subscriptions = const [];
  Future<GvboardUserStat>? _dashboardStatFuture;
  String? _dashboardStatEmail;
  int? _selectedSubscriptionId;

  AccountState get state => value;
  OssConfig? get oss => value.oss;
  GvboardApi? get api => _api;
  List<GvboardSubscription> get subscriptions => _subscriptions;
  int? get selectedSubscriptionId => _selectedSubscriptionId;

  Future<GvboardUserStat> dashboardStat() async {
    final credentials = await _credentials.read();
    final email = credentials?.email ?? '';
    if (_dashboardStatEmail != email) {
      _dashboardStatEmail = email;
      _dashboardStatFuture = _fetchDashboardStat(email);
    }
    return _dashboardStatFuture!;
  }

  Future<GvboardUserStat> _fetchDashboardStat(String email) async {
    final preferences = await SharedPreferences.getInstance();
    final key = 'gvboard.dashboard_stat.$email';
    final cached = preferences.getString(key);
    GvboardUserStat? cachedStat;
    if (cached != null) {
      try {
        cachedStat = GvboardUserStat.fromJson(
          (jsonDecode(cached) as Map).cast<String, dynamic>(),
        );
      } on Object {
        await preferences.remove(key);
      }
    }
    try {
      try {
        final stat = await requireApi().userStat();
        await preferences.setString(key, jsonEncode(stat.toJson()));
        return stat;
      } on Object {
        _dashboardStatFuture = null;
        rethrow;
      }
    } on Object {
      if (cachedStat != null) return cachedStat;
      rethrow;
    }
  }

  GvboardSubscription? get selectedSubscription {
    final selected = _selectedSubscriptionId;
    for (final item in _subscriptions) {
      if (item.id == selected) return item;
    }
    for (final item in _subscriptions) {
      if (item.isPrimary) return item;
    }
    return _subscriptions.isEmpty ? null : _subscriptions.first;
  }

  Future<List<GvboardSubscription>> fetchSubscriptions() async {
    final api = _api;
    if (api == null || state.isOffline) {
      return _subscriptions;
    }
    try {
      final items = (await api.subscriptions())
          .where((item) => item.id > 0)
          .toList();
      await _saveSubscriptions(items);
      return items;
    } on Object {
      return _subscriptions;
    }
  }

  Future<GvboardSubscription?> fetchSubscription(int id) async {
    final api = requireApi();
    final item = await api.subscription(id);
    _subscriptions = [
      for (final current in _subscriptions)
        if (current.id != item.id) current,
      item,
    ];
    await _saveSubscriptions(_subscriptions);
    return item;
  }

  Future<void> selectSubscription(int id) async {
    if (!_subscriptions.any((item) => item.id == id)) return;
    _selectedSubscriptionId = id;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_selectedSubscriptionKey, id);
    notifyListeners();
  }

  Future<GvboardSubscription?> resetSubscriptionSecurity(int id) async {
    final url = await requireApi().resetSubscriptionSecurity(id);
    GvboardSubscription? existing;
    for (final item in _subscriptions) {
      if (item.id == id) {
        existing = item;
        break;
      }
    }
    if (existing == null) return null;
    final item = GvboardSubscription(
      id: existing.id,
      planId: existing.planId,
      planName: existing.planName,
      name: existing.name,
      isPrimary: existing.isPrimary,
      transferEnable: existing.transferEnable,
      upload: existing.upload,
      download: existing.download,
      deviceLimit: existing.deviceLimit,
      speedLimit: existing.speedLimit,
      expiredAt: existing.expiredAt,
      aliveIp: existing.aliveIp,
      subscribeUrl: url,
      banned: existing.banned,
      allowNewPeriod: existing.allowNewPeriod,
    );
    _subscriptions = [
      for (final current in _subscriptions)
        if (current.id != item.id) current,
      item,
    ];
    await _saveSubscriptions(_subscriptions);
    notifyListeners();
    return item;
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await requireApi().changePassword(
      oldPassword: oldPassword,
      newPassword: newPassword,
    );
    await _credentials.updatePassword(newPassword);
    _api = null;
    _setState(
      AccountState(status: AccountStatus.unauthenticated, oss: state.oss),
    );
  }

  Future<void> trySilentRelogin() async {
    if (_onlineAttemptActive ||
        _silentRetrying ||
        _silentRetryExhausted ||
        !state.isOffline) {
      return;
    }
    final config = oss;
    final credentials = await _credentials.read();
    if (config == null || credentials == null) return;
    _silentRetrying = true;
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final api = _createApi(config);
          final result = await api
              .login(credentials.email, credentials.password)
              .timeout(const Duration(seconds: 30));
          api.token = result.token;
          final user = await api.userInfo().timeout(
            const Duration(seconds: 30),
          );
          await _finishRestore(api, config, user, credentials);
          return;
        } on Object {
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
        }
      }
    } finally {
      _silentRetrying = false;
      if (state.isOffline) _silentRetryExhausted = true;
    }
  }

  GvboardApi requireApi() {
    final api = _api;
    if (api == null) throw const GvboardApiException('当前未连接 GVBoard');
    return api;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final credentials = await _credentials.read();
    try {
      // Restore local state first while refreshing OSS in the background.
      _configs = await _ossRepository.loadCached();
      if (_configs.isEmpty) {
        // A first-time user has no local state, so a bundled/remote config is
        // required before the login page can be shown.
        _configs = await _ossRepository.loadBundledOrCached();
      }
      if (_configs.isEmpty) throw const FormatException('没有可用的 OSS 配置');
      final config = _preferredConfig(_configs, credentials?.ossId);
      if (credentials == null) {
        _setState(
          AccountState(status: AccountStatus.unauthenticated, oss: config),
        );
        unawaited(_refreshOss());
        return;
      }
      await _loadSubscriptions(credentials.email);
      final cachedUser = await _loadCachedUser(credentials.email);
      final canStartOffline = _offlineAllowed(config, credentials.lastOnlineAt);
      _setState(
        AccountState(
          status: canStartOffline ? AccountStatus.offline : AccountStatus.loading,
          oss: config,
          user: cachedUser,
          error: canStartOffline ? '正在同步最新数据……' : null,
        ),
      );
      _startBackgroundSync(_configs, credentials);
    } on Object catch (error) {
      _setState(
        AccountState(status: AccountStatus.unauthenticated, error: '$error'),
      );
    }
  }

  OssConfig _preferredConfig(List<OssConfig> configs, String? ossId) {
    for (final config in configs) {
      if (config.ossId == ossId) return config;
    }
    return configs.first;
  }

  bool _offlineAllowed(OssConfig config, int? lastOnlineAt) {
    return config.offline.enabled &&
        lastOnlineAt != null &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(lastOnlineAt),
            ) <=
            Duration(days: config.offline.maxDays);
  }

  void _startBackgroundSync(
    List<OssConfig> initialConfigs,
    ({
      String email,
      String password,
      String? token,
      String? ossId,
      String? apiId,
      int? lastOnlineAt,
    })
    credentials,
  ) {
    if (_onlineAttemptActive) return;
    _onlineAttemptActive = true;
    final refresh = _refreshOss();
    Future<void>(() async {
      List<OssConfig>? refreshed;
      try {
        var restored = await _attemptAllOss(initialConfigs, credentials);
        if (!restored) {
          refreshed = await refresh;
          if (refreshed != null) {
            restored = await _attemptAllOss(refreshed, credentials);
          }
        } else {
          refreshed = await refresh;
        }
        if (!restored && state.status != AccountStatus.online) {
          _setRestoreFailure(
            _preferredConfig(_configs, credentials.ossId),
            credentials,
          );
        }
      } on GvboardApiException catch (error) {
        if (_isAuthenticationError(error)) {
          // A refreshed OSS may point to the current account service. Give it
          // one chance before treating the saved credentials as invalid.
          var authError = error;
          refreshed ??= await refresh;
          final latest = refreshed;
          if (latest != null) {
            try {
              if (await _attemptAllOss(latest, credentials)) return;
            } on GvboardApiException catch (refreshedError) {
              authError = refreshedError;
            }
          }
          _setState(
            AccountState(
              status: AccountStatus.unauthenticated,
              oss: _preferredConfig(_configs, credentials.ossId),
              error: '$authError',
            ),
          );
        } else if (state.status != AccountStatus.online) {
          _setRestoreFailure(
            _preferredConfig(_configs, credentials.ossId),
            credentials,
          );
        }
      } on Object {
        if (state.status != AccountStatus.online) {
          _setRestoreFailure(
            _preferredConfig(_configs, credentials.ossId),
            credentials,
          );
        }
      } finally {
        _onlineAttemptActive = false;
      }
    });
  }

  Future<List<OssConfig>?> _refreshOss() async {
    try {
      final configs = await _ossRepository.refreshBundled();
      _configs = configs;
      final config = _preferredConfig(configs, state.oss?.ossId);
      if (state.oss != config && state.status != AccountStatus.online) {
        _setState(
          AccountState(
            status: state.status,
            oss: config,
            user: state.user,
            error: state.error,
            remainingSeconds: state.remainingSeconds,
          ),
        );
      }
      return configs;
    } on Object {
      return null;
    }
  }

  void _setRestoreFailure(
    OssConfig config,
    ({
      String email,
      String password,
      String? token,
      String? ossId,
      String? apiId,
      int? lastOnlineAt,
    })
    credentials,
  ) {
    final lastOnlineAt = credentials.lastOnlineAt;
    final offlineAllowed =
        config.offline.enabled &&
        lastOnlineAt != null &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(lastOnlineAt),
            ) <=
            Duration(days: config.offline.maxDays);
    _setState(
      AccountState(
        status: offlineAllowed ? AccountStatus.offline : AccountStatus.expired,
        oss: config,
        user: state.user,
        error: offlineAllowed
            ? '当前无法连接服务器，已进入离线模式。当前显示的是上次缓存的节点数据'
            : '登录状态已过期，请连接网络后重新登录',
      ),
    );
  }

  static const _subscriptionsKey = 'gvboard.subscriptions';
  static const _selectedSubscriptionKey = 'gvboard.selected_subscription_id';

  Future<void> _loadSubscriptions(String email) async {
    final preferences = await SharedPreferences.getInstance();
    final owner = preferences.getString('$_subscriptionsKey.owner');
    if (owner != email) {
      _subscriptions = const [];
      _selectedSubscriptionId = null;
      return;
    }
    final raw = preferences.getString(_subscriptionsKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw);
      if (json is List) {
        _subscriptions = [
          for (final item in json)
            if (item is Map) GvboardSubscription.fromJson(item.cast()),
        ];
      }
      _selectedSubscriptionId = preferences.getInt(_selectedSubscriptionKey);
    } on Object {
      _subscriptions = const [];
    }
  }

  Future<GvboardUserInfo?> _loadCachedUser(String email) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString('gvboard.user.$email');
    if (raw == null) return null;
    try {
      final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return GvboardUserInfo.fromJson(json);
    } on Object {
      await preferences.remove('gvboard.user.$email');
      return null;
    }
  }

  Future<void> _saveCachedUser(GvboardUserInfo user) async {
    final email = (await _credentials.read())?.email;
    if (email == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'gvboard.user.$email',
      jsonEncode({
        'id': user.id,
        'email': user.email,
        'balance': user.balance,
        'commission_balance': user.commissionBalance,
        'subscription_limit': user.subscriptionLimit,
        'created_at': user.createdAt,
      }),
    );
  }

  Future<void> _saveSubscriptions(List<GvboardSubscription> items) async {
    _subscriptions = items;
    final email = (await _credentials.read())?.email;
    if (email == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _subscriptionsKey,
      jsonEncode([for (final item in items) item.toJson()]),
    );
    await preferences.setString('$_subscriptionsKey.owner', email);
    if (_selectedSubscriptionId != null &&
        !items.any((item) => item.id == _selectedSubscriptionId)) {
      _selectedSubscriptionId = null;
      await preferences.remove(_selectedSubscriptionKey);
    }
    notifyListeners();
  }

  Future<bool> _attemptAllOss(
    List<OssConfig> configs,
    ({
      String email,
      String password,
      String? token,
      String? ossId,
      String? apiId,
      int? lastOnlineAt,
    })
    credentials,
  ) async {
    final ordered = [...configs]
      ..sort(
        (a, b) => a.ossId == credentials.ossId
            ? -1
            : b.ossId == credentials.ossId
            ? 1
            : 0,
      );
    for (final config in ordered) {
      try {
        if (await _restoreOnline(config, credentials)) return true;
      } on GvboardApiException catch (error) {
        if (_isAuthenticationError(error)) rethrow;
      } on Object {
        continue;
      }
    }
    return false;
  }

  Future<bool> _restoreOnline(
    OssConfig config,
    ({
      String email,
      String password,
      String? token,
      String? ossId,
      String? apiId,
      int? lastOnlineAt,
    })
    credentials,
  ) async {
    final api = _createApi(config)..selectApi(credentials.apiId);
    if (credentials.token != null) {
      api.token = credentials.token;
      try {
        final user = await api.userInfo().timeout(const Duration(seconds: 10));
        await _finishRestore(api, config, user, credentials);
        return true;
      } on GvboardApiException catch (error) {
        if (_isAuthenticationError(error)) {
          api.token = null;
        } else if (!await api.selectReachableApi()) {
          throw const GvboardApiException('API 不可达');
        }
      } on Object {
        if (!await api.selectReachableApi()) {
          throw const GvboardApiException('API 不可达');
        }
      }
    }
    final result = await api
        .login(credentials.email, credentials.password, failover: false)
        .timeout(const Duration(seconds: 10));
    api.token = result.token;
    final user = await api.userInfo().timeout(const Duration(seconds: 10));
    await _finishRestore(api, config, user, credentials);
    return true;
  }

  Future<void> login(String email, String password) async {
    final config = oss;
    if (config == null) return;
    _silentRetryExhausted = false;
    _setState(AccountState(status: AccountStatus.authenticating, oss: config));
    Object? lastError;
    for (final candidate in _configs.isEmpty ? [config] : _configs) {
      try {
        final api = _createApi(candidate);
        GvboardAuthResult result;
        try {
          result = await api.login(email.trim(), password, failover: false);
        } on GvboardApiException catch (error) {
          if (_isAuthenticationError(error)) rethrow;
          if (!await api.selectReachableApi()) rethrow;
          result = await api.login(email.trim(), password, failover: false);
        } on Object {
          if (!await api.selectReachableApi()) rethrow;
          result = await api.login(email.trim(), password, failover: false);
        }
        if (result.token.isEmpty) {
          throw const GvboardApiException('登录响应缺少 Token');
        }
        api.token = result.token;
        final user = await api.userInfo();
        await _credentials.save(
          email: email.trim(),
          password: password,
          token: result.token,
          ossId: candidate.ossId,
          apiId: api.currentApiId,
          lastOnlineAt: DateTime.now().millisecondsSinceEpoch,
        );
        await _saveCachedUser(user);
        _setState(
          AccountState(
            status: AccountStatus.online,
            oss: candidate,
            user: user,
          ),
        );
        return;
      } on GvboardApiException catch (error) {
        lastError = error;
        if (_isAuthenticationError(error)) break;
      } on Object catch (error) {
        lastError = error;
      }
    }
    if (lastError != null) {
      _setState(
        AccountState(
          status: AccountStatus.unauthenticated,
          oss: config,
          error: '$lastError',
        ),
      );
      if (lastError is Exception) {
        throw lastError;
      }
      throw Exception('$lastError');
    }
  }

  Future<void> register(
    String email,
    String password, {
    String inviteCode = '',
    String emailCode = '',
  }) async {
    final config = oss;
    if (config == null) return;
    _silentRetryExhausted = false;
    final api = _createApi(config);
    final result = await api.register(
      email: email.trim(),
      password: password,
      inviteCode: inviteCode,
      emailCode: emailCode,
    );
    if (result.token.isEmpty) throw const GvboardApiException('注册响应缺少 Token');
    api.token = result.token;
    final user = await api.userInfo();
    await _credentials.save(
      email: email.trim(),
      password: password,
      token: result.token,
      ossId: config.ossId,
      apiId: api.currentApiId,
      lastOnlineAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveCachedUser(user);
    _setState(
      AccountState(status: AccountStatus.online, oss: config, user: user),
    );
  }

  Future<void> sendEmailCode(String email, String scene) async {
    final config = oss;
    if (config == null) return;
    await _createApi(config).sendEmailCode(email.trim(), scene);
  }

  Future<void> resetPassword({
    required String email,
    required String password,
    required String code,
  }) async {
    final config = oss;
    if (config == null) return;
    await _createApi(
      config,
    ).resetPassword(email: email.trim(), password: password, code: code);
  }

  Future<void> _finishRestore(
    GvboardApi api,
    OssConfig config,
    GvboardUserInfo user,
    ({
      String email,
      String password,
      String? token,
      String? ossId,
      String? apiId,
      int? lastOnlineAt,
    })
    credentials,
  ) async {
    await _credentials.save(
      email: credentials.email,
      password: credentials.password,
      token: api.token ?? '',
      ossId: config.ossId,
      apiId: api.currentApiId,
      lastOnlineAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _saveCachedUser(user);
    _setState(
      AccountState(status: AccountStatus.online, oss: config, user: user),
    );
  }

  GvboardApi _createApi(OssConfig config) {
    final api = GvboardApi(config);
    _api = api;
    return api;
  }

  Future<void> logout() async {
    await _credentials.clear();
    _api = null;
    _setState(AccountState(status: AccountStatus.unauthenticated, oss: oss));
  }

  void _setState(AccountState state) {
    value = state;
  }

  bool _isAuthenticationError(GvboardApiException error) {
    final statusCode = error.statusCode;
    return statusCode != null && statusCode >= 400 && statusCode < 500;
  }
}
