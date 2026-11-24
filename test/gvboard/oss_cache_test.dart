import 'dart:convert';

import 'package:fl_clash/oss/oss.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final legacyConfig = {
    'schema_version': 1,
    'oss_id': 'primary',
    'brand': {'name': 'Example'},
    'apis': [
      {'id': 'primary', 'base_url': 'https://api.example.com'},
    ],
    'offline': {'enabled': true, 'max_days': 7},
    'cache_ttl_seconds': 60,
  };

  test(
    'old cached configuration remains available regardless of age',
    () async {
      SharedPreferences.setMockInitialValues({
        'gvboard.oss.config.primary': jsonEncode(legacyConfig),
        'gvboard.oss.cached_at.primary': 1,
      });
      final repository = OssRepository();
      final configs = await repository.loadCached();

      expect(configs.single.ossId, 'primary');
      expect(configs.single.offline.maxDays, 7);
      expect(
        jsonDecode(repository.encode(configs.single)),
        isNot(contains('cache_ttl_seconds')),
      );
    },
  );

  test(
    'legacy TTL is ignored and cache without a timestamp is readable',
    () async {
      SharedPreferences.setMockInitialValues({
        'gvboard.oss.config.primary': jsonEncode({
          ...legacyConfig,
          'cache_ttl_seconds': 'obsolete value',
        }),
      });

      final configs = await OssRepository().loadCached();
      expect(configs.single.apis.single.baseUrl, 'https://api.example.com');
    },
  );
}
