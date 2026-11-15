import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/loop_link.dart';

void main() {
  test('默认：连播开、循环关', () {
    const l = LoopLink();
    expect(l.loopOne, isFalse);
    expect(l.autoplay, isTrue);
    expect(l.nextEnabled, isTrue);
  });

  test('打开循环自动关闭连播并记住原状态', () {
    final l = const LoopLink().toggleLoop();
    expect(l.loopOne, isTrue);
    expect(l.autoplay, isFalse);
    expect(l.restoreAutoplay, isTrue);
    expect(l.nextEnabled, isFalse);
  });

  test('关闭循环恢复开启前的连播状态（原来开）', () {
    final l = const LoopLink().toggleLoop().toggleLoop();
    expect(l.loopOne, isFalse);
    expect(l.autoplay, isTrue);
    expect(l.nextEnabled, isTrue);
  });

  test('原来连播是关的，关闭循环后仍然关', () {
    final l = const LoopLink(autoplay: false).toggleLoop().toggleLoop();
    expect(l.loopOne, isFalse);
    expect(l.autoplay, isFalse);
    expect(l.restoreAutoplay, isFalse);
  });

  test('循环期间手动切连播不覆盖记忆值', () {
    final looping = const LoopLink().toggleLoop(); // restore=true
    final turnedOn = looping.toggleAutoplay();
    expect(turnedOn.autoplay, isTrue);
    expect(turnedOn.restoreAutoplay, isTrue);
    // 循环优先级最高：连播开着也不调度下一条
    expect(turnedOn.nextEnabled, isFalse);
    final off = turnedOn.toggleLoop();
    expect(off.loopOne, isFalse);
    expect(off.autoplay, isTrue);
  });

  test('连续开关两次回到初始语义', () {
    final l = const LoopLink(autoplay: false).toggleLoop().toggleLoop();
    expect(l, const LoopLink(autoplay: false));
    final m = const LoopLink().toggleLoop().toggleLoop();
    expect(m, const LoopLink());
  });
}
