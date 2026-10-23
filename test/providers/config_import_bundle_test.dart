import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teapodstream/core/models/connections_bundle.dart';
import 'package:teapodstream/core/models/vpn_config.dart';
import 'package:teapodstream/protocols/xray/vless_parser.dart';
import 'package:teapodstream/providers/config_provider.dart';

final pinHex = List.filled(32, '2a').join();

/// Every optional field set, so a field dropped on import shows up in toJson.
VpnConfig fullConfig() => VpnConfig(
      id: 'cfg_src',
      name: 'pinned',
      protocol: VpnProtocol.vless,
      address: 'edge.example',
      port: 443,
      uuid: '11111111-2222-4333-8444-555555555555',
      security: VpnSecurity.tls,
      transport: VpnTransport.xhttp,
      sni: 'cover.example',
      wsPath: '/p',
      wsHost: 'edge.example',
      grpcServiceName: 'svc',
      fingerprint: 'firefox',
      publicKey: 'pk',
      shortId: '1234',
      spiderX: '/s',
      postQuantumKey: 'pq',
      flow: 'xtls-rprx-vision',
      encryption: 'none',
      alterId: '0',
      method: 'aes-128-gcm',
      password: 'secret',
      createdAt: DateTime(2026),
      rawUri: 'vless://pinned',
      latencyMs: 42,
      lastPingedAt: DateTime(2026, 2),
      ssPrefix: '1603',
      obfsPassword: 'obfs',
      hopPorts: '20000-30000',
      allowInsecure: true,
      pinSHA256: pinHex,
      xhttpMode: 'packet-up',
      xhttpExtra: const {'xPaddingBytes': '100-1000'},
      finalmask: const {'udp': <Object>[]},
      alpn: 'h2,http/1.1',
      ech: 'AEX+DQ==',
      rawXrayConfig: '{"outbounds":[]}',
    );

Map<String, dynamic> withoutIdentity(VpnConfig c) => c.toJson()
  ..remove('id')
  ..remove('createdAt')
  ..remove('subscriptionId');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('importBundle keeps pin, allowInsecure and every other field', () async {
    SharedPreferences.setMockInitialValues({'storage_migrated_v2': true});
    FlutterSecureStorage.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(configProvider.future);

    final source = fullConfig();
    // Round-trip through the bundle JSON, as a profile/deeplink import does.
    final bundle = ConnectionsBundle.fromJson(
      ConnectionsBundle(exportedAt: DateTime(2026), configs: [source]).toJson(),
    );
    final result =
        await container.read(configProvider.notifier).importBundle(bundle);
    expect(result.addedConfigs, 1);

    final imported = container.read(configProvider).value!.configs.single;
    expect(imported.id, isNot(source.id));
    expect(imported.allowInsecure, isTrue);
    expect(imported.pinSHA256, pinHex);
    expect(withoutIdentity(imported), withoutIdentity(source));
  });

  test('copyWith replaces identity and keeps parsed Hysteria2 fields', () {
    final parsed = VlessParser.parseUri(
      'hy2://pw@host.example:20000/?insecure=1&pinSHA256=$pinHex&sni=s#hy',
    )!;
    final kept = parsed.copyWith(
      id: 'cfg_old',
      createdAt: DateTime(2025),
      latencyMs: 7,
      subscriptionId: 'sub_1',
    );
    expect(kept.id, 'cfg_old');
    expect(kept.createdAt, DateTime(2025));
    expect(kept.password, 'pw');
    expect(kept.allowInsecure, isTrue);
    expect(kept.pinSHA256, pinHex);
    expect(kept.port, 20000);
    expect(kept.subscriptionId, 'sub_1');
  });
}
