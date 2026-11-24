import 'dart:convert';

class OssApiEndpoint {
  const OssApiEndpoint({
    required this.id,
    required this.baseUrl,
    this.priority = 0,
  });

  final String id;
  final String baseUrl;
  final int priority;

  factory OssApiEndpoint.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['base_url'] as String? ?? '';
    return OssApiEndpoint(
      id: json['id'] as String? ?? 'api',
      baseUrl: rawUrl.replaceFirst(RegExp(r'/+$'), ''),
      priority: (json['priority'] as num?)?.toInt() ?? 0,
    );
  }
}

class OssBrand {
  const OssBrand({required this.name, this.shortName, this.logoUrl});

  final String name;
  final String? shortName;
  final String? logoUrl;

  factory OssBrand.fromJson(Map<String, dynamic> json) {
    return OssBrand(
      name: json['name'] as String? ?? 'FlClash',
      shortName: json['short_name'] as String?,
      logoUrl: json['logo_url'] as String?,
    );
  }
}

class OssCustomerService {
  const OssCustomerService({required this.type, required this.url});

  final String type;
  final String url;

  factory OssCustomerService.fromJson(Map<String, dynamic> json) {
    return OssCustomerService(
      type: json['type'] as String? ?? 'web',
      url: json['url'] as String? ?? '',
    );
  }
}

class OssOfflinePolicy {
  const OssOfflinePolicy({required this.enabled, required this.maxDays});

  final bool enabled;
  final int maxDays;

  factory OssOfflinePolicy.fromJson(Map<String, dynamic> json) {
    return OssOfflinePolicy(
      enabled: json['enabled'] as bool? ?? true,
      maxDays: (json['max_days'] as num?)?.toInt() ?? 7,
    );
  }
}

class OssClientUpdate {
  const OssClientUpdate({
    required this.latestVersion,
    required this.minimumVersion,
    required this.updateUrl,
    required this.releaseNotes,
  });

  final String latestVersion;
  final String minimumVersion;
  final String updateUrl;
  final String releaseNotes;

  factory OssClientUpdate.fromJson(Map<String, dynamic> json) {
    return OssClientUpdate(
      latestVersion: json['latest_version'] as String? ?? '',
      minimumVersion: json['minimum_version'] as String? ?? '',
      updateUrl: json['update_url'] as String? ?? '',
      releaseNotes: json['release_notes'] as String? ?? '',
    );
  }
}

class OssNetworkPolicy {
  const OssNetworkPolicy({
    required this.ossTimeoutSeconds,
    required this.apiTimeoutSeconds,
    required this.apiRetryCount,
  });

  final int ossTimeoutSeconds;
  final int apiTimeoutSeconds;
  final int apiRetryCount;

  factory OssNetworkPolicy.fromJson(Map<String, dynamic> json) {
    return OssNetworkPolicy(
      ossTimeoutSeconds: (json['oss_timeout_seconds'] as num?)?.toInt() ?? 8,
      apiTimeoutSeconds: (json['api_timeout_seconds'] as num?)?.toInt() ?? 10,
      apiRetryCount: (json['api_retry_count'] as num?)?.toInt() ?? 1,
    );
  }
}

class OssConfig {
  const OssConfig({
    required this.schemaVersion,
    required this.ossId,
    required this.brand,
    required this.apis,
    required this.customerService,
    required this.offline,
    required this.clientUpdate,
    required this.network,
    this.websiteUrl = '',
  });

  final int schemaVersion;
  final String ossId;
  final OssBrand brand;
  final List<OssApiEndpoint> apis;
  final OssCustomerService customerService;
  final OssOfflinePolicy offline;
  final OssClientUpdate clientUpdate;
  final OssNetworkPolicy network;
  final String websiteUrl;

  String get officialWebsite {
    final uri = Uri.tryParse(websiteUrl);
    if (uri?.scheme == 'https' && uri!.host.isNotEmpty) return websiteUrl;
    return apis.isEmpty ? '' : Uri.parse(apis.first.baseUrl).origin;
  }

  void validate({bool requireApi = false}) {
    if (schemaVersion != 1) {
      throw FormatException('不支持的 OSS 配置版本：$schemaVersion');
    }
    if (ossId.trim().isEmpty || brand.name.trim().isEmpty) {
      throw const FormatException('OSS 配置缺少标识或品牌名称');
    }
    if (requireApi && apis.isEmpty) {
      throw const FormatException('OSS 配置没有可用 API');
    }
    for (final api in apis) {
      final uri = Uri.tryParse(api.baseUrl);
      if (uri == null ||
          !uri.hasScheme ||
          uri.host.isEmpty ||
          uri.scheme != 'https') {
        throw FormatException('OSS API 地址无效：${api.baseUrl}');
      }
    }
    if (offline.maxDays < 0 || offline.maxDays > 3650) {
      throw const FormatException('OSS 离线有效期无效');
    }
  }

  factory OssConfig.fromJson(Map<String, dynamic> json) {
    final rawApis = json['apis'] as List<dynamic>? ?? const [];
    final apis =
        rawApis
            .whereType<Map<String, dynamic>>()
            .map(OssApiEndpoint.fromJson)
            .where((endpoint) => endpoint.baseUrl.isNotEmpty)
            .toList()
          ..sort((a, b) => a.priority.compareTo(b.priority));
    return OssConfig(
      schemaVersion: (json['schema_version'] as num?)?.toInt() ?? 1,
      ossId: json['oss_id'] as String? ?? 'default',
      brand: OssBrand.fromJson(
        (json['brand'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      apis: apis,
      customerService: OssCustomerService.fromJson(
        (json['customer_service'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      offline: OssOfflinePolicy.fromJson(
        (json['offline'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      clientUpdate: OssClientUpdate.fromJson(
        (json['client_update'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      network: OssNetworkPolicy.fromJson(
        (json['network'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      websiteUrl: json['website_url'] as String? ?? '',
    );
  }

  factory OssConfig.fromText(String text) {
    final json = jsonDecode(text);
    if (json is! Map) {
      throw const FormatException('OSS 配置必须是 JSON 对象');
    }
    return OssConfig.fromJson(json.cast<String, dynamic>());
  }
}
