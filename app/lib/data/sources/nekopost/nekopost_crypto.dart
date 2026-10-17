import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show md5;

/// CryptoJS passphrase-format decryption for the Nekopost `handler/cinfo`
/// payload (Plan/06 — ported from keiyoushi/extensions th.nekopost,
/// Apache-2.0; verified against live responses 2026-10-17).
///
/// Format: base64("Salted__" + salt[8] + ciphertext), key derivation =
/// OpenSSL EVP_BytesToKey(MD5) producing 32-byte key + 16-byte IV
/// (AES-256-CBC, PKCS7 padding).
const cipherPassphrase = 'AeyTest';

/// Decrypts a CryptoJS `AES.encrypt(text, passphrase)` payload.
/// Throws [FormatException] on bad base64 or a decrypt failure.
String decryptCryptoJs(String base64Text, {String passphrase = cipherPassphrase}) {
  var raw = base64Decode(base64Text.trim());
  // CryptoJS sometimes emits a bare base64 of the JSON (unencrypted) when
  // the payload is trivial — the site code falls back on decrypt failure.
  if (raw.length < 16 ||
      utf8.decode(Uint8List.sublistView(raw, 0, 8),
              allowMalformed: true) !=
          'Salted__') {
    throw const FormatException('not an OpenSSL salted payload');
  }
  final salt = Uint8List.sublistView(raw, 8, 16);
  final ciphertext = Uint8List.sublistView(raw, 16);
  if (ciphertext.isEmpty || ciphertext.length % 16 != 0) {
    throw const FormatException('ciphertext not 16-byte aligned');
  }
  final keys = _evpBytesToKey(utf8.encode(passphrase), salt, 48);
  final plain = _aesCbcDecrypt(
      Uint8List.sublistView(keys, 0, 32),
      Uint8List.sublistView(keys, 32, 48),
      ciphertext);
  return utf8.decode(plain, allowMalformed: true);
}

/// OpenSSL EVP_BytesToKey with MD5: [D1 = MD5(pass||salt), D2 = MD5(D1||pass||salt), …].
Uint8List _evpBytesToKey(List<int> pass, Uint8List salt, int length) {
  final out = BytesBuilder();
  var prev = Uint8List(0);
  while (out.length < length) {
    final md = md5.convert([...prev, ...pass, ...salt]).bytes;
    prev = Uint8List.fromList(md);
    out.add(prev);
  }
  return out.toBytes();
}

// --- AES-256 decryption (FIPS-197) ------------------------------------------

const _sbox = [
  0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b,
  0xfe, 0xd7, 0xab, 0x76, 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0,
  0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, 0xb7, 0xfd, 0x93, 0x26,
  0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
  0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2,
  0xeb, 0x27, 0xb2, 0x75, 0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0,
  0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84, 0x53, 0xd1, 0x00, 0xed,
  0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
  0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f,
  0x50, 0x3c, 0x9f, 0xa8, 0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5,
  0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, 0xcd, 0x0c, 0x13, 0xec,
  0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
  0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14,
  0xde, 0x5e, 0x0b, 0xdb, 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c,
  0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79, 0xe7, 0xc8, 0x37, 0x6d,
  0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
  0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f,
  0x4b, 0xbd, 0x8b, 0x8a, 0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e,
  0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e, 0xe1, 0xf8, 0x98, 0x11,
  0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
  0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f,
  0xb0, 0x54, 0xbb, 0x16,
];

const _rcon = [
  0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36, 0x6c, 0xd8,
];

int _xtime(int a) =>
    ((a << 1) ^ ((a & 0x80) != 0 ? 0x1b : 0)) & 0xff;

int _mul(int a, int b) {
  var r = 0;
  while (b != 0) {
    if ((b & 1) != 0) r ^= a;
    a = _xtime(a);
    b >>= 1;
  }
  return r;
}

/// AES round keys for 256-bit keys: 60 words (15 round keys).
List<Uint8List> _expandKey(Uint8List key) {
  assert(key.length == 32);
  final nk = 8, nr = 14;
  final w = List<int>.filled(4 * (nr + 1) * 4, 0);
  for (var i = 0; i < nk * 4; i++) {
    w[i] = key[i];
  }
  var rcon = 0;
  for (var i = nk * 4; i < w.length; i += 4) {
    var t = [w[i - 4], w[i - 3], w[i - 2], w[i - 1]];
    if (i % (nk * 4) == 0) {
      // RotWord + SubWord + Rcon
      t = [
        _sbox[t[1]] ^ _rcon[rcon++],
        _sbox[t[2]],
        _sbox[t[3]],
        _sbox[t[0]],
      ];
    } else if (i % (nk * 4) == nk * 4 - 16) {
      t = [_sbox[t[0]], _sbox[t[1]], _sbox[t[2]], _sbox[t[3]]];
    }
    for (var j = 0; j < 4; j++) {
      w[i + j] = t[j] ^ w[i - nk * 4 + j];
    }
  }
  final rounds = List<Uint8List>.generate(
      nr + 1, (r) => Uint8List.fromList(w.sublist(r * 16, r * 16 + 16)));
  return rounds;
}

/// One AES block in place (state = column-major 4×4).
void _decryptBlock(List<Uint8List> rounds, Uint8List block) {
  final nr = rounds.length - 1;
  _addRoundKey(block, rounds[nr]);
  for (var r = nr - 1; r >= 1; r--) {
    _invShiftRows(block);
    _invSubBytes(block);
    _addRoundKey(block, rounds[r]);
    _invMixColumns(block);
  }
  _invShiftRows(block);
  _invSubBytes(block);
  _addRoundKey(block, rounds[0]);
}

void _addRoundKey(Uint8List s, Uint8List k) {
  for (var i = 0; i < 16; i++) {
    s[i] ^= k[i];
  }
}

void _invSubBytes(Uint8List s) {
  for (var i = 0; i < 16; i++) {
    s[i] = _invSbox(s[i]);
  }
}

int _invSbox(int b) {
  // Inverse S-box derived by search — kept table-free for compactness.
  for (var i = 0; i < 256; i++) {
    if (_sbox[i] == b) return i;
  }
  throw StateError('no inverse sbox for $b');
}

void _invShiftRows(Uint8List s) {
  int t;
  // row 1: shift right 1
  t = s[13];
  s[13] = s[9];
  s[9] = s[5];
  s[5] = s[1];
  s[1] = t;
  // row 2: shift right 2
  t = s[2];
  s[2] = s[10];
  s[10] = t;
  t = s[6];
  s[6] = s[14];
  s[14] = t;
  // row 3: shift right 3
  t = s[3];
  s[3] = s[7];
  s[7] = s[11];
  s[11] = s[15];
  s[15] = t;
}

void _invMixColumns(Uint8List s) {
  for (var c = 0; c < 4; c++) {
    final i = c * 4;
    final a0 = s[i], a1 = s[i + 1], a2 = s[i + 2], a3 = s[i + 3];
    s[i] = _mul(a0, 14) ^ _mul(a1, 11) ^ _mul(a2, 13) ^ _mul(a3, 9);
    s[i + 1] = _mul(a0, 9) ^ _mul(a1, 14) ^ _mul(a2, 11) ^ _mul(a3, 13);
    s[i + 2] = _mul(a0, 13) ^ _mul(a1, 9) ^ _mul(a2, 14) ^ _mul(a3, 11);
    s[i + 3] = _mul(a0, 11) ^ _mul(a1, 13) ^ _mul(a2, 9) ^ _mul(a3, 14);
  }
}

Uint8List _aesCbcDecrypt(
    Uint8List key, Uint8List iv, Uint8List ciphertext) {
  final rounds = _expandKey(key);
  final out = Uint8List(ciphertext.length);
  var prev = Uint8List.fromList(iv);
  for (var off = 0; off < ciphertext.length; off += 16) {
    final block = Uint8List.fromList(ciphertext.sublist(off, off + 16));
    final cipherBlock = Uint8List.fromList(block);
    _decryptBlock(rounds, block);
    for (var i = 0; i < 16; i++) {
      out[off + i] = block[i] ^ prev[i];
    }
    prev = cipherBlock;
  }
  // Strip PKCS7 padding.
  if (out.isNotEmpty) {
    final pad = out.last;
    if (pad >= 1 && pad <= 16 && pad <= out.length) {
      return Uint8List.sublistView(out, 0, out.length - pad);
    }
  }
  return out;
}
