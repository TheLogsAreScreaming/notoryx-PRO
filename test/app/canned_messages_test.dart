import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/app/canned_messages.dart';

void main() {
  group('CannedMessages', () {
    test('encode and decode round-trips', () {
      final original = const CannedMessages().add('Hello').add('On my way');
      final decoded = CannedMessages.decode(original.encode());
      expect(decoded.messages.length, 2);
      expect(decoded.messages[0].text, 'Hello');
      expect(decoded.messages[1].text, 'On my way');
    });

    test('decode null returns empty', () {
      expect(CannedMessages.decode(null).messages, isEmpty);
    });

    test('decode invalid JSON returns empty', () {
      expect(CannedMessages.decode('not json').messages, isEmpty);
    });

    test('add trims whitespace', () {
      final c = const CannedMessages().add('  trimmed  ');
      expect(c.messages.single.text, 'trimmed');
    });

    test('add ignores blank text', () {
      final c = const CannedMessages().add('   ');
      expect(c.messages, isEmpty);
    });

    test('add increments IDs', () {
      final c = const CannedMessages().add('a').add('b').add('c');
      final ids = c.messages.map((m) => m.id).toList();
      expect(ids, [1, 2, 3]);
    });

    test('remove deletes by ID', () {
      final c = const CannedMessages().add('keep').add('remove');
      final id = c.messages.last.id;
      final after = c.remove(id);
      expect(after.messages.length, 1);
      expect(after.messages.single.text, 'keep');
    });

    test('fromJson ignores entries with blank text', () {
      expect(CannedMessage.fromJson({'id': 1, 't': '  '}), isNull);
    });
  });
}
