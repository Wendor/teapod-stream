import 'dart:isolate';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/app_settings.dart';
import '../core/services/geodata_service.dart';
import '../core/services/geosite_index.dart';
import '../core/services/tunnel_socks.dart';
import 'settings_provider.dart';
import 'vpn_provider.dart';
import '../core/models/app_message.dart';
import '../core/services/platform_service.dart';

sealed class GeoState {}

class GeoMissing extends GeoState {}

class GeoReady extends GeoState {
  final DateTime? lastUpdated;
  GeoReady({this.lastUpdated});
}

class GeoDownloading extends GeoState {
  final int downloaded;
  final int total;
  GeoDownloading({required this.downloaded, required this.total});
}

class GeoError extends GeoState {
  final AppMessage message;
  GeoError(this.message);
}

class GeoNotifier extends Notifier<GeoState> {
  GeodataService get _service => ref.read(geodataServiceProvider);

  /// A download is running: it owns the `.tmp` files, the geodata files and the state until it ends.
  var _downloading = false;

  /// Bumped when a download starts: a [check] that began before it publishes nothing.
  var _epoch = 0;

  /// The check running now; a download waits for it, so the bundled-copy extraction never overlaps the install.
  Future<void>? _checking;

  @override
  GeoState build() {
    Future.microtask(check);
    return GeoMissing();
  }

  /// Whether the files are there (extracting the bundled copy if not). Does nothing during a download; a call during a
  /// check joins it; a check that a download overtook neither extracts nor publishes.
  Future<void> check() {
    if (_downloading) return Future.value();
    // Calls during a check join it: one extraction at a time, and the download waits for the one that runs.
    if (_checking case final running?) return running;
    final run = _check(_epoch);
    _checking = run;
    return run.whenComplete(() {
      if (identical(_checking, run)) _checking = null;
    });
  }

  Future<void> _check(int epoch) async {
    bool stale() => _downloading || epoch != _epoch;
    try {
      final platform = ref.read(platformServiceProvider);
      final dir = await platform.filesDir();
      if (dir.isEmpty || stale()) return;
      final missing = !_service.present(dir);
      // Try to extract the bundled fallback from assets.
      if (missing) await platform.prepareBinaries();
      if (stale()) return;
      if (_service.present(dir)) {
        final lastUpdated = await _service.lastUpdated();
        if (stale()) return;
        if (missing) ref.invalidate(geositeIndexProvider);
        state = GeoReady(lastUpdated: lastUpdated);
      } else {
        state = GeoMissing();
      }
    } catch (_) {
      if (!stale()) state = GeoMissing();
    }
  }

  /// One download at a time: a second call while one runs (the button is still shown until the first await) returns
  /// at once — both would write the same `.tmp` files. A check running when it starts is finished first and
  /// discarded.
  Future<void> download() async {
    if (_downloading) return;
    _downloading = true;
    _epoch++;
    state = GeoDownloading(downloaded: 0, total: -1);
    try {
      await _checking;
      await _download();
    } finally {
      _downloading = false;
    }
  }

  Future<void> _download() async {
    final AppSettings settings;
    try {
      settings = await ref.read(settingsProvider.future);
    } catch (e) {
      state = GeoError(AppMessage.text('$e'));
      return;
    }
    final String dir;
    try {
      dir = await ref.read(platformServiceProvider).filesDir();
    } catch (_) {
      state = GeoError(const AppMessage(MessageCode.geoNoFilesDir));
      return;
    }
    if (dir.isEmpty) {
      state = GeoError(const AppMessage(MessageCode.geoNoFilesDir));
      return;
    }

    try {
      // GitHub CDN is often blocked — with the VPN connected we download through the tunnel (#150).
      final finished = await TunnelSocks.orDirect(
        ref.read(tunnelSocksProvider),
        (socks) => _service.download(
          dir: dir,
          geoipUrl: settings.geoipUrl,
          geositeUrl: settings.geositeUrl,
          socks: socks,
          onProgress: (downloaded, total) => state = GeoDownloading(downloaded: downloaded, total: total),
        ),
      );
      ref.invalidate(geositeIndexProvider);
      state = GeoReady(lastUpdated: finished);
    } on ReasonException catch (e) {
      state = GeoError(e.reason);
    } catch (e) {
      state = GeoError(AppMessage.text(e.toString().replaceFirst('Exception: ', '')));
    }
  }
}

final geoProvider = NotifierProvider<GeoNotifier, GeoState>(GeoNotifier.new);

/// The index of `filesDir/geosite.dat` (null without the file), built off the UI isolate; [GeoNotifier]
/// refreshes it when the files change.
final geositeIndexProvider = FutureProvider<GeositeIndex?>(
  (ref) async {
    final dir = await ref.read(platformServiceProvider).filesDir();
    if (dir.isEmpty) return null;
    // One build at a time: a refresh while a build is running waits for it, then reads its cache.
    final run = _geositeLoads.then((_) => Isolate.run(() => GeositeIndex.load(dir)));
    _geositeLoads = run.then((_) {}, onError: (_) {});
    return run;
  },
  // A file that fails to parse fails again: no retries, the connect goes on without the index.
  retry: (_, _) => null,
);

Future<void> _geositeLoads = Future.value();
