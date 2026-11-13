import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// The password didn't open the file, or the file was changed.
class WrongPassword implements Exception {
  const WrongPassword();
}

const _format = 'notoryx-pro-encrypted';

/// How hard the password is stretched. Higher is slower to guess, and
/// slower to open on a phone.
const defaultIterations = 200000;

/// Whether [text] is a password-protected export.
bool isEncryptedExport(String text) {
  try {
    final j = jsonDecode(text);
    return j is Map<String, Object?> && j['format'] == _format;
  } on FormatException {
    return false;
  }
}

Future<List<int>> _key(String password, List<int> salt, int iterations) async {
  final kdf = DartPbkdf2(
    macAlgorithm: DartHmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  final key = await kdf.deriveKeyFromPassword(password: password, nonce: salt);
  return key.extractBytes();
}

/// Wraps [plain] in a JSON container encrypted with AES-256-GCM under a key
/// stretched from [password] with PBKDF2-HMAC-SHA256.
Future<String> encryptExport(
  String plain,
  String password, {
  int iterations = defaultIterations,
  Random? random,
}) async {
  final r = random ?? Random.secure();
  final salt = List<int>.generate(16, (_) => r.nextInt(256));
  final nonce = List<int>.generate(12, (_) => r.nextInt(256));
  final aes = DartAesGcm.with256bits();
  final box = await aes.encrypt(
    utf8.encode(plain),
    secretKey: await aes.newSecretKeyFromBytes(
      await _key(password, salt, iterations),
    ),
    nonce: nonce,
  );
  return const JsonEncoder.withIndent('  ').convert({
    'format': _format,
    'formatVersion': 1,
    'kdf': 'pbkdf2-hmac-sha256',
    'iterations': iterations,
    'salt': base64Encode(salt),
    'cipher': 'aes-256-gcm',
    'nonce': base64Encode(nonce),
    'data': base64Encode([...box.cipherText, ...box.mac.bytes]),
  });
}

/// Opens a container made by [encryptExport]. Throws [WrongPassword] if
/// the password is wrong or the file was altered, and [FormatException]
/// if it isn't a container this version can read.
Future<String> decryptExport(String text, String password) async {
  final j = jsonDecode(text);
  if (j is! Map<String, Object?> ||
      j['format'] != _format ||
      j['formatVersion'] != 1 ||
      j['iterations'] is! int ||
      j['salt'] is! String ||
      j['nonce'] is! String ||
      j['data'] is! String) {
    throw const FormatException('Not a NOTORYX PRO encrypted export');
  }
  final iterations = j['iterations']! as int;
  if (iterations < 1 || iterations > 10000000) {
    throw const FormatException('Unreasonable key stretching');
  }
  final data = base64Decode(j['data']! as String);
  if (data.length < 16) throw const WrongPassword();
  final aes = DartAesGcm.with256bits();
  try {
    final plain = await aes.decrypt(
      SecretBox(
        data.sublist(0, data.length - 16),
        nonce: base64Decode(j['nonce']! as String),
        mac: Mac(data.sublist(data.length - 16)),
      ),
      secretKey: await aes.newSecretKeyFromBytes(
        await _key(password, base64Decode(j['salt']! as String), iterations),
      ),
    );
    return utf8.decode(plain);
  } on SecretBoxAuthenticationError {
    throw const WrongPassword();
  }
}
