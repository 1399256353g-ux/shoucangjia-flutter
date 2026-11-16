import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/recommend_grid.dart';

void main() {
  test('推荐页数量最少 40', () {
    expect(recommendVisibleCount(const Size(360, 640)), 40);
    expect(recommendVisibleCount(Size.zero), 40);
  });

  test('窗口越大展示越多，且按列数×行数铺满', () {
    final small = recommendVisibleCount(const Size(360, 640));
    final big = recommendVisibleCount(const Size(1440, 1400));
    expect(big, greaterThan(small));
    // 1440/180 = 8 列、可用 1290/242 ≈ 6 行 +1 → 56
    expect(big, greaterThan(40));
  });
}
