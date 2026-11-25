import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One geosite.dat entry: its encoded size and the number of domains in it.
typedef GeositeEntry = ({int bytes, int domains});

/// The codes in geosite.dat with their sizes, so rules never reference a missing
/// code and no core is handed an entry over its limits.
class GeositeIndex {
  /// Entries by lower-case code.
  final Map<String, GeositeEntry> entries;

  /// A copy of geosite.dat in the same directory without the entries over xray-rust's limits, when the
  /// original has any: xray-rust refuses the whole file for one oversized entry.
  final String? rustFile;

  const GeositeIndex(this.entries, {this.rustFile});

  static const fileName = 'geosite.dat';
  static const rustFileName = 'geosite-rust.dat';
  static const _cacheName = 'geosite.index.json';

  /// xray-rust 0.10's limits for one entry (`MAX_GEODATA_ENTRY_SIZE`, `MAX_GEODATA_DOMAINS`).
  static const rustMaxEntryBytes = 32 * 1024 * 1024;
  static const rustMaxDomains = 200000;

  /// The entry of a rule's code (`code` or `code@attr`, any case), null when the file has none.
  GeositeEntry? operator [](String code) => entries[baseCode(code)];

  bool has(String code) => this[code] != null;

  static String baseCode(String code) => code.split('@').first.trim().toLowerCase();

  static bool fitsRust(GeositeEntry e) => e.bytes <= rustMaxEntryBytes && e.domains <= rustMaxDomains;

  /// The index of `dir/geosite.dat`, null without the file. Built once per file version and cached in
  /// `dir`; the xray-rust copy is written along with it. Blocking IO — run it off the UI isolate.
  static GeositeIndex? load(String dir) {
    final source = File('$dir/$fileName');
    if (!source.existsSync()) return null;
    final stat = source.statSync();
    final version = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
    final cache = File('$dir/$_cacheName');
    final rust = File('$dir/$rustFileName');
    try {
      final json = jsonDecode(cache.readAsStringSync()) as Map<String, dynamic>;
      final rustFile = json['rustFile'] as String?;
      if (json['version'] == version && (rustFile == null || rust.existsSync())) {
        final entries = (json['entries'] as Map<String, dynamic>).map((code, value) {
          final e = (value as List<dynamic>).cast<int>();
          return MapEntry(code, (bytes: e[0], domains: e[1]));
        });
        return GeositeIndex(entries, rustFile: rustFile);
      }
    } catch (_) {
      // No cache or an unreadable one: build it again.
    }
    final index = _build(source, rust);
    try {
      cache.writeAsStringSync(
        jsonEncode({
          'version': version,
          'rustFile': index.rustFile,
          'entries': index.entries.map((code, e) => MapEntry(code, [e.bytes, e.domains])),
        }),
      );
    } catch (_) {
      // Rebuilt on the next load.
    }
    return index;
  }

  static GeositeIndex _build(File source, File rust) {
    final entries = <String, GeositeEntry>{};
    var oversized = false;
    final raf = source.openSync();
    try {
      for (final record in _records(raf)) {
        final entry = _scan(record.body);
        if (entry.code == null) continue;
        entries[entry.code!.toLowerCase()] = (bytes: record.body.length, domains: entry.domains);
        if (record.body.length > rustMaxEntryBytes) oversized = true;
      }
    } finally {
      raf.closeSync();
    }
    if (!oversized) {
      if (rust.existsSync()) rust.deleteSync();
      return GeositeIndex(entries);
    }
    final tmp = File('${rust.path}.tmp');
    final out = tmp.openSync(mode: FileMode.write);
    final input = source.openSync();
    try {
      for (final record in _records(input)) {
        if (record.body.length > rustMaxEntryBytes) continue;
        out
          ..writeFromSync(record.header)
          ..writeFromSync(record.body);
      }
    } finally {
      input.closeSync();
      out.closeSync();
    }
    tmp.renameSync(rust.path);
    return GeositeIndex(entries, rustFile: rustFileName);
  }

  /// The top-level `repeated GeoSite entry = 1` records: the raw key+length header and the body.
  static Iterable<({Uint8List header, Uint8List body})> _records(RandomAccessFile raf) sync* {
    final length = raf.lengthSync();
    while (raf.positionSync() < length) {
      final start = raf.positionSync();
      final key = _readVarint(raf);
      if (key & 7 != 2) throw const FormatException('geosite.dat: unexpected top-level field');
      final size = _readVarint(raf);
      final headerLength = raf.positionSync() - start;
      raf.setPositionSync(start);
      final header = raf.readSync(headerLength);
      final body = raf.readSync(size);
      if (body.length != size) throw const FormatException('geosite.dat: truncated entry');
      yield (header: header, body: body);
    }
  }

  static int _readVarint(RandomAccessFile raf) {
    var result = 0;
    for (var shift = 0; shift < 64; shift += 7) {
      final b = raf.readByteSync();
      if (b < 0) throw const FormatException('geosite.dat: truncated varint');
      result |= (b & 0x7f) << shift;
      if (b < 0x80) return result;
    }
    throw const FormatException('geosite.dat: bad varint');
  }

  /// `GeoSite { string country_code = 1; repeated Domain domain = 2; … }`.
  static ({String? code, int domains}) _scan(Uint8List body) {
    String? code;
    var domains = 0;
    var i = 0;
    int varint() {
      var result = 0;
      for (var shift = 0; shift < 64; shift += 7) {
        if (i >= body.length) throw const FormatException('geosite.dat: truncated entry');
        final b = body[i++];
        result |= (b & 0x7f) << shift;
        if (b < 0x80) return result;
      }
      throw const FormatException('geosite.dat: bad varint');
    }

    while (i < body.length) {
      final key = varint();
      switch (key & 7) {
        case 0:
          varint();
        case 1:
          i += 8;
        case 5:
          i += 4;
        case 2:
          final size = varint();
          if (key >> 3 == 1) code = utf8.decode(Uint8List.sublistView(body, i, i + size), allowMalformed: true);
          if (key >> 3 == 2) domains++;
          i += size;
        default:
          throw const FormatException('geosite.dat: unsupported wire type');
      }
    }
    return (code: code, domains: domains);
  }
}
