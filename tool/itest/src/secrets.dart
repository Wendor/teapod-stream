import 'dart:convert';
import 'dart:io';

typedef SecretConfig = ({String uri, bool owned, String? egressIp});
typedef SecretSub = ({String url, bool owned});

/// `tool/itest/secrets.json` (not in git): test connections.
class Secrets {
  final List<SecretConfig> configs;
  final List<SecretSub> subs;

  /// Core nativeId → reference config name (optional).
  final Map<String, String> reference;

  /// Glob on `host:port`: such configs (usually from a subscription) aren't tested.
  final List<String> exclude;

  const Secrets(this.configs, this.subs, this.reference, [this.exclude = const []]);

  factory Secrets.fromJson(Map<String, dynamic> j) => Secrets(
        [
          for (final c in (j['configs'] as List? ?? const []).cast<Map<String, dynamic>>())
            (uri: c['uri'] as String, owned: c['owned'] as bool? ?? true, egressIp: c['egressIp'] as String?),
        ],
        [
          for (final s in (j['subs'] as List? ?? const []).cast<Map<String, dynamic>>())
            (url: s['url'] as String, owned: s['owned'] as bool? ?? true),
        ],
        (j['reference'] as Map? ?? const {}).cast<String, String>(),
        (j['exclude'] as List? ?? const []).cast<String>(),
      );

  static Secrets load(String path) {
    final f = File(path);
    if (!f.existsSync()) throw StateError('no $path — copy secrets.example.json');
    return Secrets.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>);
  }
}
