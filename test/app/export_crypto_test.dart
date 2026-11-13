import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/export_crypto.dart';

void main() {
  const plain = '{"format":"notoryx-pro-messages","messages":[]}';

  test('round trips, and the text is not in the file', () async {
    final box = await encryptExport(plain, 'correct horse', iterations: 1000);
    expect(isEncryptedExport(box), isTrue);
    expect(isEncryptedExport(plain), isFalse);
    expect(box.contains('notoryx-pro-messages'), isFalse);
    expect(await decryptExport(box, 'correct horse'), plain);
  });

  test('a wrong password or a changed file is refused', () async {
    final box = await encryptExport(plain, 'right', iterations: 1000);
    await expectLater(
      decryptExport(box, 'wrong'),
      throwsA(isA<WrongPassword>()),
    );
    final j = jsonDecode(box) as Map<String, dynamic>;
    final data = base64Decode(j['data'] as String)..[0] ^= 1;
    j['data'] = base64Encode(data);
    await expectLater(
      decryptExport(jsonEncode(j), 'right'),
      throwsA(isA<WrongPassword>()),
    );
  });

  test('each export gets a fresh salt and nonce', () async {
    final a = jsonDecode(await encryptExport(plain, 'p', iterations: 1000));
    final b = jsonDecode(await encryptExport(plain, 'p', iterations: 1000));
    expect(a['salt'], isNot(b['salt']));
    expect(a['nonce'], isNot(b['nonce']));
  });

  test('the same salt and nonce always give the same file', () async {
    final fixed = Random(7);
    final a = await encryptExport('x', 'p', iterations: 10, random: fixed);
    final b = await encryptExport('x', 'p', iterations: 10, random: Random(7));
    expect(jsonDecode(a)['data'], jsonDecode(b)['data']);
  });

  test(
    'refuses files that aren\'t containers, or ask for absurd work',
    () async {
      await expectLater(decryptExport('{}', 'p'), throwsFormatException);
      final j =
          jsonDecode(await encryptExport(plain, 'p', iterations: 1000))
              as Map<String, dynamic>;
      j['iterations'] = 999999999;
      await expectLater(
        decryptExport(jsonEncode(j), 'p'),
        throwsFormatException,
      );
    },
  );
}
