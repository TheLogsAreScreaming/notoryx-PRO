import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/l10n/app_localizations.dart';

Map<String, String> strings(String lang) {
  final j =
      jsonDecode(File('lib/l10n/app_$lang.arb').readAsStringSync())
          as Map<String, dynamic>;
  return {
    for (final MapEntry(:key, :value) in j.entries)
      if (!key.startsWith('@')) key: value as String,
  };
}

Set<String> placeholders(String s) =>
    RegExp(r'\{(\w+)[,}]').allMatches(s).map((m) => m[1]!).toSet();

void main() {
  final en = strings('en');
  for (final lang in ['es', 'fr', 'de', 'pt', 'it']) {
    test('$lang has every string, with the same placeholders', () {
      final tr = strings(lang);
      expect(tr.keys.toSet(), en.keys.toSet());
      final wrong = [
        for (final k in en.keys)
          if (!setEquals(placeholders(en[k]!), placeholders(tr[k]!))) k,
      ];
      expect(wrong, isEmpty);
    });

    test('$lang loads and formats a plural', () async {
      final l = await AppLocalizations.delegate.load(Locale(lang));
      expect(l.unreadCount(3), contains('3'));
      expect(l.appTitle, 'NOTORYX PRO');
    });
  }
}

bool setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);
