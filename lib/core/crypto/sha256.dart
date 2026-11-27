/// SHA-256 and HMAC-SHA256, written here rather than taken from a package: they make the certificate fingerprint
/// the user confirms (the subscription TLS pin), the per-host HWID and the geodata checksum. Tested against the
/// FIPS 180-4 and RFC 4231 vectors (`test/core/crypto/sha256_test.dart`).
library;

import 'dart:math';
import 'dart:typed_data';

/// HMAC-SHA256 (RFC 2104) of [message] under [key].
Uint8List hmacSha256(List<int> key, List<int> message) {
  final block = Uint8List(64)..setAll(0, key.length > 64 ? sha256(key) : key);
  final inner = sha256([for (final b in block) b ^ 0x36, ...message]);
  return sha256([for (final b in block) b ^ 0x5c, ...inner]);
}

/// SHA-256 (FIPS 180-4) of [data].
Uint8List sha256(List<int> data) => (Sha256()..add(data)).close();

/// SHA-256 of data that arrives in pieces (a download): [add] each piece, then [close] once for the hash.
/// Keeps one 64-byte block, not the data.
class Sha256 {
  static const _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final _h = <int>[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  final _block = Uint8List(64);
  late final _view = ByteData.sublistView(_block);
  final _w = List<int>.filled(64, 0);
  var _fill = 0;
  var _length = 0;
  var _closed = false;

  void add(List<int> data) {
    if (_closed) throw StateError('Sha256 is closed');
    _length += data.length;
    for (var i = 0; i < data.length;) {
      final n = min(64 - _fill, data.length - i);
      _block.setRange(_fill, _fill + n, data, i);
      _fill += n;
      i += n;
      if (_fill == 64) _compress();
    }
  }

  /// The hash of everything added; the hasher takes no more data.
  Uint8List close() {
    if (_closed) throw StateError('Sha256 is closed');
    _closed = true;
    _block[_fill++] = 0x80;
    if (_fill > 56) {
      _block.fillRange(_fill, 64, 0);
      _compress();
    }
    _block.fillRange(_fill, 56, 0);
    _view.setUint64(56, _length * 8);
    _compress();
    final out = ByteData(32);
    for (var i = 0; i < 8; i++) {
      out.setUint32(i * 4, _h[i]);
    }
    return out.buffer.asUint8List();
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  void _compress() {
    final w = _w;
    for (var i = 0; i < 16; i++) {
      w[i] = _view.getUint32(i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var [a, b, c, d, e, f, g, hh] = _h;
    for (var i = 0; i < 64; i++) {
      final t1 = (hh + (_rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25)) + ((e & f) ^ (~e & g)) + _k[i] + w[i]) & 0xffffffff;
      final t2 = ((_rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    final v = [a, b, c, d, e, f, g, hh];
    for (var i = 0; i < 8; i++) {
      _h[i] = (_h[i] + v[i]) & 0xffffffff;
    }
    _fill = 0;
  }
}
