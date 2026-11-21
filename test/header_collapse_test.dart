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

  // owner 2026-11-22 回归：滚到底时收起态必须稳定。
  // 旧规则 `pixels >= maxScrollExtent → expand` 会在这里与「收起缩小 max」互相喂回，
  // 表现为信息栏逐帧闪隐；新规则到底不再强制展开。
  test('已收起且到底：保持收起（不得因 max 变化自激）', () {
    expect(
      headerActionFor(collapsed: true, pixels: 300, maxScrollExtent: 300),
      HeaderAction.none,
    );
    expect(
      headerActionFor(
          collapsed: true, pixels: 300, maxScrollExtent: 300, delta: 12),
      HeaderAction.none,
    );
  });

  test('未收起且接近底部：留不出收起余量时保持展开', () {
    // 收起会让 max 减少 ~120px；剩余 100px 不够 → 不收起，避免顶到底后反复展开。
    expect(
      headerActionFor(
          collapsed: false,
          pixels: 200,
          maxScrollExtent: 300,
          headerExtent: 120),
      HeaderAction.none,
    );
    // 余量足够（300-64=236 > 120+48）才允许收起。
    expect(
      headerActionFor(
          collapsed: false,
          pixels: 64,
          maxScrollExtent: 300,
          headerExtent: 120),
      HeaderAction.collapse,
    );
  });

  test('底部继续下推（overscroll）展开一次后不再抖动', () {
    expect(
      headerActionFor(
          collapsed: true,
          pixels: 300,
          maxScrollExtent: 300,
          overscroll: true),
      HeaderAction.expand,
    );
    // 展开后 max 变大，剩余 = headerExtent，不足以再次收起。
    expect(
      headerActionFor(
          collapsed: false,
          pixels: 300,
          maxScrollExtent: 420,
          headerExtent: 120),
      HeaderAction.none,
    );
  });

  test('已收起但 max 过小：展开恢复滚动（无定时器兜底）', () {
    expect(
      headerActionFor(collapsed: true, pixels: 30, maxScrollExtent: 30),
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
