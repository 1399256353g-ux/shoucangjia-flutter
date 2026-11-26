import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/author_filter_options.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/unit_library.dart';

/// 0.9.319 第八十四批：
///
/// 推荐页与搜索页各写了 8 个 getter（基础库/大库/单元库/顶级节点 + 四张名称表）
/// 来汇总筛选面板的选项，两处只在「输入是一份 meta 还是多份」上不同。
/// 现在只有 [authorFilterOptionsFrom] 一处，页面只提供作用域。
BasicLib _basic(String id, {String name = '', String bigId = '', String rel = ''}) =>
    BasicLib(
      id: id,
      name: name.isEmpty ? id : name,
      rel: rel.isEmpty ? id : rel,
      bigId: bigId,
      authors: 0,
      works: 0,
    );

UnitLibrary _unit(String id,
        {String name = '', List<UnitLibrary> children = const []}) =>
    UnitLibrary(
      node: LibNode(
        id: id,
        rel: id,
        name: name.isEmpty ? id : name,
      ),
      basics: const [],
      children: children,
    );

String fileText(String path) => File(path).readAsStringSync();

void main() {
  group('筛选项汇总只有一个出口', () {
    test('基础库按 id 去重、名称走 basicLibLabel、排序稳定', () {
      final o = authorFilterOptionsFrom(basics: [
        _basic('b2', rel: 'z/二'),
        _basic('b1', rel: 'a/一'),
        _basic('b2', rel: 'z/二'), // 跨连接重复
      ]);
      expect(o.basics.map((e) => e.id), ['b1', 'b2']);
      expect(o.basicNames['b1'], isNotEmpty);
      expect(o.basicNames.containsKey('b2'), isTrue);
      expect(o.basics.length, 2, reason: '同一个基础库 id 只该出现一次');
    });

    test('旧历史分组维度由基础库的 bigId 汇总，名称缺失回落 id', () {
      final o = authorFilterOptionsFrom(
        basics: [
          _basic('b1', bigId: 'g2'),
          _basic('b2', bigId: 'g1'),
          _basic('b3', bigId: ''),
          _basic('b4', bigId: 'g1'),
        ],
        bigNames: const {'g2': '已知分组'},
      );
      expect(o.bigs.map((e) => e.id), ['g1', 'g2']);
      expect(o.bigNames['g1'], 'g1', reason: '没有名称就回落 id，不猜');
      expect(o.bigNames['g2'], '已知分组');
      expect(o.bigNames.containsKey(''), isFalse, reason: '空 bigId 不产生条目');
    });

    test('单元库/顶级节点按 id 去重，名称走传入的解析器', () {
      final o = authorFilterOptionsFrom(
        basics: const [],
        units: [
          _unit('u1', name: '节点名'),
          _unit('u1', name: '另一个名字'),
          _unit('secret', name: '不该用这个名字'),
        ],
        tops: [_unit('t1', name: '媒体库'), _unit('t1', name: '重复')],
        unitNameOf: (id) => id == 'secret' ? '媒体库根' : '',
      );
      expect(o.units.map((e) => e.id).toList()..sort(), ['secret', 'u1']);
      // `unitNameOf` 返回空串时回落节点自身名称（不是 id）：
      expect(o.unitNames['u1'], '节点名', reason: '同一 id 先到先得');
      expect(o.unitNames['secret'], '媒体库根',
          reason: 'secret 这一层的名字来自 TopNodeName，必须走解析器');
      expect(o.tops.map((e) => e.id), ['t1']);
      expect(o.topNames['t1'], '媒体库');
    });

    test('空输入返回空选项，面板据此显示「暂无可筛选的库信息」', () {
      final o = authorFilterOptionsFrom(basics: const []);
      expect(o.isEmpty, isTrue);
      expect(o.basicNames, isEmpty);
      expect(o.bigNames, isEmpty);
      expect(o.unitNames, isEmpty);
      expect(o.topNames, isEmpty);
    });

    test('名称表与列表同源：不会出现「列表有、摘要没名」', () {
      final o = authorFilterOptionsFrom(
        basics: [_basic('b1', bigId: 'g1')],
        units: [_unit('u1')],
        tops: [_unit('t1')],
      );
      for (final n in o.basics) {
        expect(o.basicNames[n.id], n.name);
      }
      for (final n in o.bigs) {
        expect(o.bigNames[n.id], n.name);
      }
      for (final n in o.units) {
        expect(o.unitNames[n.id], n.name);
      }
      for (final n in o.tops) {
        expect(o.topNames[n.id], n.name);
      }
    });
  });

  group('基础库 → 单元库归属的单一查询', () {
    test('命中返回单元库 id，缺失返回空串（不猜）', () {
      const m = {'lib-1': 'u1'};
      expect(unitIdOfBasic(m, 'lib-1'), 'u1');
      expect(unitIdOfBasic(m, 'lib-2'), '');
      expect(unitIdOfBasic(m, ''), '');
    });
  });

  group('页面不再各写一份选项构造', () {
    test('main.dart 里没有 _filterBasics/_filterUnits/_filterTops 之类的 getter', () {
      final src = fileText('lib/main.dart');
      for (final name in [
        'get _filterBasics',
        'get _filterBigs',
        'get _filterUnits',
        'get _filterTops',
        'get _filterLibNames',
        'get _filterBigNames',
        'get _filterUnitNames',
        'get _filterTopNames',
      ]) {
        expect(src.contains(name), isFalse, reason: '$name 应已收进汇总函数');
      }
      expect(src.contains('authorFilterOptionsFrom('), isTrue);
    });

    test('汇总函数是纯计算，不 import main.dart（避免循环依赖）', () {
      final src = fileText('lib/author_filter_options.dart');
      expect(src.contains("import 'main.dart'"), isFalse);
    });
  });

  group('筛选摘要一行字只汇总一次', () {
    test('摘要用同一份选项的四张名称表', () {
      final o = authorFilterOptionsFrom(
        basics: [_basic('b1', name: '基础一', bigId: 'g1')],
        units: [_unit('u1', name: '单元一')],
        tops: [_unit('t1', name: '媒体库一')],
      );
      final f = AuthorFilterState()
        ..toggleBasic('b1')
        ..toggleUnit('u1')
        ..toggleTop('t1')
        ..toggleBig('g1');
      final text = authorFilterSummary(f, o);
      expect(text.contains('基础一'), isTrue);
      expect(text.contains('媒体库一'), isTrue);
      expect(text.contains('g1'), isTrue, reason: '历史分组没有名字时回落 id');
    });

    test('页面不再把同一个选项 getter 求值四次', () {
      final src = fileText('lib/main.dart');
      expect(src.contains('authorFilterSummary('), isTrue);
      expect(
          src.contains('summary(basicNames: _options.basicNames'), isFalse,
          reason: '四处分开求值 = 每个 build 汇总四遍并排序四遍');
    });
  });

  group('一个 build 只汇总一次', () {
    test('两页的 build 与打开面板都先取一次 opts', () {
      final src = fileText('lib/main.dart');
      // build 里先取一次，摘要与面板都用它
      expect('final opts = _options;'.allMatches(src).length,
          greaterThanOrEqualTo(3),
          reason: '推荐页 build、搜索页 build、两处 _openFilter');
      // 不再有「每个参数各求值一次」的写法
      expect(src.contains('basics: _options.basics'), isFalse);
      expect(src.contains('summary(basicNames: _options'), isFalse);
    });
  });
}
