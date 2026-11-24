import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/constant.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'oss_config.dart';

class OssRepository {
  OssRepository({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<OssConfig> loadBundled() async {
    final configs = await loadBundledAll();
    if (configs.isEmpty) throw const FormatException('没有可用的 OSS 配置');
    return configs.first;
  }

  Future<List<OssConfig>> loadBundledAll() async {
    final indexText = await rootBundle.loadString('assets/oss/index.json');
    final index = jsonDecode(indexText);
    if (index is! Map || index['configs'] is! List) {
      throw const FormatException('OSS 配置索引格式错误');
    }
    final configs = <OssConfig>[];
    for (final path in (index['configs'] as List).whereType<String>()) {
      try {
        if (path.startsWith('http://') || path.startsWith('https://')) {
          configs.add(await loadRemoteEncrypted(path));
        } else {
          configs.add(OssConfig.fromText(await rootBundle.loadString(path)));
        }
      } on Object {
        continue;
      }
    }
    return configs;
  }

  Future<OssConfig> loadRemoteEncrypted(String url) async {
    if (gvboardOssKey.isEmpty) {
      throw const FormatException('未配置 GVBoard OSS 解密密钥');
    }
    final response = await _dio
        .get<String>(url, options: Options(responseType: ResponseType.plain))
        .timeout(const Duration(seconds: 8));
    final encoded = response.data;
    if (encoded == null || encoded.isEmpty) {
      throw const FormatException('加密 OSS 配置为空');
    }
    final encrypted = base64.decode(encoded.trim());
    if (encrypted.length <= 12 + 16) {
      throw const FormatException('加密 OSS 配置长度无效');
    }
    final keyBytes = _deriveKey(gvboardOssKey);
    final secretKey = SecretKey(keyBytes);
    final box = SecretBox.fromConcatenation(
      encrypted,
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await AesGcm.with256bits().decrypt(box, secretKey: secretKey);
    final config = OssConfig.fromText(utf8.decode(clear));
    config.validate(requireApi: true);
    return config;
  }

  Future<List<OssConfig>> loadBundledOrCached() async {
    final cached = await loadCached();
    if (cached.isNotEmpty) return cached;
    try {
      final configs = await loadBundledAll();
      if (configs.isNotEmpty) {
        await saveCached(configs);
        return configs;
      }
      throw const FormatException('没有可用的 OSS 配置');
    } on Object {
      return loadCached();
    }
  }

  /// Loads the last valid local configurations.
  ///
  /// Cached configurations remain usable until replaced by a valid refresh.
  Future<List<OssConfig>> loadCached() async {
    final preferences = await SharedPreferences.getInstance();
    return _readCached(preferences);
  }

  Future<void> saveCached(List<OssConfig> configs) => _saveCache(configs);

  Future<List<OssConfig>> refreshBundled() async {
    final configs = await loadBundledAll();
    if (configs.isEmpty) throw const FormatException('没有可用的 OSS 配置');
    await saveCached(configs);
    return configs;
  }

  Future<OssConfig> loadRemote(String url, {Duration? timeout}) async {
    final response = await _dio
        .get<String>(url, options: Options(responseType: ResponseType.plain))
        .timeout(timeout ?? const Duration(seconds: 8));
    final body = response.data;
    if (body == null || body.isEmpty) {
      throw const FormatException('OSS 配置为空');
    }
    return OssConfig.fromText(body);
  }

  String encode(OssConfig config) {
    return jsonEncode({
      'schema_version': config.schemaVersion,
      'oss_id': config.ossId,
      'website_url': config.websiteUrl,
      'brand': {
        'name': config.brand.name,
        'short_name': config.brand.shortName,
        'logo_url': config.brand.logoUrl,
      },
      'apis': [
        for (final api in config.apis)
          {'id': api.id, 'base_url': api.baseUrl, 'priority': api.priority},
      ],
      'customer_service': {
        'type': config.customerService.type,
        'url': config.customerService.url,
      },
      'offline': {
        'enabled': config.offline.enabled,
        'max_days': config.offline.maxDays,
      },
      'client_update': {
        'latest_version': config.clientUpdate.latestVersion,
        'minimum_version': config.clientUpdate.minimumVersion,
        'update_url': config.clientUpdate.updateUrl,
        'release_notes': config.clientUpdate.releaseNotes,
      },
      'network': {
        'oss_timeout_seconds': config.network.ossTimeoutSeconds,
        'api_timeout_seconds': config.network.apiTimeoutSeconds,
        'api_retry_count': config.network.apiRetryCount,
      },
    });
  }

  Future<void> _saveCache(List<OssConfig> configs) async {
    final preferences = await SharedPreferences.getInstance();
    for (final config in configs.where((config) => config.apis.isNotEmpty)) {
      await preferences.setString(
        'gvboard.oss.config.${config.ossId}',
        encode(config),
      );
      await preferences.setInt(
        'gvboard.oss.cached_at.${config.ossId}',
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  Future<List<OssConfig>> _readCached(SharedPreferences preferences) async {
    final configs = <({OssConfig config, int cachedAt})>[];
    for (final key in preferences.getKeys()) {
      if (!key.startsWith('gvboard.oss.config.')) continue;
      final raw = preferences.getString(key);
      if (raw == null) continue;
      try {
        final config = OssConfig.fromText(raw);
        config.validate(requireApi: true);
        final cachedAt = preferences.getInt(
          'gvboard.oss.cached_at.${config.ossId}',
        );
        configs.add((config: config, cachedAt: cachedAt ?? 0));
      } on Object {
        continue;
      }
    }
    configs.sort((a, b) => b.cachedAt.compareTo(a.cachedAt));
    return [for (final entry in configs) entry.config];
  }

  List<int> _deriveKey(String raw) {
    final value = raw.trim();
    try {
      final decoded = base64.decode(value);
      if (decoded.length == 32) return decoded;
    } on FormatException {
      // Fall through to the hexadecimal form.
    }
    if (RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value)) {
      return Uint8List.fromList([
        for (var i = 0; i < value.length; i += 2)
          int.parse(value.substring(i, i + 2), radix: 16),
      ]);
    }
    throw const FormatException('GVBoard OSS 密钥必须是 32 字节 Base64 或 64 位十六进制');
  }
}
