import 'vpn_config.dart';

/// Тип физической сети, к которому привязывается конфиг.
enum NetTransport {
  wifi,
  cellular;

  static NetTransport? parse(String? name) =>
      NetTransport.values.where((t) => t.name == name).firstOrNull;
}

/// Правило «в такой сети — такой конфиг». Как и [PinnedRef], идентифицирует
/// конфиг парой (подписка, имя): при обновлении подписки конфиги
/// пересоздаются с новыми id, а правило продолжает указывать на одноимённый.
class NetworkRule {
  final NetTransport transport;

  /// null — standalone-конфиг (не из подписки).
  final String? subscriptionId;
  final String name;

  const NetworkRule({
    required this.transport,
    required this.subscriptionId,
    required this.name,
  });

  bool matches(VpnConfig c) =>
      c.subscriptionId == subscriptionId && c.name == name;

  Map<String, dynamic> toJson() => {
        'transport': transport.name,
        'subscriptionId': subscriptionId,
        'name': name,
      };

  static NetworkRule? fromJson(Map<String, dynamic> json) {
    final transport = NetTransport.parse(json['transport'] as String?);
    if (transport == null) return null;
    return NetworkRule(
      transport: transport,
      subscriptionId: json['subscriptionId'] as String?,
      name: json['name'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkRule &&
      other.transport == transport &&
      other.subscriptionId == subscriptionId &&
      other.name == name;

  @override
  int get hashCode => Object.hash(transport, subscriptionId, name);
}
