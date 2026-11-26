import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teapodstream/core/crypto/sha256.dart';

void main() {
  test('sha256 matches the FIPS 180-4 vectors', () {
    String hex(String s) => sha256(utf8.encode(s)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(hex(''), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(
      hex('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
    expect(hex('a' * 1000000), 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
  });

  test('HMAC-SHA256 matches RFC 4231 test case 2', () {
    final mac = hmacSha256(utf8.encode('Jefe'), utf8.encode('what do ya want for nothing?'));
    expect(
      mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
    );
  });

  test('HMAC-SHA256 hashes a key longer than the block first (RFC 4231 test case 6)', () {
    final mac = hmacSha256(
      List<int>.filled(131, 0xaa),
      utf8.encode('Test Using Larger Than Block-Size Key - Hash Key First'),
    );
    expect(
      mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      '60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54',
    );
  });
}
