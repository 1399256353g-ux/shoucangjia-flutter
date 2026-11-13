import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/emoji_text.dart';

void main() {
  group('fixEmojiText', () {
    test('keeps normal Chinese and ASCII names untouched', () {
      expect(fixEmojiText('其他'), '其他');
      expect(fixEmojiText('vibe'), 'vibe');
    });

    test('keeps astral emoji and their surrogate pair', () {
      const name = '🦶';
      final fixed = fixEmojiText(name);
      expect(fixed, name);
      expect(fixed.runes.length, 1);
      expect(containsAstralChar(fixed), isTrue);
    });

    test('keeps ZWJ and variation selectors used by compound emoji', () {
      const family = '👨‍👩‍👧';
      expect(fixEmojiText(family), family);
      expect(fixEmojiText('❤️'), '❤️');
    });

    test('drops an unpaired high surrogate instead of rendering a box', () {
      final broken = 'a\uD83Db';
      final fixed = fixEmojiText(broken);
      expect(fixed, 'ab');
      expect(hasBrokenText(broken), isTrue);
    });

    test('drops a stray low surrogate', () {
      expect(fixEmojiText('\uDE36x'), 'x');
    });

    test('drops replacement chars, BOM and zero-width spaces', () {
      expect(fixEmojiText('\uFEFF\u200B🦶\uFFFD'), '🦶');
    });

    test('trims surrounding whitespace', () {
      expect(fixEmojiText('  🦶  '), '🦶');
    });

    test('hasBrokenText is false for valid emoji names', () {
      expect(hasBrokenText('🦶'), isFalse);
      expect(hasBrokenText('其他'), isFalse);
    });
  });

  group('fixDisplayName', () {
    test('falls back when the name becomes empty after repair', () {
      expect(fixDisplayName('\uFFFD\uD83D'), '未命名');
      expect(fixDisplayName('   '), '未命名');
    });

    test('keeps valid names and accepts a custom fallback', () {
      expect(fixDisplayName('🦶'), '🦶');
      expect(fixDisplayName('', fallback: '收藏夹'), '收藏夹');
    });
  });
}
