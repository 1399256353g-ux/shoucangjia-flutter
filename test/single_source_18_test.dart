/// 第三十四批契约：六个「测试绿、真机错」的缺口。
///
///  - `DateTime(y, m, d)` 对 `2026-13-45` **静默滚动**成 2027-02-14，
///    对 `275761-01-01` 直接抛 `ArgumentError`——两条都在
///    `List.sort` 的比较函数里（整张作品列表崩或日期悄悄错一个月）；
///  - 秒级时间戳 `sec * 1000` 在 int64 上**静默回绕**成负数
///    （排序沉底、显示 1969 年）；
///  - 顶部动作条只数按钮个数、不算总宽，窄屏上「按钮 + ⋯ + 设置」
///    实际需要的宽度超过可用宽度 → Row 溢出；
///  - `formatCount` 没有「亿」档（1.23e8 → `12345.7万`）、负数原样输出，
///    且先切档再四舍五入会把 `999949` 说成 `100万`（凭空跨档）；
///  - 库卡片首字占位用 `characters.first`，零宽字符/组合符号会取到一个
///    画不出来的字符（圆圈看起来是空的），与 `avatarInitial` 两套口径；
///  - 基础库封面与单元库封面是两份**逐字相同**的取图实现。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_avatar.dart';
import 'package:shoucangjia/home_top_bar.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/time_labels.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/work_forms.dart';
import 'package:shoucangjia/main.dart' show LibBadges;

String codeOfLib(String path) => File(path).readAsStringSync();

TopBarAction _act(String id) =>
    TopBarAction(id: id, tooltip: id, icon: Icons.circle, onPressed: () {});

void main() {
  group('日期分量：静默滚动与越界抛异常都不允许', () {
    test('非法月/日返回 null（旧实现会滚成 2027-02-14）', () {
      expect(msFromDateParts(2026, 13, 45), isNull);
      expect(msFromDateParts(2026, 0, 0), isNull);
      expect(msFromDateParts(2026, 2, 31), isNull);
      expect(msFromDateParts(2026, 4, 31), isNull);
      expect(msFromDateParts(2026, 12, 32), isNull);
    });

    test('闰年与非闰年的 2 月 29 日', () {
      expect(msFromDateParts(2024, 2, 29), isNotNull);
      expect(msFromDateParts(2026, 2, 29), isNull);
    });

    test('越界年份返回 null（DateTime 会抛 ArgumentError）', () {
      expect(msFromDateParts(275761, 1, 1), isNull);
      expect(msFromDateParts(0, 1, 1), isNull);
      expect(msFromDateParts(-5, 1, 1), isNull);
    });

    test('正常日期与 DateTime 一致', () {
      expect(msFromDateParts(2026, 11, 17),
          DateTime(2026, 11, 17).millisecondsSinceEpoch);
    });

    test('workIngestMs 遇坏日期返回 0（排序保持原序，不崩）', () {
      expect(workIngestMs({'d': '2026-13-45'}), 0);
      expect(workIngestMs({'d': '2026-02-31'}), 0);
      expect(workIngestMs({'d': '正常文本'}), 0);
      expect(workIngestMs({'d': '2026-11-17'}),
          DateTime(2026, 11, 17).millisecondsSinceEpoch);
    });

    test('workIngestMs 排序时不抛异常（含越界年份）', () {
      final list = <dynamic>[
        {'id': 'a', 'd': '275761-01-01'},
        {'id': 'b', 'd': '2026-13-45'},
        {'id': 'c', 'd': '2026-11-17'},
      ];
      late List<dynamic> sorted;
      expect(() => sorted = sortWorks(list, WorkSort.ingest), returnsNormally);
      // 坏日期按 0（无时间）排在后面，原序保持：c 有真实时间 → 排第一。
      expect(sorted.first['id'], 'c');
    });
  });

  group('秒 → 毫秒：越界不得回绕成负数', () {
    test('合法秒级时间戳正常换算', () {
      expect(msFromEpochSeconds(1700000000), 1700000000000);
      expect(msFromEpochSeconds(0), 0);
    });

    test('越界/负数返回 0（旧实现 n*1000 得到负数）', () {
      expect(msFromEpochSeconds(1 << 62), 0);
      expect(msFromEpochSeconds(9223372036854775807), 0);
      expect(msFromEpochSeconds(-1), 0);
    });

    test('workIngestMs 的秒级/毫秒级越界都返回 0', () {
      // 秒级：`sec * 1000` 会回绕成负数。
      expect(workIngestMs({'srcAt': 92233720368547758}), 0);
      expect(workIngestMs({'srcAt': 1700000000}), 1700000000000);
      // 毫秒级：值本身超出 DateTime 的 ±8.64e15，下游构造会抛。
      expect(workIngestMs({'srcAt': 92233720368547758 * 10}), 0);
      expect(workIngestMs({'srcAt': 9223372036854775807}), 0);
    });
  });

  group('顶部动作条：保留项必须真的放得下', () {
    test('任何宽度下「可见项 + ⋯ + 设置」不超过可用宽度（≥150dp）', () {
      final actions = [
        _act('refresh'),
        _act('search'),
        _act('folders'),
        _act('recommend'),
        _act('authors'),
        _act('rank'),
        _act('settings'),
      ];
      for (var w = 150.0; w <= 900; w += 10) {
        final l = topBarLayout(width: w, actions: actions);
        final need = l.visible.length * kTopBarSlot +
            (l.hasOverflow ? kTopBarMoreWidth : 0) +
            // 顶部栏自身不含间距，可见按钮按 44 + 8 间距计。
            0;
        expect(need <= w, isTrue,
            reason: 'w=$w 需要 $need，会溢出（可见 ${l.visible.length} 项）');
        expect(l.visible.length, lessThanOrEqualTo(kTopBarMaxVisible));
      }
    });

    test('极窄宽度仍至少保留一项（没有主按钮的顶部栏不可用）', () {
      final l = topBarLayout(width: 40, actions: [_act('a'), _act('b')]);
      expect(l.visible.length, 1);
      expect(l.hasOverflow, isTrue);
    });

    test('设置仍是尾位且不参与溢出竞争', () {
      final l = topBarLayout(width: 170, actions: [
        _act('refresh'),
        _act('search'),
        _act('settings'),
      ]);
      expect(l.visible.last.id, 'settings');
      expect(l.overflow.map((a) => a.id), isNot(contains('settings')));
    });
  });

  group('计数文案：亿档 / 负数 / 不得虚假跨档', () {
    test('分档边界', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1k');
      expect(formatCount(1200), '1.2k');
      expect(formatCount(9999), '9.9k');
      expect(formatCount(10000), '1万');
      expect(formatCount(12345), '1.2万');
      expect(formatCount(100000000), '1亿');
      expect(formatCount(123456789), '1.2亿');
    });

    test('负数不显示成负数', () {
      expect(formatCount(-1), '0');
      expect(formatCount(-999), '0');
    });

    test('999949 不得说成 100万（计数一律向下截断）', () {
      expect(formatCount(999949), '99.9万');
      expect(formatCount(999999), '99.9万');
      expect(formatCount(999999999), '9.9亿');
    });

    test('大数不再产出五位数字的「万」', () {
      // 旧实现：1.23e8 → '12345.7万'
      final s = formatCount(123456789);
      expect(s.endsWith('亿'), isTrue);
      expect(s.contains('万'), isFalse);
    });
  });

  group('首字占位与 avatarInitial 同一口径', () {
    test('零宽/组合符号不会成为首字（旧 characters.first 会取到）', () {
      expect(avatarInitial('\u200b张三'), '张');
      expect(avatarInitial('\u0301abc'), 'a');
      expect(avatarInitial('   '), '?');
    });

    test('基础库页不再自己写 characters.first', () {
      final src = codeOfLib('lib/basic_lib_page.dart');
      expect(src.contains('name.characters.first'), isFalse,
          reason: '首字口径必须走 avatar_initial 唯一实现');
      expect(src.contains('avatarInitial('), isTrue);
    });
  });

  group('库封面取图：基础库与单元库各自一个作用域入口', () {
    test('两个入口共享同一条优先级链（差别只在作用域目录）', () {
      // 自定义 `_cover/` 优先于最高播放作品图（这条链两个作用域共用），
      // 差别只在自定义封面文件落在哪：库根 vs 节点目录。
      final b = resolveBasicCover(
          bestThumb: '/media/l/th.jpg', version: 'v1');
      final u = resolveUnitCover(
          unitRel: '(1) A', bestThumb: '/media/l/th.jpg', version: 'v1');
      expect(b.path, '_cover/v1.jpg');
      expect(b.source, CoverSource.custom);
      expect(u.path, '(1) A/_cover/v1.jpg');
      expect(u.source, CoverSource.custom);

      // 没有自定义封面时两个作用域给出**逐字相同**的答案。
      final b2 = resolveBasicCover(bestThumb: '/media/l/th.jpg');
      final u2 = resolveUnitCover(unitRel: '(1) A', bestThumb: '/media/l/th.jpg');
      expect(b2.path, '/media/l/th.jpg');
      expect(u2.path, '/media/l/th.jpg');
      expect(b2.source, u2.source);
    });

    test('基础库封面永远在库根（传什么 rel 都不影响）', () {
      expect(resolveBasicCover(version: 'v2', ext: 'png').path,
          '_cover/v2.png');
      expect(resolveBasicCover().path, '');
    });

    test('单元库封面在节点目录；rel 为空时回到库根', () {
      expect(resolveUnitCover(unitRel: '(1) A', version: 'v1').path,
          '(1) A/_cover/v1.jpg');
      expect(resolveUnitCover(unitRel: '', version: 'v1').path,
          '_cover/v1.jpg');
      expect(resolveUnitCover(unitRel: '/', version: 'v1').path,
          '_cover/v1.jpg');
    });

    test('自己的封面链只剩 resolveBasicCover / resolveUnitCover', () {
      final src = codeOfLib('lib/lib_cover.dart');
      // 只允许一份 `coverImageRel(rel, version, ext: ext)` 的调用点。
      final hits = RegExp(r'coverImageRel\(rel, version').allMatches(src).length;
      expect(hits, 1, reason: '取图实现应只有一处（resolveCover）');
      // 旧三件套不得复活：它们的 `required String rel` 就是那条判断本身。
      // 扫描时去掉注释行（它们在文件头注释里用作反面例子）。
      final code = src
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('pickBasicCover'), isFalse);
      expect(code.contains('pickUnitCover'), isFalse);
      expect(code.contains('_pickLibCover'), isFalse);
    });
  });

  group('契约扫描：这几条规则不得被绕开', () {
    test('lib/ 内不得再裸构造 DateTime(年,月,日) 做时间戳', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        for (final line in src.split('\n')) {
          if (line.trimLeft().startsWith('//')) continue;
          if (RegExp(r'DateTime\(\s*int\.parse').hasMatch(line)) {
            offenders.add('${f.path.replaceAll('\\', '/')}: ${line.trim()}');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('lib/ 内不得再出现 sec * 1000 的秒级换算', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final src = f.readAsStringSync();
        for (final line in src.split('\n')) {
          final t = line.trim();
          if (t.startsWith('//')) continue;
          if (RegExp(r'\bsec\s*\*\s*1000\b').hasMatch(t)) {
            offenders.add('${f.path.replaceAll('\\', '/')}: $t');
          }
        }
      }
      // time_labels 里的 dateTimeOfSec / msFromEpochSeconds 已先判范围，
      // 允许它们保留唯一换算点；其它文件不得再自乘。
      expect(offenders.every((o) => o.startsWith('lib/time_labels.dart')),
          isTrue, reason: offenders.join('\n'));
    });
  });

  group('词条列表：去重口径与颜色索引同序', () {
    testWidgets('labels 去重后按下标取 id，不会把颜色错位到别的库', (tester) async {
      // `LibBadges` 内部对 libIds 的去重必须与 LibraryBadge.labels 一致：
      // 旧实现对 libIds 只过滤空串、不去重，`['a','a','b']` 的第二条
      // label 是「乙」却用了「a」的颜色与层级。
      const app = MaterialApp(
        home: Scaffold(
          body: LibBadges(
            libIds: <String>['a', 'a', 'b'],
            names: <String, String>{'a': '甲', 'b': '乙'},
          ),
        ),
      );
      await tester.pumpWidget(app);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .whereType<String>()
          .toList();
      expect(texts, <String>['甲', '乙']);
    });

    test('LibraryBadge.labels 本身按首次出现去重', () {
      expect(LibraryBadge.labels(<String>['a', 'a', 'b']), <String>['a', 'b']);
    });
  });
}
