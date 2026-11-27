import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/card_metrics.dart';
import 'package:shoucangjia/crash_reports_page.dart';
import 'package:shoucangjia/thumb_prefetch.dart';

void main() {
  group('firstScreenThumbCount', () {
    test('手机竖屏：3 列 × 2 屏，取整后不超过上限', () {
      final n = firstScreenThumbCount(
        viewportWidth: 400,
        viewportHeight: 800,
        maxCrossAxisExtent: 150,
        padding: 10,
        crossSpacing: 8,
        mainSpacing: 8,
        aspectRatio: 0.72,
      );
      expect(n, greaterThan(0));
      expect(n, lessThanOrEqualTo(24));
      // 3 列、卡片高约 168px → 800/176 ≈ 5 行（两屏）
      expect(n % 3, 0);
    });

    test('宽窗口（桌面）列更多，仍受 maxItems 限制', () {
      final n = firstScreenThumbCount(
        viewportWidth: 1600,
        viewportHeight: 900,
        maxItems: 12,
      );
      expect(n, 12);
      expect(firstScreenThumbCount(viewportWidth: 0, viewportHeight: 800), 0);
      expect(
          firstScreenThumbCount(
              viewportWidth: 400, viewportHeight: 800, maxItems: 0),
          0);
    });

    test('窄屏至少 1 张，参数异常不崩', () {
      final n = firstScreenThumbCount(
          viewportWidth: 40, viewportHeight: 120, aspectRatio: 0);
      expect(n, greaterThanOrEqualTo(1));
      expect(n, lessThanOrEqualTo(24));
    });

    test('固定行高（mainAxisExtent）优于按宽高比估算', () {
      // 作者页：delegate 给了 mainAxisExtent=170，行高与列宽无关。
      final fixed = firstScreenThumbCount(
        viewportWidth: 400,
        viewportHeight: 800,
        maxCrossAxisExtent: 150,
        paddingX: 12,
        paddingY: 10,
        crossSpacing: 10,
        mainSpacing: 10,
        mainAxisExtent: 170,
        screens: 1,
      );
      // 可用 376 宽 → 3 列；可用 780 高 → ceil(780/180)=5 行。
      expect(fixed, 15);
      // 不传固定行高时按 150/170 比例算（列宽 118.67/0.88 ≈ 134），行更多。
      final byRatio = firstScreenThumbCount(
        viewportWidth: 400,
        viewportHeight: 800,
        maxCrossAxisExtent: 150,
        paddingX: 12,
        paddingY: 10,
        crossSpacing: 10,
        mainSpacing: 10,
        aspectRatio: 150 / 170,
        screens: 1,
      );
      expect(byRatio, greaterThan(fixed),
          reason: '旧口径按比例估行高，会把屏幕外的封面也算进去');
    });

    test('横纵内边距可以分开（fromLTRB 那类四边不等）', () {
      final symmetric = firstScreenThumbCount(
        viewportWidth: 400,
        viewportHeight: 800,
        padding: 12,
        crossSpacing: 10,
        mainSpacing: 10,
        aspectRatio: 1.0,
        screens: 1,
      );
      final split = firstScreenThumbCount(
        viewportWidth: 400,
        viewportHeight: 800,
        paddingX: 12,
        paddingY: 18,
        crossSpacing: 10,
        mainSpacing: 10,
        aspectRatio: 1.0,
        screens: 1,
      );
      // 纵向内边距更大 → 可用高度更小 → 行数不多于对称值。
      expect(split, lessThanOrEqualTo(symmetric));
      // 负数/非有限 padding 不得算出比 0 还大的可用尺寸后崩。
      expect(
          firstScreenThumbCount(
              viewportWidth: 400,
              viewportHeight: 800,
              paddingX: double.infinity),
          0);
    });
  });

  group('firstScreenRowCount', () {
    test('手机竖屏：两屏行数，受 maxItems 限制', () {
      expect(
          firstScreenRowCount(
              viewportHeight: 800, rowExtent: kAuthorRankRowExtent),
          12);
      expect(
          firstScreenRowCount(
              viewportHeight: 400,
              rowExtent: kAuthorRankRowExtent,
              screens: 1),
          6);
    });

    test('排行榜真实行步进 68.6（67.6 + 1dp 分隔线），不是默认的 72', () {
      // 0.9.289：默认 72 已删除（第二份几何）。
      // 0.9.343：行高改为**测出来**的 67.6（媒体库词条接入后词条块 11 →
      // 14.6dp，`ListTile` 自查出来的高度不是整数）。常量为整数时，
      // 每行少算 0.6dp——同一屏两屏的边界上会多预热屏幕外一行。
      expect(kAuthorRankRowExtent, closeTo(68.6, 1e-9));
      expect(kAuthorRankTileHeight, closeTo(67.6, 1e-9));
    });

    test('参数异常不崩，至少 1 行', () {
      expect(firstScreenRowCount(viewportHeight: 10, rowExtent: 68), 1);
      expect(firstScreenRowCount(viewportHeight: 0, rowExtent: 68), 0);
      expect(
          firstScreenRowCount(
              viewportHeight: 800, rowExtent: 68, maxItems: 0),
          0);
      expect(firstScreenRowCount(viewportHeight: 800, rowExtent: 0), 0);
    });
  });

  group('ThumbPrefetch', () {
    test('去重：同一 URL 第二次进入跳过，失败的下次还能重试', () async {
      final p = ThumbPrefetch(maxConcurrent: 2);
      final calls = <String>[];
      var failFirst = true;
      Future<bool> fetch(String u) async {
        calls.add(u);
        if (u == 'b' && failFirst) {
          failFirst = false;
          return false;
        }
        return true;
      }

      expect(await p.runWith(['a', 'b', 'a'], fetch: fetch), 2);
      expect(calls, ['a', 'b']);
      expect(p.stats.loaded, 1);
      expect(p.stats.failed, 1);
      expect(p.stats.skipped, 1);

      // a 已成功 → 不再请求；b 失败过 → 允许重试
      expect(await p.runWith(['a', 'b'], fetch: fetch), 1);
      expect(calls, ['a', 'b', 'b']);
      expect(p.stats.loaded, 2);
      expect(p.stats.failed, 1);
      expect(p.stats.lastRun, isNotNull);
    });

    test('limit 生效，且并发不超过上限', () async {
      final p = ThumbPrefetch(maxConcurrent: 2);
      var active = 0;
      var peak = 0;
      Future<bool> fetch(String u) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return true;
      }

      final urls = List<String>.generate(10, (i) => 'u$i');
      expect(await p.runWith(urls, fetch: fetch, limit: 4), 4);
      expect(peak, lessThanOrEqualTo(2));
      expect(p.stats.requested, 4);
      expect(p.stats.loaded, 4);
      expect(p.stats.pending, 0);
      // 诊断：报告在途并发峰值，且不超过预算上限。
      expect(p.stats.peakActive, 2);
      expect(p.stats.peakActive, lessThanOrEqualTo(p.effectiveLimit));
    });

    test('滚动期间收紧并发（默认 4 → 2），停下后恢复', () async {
      final p = ThumbPrefetch(maxConcurrent: 4, scrollMaxConcurrent: 2);
      expect(p.effectiveLimit, 4);
      var active = 0;
      var peakScrolling = 0;
      Future<bool> fetch(String u) async {
        active++;
        if (p.scrolling && active > peakScrolling) peakScrolling = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return true;
      }

      p.setScrolling(true);
      expect(p.effectiveLimit, 2);
      final urls = List<String>.generate(8, (i) => 's$i');
      expect(await p.runWith(urls, fetch: fetch), 8);
      expect(peakScrolling, lessThanOrEqualTo(2));
      expect(p.stats.peakActive, lessThanOrEqualTo(2));
      expect(p.stats.loaded, 8);

      p.setScrolling(false);
      expect(p.effectiveLimit, 4);
    });

    test('首屏预热（未滚动）仍按常规并发 4', () async {
      final p = ThumbPrefetch(maxConcurrent: 4);
      var active = 0;
      var peak = 0;
      Future<bool> fetch(String u) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        active--;
        return true;
      }

      final urls = List<String>.generate(10, (i) => 'f$i');
      await p.runWith(urls, fetch: fetch);
      expect(peak, 4);
    });

    test('异常按失败计数，不抛出', () async {
      final p = ThumbPrefetch(maxConcurrent: 1);
      await p.runWith(['x'], fetch: (_) async => throw StateError('boom'));
      expect(p.stats.failed, 1);
      expect(p.stats.loaded, 0);
    });

    test('去重表淘汰不踢在途项：同一 URL 不会重复预热', () async {
      final p = ThumbPrefetch(maxConcurrent: 2, seenLimit: 2);
      final gate = Completer<bool>();
      final calls = <String, int>{};
      Future<bool> fetch(String u) {
        calls[u] = (calls[u] ?? 0) + 1;
        if (u == 'a') return gate.future;
        return Future<bool>.value(true);
      }

      final firstA = p.runWith(['a'], fetch: fetch);
      await p.runWith(['b', 'c'], fetch: fetch); // 超限，但 a 仍在途
      await p.runWith(['a'], fetch: fetch); // 不得重复预热
      expect(calls['a'], 1);
      gate.complete(true);
      await firstA;
      expect(p.stats.loaded, 3);

      // 全部完成后再次超限，才允许淘汰最旧的已完成项
      await p.runWith(['d'], fetch: fetch);
      expect(calls['d'], 1);
    });

    test('reset 清空统计与去重表', () async {
      final p = ThumbPrefetch(maxConcurrent: 1);
      var calls = 0;
      Future<bool> fetch(String u) async {
        calls++;
        return true;
      }

      await p.runWith(['a'], fetch: fetch);
      p.reset();
      expect(p.stats.requested, 0);
      expect(p.stats.lastRun, isNull);
      await p.runWith(['a'], fetch: fetch);
      expect(calls, 2);
    });
  });

  testWidgets('诊断页展示首屏预热进度与图片缓存', (tester) async {
    final p = ThumbPrefetch.instance;
    p.reset();
    await p.runWith(['a', 'b'], fetch: (_) async => true);
    await tester.pumpWidget(const MaterialApp(
        home: CrashReportsPage(detail: 'http://192.168.2.4:8090')));
    await tester.pump();
    expect(find.textContaining('首屏缩略图：2/2 张就绪'), findsOneWidget);
    expect(find.textContaining('图片缓存'), findsOneWidget);
    expect(find.textContaining('当前连接'), findsOneWidget);
    p.reset();
  });
}
