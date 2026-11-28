import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/author_filter_options.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/lib_names.dart';
import 'package:shoucangjia/main.dart' show LibMeta;
import 'package:shoucangjia/source_lib.dart';
import 'package:shoucangjia/unit_library.dart';

/// 0.9.354 第一百零九批：名字出口的最后几处与旧筛选叫法。
///
/// 1. 作者卡基础库词条：名字空就整条跳过（不是显示 id）——「作者没挂这个
///    基础库」与「基础库没下发名字」长得一样。
/// 2. `basicLibLabel` 自调 `normalizeLibLabel`（无条件去序号），关掉「省略
///    编号」开关后卡片标题带 `(1) `、筛选面板/词条不带。
/// 3. 筛选条顶部词条的媒体库名被 `stripIndex` 套了两遍（`topLabelFor` 已经
///    走过 `libEntryTitle`），开关关着时限得太紧的那一处永远显示去序号结果。
/// 4. 同一个旧筛选条件在面板里叫「其他历史筛选」、在摘要里叫「历史分组」。
String _code(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String _codeOnly(String src) => src.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///');
    }).join('\n');

UnitLibrary _tree() => UnitLibrary(
      node: const LibNode(id: 'T1', rel: '', name: '根'),
      basics: const [],
      children: [
        UnitLibrary(
          node: const LibNode(id: 'T1/MID', rel: 'MID', name: '(1) 中间库'),
          basics: const [
            BasicLib(
                id: 'lib-1',
                name: '(8) 🦶',
                rel: 'MID/A',
                bigId: '',
                authors: 0,
                works: 0),
          ],
          children: const [],
        ),
      ],
    );

void main() {
  group('1. 作者卡基础库词条不再「名字空就整条消失」', () {
    test('main.dart 里不再用裸判空跳过基础库词条', () {
      final body = _codeOnly(_code('lib/main.dart'));
      expect(
        body.contains(
            "final label = (meta?.basicById(basic)?.name ?? '').trim();"),
        isFalse,
        reason: '这条只剥空白、不回落 id，名字空时整条词条被 continue 掉',
      );
      expect(
        body.contains(
            'final label = libEntryTitle(basic, meta?.basicById(basic)?.name);'),
        isTrue,
        reason: '基础库词条文字必须与卡片标题/其他词条同一个出口',
      );
    });

    test('空名字回落该基础库 id（外部行为）', () {
      // 出口本身的行为：就是 libEntryTitle。
      expect(libEntryTitle('lib-1', ''), 'lib-1');
      expect(libEntryTitle('lib-1', '   '), 'lib-1');
      expect(libEntryTitle('lib-1', null), 'lib-1');
    });
  });

  group('2. basicLibLabel 跟随「省略编号」开关', () {
    const b = BasicLib(
      id: 'lib-1',
      name: '(8) 🦶',
      rel: 'A',
      bigId: '',
      authors: 0,
      works: 0,
    );

    test('开关开：去序号（旧行为）', () {
      AppSettings.stripLibIndex = true;
      expect(basicLibLabel(b, '兜底'), '🦶');
      expect(libDisplayName('(8) 🦶'), '🦶');
    });

    test('开关关：保留序号（此前这里仍被剥掉）', () {
      AppSettings.stripLibIndex = false;
      expect(basicLibLabel(b, '兜底'), '(8) 🦶',
          reason: '关掉开关后标题显示 (8) 🦶，筛选面板/词条也必须一样');
      expect(libDisplayName('(8) 🦶'), '(8) 🦶');
      AppSettings.stripLibIndex = true;
    });

    test('空白折叠仍在：多余空格被压成一个', () {
      AppSettings.stripLibIndex = false;
      expect(libDisplayName('( 14 )  擦边 '), '( 14 ) 擦边');
      AppSettings.stripLibIndex = true;
    });

    test('lib/ 里 basicLibLabel 不再直接调 normalizeLibLabel', () {
      final src = _codeOnly(_code('lib/source_lib.dart'));
      final start = src.indexOf('String basicLibLabel(');
      expect(start, greaterThan(0));
      final body = src.substring(
          start, src.length < start + 400 ? src.length : start + 400);
      expect(body.contains('normalizeLibLabel('), isFalse);
      expect(body.contains('libDisplayName('), isTrue);
    });
  });

  group('3. 筛选条顶部词条的媒体库名只套一次去序号', () {
    test('topLabelFor 走 libEntryTitle（名字空回落 id + 跟随开关）', () {
      final tree = _tree();
      final meta = LibMeta(
        basics: const [],
        stats: const {},
        unitTree: tree,
        units: flattenUnits(tree),
        basicToUnit: const {},
      );
      AppSettings.stripLibIndex = true;
      expect(meta.topLabelFor('T1/MID'), '中间库');
      AppSettings.stripLibIndex = false;
      expect(meta.topLabelFor('T1/MID'), '(1) 中间库',
          reason: '开关关着时筛选条不能再替用户剥序号');
      AppSettings.stripLibIndex = true;
      expect(meta.topLabelFor('media:none'), 'media:none');
    });

    test('main.dart 两处顶部筛选不再二次 stripIndex(_topLabel(...))', () {
      final src = _codeOnly(_code('lib/main.dart'));
      expect(src.contains('LibraryBadge.stripIndex(_topLabel('), isFalse,
          reason: '`_topLabel` 已经经 `libEntryTitle` 去一次，外面再套一次会在'
              '「开关关」时把序号重新剥掉');
      expect(src.contains("'\${_topLabel(o.key)} \${o.value}'"), isTrue);
    });
  });

  group('3b. 筛选面板 chip 的名字与卡片同一个出口', () {
    test('单元库/媒体库/旧分组 chip 都经 libEntryTitle（跟随开关）', () {
      final tree = _tree();
      AppSettings.stripLibIndex = false;
      final o = authorFilterOptionsFrom(
        basics: const [
          BasicLib(
              id: 'lib-1',
              name: '(8) 🦶',
              rel: 'MID/A',
              bigId: 'g1',
              authors: 0,
              works: 0),
        ],
        units: flattenUnits(tree),
        tops: [tree.children.first],
        bigNames: const {'g1': '(2) 分组'},
        unitNameOf: (id) => '',
      );
      expect(o.unitNames['T1/MID'], '(1) 中间库', reason: '开关关着时面板 chip 不能替用户剥序号');
      expect(o.topNames['T1/MID'], '(1) 中间库');
      expect(o.bigNames['g1'], '(2) 分组');
      expect(o.basicNames['lib-1'], '(8) 🦶');
      AppSettings.stripLibIndex = true;
      final on = authorFilterOptionsFrom(
        basics: const [
          BasicLib(
              id: 'lib-1',
              name: '(8) 🦶',
              rel: 'MID/A',
              bigId: 'g1',
              authors: 0,
              works: 0),
        ],
        units: flattenUnits(tree),
        tops: [tree.children.first],
        bigNames: const {'g1': '(2) 分组'},
        unitNameOf: (id) => '',
      );
      expect(on.unitNames['T1/MID'], '中间库');
      expect(on.bigNames['g1'], '分组');
      expect(on.basicNames['lib-1'], '🦶');
    });

    test('名字空时 chip 回落 id（不再是一个空白 chip）', () {
      final o = authorFilterOptionsFrom(
        basics: const [],
        units: [
          UnitLibrary(
            node: const LibNode(id: 'u9', rel: 'u9', name: '   '),
            basics: const [],
            children: const [],
          ),
        ],
        unitNameOf: (id) => '',
      );
      expect(o.unitNames['u9'], 'u9');
    });
  });

  group('4. 旧筛选条件只有一个叫法', () {
    test('摘要与面板同用 kLegacyFilterLabel', () {
      final f = AuthorFilterState()..toggleBig('g1');
      final text = f.summary(bigNames: const {'g1': '分组甲'});
      expect(text, contains(kLegacyFilterLabel));
      expect(text.contains('历史分组'), isFalse);

      final ui = _codeOnly(_code('lib/author_filter_ui.dart'));
      expect(ui.contains("_section(kLegacyFilterLabel, bigChips)"), isTrue);
      expect(ui.contains("_section('其他历史筛选', bigChips)"), isFalse,
          reason: '字面量再写一遍就还会分叉');
    });

    test('常量值就是界面上那个说法', () {
      expect(kLegacyFilterLabel, '其他历史筛选');
    });
  });
}
