import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/services/config_storage_service.dart';
import 'package:teapodstream/core/services/settings_service.dart';

// StorageMigrationService runs once per process, so this file holds a single scenario.
void main() {
  test('plaintext prefs are moved to secure storage and wiped', () async {
    final config = {
      'id': 'c1', 'name': 'n', 'protocol': 'vless', 'address': 'h', 'port': 443, 'uuid': 'u',
      'security': 'none', 'transport': 'tcp', 'createdAt': '2026-01-01T00:00:00.000',
    };
    final sub = {'id': 's1', 'name': 'S', 'url': 'https://s', 'createdAt': '2026-01-01T00:00:00.000'};
    SharedPreferences.setMockInitialValues({
      'vpn_configs': [jsonEncode(config)],
      'active_config_id': 'c1',
      'subscriptions': [jsonEncode(sub)],
      'socks_user': 'old_user',
      'socks_password': 'old_pass',
      'mtu': 1400,
    });
    FlutterSecureStorage.setMockInitialValues({});

    final storage = ConfigStorageService();
    expect((await storage.loadConfigs()).single.id, 'c1');
    expect(await storage.loadActiveConfigId(), 'c1');
    expect((await storage.loadSubscriptions()).single.url, 'https://s');

    final settings = await SettingsService().load();
    expect(settings.socksUser, 'old_user');
    expect(settings.socksPassword, 'old_pass');
    expect(settings.mtu, 1400);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), {'storage_migrated_v2', 'mtu'});
    expect(prefs.getBool('storage_migrated_v2'), isTrue);
  });
}
