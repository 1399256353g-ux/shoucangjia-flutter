/// 第六十批契约：**同一个问题有两份实现，而且两份给出的答案不同**。
///
/// 前几批抓的是「同一段代码被抄成两份」。这一批更隐蔽：两处代码写得都对，
/// 但它们回答的其实是两个问题，界面却当成同一个问题在用。正常数据下看不出，
/// 只在「A 库两条各 3 次、B 库一条 5 次」这类真实分布上翻车。
///
/// 本批修掉的五处（修复前实测）：
///
///  1. 作品键 `库/作品id` 在三处各拼一遍（`work_key.workKey` /
///     `watch_progress.watchProgressKey` / `work_plays.workPlaysKey`）。
///     任何一份改了 trim 口径，观看记录与播放量就落到两个键上。
///  2. 单元库 rel 归一化两份（`rel_path.normalizeRelPath` 与
///     `multi_server.normalizeUnitRel`）。分叉后封面键与树节点键用不同的 rel
///     查同一张表 → 「设了封面、返回界面又没了」。
///  3. 封面「版本.扩展名」两处各拼（`CoverVersion.fileName` 与
///     `coverImageRel`）：历史面板的 widget key 与请求路径来自两个拼法。
///  4. 「子树里第一个非空 `cv`」扫描写了三遍、「第一个非空 `fc`」两遍
///     （`main._unitCoverUrl` / `unit_library_view.unitCoverUrl` /
///     `main._firstFcOfUnit`）。
///  5. 「单元库该用哪个基础库的封面」有两个答案：`main._topPlayedBasic`
///     用整库次数之和，`unit_library_view.topPlayedInUnit` 用单条作品最大次数
///     —— 同一张单元库卡在首页与单元库页显示两张不同的封面，而两边都“算对了”。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/multi_server.dart' show normalizeUnitRel;
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';
import 'package:shoucangjia/watch_progress.dart';
import 'package:shoucangjia/work_key.dart';
import 'package:shoucangjia/work_plays.dart';

String _code(String name) => File('lib/$name')
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

Iterable<File> _libFiles() sync* {
  for (final f in Directory('lib').listSync()) {
    if (f is File && f.path.endsWith('.dart')) yield f;
  }
}

BasicLib _basic(String id, String rel, {String crawlerCover = '', String firstCover = ''}) =>
    BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 10,
      serverBase: 'http://nas:8090',
      crawlerCover: crawlerCover,
      firstCover: firstCover,
    );

void main() {
  group('作品键只有一处拼装', () {
    test('观看记录 / 播放量 / workKey 三处逐字一致', () {
      for (final c in <List<String>>[
        <String>['lib-1', 'a'],
        <String>[' A ', ' 9 '],
        <String>['', 'x'],
        <String>['lib-1', ''],
        <String>['', ''],
      ]) {
        final expected = workKey(lib: c[0], id: c[1]);
        expect(watchProgressKey(lib: c[0], id: c[1]), expected,
            reason: '观看记录键漂移：$c');
        expect(workPlaysKey(lib: c[0], id: c[1]), expected,
            reason: '播放量键漂移：$c');
      }
    });

    test('会话内同名库与作品的键就是 库/作品（trim 后）', () {
      expect(workKey(lib: 'A', id: '1'), 'A/1');
      expect(workKey(lib: '', id: '1'), '1');
      expect(workKey(lib: 'A', id: '  '), '');
    });

    test('契约：键的拼装只允许出现在 work_key.dart', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final name = f.path.split('/').last;
        if (name == 'work_key.dart') continue;
        final src = _code(name);
        // 裸拼 `'$l/$i'`（或同形表达式）是这条规则的第二份。
        if (src.contains(r"l.isEmpty ? i : '$l/$i'")) offenders.add(name);
      }
      expect(offenders, isEmpty, reason: '作品键又被拼了一遍：$offenders');
    });
  });

  group('单元库 rel 归一化只有一处', () {
    test('反斜杠 / 点段 / 空段 / 首尾斜杠 结果一致且幂等', () {
      for (final rel in <String>[
        r'A\B',
        'A/B/',
        '/A//B',
        './A/./B',
        'A',
        '',
        '(1) A/(2) B',
      ]) {
        final once = normalizeUnitRel(rel);
        expect(normalizeUnitRel(once), once, reason: '不幂等：$rel');
        expect(normalizeUnitRel(rel), normalizeUnitRel(rel));
      }
      expect(normalizeUnitRel(r'A\B'), 'A/B');
      expect(normalizeUnitRel('/A//B/'), 'A/B');
      expect(normalizeUnitRel('./A/./B'), 'A/B');
    });

    test('清空后为空的 rel 不会变成空白键', () {
      expect(normalizeUnitRel(' . '), '');
      expect(normalizeUnitRel('///'), '');
    });
  });

  group('封面「版本.扩展名」只有一处拼装', () {
    test('历史面板的文件名与请求路径来自同一拼法', () {
      for (final v in <String>['v1', 'v1.png', 'v1.PNG?w=480']) {
        for (final e in <String>['jpg', 'png', '.webp']) {
          final name = coverVersionFileName(v, ext: e);
          final rel = coverImageRel('', v, ext: e);
          expect(rel, '_cover/$name',
              reason: '版本 $v 扩展 $e 的两处拼法不一致');
        }
      }
    });

    test('非法版本名两侧都为空（不留半截路径）', () {
      expect(coverVersionFileName('..', ext: 'jpg'), '');
      expect(coverImageRel('a', '..', ext: 'jpg'), '');
      expect(coverVersionFileName('', ext: 'jpg'), '');
    });
  });

  group('子树「第一个非空封面」只有一处扫描', () {
    final tree = buildUnitTree(
      nodes: const [LibNode(id: 'u1', rel: '(1) A', name: '(1) A')],
      basics: [
        _basic('l1', '(1) A/x'),
        _basic('l2', '(1) A/y', crawlerCover: '/media/l2/y/cv.jpg'),
        _basic('l3', '(1) A/z', crawlerCover: '/media/l3/z/cv.jpg'),
      ],
    )!;
    final unit = tree.children.first;

    test('爬虫封面取第一个非空，不再各自遍历', () {
      expect(unit.firstCrawlerCover, '/media/l2/y/cv.jpg');
      expect(const UnitLibrary(
        node: LibNode(id: 'e', rel: 'e', name: 'e'),
        basics: <BasicLib>[],
        children: <UnitLibrary>[],
      ).firstCrawlerCover, '');
    });

    test('首张作品封面取第一个非空，并带回所属基础库', () {
      final t = buildUnitTree(
        nodes: const [LibNode(id: 'u2', rel: '(2) B', name: '(2) B')],
        basics: [
          _basic('l4', '(2) B/p'),
          _basic('l5', '(2) B/q', firstCover: '/media/l5/q/fc.jpg'),
        ],
      )!;
      final u = t.children.first;
      expect(u.firstWorkCover?.lib, 'l5');
      expect(u.firstWorkCover?.path, '/media/l5/q/fc.jpg');
    });

    test('契约：main 与 view 都不再手写 cv / fc 扫描循环', () {
      for (final name in <String>['main.dart', 'unit_library_view.dart']) {
        final src = _code(name);
        expect(src.contains('crawlerCover.trim();'), isFalse,
            reason: '$name 又手写了一遍「第一个非空 cv」扫描');
        expect(src.contains('firstCover.trim();'), isFalse,
            reason: '$name 又手写了一遍「第一个非空 fc」扫描');
      }
      expect(_code('unit_library.dart').contains('firstCrawlerCover'), isTrue);
      expect(_code('unit_library.dart').contains('firstWorkCover'), isTrue);
    });
  });

  group('「单元库用哪个基础库的封面」只有一个答案', () {
    test('整库次数之和 优先于 单条最高次数（首页与卡片同一结论）', () {
      WorkPlaysStore.resetForTest(items: {
        // A 库：3 + 4 = 7（单条最高也是 A 的 4）
        'l1/w1': const WorkPlay(count: 3, thumb: '/media/l1/x/a.jpg'),
        'l1/w2': const WorkPlay(count: 4, thumb: '/media/l1/x/b.jpg'),
        // B 库：一条 5 次 → 合计 5
        'l2/w1': const WorkPlay(count: 5, thumb: '/media/l2/y/c.jpg'),
      });
      final t = buildUnitTree(
        nodes: const [LibNode(id: 'u3', rel: '(3) C', name: '(3) C')],
        basics: [
          _basic('l1', '(3) C/x'),
          _basic('l2', '(3) C/y'),
        ],
      )!;
      final unit = t.children.first;
      // 修前：单条最大次数选中 B（5 > 4）；修后：整库累计选中 A（7 > 5）。
      expect(topPlayedBasicOf(unit)?.id, 'l1');
      expect(topPlayedInUnit(unit)?.basic.id, 'l1');
      expect(unitCoverUrl(unit), 'http://nas:8090/media/l1/x/b.jpg');
      WorkPlaysStore.resetForTest(items: const {});
    });

    test('全部为 0 或没有记录时都给 null（交给调用方兜底）', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 0, thumb: '/media/l1/x/a.jpg'),
      });
      final t = buildUnitTree(
        nodes: const [LibNode(id: 'u4', rel: '(4) D', name: '(4) D')],
        basics: [_basic('l1', '(4) D/x')],
      )!;
      expect(topPlayedBasicOf(t.children.first), isNull);
      expect(topPlayedInUnit(t.children.first), isNull);
      WorkPlaysStore.resetForTest(items: const {});
    });

    test('契约：「最高播放基础库」的判定只在 unit_library_view 一处', () {
      final main = _code('main.dart');
      expect(main.contains('sumSat(WorkPlaysStore.countsFor'), isFalse,
          reason: 'main 又自己算了一遍整库播放量');
      expect(main.contains('topPlayedBasicOf'), isTrue,
          reason: 'main 必须转发同一个判定');
      expect(_code('unit_library_view.dart').contains('topPlayedBasicOf'), isTrue);
    });
  });
}
