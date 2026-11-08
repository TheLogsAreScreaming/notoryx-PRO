import 'package:flutter_test/flutter_test.dart';
import 'package:notoryx_pro/mesh/mecp.dart';
import 'package:notoryx_pro/mesh/mecp_codes.dart';
import 'package:notoryx_pro/mesh/mecp_labels.dart';
import 'package:notoryx_pro/mesh/mecp_translations.dart';

void main() {
  test('every published language covers every code', () {
    expect(mecpTranslations, hasLength(19));
    mecpTranslations.forEach((language, set) {
      expect(set.severities, hasLength(MecpSeverity.values.length));
      expect(set.codes.keys.toSet(), mecpCodes.keys.toSet(), reason: language);
      expect(set.categories.keys.toSet(), mecpCategories.keys.toSet());
    });
  });

  test('picks the language, script and Norwegian variants', () {
    final de = MecpLabels.forLocale('de');
    expect(de.code('M01'), mecpTranslations['de']!.codes['M01']);
    expect(de.code('M01'), isNot(mecpCodes['M01']));
    for (final (locale, key) in [
      (MecpLabels.forLocale('zh', country: 'CN'), 'zh-cn'),
      (MecpLabels.forLocale('zh', country: 'TW'), 'zh-tw'),
      (MecpLabels.forLocale('zh', script: 'Hant'), 'zh-tw'),
      (MecpLabels.forLocale('nb'), 'no'),
    ]) {
      expect(locale.code('M02'), mecpTranslations[key]!.codes['M02']);
    }
  });

  test('English and unknown languages use the English labels', () {
    for (final language in ['en', 'xx']) {
      final l = MecpLabels.forLocale(language);
      expect(l.severity(MecpSeverity.mayday), isNull);
      expect(l.code('M01'), mecpCodes['M01']);
      expect(l.category('M'), mecpCategories['M']);
      expect(l.code('Z99'), isNull);
    }
  });
}
