import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });

  group('firstScreenRowCount', () {
    test('手机竖屏：两屏行数，受 maxItems 限制', () {
      expect(firstScreenRowCount(viewportHeight: 800), 12);
      expect(firstScreenRowCount(viewportHeight: 400, screens: 1), 6);
    });

    test('参数异常不崩，至少 1 行', () {
      expect(firstScreenRowCount(viewportHeight: 10), 1);
      expect(firstScreenRowCount(viewportHeight: 0), 0);
      expect(firstScreenRowCount(viewportHeight: 800, maxItems: 0), 0);
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
