import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/rank_filter.dart';

/// 0.9.317 第八十三批：
///  1. 排行榜「按库看」把注册库 id 当历史分组 id 比 —— 两个命名空间永不相等，
///     点「某库」进来一条作者都不显示（真缺陷）；
///  2. 排行榜的库列表从 `bigNames`（服务端早已不下发的 `big_id`）造 → 恒空；
///  3. 「当前」是单库时代的词：服务端只有 `default`（默认库）；
///  4. 统计来自服务端，不写「本机」。
void main() {
  String codeOf(String path) => File(path)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('评分归属：注册库 id 与基础库 id 不在同一个命名空间', () {
    test('选中库展开成成员基础库后按 libs 命中', () {
      // `douyin` 是注册库，它包含 lib-001/lib-002；榜单行带的是基础库 id。
      expect(
          authorInLibrary(
            memberBasics: {'lib-001', 'lib-002'},
            basicId: '',
            rowLibs: const ['lib-002', 'lib-009'],
          ),
          isTrue);
      expect(
          authorInLibrary(
            memberBasics: {'lib-001'},
            basicId: 'lib-009',
            rowLibs: const [],
          ),
          isFalse,
          reason: '不在这个库里就不能命中');
    });

    test('没有成员基础库时不猜（不退回全量）', () {
      expect(
          authorInLibrary(
              memberBasics: const <String>{},
              basicId: 'lib-001',
              rowLibs: const ['lib-001']),
          isFalse,
          reason: '空集合退回全量会让用户以为筛选没生效');
    });

    test('按头像路径反查出的基础库也参与判定', () {
      expect(
          authorInLibrary(
            memberBasics: {'lib-015'},
            basicId: 'lib-015',
            rowLibs: const [],
          ),
          isTrue);
    });

    test('空串不命中（libs 里可能有空元素）', () {
      expect(
          authorInLibrary(
              memberBasics: {'lib-001'}, basicId: '', rowLibs: const ['', '  ']),
          isFalse);
    });
  });

  group('排行榜页面不得再用 big_id 判归属 / 造库列表', () {
    final main = codeOf('lib/main.dart');

    test('归属判定走 rank_filter，不再直接比 bigIdFor', () {
      expect(main.contains("import 'rank_filter.dart';"), isTrue);
      expect(main.contains('authorInLibrary('), isTrue);
      final start = main.indexOf('class _RankPageState');
      final end = main.indexOf('class LibraryRankPage');
      expect(start, greaterThan(0));
      final body = main.substring(start, end);
      expect(body.contains('bigIdFor'), isFalse,
          reason: 'sel 是注册库 id，bigIdFor 返回 big_id，两者永不相等');
      expect(body.contains('authorInLibrary'), isTrue);
    });

    test('库列表来自 /api/libraries（注册库），不是 bigNames', () {
      final start = main.indexOf('class _RankPageState');
      final end = main.indexOf('class LibraryRankPage');
      final body = main.substring(start, end);
      expect(body.contains("cfg.u('/api/libraries')"), isTrue);
      expect(body.contains('bigNames'), isFalse,
          reason: '服务端已不下发 big_id，bigNames 恒空 → 列表恒空');
      expect(body.contains('libraryDisplayName('), isTrue,
          reason: '库名走唯一出口（规范化 + 去序号）');
    });
  });

  group('空列表的两种原因不说成一句话', () {
    test('选中库的元数据还没读完时转圈，不写「没有播放记录」', () {
      final main = codeOf('lib/main.dart');
      final start = main.indexOf('class _RankPageState');
      final end = main.indexOf('class LibraryRankPage');
      final body = main.substring(start, end);
      expect(body.contains('bool metaLoading = false;'), isTrue);
      expect(body.contains('visible.isEmpty && metaLoading'), isTrue,
          reason: '元数据未就绪与「本期没有播放」是两件事');
      // 空态文案只由 rank_metric.rankEmptyText 一处表达
      expect(body.contains('rankEmptyText('), isTrue);
      expect(body.contains("metric == 'drop' ?  '本期"), isFalse);
      final metric = codeOf('lib/rank_metric.dart');
      expect(metric.contains('String rankEmptyText('), isTrue);
      expect(metric.contains('这个库本期还没有'), isTrue,
          reason: '选了具体库时要说清作用域');
    });
  });

  group('「当前」不是多库的说法', () {
    test('各库排行标「默认」，字段名 isDefault', () {
      final rank = codeOf('lib/library_rank.dart');
      expect(rank.contains('final bool isDefault;'), isTrue);
      expect(rank.contains('final bool current;'), isFalse);
      expect(rank.contains('String? defaultLib,'), isTrue);
      final main = codeOf('lib/main.dart');
      expect(main.contains("Text('当前',"), isFalse);
      expect(main.contains("Text('默认',"), isTrue);
      expect(main.contains('r.current'), isFalse);
    });

    test('默认库由服务端 default 决定，不是客户端当前库', () {
      final main = codeOf('lib/main.dart');
      expect(main.contains("defaultId = '\${j['default'] ?? ''}'.trim();"), isTrue);
      expect(main.contains('currentLib: cfg.lib'), isFalse);
    });
  });

  group('统计来源写服务端，不写「本机」', () {
    test('两个页面都不再把服务端统计说成本机统计', () {
      final main = codeOf('lib/main.dart');
      expect(main.contains('统计来自本机'), isFalse);
      expect(main.contains('为本机统计'), isFalse);
      expect(main.contains('统计来自服务端'), isTrue);
      expect(main.contains('来自服务端'), isTrue);
    });
  });
}
