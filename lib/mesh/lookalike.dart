import 'dart:math' as math;

import 'model.dart';

/// Spots node names made to look like a trusted node's name: look-alike
/// letters (Cyrillic "а" for "a", "0" for "o"), or one character changed.
///
/// Anyone can set any name on either mesh, so this is a hint to check, never
/// proof. Exact copies on one radio are already flagged by `nameClashes`.
abstract final class Lookalike {
  static const _homoglyphs = {
    // Cyrillic
    'а': 'a', 'е': 'e', 'о': 'o', 'р': 'p', 'с': 'c', 'у': 'y', 'х': 'x', //
    'і': 'i', 'в': 'b', 'м': 'm', 'н': 'h', 'т': 't', 'к': 'k', 'ј': 'j',
    'ѕ': 's', 'ԁ': 'd', 'һ': 'h', 'ɡ': 'g',
    // Greek
    'κ': 'k', 'ο': 'o', 'ν': 'v', 'α': 'a', 'ρ': 'p', 'τ': 't', 'ι': 'i',
    // Digits and symbols used as letters
    '0': 'o', '1': 'l', 'i': 'l', '|': 'l', '3': 'e', '4': 'a', '5': 's',
    '7': 't', '8': 'b', r'$': 's', '@': 'a',
  };

  static final _keep = RegExp(r'[a-z0-9]');
  static final _letter = RegExp(r'\p{L}', unicode: true);

  /// [name] lower-cased, look-alike characters folded together, and spaces,
  /// punctuation and symbols removed.
  static String fold(String name) {
    final b = StringBuffer();
    for (final rune in name.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final mapped = _homoglyphs[ch] ?? ch;
      if (_keep.hasMatch(mapped) || (rune > 0x7f && _letter.hasMatch(mapped))) {
        b.write(mapped);
      }
    }
    return b.toString().replaceAll('rn', 'm').replaceAll('vv', 'w');
  }

  /// Whether [candidate] looks like [trusted] without being exactly the
  /// same text (ignoring case and outer spaces).
  static bool looksLike(String candidate, String trusted) {
    if (candidate.trim().toLowerCase() == trusted.trim().toLowerCase()) {
      return false;
    }
    final a = fold(candidate), b = fold(trusted);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    // "Relay 2" next to "Relay 1": numbered units of one group are normal.
    if (_unitNumbersOnly(candidate, trusted)) return false;
    if (math.min(a.length, b.length) < 5) return false;
    return _withinOneEdit(a, b);
  }

  /// The trusted node whose name [sender]'s name imitates, or null.
  ///
  /// [trusted] says whether a node is trusted. A trusted sender never
  /// imitates, and a node never imitates itself.
  static Node? imitated(
    Node sender,
    Iterable<Node> nodes,
    bool Function(Node) trusted,
  ) {
    if (sender.name.trim().isEmpty || trusted(sender)) return null;
    for (final n in nodes) {
      if (n.key == sender.key || n.name.trim().isEmpty) continue;
      if (trusted(n) && looksLike(sender.name, n.name)) return n;
    }
    return null;
  }

  static bool _unitNumbersOnly(String a, String b) {
    String plain(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    final base = RegExp(r'^(.*?)(\d*)$');
    final ma = base.firstMatch(plain(a))!, mb = base.firstMatch(plain(b))!;
    return ma.group(1) == mb.group(1) &&
        ma.group(1)!.isNotEmpty &&
        ma.group(2) != mb.group(2);
  }

  static bool _withinOneEdit(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    var i = 0, j = 0, edits = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        i++;
        j++;
        continue;
      }
      if (++edits > 1) return false;
      if (a.length > b.length) {
        i++;
      } else if (b.length > a.length) {
        j++;
      } else {
        i++;
        j++;
      }
    }
    return edits + (a.length - i) + (b.length - j) <= 1;
  }
}
