import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_drag.dart';

void main() {
  group('AuthorDrag.progress', () {
    test('前段线性跟手', () {
      expect(AuthorDrag.progress(dx: 0, width: 400), 0);
      expect(AuthorDrag.progress(dx: 100, width: 400), closeTo(0.25, 1e-9));
      expect(AuthorDrag.progress(dx: 240, width: 400), closeTo(0.6, 1e-9));
    });

    test('超过阻尼点后位移折算变小', () {
      final p = AuthorDrag.progress(dx: 320, width: 400);
      expect(p, closeTo(0.6 + 0.2 * AuthorDrag.dampFactor, 1e-9));
      expect(p, lessThan(0.8));
    });

    test('拖过整屏也不超过 1', () {
      expect(AuthorDrag.progress(dx: 2000, width: 400), 1);
    });

    test('反向位移不产生负进度，宽度非法时返回 0', () {
      expect(AuthorDrag.progress(dx: -50, width: 400), 0);
      expect(AuthorDrag.progress(dx: 100, width: 0), 0);
    });
  });

  group('AuthorDrag.completes', () {
    test('进度达到 30% 即完成', () {
      expect(AuthorDrag.completes(progress: 0.3, velocity: 0), isTrue);
      expect(AuthorDrag.completes(progress: 0.29, velocity: 0), isFalse);
    });

    test('速度足够时即使进度不足也完成', () {
      expect(
          AuthorDrag.completes(
              progress: 0.1, velocity: -AuthorDrag.flingVelocity),
          isTrue);
      expect(
          AuthorDrag.completes(
              progress: 0.1, velocity: -(AuthorDrag.flingVelocity - 1)),
          isFalse);
    });

    test('右向速度不会误触发完成', () {
      expect(AuthorDrag.completes(progress: 0.2, velocity: 2000), isFalse);
    });
  });

  group('AuthorDrag.dismisses', () {
    test('进度低于 70% 即收回', () {
      expect(AuthorDrag.dismisses(progress: 0.7, velocity: 0), isTrue);
      expect(AuthorDrag.dismisses(progress: 0.71, velocity: 0), isFalse);
    });

    test('右向速度足够时即使进度高也收回', () {
      expect(
          AuthorDrag.dismisses(progress: 0.95, velocity: AuthorDrag.flingVelocity),
          isTrue);
      expect(
          AuthorDrag.dismisses(
              progress: 0.95, velocity: AuthorDrag.flingVelocity - 1),
          isFalse);
    });
  });

  group('AuthorDrag.progressFromClose', () {
    test('右移减小进度', () {
      expect(AuthorDrag.progressFromClose(start: 1, dx: 100, width: 400),
          closeTo(0.75, 1e-9));
    });

    test('越界裁剪', () {
      expect(AuthorDrag.progressFromClose(start: 1, dx: 900, width: 400), 0);
      expect(AuthorDrag.progressFromClose(start: 1, dx: -100, width: 400), 1);
    });
  });
}
