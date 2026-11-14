import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/infinite.dart';

void main() {
  group('initialGridCount', () {
    test('空列表与非法页大小返回 0', () {
      expect(initialGridCount(0), 0);
      expect(initialGridCount(-5), 0);
      expect(initialGridCount(100, pageSize: 0), 0);
    });

    test('不足一页时全量显示', () {
      expect(initialGridCount(1), 1);
      expect(initialGridCount(59), 59);
    });

    test('超过一页只显示一页', () {
      expect(initialGridCount(60), 60);
      expect(initialGridCount(1426), 60);
      expect(initialGridCount(1426, pageSize: 80), 80);
    });
  });

  group('nextGridCount', () {
    test('每次追加一页并夹紧到总数', () {
      expect(nextGridCount(60, 1426), 120);
      expect(nextGridCount(120, 1426), 180);
      expect(nextGridCount(1400, 1426), 1426);
    });

    test('已到末尾或超出时保持不变', () {
      expect(nextGridCount(1426, 1426), 1426);
      expect(nextGridCount(9999, 1426), 1426);
    });

    test('非法当前值从 0 开始', () {
      expect(nextGridCount(-10, 1426), 60);
      expect(nextGridCount(60, 0), 0);
    });
  });

  group('shouldLoadNextPage', () {
    test('远离底部不加载', () {
      expect(
          shouldLoadNextPage(
              pixels: 100, maxScrollExtent: 9000, viewportDimension: 800),
          isFalse);
    });

    test('接近底部（默认 480px）加载', () {
      expect(
          shouldLoadNextPage(
              pixels: 8600, maxScrollExtent: 9000, viewportDimension: 800),
          isTrue);
      expect(
          shouldLoadNextPage(
              pixels: 9000, maxScrollExtent: 9000, viewportDimension: 800),
          isTrue);
    });

    test('阈值可调，视口非法时不加载', () {
      expect(
          shouldLoadNextPage(
              pixels: 8200,
              maxScrollExtent: 9000,
              viewportDimension: 800,
              threshold: 900),
          isTrue);
      expect(
          shouldLoadNextPage(
              pixels: 8000, maxScrollExtent: 9000, viewportDimension: 0),
          isFalse);
      expect(
          shouldLoadNextPage(
              pixels: 8000,
              maxScrollExtent: 9000,
              viewportDimension: 800,
              threshold: -1),
          isFalse);
    });
  });
}
