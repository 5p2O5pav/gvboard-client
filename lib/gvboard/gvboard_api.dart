import 'dart:io';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../oss/oss.dart';
import 'subscription.dart';
import 'user_center.dart';

class GvboardApiException implements Exception {
  const GvboardApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class GvboardAuthResult {
  const GvboardAuthResult({required this.token, required this.isAdmin});

  final String token;
  final bool isAdmin;

  factory GvboardAuthResult.fromJson(Map<String, dynamic> json) {
    return GvboardAuthResult(
      token: json['token'] as String? ?? '',
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }
}

class GvboardApi {
  GvboardApi(this.config, {Dio? dio}) : _dio = dio ?? Dio();

  final OssConfig config;
  final Dio _dio;
  String? token;
  int _apiIndex = 0;

  OssApiEndpoint get _endpoint => config.apis[_apiIndex];

  String get currentApiId => _endpoint.id;

  Future<({List<String> suffixes, bool emailCode, bool inviteRequired})>
  registrationOptions() async {
    Map<String, dynamic> site;
    try {
      site = await _request<Map<String, dynamic>>(
        '/site',
        method: 'GET',
        authenticated: false,
      );
    } on GvboardApiException catch (error) {
      if (error.statusCode != 404 || config.officialWebsite.isEmpty) rethrow;
      final response = await _dio
          .get<String>(
            config.officialWebsite,
            options: Options(responseType: ResponseType.plain),
          )
          .timeout(Duration(seconds: config.network.apiTimeoutSeconds));
      final match = RegExp(
        r'<script>window\.APP_CONFIG\s*=\s*(.*?)\s*;\s*</script>',
        dotAll: true,
      ).firstMatch(response.data ?? '');
      if (match == null) throw const FormatException('未获取到站点注册设置');
      site = (jsonDecode(match.group(1)!) as Map).cast<String, dynamic>();
    }
    final register = site['register'];
    if (register is! Map) throw const FormatException('站点注册设置格式错误');
    final suffixes = register['email_suffixes'];
    return (
      suffixes: [
        if (suffixes is List)
          for (final suffix in suffixes.whereType<String>())
            if (suffix.trim().replaceFirst(RegExp(r'^@'), '').isNotEmpty)
              suffix.trim().replaceFirst(RegExp(r'^@'), ''),
      ],
      emailCode: register['email_code'] == true,
      inviteRequired: register['invite_required'] == true,
    );
  }

  void selectApi(String? id) {
    if (id == null) return;
    final index = config.apis.indexWhere((api) => api.id == id);
    if (index >= 0) _apiIndex = index;
  }

  Future<bool> pingApi(OssApiEndpoint endpoint) async {
    final host = Uri.parse(endpoint.baseUrl).host;
    if (host.isEmpty) return false;
    try {
      final result = Platform.isWindows
          ? await Process.run('ping', [
              '-n',
              '1',
              '-w',
              '1500',
              host,
            ]).timeout(const Duration(seconds: 2))
          : await Process.run('ping', [
              '-c',
              '1',
              '-W',
              '1',
              host,
            ]).timeout(const Duration(seconds: 2));
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<bool> selectReachableApi() async {
    for (var index = 0; index < config.apis.length; index++) {
      if (await pingApi(config.apis[index])) {
        _apiIndex = index;
        return true;
      }
    }
    return false;
  }

  Future<GvboardAuthResult> login(
    String email,
    String password, {
    bool failover = true,
  }) async {
    final data = await _request<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
      authenticated: false,
      failover: failover,
    );
    return GvboardAuthResult.fromJson(data);
  }

  Future<GvboardAuthResult> register({
    required String email,
    required String password,
    String inviteCode = '',
    String emailCode = '',
  }) async {
    final data = await _request<Map<String, dynamic>>(
      '/auth/register',
      data: {
        'email': email,
        'password': password,
        if (inviteCode.isNotEmpty) 'invite_code': inviteCode,
        if (emailCode.isNotEmpty) 'email_code': emailCode,
      },
      authenticated: false,
    );
    return GvboardAuthResult.fromJson(data);
  }

  Future<void> sendEmailCode(String email, String scene) async {
    await _request<Object?>(
      '/auth/email-code',
      data: {'email': email, 'scene': scene},
      authenticated: false,
    );
  }

  Future<void> resetPassword({
    required String email,
    required String password,
    required String code,
  }) async {
    await _request<Object?>(
      '/auth/reset-password',
      data: {'email': email, 'password': password, 'code': code},
      authenticated: false,
    );
  }

  Future<GvboardUserInfo> userInfo() async {
    return GvboardUserInfo.fromJson(
      await _request<Map<String, dynamic>>('/user/info', method: 'GET'),
    );
  }

  Future<GvboardUserStat> userStat() async {
    return GvboardUserStat.fromJson(
      await _request<Map<String, dynamic>>('/user/stat', method: 'GET'),
    );
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    await _request<Object>(
      '/user/password',
      data: {'old_password': oldPassword, 'new_password': newPassword},
    );
  }

  Future<List<GvboardSession>> sessions() async {
    final data = await _request<List<dynamic>>('/user/sessions', method: 'GET');
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) GvboardSession.fromJson(item),
    ];
  }

  Future<void> removeSession(String id) async {
    await _request<Object>(
      '/user/sessions/${Uri.encodeComponent(id)}',
      method: 'DELETE',
    );
  }

  Future<List<GvboardSubscription>> subscriptions() async {
    final data = await _request<List<dynamic>>(
      '/user/subscriptions',
      method: 'GET',
    );
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) GvboardSubscription.fromJson(item),
    ];
  }

  Future<GvboardSubscription> subscription(int id) async {
    return GvboardSubscription.fromJson(
      await _request<Map<String, dynamic>>(
        '/user/subscriptions/$id',
        method: 'GET',
      ),
    );
  }

  Future<String> resetSubscriptionSecurity(int id) async {
    final result = await _request<Object>(
      '/user/subscriptions/$id/reset-security',
    );
    return result.toString();
  }

  Future<List<Map<String, dynamic>>> plans() async {
    final data = await _request<List<dynamic>>('/user/plans', method: 'GET');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> orderPreview(Map<String, dynamic> input) {
    return _request<Map<String, dynamic>>('/user/orders/preview', data: input);
  }

  Future<String> createOrder(Map<String, dynamic> input) async {
    final data = await _request<Object>('/user/orders', data: input);
    return data.toString();
  }

  Future<Map<String, dynamic>> order(String tradeNo) {
    return _request<Map<String, dynamic>>(
      '/user/orders/$tradeNo',
      method: 'GET',
    );
  }

  Future<int> orderStatus(String tradeNo) {
    return _request<int>('/user/orders/$tradeNo/status', method: 'GET');
  }

  Future<List<GvboardOrder>> orders() async {
    final data = await _request<List<dynamic>>('/user/orders', method: 'GET');
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) GvboardOrder.fromJson(item),
    ];
  }

  Future<List<Map<String, dynamic>>> paymentMethods() async {
    final data = await _request<List<dynamic>>(
      '/user/payment-methods',
      method: 'GET',
    );
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<Map<String, dynamic>> checkout(String tradeNo, int method) {
    return _request<Map<String, dynamic>>(
      '/user/orders/$tradeNo/checkout',
      data: {'method': method},
    );
  }

  Future<void> cancelOrder(String tradeNo) async {
    await _request<Object>('/user/orders/$tradeNo/cancel');
  }

  Future<Map<String, dynamic>> checkCoupon({
    required String code,
    required int planId,
    required String period,
  }) {
    return _request<Map<String, dynamic>>(
      '/user/coupons/check',
      data: {'code': code, 'plan_id': planId, 'period': period},
    );
  }

  Future<GvboardInviteOverview> invite() async {
    return GvboardInviteOverview.fromJson(
      await _request<Map<String, dynamic>>('/user/invite', method: 'GET'),
    );
  }

  Future<List<GvboardCommissionEntry>> commissions({
    int current = 1,
    int pageSize = 20,
  }) async {
    final result = await _request<Map<String, dynamic>>(
      '/user/invite/commissions',
      method: 'GET',
      data: {'current': current, 'page_size': pageSize},
    );
    final data = result['data'];
    if (data is! List) return const [];
    return [
      for (final item in data)
        if (item is Map<String, dynamic>) GvboardCommissionEntry.fromJson(item),
    ];
  }

  Future<Map<String, dynamic>> generateInviteCode() {
    return _request<Map<String, dynamic>>('/user/invite/codes');
  }

  Future<List<Map<String, dynamic>>> tickets() async {
    final data = await _request<List<dynamic>>('/user/tickets', method: 'GET');
    return data.whereType<Map<String, dynamic>>().toList();
  }

  Future<T> _request<T>(
    String path, {
    Map<String, dynamic>? data,
    String method = 'POST',
    bool authenticated = true,
    bool failover = true,
  }) async {
    if (config.apis.isEmpty) {
      throw const GvboardApiException('未配置 GVBoard API');
    }
    Object? lastError;
    final start = _apiIndex;
    final endpointCount = failover ? config.apis.length : 1;
    for (
      var endpointAttempt = 0;
      endpointAttempt < endpointCount;
      endpointAttempt++
    ) {
      final index = (start + endpointAttempt) % config.apis.length;
      _apiIndex = index;
      final retries = config.network.apiRetryCount.clamp(0, 5);
      for (var retry = 0; retry <= retries; retry++) {
        try {
          final response = await _dio
              .request<Object?>(
                '${_endpoint.baseUrl}$path',
                queryParameters: method == 'GET' ? data : null,
                data: method == 'GET' ? null : data,
                options: Options(
                  method: method,
                  responseType: ResponseType.json,
                  headers: {
                    if (authenticated && token != null)
                      'Authorization': 'Bearer $token',
                  },
                  validateStatus: (status) => status != null,
                ),
              )
              .timeout(Duration(seconds: config.network.apiTimeoutSeconds));
          final body = response.data;
          if (response.statusCode != null && response.statusCode! >= 500) {
            lastError = GvboardApiException(
              'GVBoard 服务暂时不可用',
              statusCode: response.statusCode,
            );
            continue;
          }
          if (body is! Map) {
            throw GvboardApiException(
              'GVBoard 返回格式错误',
              statusCode: response.statusCode,
            );
          }
          final envelope = body.cast<String, dynamic>();
          if (response.statusCode == null || response.statusCode! >= 400) {
            throw GvboardApiException(
              _errorMessage(envelope),
              statusCode: response.statusCode,
            );
          }
          if (envelope['data'] is T) {
            return envelope['data'] as T;
          }
          if (envelope['data'] == null) {
            return null as T;
          }
          throw const GvboardApiException('GVBoard 响应缺少 data 字段');
        } on GvboardApiException catch (error) {
          if (error.statusCode == null || error.statusCode! < 500) rethrow;
          lastError = error;
        } on DioException catch (error) {
          lastError = error;
        } on Exception catch (error) {
          lastError = error;
        }
      }
    }
    _apiIndex = start;
    throw GvboardApiException('无法连接 GVBoard：$lastError');
  }

  String _errorMessage(Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map && error['message'] is String) {
      return error['message'] as String;
    }
    if (body['message'] is String) return body['message'] as String;
    return 'GVBoard 请求失败';
  }
}
