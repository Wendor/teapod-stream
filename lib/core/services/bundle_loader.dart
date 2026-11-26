import 'dart:convert';

import '../models/app_message.dart';
import '../models/connections_bundle.dart';
import '../models/profile_bundle.dart';
import 'app_http.dart';
import 'deeplink_router.dart';
import 'tunnel_socks.dart';

/// What [BundleLoader] got: a profile, connections, or the reason it got neither.
sealed class BundleLoad {
  const BundleLoad();
}

final class ProfileLoaded extends BundleLoad {
  const ProfileLoaded(this.bundle, {this.sourceUrl});

  final ProfileBundle bundle;

  /// The URL it was downloaded from, or the one an inline bundle names; the profile is refreshed from it.
  final String? sourceUrl;
}

final class ConnectionsLoaded extends BundleLoad {
  const ConnectionsLoaded(this.bundle);

  final ConnectionsBundle bundle;
}

final class BundleFailed extends BundleLoad {
  const BundleFailed(this.reason);

  final AppMessage reason;
}

/// Loads profile and connections bundles: from a teapod link, from text pasted into the profile import, or from a URL
/// (deep link, profile refresh). Downloads are https only, at most [maxBundleBytes], through the tunnel's SOCKS when
/// the tunnel is up — [socks] is read at each download.
class BundleLoader {
  const BundleLoader(this.socks);

  final TunnelSocks? Function() socks;

  /// A bundle is a small JSON document.
  static const maxBundleBytes = 1024 * 1024;

  static const _fetchFailed = BundleFailed(AppMessage(MessageCode.bundleFetchFailed));

  /// The bundle [link] carries, or the one it points to, downloaded. A `url=` link from outside the app is
  /// downloaded only after the user agreed (`DeeplinkHandler`).
  Future<BundleLoad> load(DeeplinkParseResult link) async {
    if (link.source == DeeplinkSource.data) {
      return switch (link.type) {
        DeeplinkType.profile => ProfileLoaded(link.profileBundle!, sourceUrl: link.effectiveSourceUrl),
        DeeplinkType.connections => ConnectionsLoaded(link.connectionsBundle!),
      };
    }
    final url = Uri.tryParse(link.urlValue ?? '');
    return url == null ? _fetchFailed : fetch(url, link.type);
  }

  /// Text pasted into the profile import: a teapod profile link, or a profile bundle's JSON.
  Future<BundleLoad> profileInput(String input) async {
    final link = DeeplinkRouter.parse(input);
    if (link != null && link.type == DeeplinkType.profile) return load(link);
    return _decode(input.trim(), DeeplinkType.profile);
  }

  /// Downloads the bundle of [type] at [url].
  Future<BundleLoad> fetch(Uri url, DeeplinkType type) async {
    final AppHttpResponse response;
    try {
      response = await TunnelSocks.orDirect(
        socks(),
        (s) => AppHttp.get(url, socks: s, httpsOnly: true, maxBytes: maxBundleBytes),
      );
    } catch (_) {
      return _fetchFailed;
    }
    if (response.statusCode != 200) return _fetchFailed;
    return _decode(response.body, type, sourceUrl: url.toString());
  }

  static BundleLoad _decode(String body, DeeplinkType type, {String? sourceUrl}) {
    try {
      final json = jsonDecode(body);
      if (json is! Map<String, dynamic>) throw const FormatException('not a JSON object');
      return switch (type) {
        DeeplinkType.profile => ProfileLoaded(ProfileBundle.fromJson(json), sourceUrl: sourceUrl),
        DeeplinkType.connections => ConnectionsLoaded(ConnectionsBundle.fromJson(json)),
      };
    } on FormatException catch (e) {
      return BundleFailed(AppMessage(MessageCode.bundleInvalid, e.message));
    } catch (e) {
      // A field of the wrong type in the bundle.
      return BundleFailed(AppMessage(MessageCode.bundleInvalid, '$e'));
    }
  }
}
