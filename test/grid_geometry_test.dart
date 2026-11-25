import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/grid_geometry.dart';

/// 第三十二批：网格几何（列数/列宽/行高）只留一份实现。
///
/// 缺口：`author_index` / `thumb_prefetch` 用
/// `ceil((可用宽 + 间距) / (最大列宽 + 间距))`、`recommend_grid` 用
/// `ceil(宽 / 最大列宽)`，而 Flutter 的 `SliverGridDelegateWithMaxCrossAxisExtent`
/// 是 `ceil(可用宽 / (最大列宽 + 间距))`。同一个窗口，客户端算出的列数与
/// 真实排版不同 → 字母索引滚错行、首屏预热多拉/少拉一整列。
void main() {
  group('gridColumnCount 与 Flutter delegate 同一规则', () {
    test('宽 400 / max 180 / 间距 10：2 列（旧写法算出 3 列）', () {
      expect(
          gridColumnCount(
              crossAxisExtent: 376, maxCrossAxisExtent: 180, spacing: 10),
          2);
      // 旧写法（作者索引 / 首屏预热）分子多一个间距：
      expect(((376 + 10) / (180 + 10)).ceil(), 3);
      // 旧写法（推荐页）完全没算间距：
      expect((376 / 180).ceil(), 3);
    });

    test('整除边界不多算一列', () {
      // 190 × 2 = 380 恰好放两列；若像旧写法那样在分子加间距就会算出 3 列。
      expect(
          gridColumnCount(
              crossAxisExtent: 380, maxCrossAxisExtent: 180, spacing: 10),
          2);
      expect(
          gridColumnCount(
              crossAxisExtent: 1440, maxCrossAxisExtent: 180, spacing: 2),
          8);
      expect(
          gridColumnCount(
              crossAxisExtent: 1440, maxCrossAxisExtent: 182, spacing: 2),
          8);
    });

    test('非法参数不抛：0/负数/非有限宽一律 1 列', () {
      expect(
          gridColumnCount(
              crossAxisExtent: 0, maxCrossAxisExtent: 180, spacing: 10),
          1);
      expect(
          gridColumnCount(
              crossAxisExtent: -50, maxCrossAxisExtent: 180, spacing: 10),
          1);
      expect(
          gridColumnCount(
              crossAxisExtent: double.infinity,
              maxCrossAxisExtent: 180,
              spacing: 10),
          1);
      expect(
          gridColumnCount(
              crossAxisExtent: 400,
              maxCrossAxisExtent: double.nan,
              spacing: 10),
          1);
      expect(
          gridColumnCount(
              crossAxisExtent: 400,
              maxCrossAxisExtent: 180,
              spacing: double.nan),
          3);
    });

    test('列宽扣掉间距后均分；行高 = 列宽 / 宽高比', () {
      expect(gridTileWidth(crossAxisExtent: 376, columns: 2, spacing: 10), 183);
      expect(gridTileHeight(tileWidth: 183, aspectRatio: 0.86),
          closeTo(212.79, 0.01));
      // 列数非法（0）按 1 列处理，不是按 0 列（除零）。
      expect(gridTileWidth(crossAxisExtent: 376, columns: 0, spacing: 10), 376);
      expect(gridTileWidth(crossAxisExtent: 0, columns: 2, spacing: 10), 0);
      expect(gridTileHeight(tileWidth: 0, aspectRatio: 0.86), 0);
      expect(gridTileHeight(tileWidth: 183, aspectRatio: 0), 0);
    });
  });

  group('实测对齐：与真实 GridView 的列数逐一相等', () {
    /// 真机同款 delegate，数第一行有几个格子。
    Future<int> realColumns(
        WidgetTester t, double width, double max, double gap) async {
      t.view.physicalSize = Size(width, 600);
      t.view.devicePixelRatio = 1.0;
      final keys = [for (var i = 0; i < 60; i++) GlobalKey()];
      await t.pumpWidget(MaterialApp(
        home: GridView.builder(
          padding: EdgeInsets.zero,
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: max,
            mainAxisSpacing: gap,
            crossAxisSpacing: gap,
          ),
          itemCount: keys.length,
          itemBuilder: (c, i) => SizedBox(key: keys[i]),
        ),
      ));
      final y0 = (keys[0].currentContext!.findRenderObject() as RenderBox)
          .localToGlobal(Offset.zero)
          .dy;
      // 全部落在同一行（窗口很宽时格子数少于列数）就按格子总数算。
      var cols = keys.length;
      for (var i = 1; i < keys.length; i++) {
        final b = keys[i].currentContext?.findRenderObject() as RenderBox?;
        if (b == null) break;
        if (b.localToGlobal(Offset.zero).dy != y0) {
          cols = i;
          break;
        }
      }
      t.view.reset();
      return cols;
    }

    testWidgets('宽 120–2000 扫一遍，三套参数全部一致', (t) async {
      final configs = <List<double>>[
        [180, 2], // 推荐 / 作品网格
        [180, 10], // 作者网格（基础库页）
        [260, 10], // 单元库卡片
        [150, 8], // 作品网格（基础库页）
      ];
      for (var w = 120.0; w <= 2000.0; w += 20) {
        for (final c in configs) {
          final real = await realColumns(t, w, c[0], c[1]);
          final computed = gridColumnCount(
              crossAxisExtent: w, maxCrossAxisExtent: c[0], spacing: c[1]);
          expect(computed, real,
              reason: '宽 $w / max ${c[0]} / 间距 ${c[1]}：算 $computed，实际 $real');
        }
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
