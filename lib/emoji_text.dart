/// Emoji/text robustness helpers (F12 follow-up, H12).
///
/// Some collection names consist of (or contain) emoji such as 🦶. Two things
/// can break their rendering:
///  * the default UI font has no emoji glyph and the platform fallback chain is
///    incomplete (Windows especially), and
///  * the string contains an unpaired UTF-16 surrogate (e.g. after a bad
///    truncation or a decoding error), which renders as a replacement box no
///    matter which font is used.
///
/// [kEmojiFontFallback] is applied to the global theme, and [fixEmojiText]
/// repairs strings at the data boundary so broken units never reach a `Text`.
library;

/// Platform emoji fonts in resolution order. Missing families are ignored by
/// the engine, so the same list is safe on Android, iOS, Windows, macOS and
/// Linux.
const List<String> kEmojiFontFallback = <String>[
  'Apple Color Emoji', // iOS / macOS
  'Segoe UI Emoji', // Windows
  'Noto Color Emoji', // Android / Linux
  'Segoe UI Symbol', // Windows symbol fallback
  'Noto Sans Symbols 2', // Linux
  'Noto Sans Symbols',
];

/// Removes characters that cannot form a valid glyph:
///  * unpaired UTF-16 surrogates (high without low, or stray low),
///  * the Unicode replacement character U+FFFD (already broken input),
///  * BOM and zero-width space padding.
///
/// Valid surrogate pairs (most emoji), variation selectors (FE0F) and ZWJ
/// sequences (200D) are preserved, so multi-codepoint emoji keep working.
/// Leading/trailing whitespace is trimmed afterwards.
String fixEmojiText(String input) {
  if (input.isEmpty) return input;
  final units = input.codeUnits;
  final out = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final u = units[i];
    if (u >= 0xD800 && u <= 0xDBFF) {
      if (i + 1 < units.length &&
          units[i + 1] >= 0xDC00 &&
          units[i + 1] <= 0xDFFF) {
        out.writeCharCode(u);
        out.writeCharCode(units[i + 1]);
        i++;
      }
      // Unpaired high surrogate: drop it.
      continue;
    }
    if (u >= 0xDC00 && u <= 0xDFFF) continue; // Stray low surrogate.
    if (u == 0xFFFD) continue; // Replacement character.
    if (u == 0xFEFF || u == 0x200B) continue; // BOM / zero-width space.
    out.writeCharCode(u);
  }
  return out.toString().trim();
}

/// [fixEmojiText] with a fallback for names that become empty after repair.
String fixDisplayName(String name, {String fallback = '未命名'}) {
  final fixed = fixEmojiText(name);
  return fixed.isEmpty ? fallback : fixed;
}

/// True when [input] contains something [fixEmojiText] would remove, i.e. the
/// data needs repair before display.
bool hasBrokenText(String input) {
  return fixEmojiText(input) != input;
}

/// True when the string contains at least one astral-plane code point (most
/// emoji), useful for diagnostics and tests.
bool containsAstralChar(String input) {
  for (final r in input.runes) {
    if (r > 0xFFFF) return true;
  }
  return false;
}
