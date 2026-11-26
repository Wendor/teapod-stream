import '../models/profile_bundle.dart';
import '../models/connections_bundle.dart';

enum DeeplinkType { profile, connections }

enum DeeplinkSource { data, url }

/// Result of parsing a teapod deeplink URI.
///
/// For [source] == [DeeplinkSource.data], [dataValue] contains the
/// already-decoded bundle and [urlValue] is null.
/// For [source] == [DeeplinkSource.url], [urlValue] contains the fetch URL
/// and [dataValue] is null.
class DeeplinkParseResult {
  final DeeplinkType type;
  final DeeplinkSource source;
  final ProfileBundle? profileBundle;
  final ConnectionsBundle? connectionsBundle;
  final String? urlValue;

  const DeeplinkParseResult._({
    required this.type,
    required this.source,
    this.profileBundle,
    this.connectionsBundle,
    this.urlValue,
  });

  factory DeeplinkParseResult.inlineProfile(ProfileBundle bundle) =>
      DeeplinkParseResult._(type: DeeplinkType.profile, source: DeeplinkSource.data, profileBundle: bundle);

  factory DeeplinkParseResult.urlProfile(String url) =>
      DeeplinkParseResult._(type: DeeplinkType.profile, source: DeeplinkSource.url, urlValue: url);

  factory DeeplinkParseResult.inlineConnections(ConnectionsBundle bundle) =>
      DeeplinkParseResult._(type: DeeplinkType.connections, source: DeeplinkSource.data, connectionsBundle: bundle);

  factory DeeplinkParseResult.urlConnections(String url) =>
      DeeplinkParseResult._(type: DeeplinkType.connections, source: DeeplinkSource.url, urlValue: url);

  String? get effectiveSourceUrl {
    if (source == DeeplinkSource.url) return urlValue;
    return source == DeeplinkSource.data ? profileBundle?.sourceUrl : null;
  }
}

/// Unified deeplink router for `teapod://import/{type}?{source}={value}`.
///
/// Supported formats:
///   `teapod://import/profile?data=<base64>`
///   `teapod://import/profile?url=https://...`
///   `teapod://import/connections?data=<base64>`
///   `teapod://import/connections?url=https://...`
class DeeplinkRouter {
  static const _scheme = 'teapod';

  /// Parse a deeplink URI string. Returns null if the URI is not a valid teapod import link.
  static DeeplinkParseResult? parse(String raw) {
    try {
      final trimmed = raw.trim();
      final uri = Uri.parse(trimmed);

      if (uri.scheme != _scheme) return null;
      if (uri.host != 'import') return null;

      final typeRaw = uri.path.substring(1).toLowerCase();
      final type = _parseType(typeRaw);
      if (type == null) return null;

      final dataParam = uri.queryParameters['data'];
      final urlParam = uri.queryParameters['url'];

      if (dataParam != null) {
        switch (type) {
          case DeeplinkType.profile:
            return DeeplinkParseResult.inlineProfile(ProfileBundle.fromBase64(dataParam));
          case DeeplinkType.connections:
            return DeeplinkParseResult.inlineConnections(ConnectionsBundle.fromBase64(dataParam));
        }
      }

      if (urlParam != null) {
        switch (type) {
          case DeeplinkType.profile:
            return DeeplinkParseResult.urlProfile(urlParam);
          case DeeplinkType.connections:
            return DeeplinkParseResult.urlConnections(urlParam);
        }
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  static DeeplinkType? _parseType(String raw) {
    switch (raw) {
      case 'profile':
        return DeeplinkType.profile;
      case 'connections':
        return DeeplinkType.connections;
      default:
        return null;
    }
  }
}
