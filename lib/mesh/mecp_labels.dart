import 'mecp.dart';
import 'mecp_codes.dart';
import 'mecp_translations.dart';

/// One language's names for MECP severities, categories and codes.
class MecpLabelSet {
  const MecpLabelSet({
    required this.severities,
    required this.categories,
    required this.codes,
  });

  /// In [MecpSeverity] order.
  final List<String> severities;
  final Map<String, String> categories;
  final Map<String, String> codes;
}

/// MECP labels for a phone's language, falling back to English one label
/// at a time. Only the words shown change: messages on the air always use
/// the language-neutral codes.
class MecpLabels {
  const MecpLabels._(this._set);

  /// Labels for a language such as `de`, with its script or region if any.
  factory MecpLabels.forLocale(
    String language, {
    String? script,
    String? country,
  }) {
    final String key;
    if (language == 'zh') {
      final traditional =
          script == 'Hant' || const {'TW', 'HK', 'MO'}.contains(country);
      key = traditional ? 'zh-tw' : 'zh-cn';
    } else if (language == 'nb' || language == 'nn') {
      key = 'no';
    } else {
      key = language;
    }
    return MecpLabels._(mecpTranslations[key]);
  }

  final MecpLabelSet? _set;

  /// The translated severity; null in English, where the app's own words
  /// are used.
  String? severity(MecpSeverity s) => _set?.severities[s.index];

  /// The name of [category].
  String category(String category) =>
      _set?.categories[category] ?? mecpCategories[category] ?? category;

  /// What [code] means, or null if it isn't a known code.
  String? code(String code) => _set?.codes[code] ?? mecpCodes[code];
}
