import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// One geosite.dat entry: its domains, and how many of them xray-rust gets ([GeositeIndex.rustFile]).
typedef GeositeEntry = ({int domains, int rustDomains});

/// The codes in geosite.dat with their sizes, so rules never reference a missing
/// code and no core is handed an entry over its limits.
class GeositeIndex {
  /// Entries by lower-case code.
  final Map<String, GeositeEntry> entries;

  /// A copy of geosite.dat in the same directory with the entries over xray-rust's limits trimmed to them,
  /// when the original has any: xray-rust refuses the whole file for one entry over 32 MiB, and a code
  /// over 200k domains.
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
          return MapEntry(code, (domains: e[0], rustDomains: e[1]));
        });
        return GeositeIndex(entries, rustFile: rustFile);
      }
    } catch (_) {
      // No cache or an unreadable one: build it again.
    }
    final index = _build(source, rust);
    try {
      final tmp = File('${cache.path}.tmp');
      tmp.writeAsStringSync(
        jsonEncode({
          'version': version,
          'rustFile': index.rustFile,
          'entries': index.entries.map((code, e) => MapEntry(code, [e.domains, e.rustDomains])),
        }),
      );
      tmp.renameSync(cache.path);
    } catch (_) {
      // Rebuilt on the next load.
    }
    return index;
  }

  static GeositeIndex _build(File source, File rust) {
    final entries = <String, GeositeEntry>{};
    var trimmed = false;
    final raf = source.openSync();
    try {
      for (final record in _records(raf)) {
        final entry = _scan(record.body);
        if (entry.code == null) continue;
        entries[entry.code!.toLowerCase()] = (domains: entry.domains, rustDomains: entry.rustDomains);
        if (entry.rustDomains < entry.domains) trimmed = true;
      }
    } finally {
      raf.closeSync();
    }
    if (!trimmed) {
      if (rust.existsSync()) rust.deleteSync();
      return GeositeIndex(entries);
    }
    // A failed write leaves no copy behind: the previous one stays until the rename.
    final tmp = File('${rust.path}.tmp');
    try {
      final out = tmp.openSync(mode: FileMode.write);
      final input = source.openSync();
      try {
        for (final record in _records(input)) {
          final entry = _scan(record.body);
          if (entry.rustDomains == entry.domains) {
            out
              ..writeFromSync(record.header)
              ..writeFromSync(record.body);
            continue;
          }
          final body = _trim(record.body, entry.rustDomains);
          out
            ..writeFromSync(_varint(1 << 3 | 2))
            ..writeFromSync(_varint(body.length))
            ..writeFromSync(body);
        }
      } finally {
        input.closeSync();
        out.closeSync();
      }
      tmp.renameSync(rust.path);
    } finally {
      if (tmp.existsSync()) tmp.deleteSync();
    }
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

  static Uint8List _varint(int value) {
    final bytes = <int>[];
    for (var v = value; ; v >>= 7) {
      if (v < 0x80) return Uint8List.fromList(bytes..add(v));
      bytes.add((v & 0x7f) | 0x80);
    }
  }

  /// The fields of a `GeoSite` body: number and byte range (key included).
  static Iterable<({int number, int start, int end, int valueStart})> _fields(Uint8List body) sync* {
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
      final start = i;
      final key = varint();
      var valueStart = i;
      switch (key & 7) {
        case 0:
          varint();
        case 1:
          i += 8;
        case 5:
          i += 4;
        case 2:
          final size = varint();
          valueStart = i;
          i += size;
        default:
          throw const FormatException('geosite.dat: unsupported wire type');
      }
      if (i > body.length) throw const FormatException('geosite.dat: truncated entry');
      yield (number: key >> 3, start: start, end: i, valueStart: valueStart);
    }
  }

  /// `GeoSite { string country_code = 1; repeated Domain domain = 2; … }`: the code, the domains, and how
  /// many of the first domains fit xray-rust's limits along with the other fields.
  static ({String? code, int domains, int rustDomains}) _scan(Uint8List body) {
    String? code;
    var domains = 0;
    var otherBytes = 0;
    for (final f in _fields(body)) {
      if (f.number == 2) {
        domains++;
      } else {
        otherBytes += f.end - f.start;
        if (f.number == 1) code = utf8.decode(Uint8List.sublistView(body, f.valueStart, f.end), allowMalformed: true);
      }
    }
    if (domains <= rustMaxDomains && body.length <= rustMaxEntryBytes) {
      return (code: code, domains: domains, rustDomains: domains);
    }
    // The trimmed body keeps the other fields and the first domains that fit.
    var size = otherBytes;
    var kept = 0;
    for (final f in _fields(body)) {
      if (f.number != 2) continue;
      if (kept == rustMaxDomains || size + f.end - f.start > rustMaxEntryBytes) break;
      size += f.end - f.start;
      kept++;
    }
    return (code: code, domains: domains, rustDomains: kept);
  }

  /// [body] with only its first [keep] domains.
  static Uint8List _trim(Uint8List body, int keep) {
    final out = BytesBuilder(copy: false);
    var kept = 0;
    for (final f in _fields(body)) {
      if (f.number == 2 && kept++ >= keep) continue;
      out.add(Uint8List.sublistView(body, f.start, f.end));
    }
    return out.takeBytes();
  }
}
