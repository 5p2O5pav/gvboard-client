import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/gvboard/gvboard.dart';
import 'package:fl_clash/oss/oss.dart';
import 'package:flutter_test/flutter_test.dart';

class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(this.responses);

  final List<ResponseBody> responses;
  var calls = 0;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responses[calls++];
  }

  @override
  void close({bool force = false}) {}
}

OssConfig _config({int retries = 1, int apiCount = 1}) {
  return OssConfig(
    schemaVersion: 1,
    ossId: 'test',
    brand: const OssBrand(name: 'Test'),
    apis: [
      for (var index = 0; index < apiCount; index++)
        OssApiEndpoint(id: 'api$index', baseUrl: 'https://api$index.test'),
    ],
    customerService: const OssCustomerService(type: 'web', url: ''),
    offline: const OssOfflinePolicy(enabled: true, maxDays: 7),
    clientUpdate: const OssClientUpdate(
      latestVersion: '',
      minimumVersion: '',
      updateUrl: '',
      releaseNotes: '',
    ),
    network: OssNetworkPolicy(
      ossTimeoutSeconds: 1,
      apiTimeoutSeconds: 1,
      apiRetryCount: retries,
    ),
  );
}

ResponseBody _json(String body, [int status = 200]) {
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  test('reads native registration flags and normalizes email suffixes', () async {
    final adapter = _SequenceAdapter([
      _json(
        '{"data":{"register":{"email_code":true,"email_suffixes":["@qq.com","gmail.com"],"invite_required":true}}}',
      ),
    ]);
    final api = GvboardApi(_config(), dio: Dio()..httpClientAdapter = adapter);
    final settings = await api.registrationOptions();
    expect(settings.suffixes, ['qq.com', 'gmail.com']);
    expect(settings.emailCode, isTrue);
    expect(settings.inviteRequired, isTrue);
    expect(adapter.requests.single.uri.path, '/site');
  });

  test('reads embedded registration settings after an HTML 404', () async {
    final adapter = _SequenceAdapter([
      ResponseBody.fromString('<h1>Not found</h1>', 404),
      ResponseBody.fromString(
        '<script>window.APP_CONFIG={"register":{"email_code":false,"email_suffixes":[]}};</script>',
        200,
      ),
    ]);
    final api = GvboardApi(_config(), dio: Dio()..httpClientAdapter = adapter);
    final settings = await api.registrationOptions();
    expect(settings.suffixes, isEmpty);
    expect(settings.emailCode, isFalse);
    expect(adapter.requests.last.uri.origin, 'https://api0.test');
  });

  test(
    'opens the selected order and posts cancellation on its native route',
    () async {
      final adapter = _SequenceAdapter([
        _json('{"data":{"trade_no":"A123","status":0,"plan":{"name":"Demo"}}}'),
        _json('{"data":true}'),
      ]);
      final api = GvboardApi(_config(), dio: Dio()..httpClientAdapter = adapter)
        ..token = 'demo-token';
      expect(GvboardOrder.fromJson(await api.order('A123')).planName, 'Demo');
      await api.cancelOrder('A123');
      expect(adapter.requests.map((r) => (r.method, r.uri.path)), [
        ('GET', '/user/orders/A123'),
        ('POST', '/user/orders/A123/cancel'),
      ]);
    },
  );

  test('forwards immediate renewal mode into order creation', () async {
    final adapter = _SequenceAdapter([_json('{"data":"T123"}')]);
    final api = GvboardApi(_config(), dio: Dio()..httpClientAdapter = adapter);
    await api.createOrder({
      'plan_id': 8,
      'period': 'month_price',
      'subscription_id': 3,
      'immediate': true,
    });
    final data = adapter.requests.single.data as Map<String, dynamic>;
    expect(data['subscription_id'], 3);
    expect(data['immediate'], isTrue);
  });
  test('retries the current API before failing over', () async {
    final adapter = _SequenceAdapter([
      _json('{}', 503),
      _json('{"data":{"email":"user@example.com"}}'),
    ]);
    final api = GvboardApi(
      _config(retries: 1),
      dio: Dio()..httpClientAdapter = adapter,
    );

    expect((await api.userInfo()).email, 'user@example.com');
    expect(adapter.calls, 2);
  });

  test('does not fail over on an authentication error', () async {
    final adapter = _SequenceAdapter([
      _json('{"message":"密码错误"}', 401),
      _json('{"data":{"email":"user@example.com"}}'),
    ]);
    final api = GvboardApi(
      _config(retries: 2, apiCount: 2),
      dio: Dio()..httpClientAdapter = adapter,
    );

    await expectLater(api.userInfo(), throwsA(isA<GvboardApiException>()));
    expect(adapter.calls, 1);
  });
}
