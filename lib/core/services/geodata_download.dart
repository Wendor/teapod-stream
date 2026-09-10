import 'dart:io';

import 'package:http/http.dart' as http;

/// Stage a complete pair; only the native validator may activate it.
class GeodataDownload {
  static const maxFileBytes = 128 * 1024 * 1024;

  static Future<void> install({
    required Directory filesDir,
    required String geoipUrl,
    required String geositeUrl,
    required Future<void> Function(String revision) activate,
    required void Function(int bytes) onProgress,
    http.Client? client,
  }) async {
    final revision = 'revision-${DateTime.now().microsecondsSinceEpoch}';
    final staging = Directory('${filesDir.path}/geodata/$revision');
    await staging.create(recursive: true);
    final connection = client ?? http.Client();
    var activated = false;
    try {
      for (final (name, url) in [
        ('geoip.dat', geoipUrl),
        ('geosite.dat', geositeUrl),
      ]) {
        final response = await connection
            .send(http.Request('GET', Uri.parse(url)))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != 200) {
          throw HttpException('$name: HTTP ${response.statusCode}');
        }
        if ((response.contentLength ?? 0) > maxFileBytes) {
          throw FormatException('$name превышает 128 MiB');
        }
        var bytes = 0;
        final sink = File('${staging.path}/$name').openWrite();
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 30),
          )) {
            bytes += chunk.length;
            if (bytes > maxFileBytes) {
              throw FormatException('$name превышает 128 MiB');
            }
            sink.add(chunk);
            onProgress(chunk.length);
          }
        } finally {
          await sink.close();
        }
        if (bytes == 0) throw FormatException('$name пуст');
      }
      await activate(revision);
      activated = true;
    } finally {
      connection.close();
      if (!activated && await staging.exists()) {
        await staging.delete(recursive: true);
      }
    }
  }
}
