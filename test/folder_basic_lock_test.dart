import 'package:shoucangjia/folder_structure_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('basicLocked', () {
    test('普通目录不锁', () {
      expect(
        basicLocked(
          isBasic: false,
          listed: false,
          basicsKnown: true,
          authors: 3,
          unlocked: false,
        ),
        isFalse,
      );
    });

    test('注册表登记的基础库锁死（除非手动解锁）', () {
      expect(
        basicLocked(
          isBasic: true,
          listed: true,
          basicsKnown: true,
          authors: 5,
          unlocked: false,
        ),
        isTrue,
      );
      expect(
        basicLocked(
          isBasic: true,
          listed: true,
          basicsKnown: true,
          authors: 5,
          unlocked: true,
        ),
        isFalse,
      );
    });

    test('注册表已不登记、只剩 @作者 残留 → 自动解锁（A2）', () {
      expect(
        basicLocked(
          isBasic: true,
          listed: false,
          basicsKnown: true,
          authors: 4,
          unlocked: false,
        ),
        isFalse,
      );
    });

    test('注册表读不到时保持保守锁定', () {
      expect(
        basicLocked(
          isBasic: true,
          listed: false,
          basicsKnown: false,
          authors: 4,
          unlocked: false,
        ),
        isTrue,
      );
    });

    test('无作者的目录一律解锁', () {
      expect(
        basicLocked(
          isBasic: true,
          listed: true,
          basicsKnown: true,
          authors: 0,
          unlocked: false,
        ),
        isFalse,
      );
    });
  });
}
