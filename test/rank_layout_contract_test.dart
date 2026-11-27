// 第七十七批契约（owner 2026-11-27）：
//
// 1. 「排行榜条目数字位置固定，数值类型统一在数字前面」——两个榜此前各写一份，
//    而且切换排行方式时同一个数字会换位置（各库榜副标题：播放量榜 `N 播放`、
//    水滴榜 `播放 N`）。现在数值格子与明细行只有 `rank_metric.dart` 一份，
//    切换指标只换类型文字，数字不挪。
//
// 2. 「多库排行入口放在排行榜页，不该在作者总览页」——入口位置是结构，
//    不是样式，所以用源码契约钉住。
//
// 3. 「删除监测页塞到对应单元库的爬虫配置页面下去，爬虫没有这个功能就显示
//    不支持」——总设置页不再有该入口；单元库爬虫页的入口在无脚本时置灰。
//
// 4. 「各地方都要适应多媒体库管理」——不再有「当前媒体库」这种单库措辞。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String codeOf(String path) => File(path)
    .readAsStringSync()
    // 行尾归一：Windows CI 检出的是 CRLF，只按 '\n' 切会留下 '\r'，
    // 于是断言里的 'SizedBox(\n      width ...' 这类字面量永远匹配不上
    // （本地 LF 绿、Windows 红）。这里统一按 CRLF/LF 切。
    .split(RegExp(r'\r?\n'))
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('排行榜数值排版只有一份（数值类型在数字前、位置固定）', () {
    final main = codeOf('lib/main.dart');
    final metric = codeOf('lib/rank_metric.dart');

    test('数值格子与明细行只在 rank_metric 定义，两个榜都调用它', () {
      expect(metric.contains('class RankScoreCell'), isTrue);
      expect(metric.contains('String rankDetailLine('), isTrue);
      expect(main.contains('RankScoreCell('), isTrue);
      // 作者榜 + 各库榜 = 两处调用点
      expect(RegExp(r'RankScoreCell\(').allMatches(main).length, 2);
      expect(RegExp(r'rankDetailLine\(').allMatches(main).length, 2,
          reason: '两个榜的明细行必须同一个出口');
      // 页面里不得再自己拼「N 播放」/「播放 N」
      expect(RegExp(r"'播放 \$\{?r\.plays").hasMatch(main), isFalse);
      expect(RegExp(r"\$\{r\.plays\} 播放").hasMatch(main), isFalse);
    });

    test('分数格子宽度固定，数字不带 emoji 前缀', () {
      expect(metric.contains('const double kRankScoreWidth'), isTrue);
      expect(metric.contains('SizedBox(\n      width: kRankScoreWidth'), isTrue);
      // 旧写法：`metric == 'drop' ? '💧 $score' : '$score'`
      expect(main.contains("'💧 \$score'"), isFalse,
          reason: 'emoji 当数值类型会让整列数字宽度不一致');
    });

    test('指标 → 类型文字只有一个出口', () {
      expect(metric.contains('String rankMetricLabel('), isTrue);
      expect(RegExp(r'rankMetricLabel\(').allMatches(main).length, 2);
      // 页面里不得再自己写「小水滴 / 播放量」的分支
      expect(main.contains("metric == 'drop' ? '小水滴'"), isFalse);
    });
  });

  group('多库排行的入口在排行榜页', () {
    final main = codeOf('lib/main.dart');

    test('排行榜 AppBar 有各库排行入口', () {
      final start = main.indexOf('class _RankPageState');
      final end = main.indexOf('class LibraryRankPage');
      expect(start, greaterThan(0));
      final body = main.substring(start, end);
      expect(body.contains("tooltip: '各库排行'"), isTrue);
      expect(body.contains('LibraryRankPage()'), isTrue);
    });

    test('作者总览页不再挂各库排行入口', () {
      final start = main.indexOf('class _AuthorGridPageState');
      expect(start, greaterThan(0));
      final body = main.substring(start, start + 20000);
      expect(body.contains("tooltip: '各库排行'"), isFalse,
          reason: '各库排行是排行榜的另一个维度，入口应在排行榜页');
    });
  });

  group('删除监测在单元库爬虫配置页内，按单元库作用域', () {
    final main = codeOf('lib/main.dart');
    final crawler = codeOf('lib/unit_crawler_page.dart');

    test('总设置页不再有删除监测入口', () {
      final start = main.indexOf('class SettingsHubPage');
      final end = main.indexOf('class CustomizationHubPage');
      expect(start, greaterThan(0));
      expect(main.substring(start, end).contains('DeletedMonitorPage'), isFalse,
          reason: '删除监测依赖具体单元库的爬虫，入口不该在总设置页');
    });

    test('单元库爬虫页提供入口，无脚本时置灰并说明不支持', () {
      expect(crawler.contains('onOpenDeletedMonitor'), isTrue);
      expect(crawler.contains("'unit-deleted-monitor'"), isTrue);
      expect(
          crawler.contains('该单元库没有爬虫脚本，因此不支持删除监测'), isTrue);
      // 判定必须复用本页唯一的 hasScript，不许另写一份
      final tile = crawler.substring(
          crawler.indexOf('Widget _deletedMonitorTile()'));
      expect(tile.contains('final ok = hasScript;'), isTrue);
    });

    test('删除监测页接受单元库作用域并按它过滤', () {
      final start = main.indexOf('class _DeletedMonitorPageState');
      final body = main.substring(start, start + 12000);
      expect(body.contains('unitRel'), isTrue);
      expect(body.contains('_scopeName'), isTrue);
      // 计数按作用域算，不拿全库总数
      final buildStart = main.indexOf('class _DeletedMonitorPageState');
      final buildBody = main.substring(buildStart, buildStart + 20000);
      expect(buildBody.contains('final scopeItems = _visibleItems;'), isTrue);
    });
  });

  group('不再有单库时代的「当前媒体库」措辞', () {
    test('界面文案只有「默认媒体库」', () {
      final hits = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (l.trimLeft().startsWith('//')) continue;
          // 旧库名映射（`抖音收藏` → 展示名）是历史数据兼容，不在改写范围。
          if (l.contains('当前媒体库') && !l.contains('legacyDouyinName')) {
            hits.add('${f.path}:${i + 1}: ${l.trim()}');
          }
        }
      }
      expect(hits, isEmpty, reason: hits.join('\n'));
    });
  });
}
