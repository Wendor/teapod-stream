/// SHA-256 and HMAC-SHA256, written here rather than taken from a package: they make the certificate fingerprint
/// the user confirms (the subscription TLS pin) and the per-host HWID. Tested against the FIPS 180-4 and RFC 4231
/// vectors (`test/core/crypto/sha256_test.dart`).
library;

import 'dart:typed_data';

/// HMAC-SHA256 (RFC 2104) of [message] under [key].
Uint8List hmacSha256(List<int> key, List<int> message) {
  final block = Uint8List(64)..setAll(0, key.length > 64 ? sha256(key) : key);
  final inner = sha256([for (final b in block) b ^ 0x36, ...message]);
  return sha256([for (final b in block) b ^ 0x5c, ...inner]);
}

/// SHA-256 (FIPS 180-4) of [data].
Uint8List sha256(List<int> data) {
  const k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  final h = <int>[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  int rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  final padLen = (data.length + 9 + 63) ~/ 64 * 64;
  final msg = Uint8List(padLen)
    ..setAll(0, data)
    ..[data.length] = 0x80;
  ByteData.sublistView(msg).setUint64(padLen - 8, data.length * 8);
  final view = ByteData.sublistView(msg);
  final w = List<int>.filled(64, 0);
  for (var off = 0; off < padLen; off += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = view.getUint32(off + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var [a, b, c, d, e, f, g, hh] = h;
    for (var i = 0; i < 64; i++) {
      final t1 = (hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + k[i] + w[i]) & 0xffffffff;
      final t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) & 0xffffffff;
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
      h[i] = (h[i] + v[i]) & 0xffffffff;
    }
  }
  final out = ByteData(32);
  for (var i = 0; i < 8; i++) {
    out.setUint32(i * 4, h[i]);
  }
  return out.buffer.asUint8List();
}
