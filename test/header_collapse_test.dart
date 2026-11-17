import 'package:shoucangjia/header_collapse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('不可滚动时强制展开（P 锁死回归）', () {
    expect(
      headerActionFor(collapsed: true, pixels: 0, maxScrollExtent: 0),
      HeaderAction.expand,
    );
    expect(
      headerActionFor(collapsed: false, pixels: 0, maxScrollExtent: 0),
      HeaderAction.expand,
    );
  });

  test('内容刚够一屏（extent 30）不允许收起', () {
    expect(
      headerActionFor(collapsed: false, pixels: 20, maxScrollExtent: 30),
      HeaderAction.none,
    );
  });

  test('可滚动且上滑超过阈值才收起', () {
    expect(
      headerActionFor(collapsed: false, pixels: 64, maxScrollExtent: 300),
      HeaderAction.collapse,
    );
    expect(
      headerActionFor(collapsed: false, pixels: 10, maxScrollExtent: 300),
      HeaderAction.none,
    );
  });

  test('已到底强制展开', () {
    expect(
      headerActionFor(collapsed: true, pixels: 300, maxScrollExtent: 300),
      HeaderAction.expand,
    );
  });

  test('回顶与中途下滑都展开', () {
    expect(
      headerActionFor(collapsed: true, pixels: 0, maxScrollExtent: 300),
      HeaderAction.expand,
    );
    expect(
      headerActionFor(
          collapsed: true, pixels: 100, maxScrollExtent: 300, delta: -20),
      HeaderAction.expand,
    );
  });

  test('顶部 overscroll 展开，收起中不再重复动作', () {
    expect(
      headerActionFor(
          collapsed: true,
          pixels: 0,
          maxScrollExtent: 300,
          overscroll: true),
      HeaderAction.expand,
    );
    expect(
      headerActionFor(collapsed: true, pixels: 120, maxScrollExtent: 300),
      HeaderAction.none,
    );
  });
}
