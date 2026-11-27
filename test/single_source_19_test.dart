/// 第三十五批契约：角标预览、卡片 IP/圆点、连接状态三态、全屏重建。
///
///  - 设置页八个候选格此前都渲染 `LibCornerBadge(kind:)`，永远画「当前
///    选中图案」——owner 看到的是「图标都是一样的」；
///  - 媒体库卡片底部原来写「已连接/已断连」文案，owner 要的是**绿/红圆点
///    + IP 地址**，且连接状态从文案反推布尔（`== '已连接'`）随时会漂移；
///  - Windows `didChangeMetrics` 为 `_winResizing` 调了两次 `setState`，而
///    该标志从不参与 build —— 每次窗口变化（进/出全屏本身就是一次）都
///    白重建整棵播放页，第一次切全屏必然卡一下；
///  - 同一段窗口期里 `toggleFs` 直接 `return`，把用户点击静默吞掉。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_corner_badge.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';

String _mainSrc() => File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');

/// 「拿连接状态文案反推布尔」的两种写法：`== '已连接'` / `== "已连接"`。
final RegExp _statusLiteral = RegExp(
    '==' r'\s*' "(?:'已连接'|\"已连接\")");

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

BasicLib basic(String id, String rel) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 2,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    LibraryCornerBadge.resetDefaults();
    LibraryBadge.topCustom.clear();
    LibraryBadge.topOfUnit.clear();
    UnitBadgeRegistry.order.clear();
  });

  group('角标设置页：候选格必须预览自己的图案', () {
    testWidgets('八个候选格的图案两两不同，且与当前选中值无关', (tester) async {
      // 当前选中固定为 0（六边形）；候选格仍应是 0..7 各自的样子。
      await LibraryCornerBadge.setPattern(LibBadgeKind.basic, 0);
      await tester.pumpWidget(host(Column(
        children: [
          for (var i = 0; i < kCornerPatternNames.length; i++)
            LibCornerBadge(kind: LibBadgeKind.basic, pattern: i),
        ],
      )));

      final badges = tester
          .widgetList<LibCornerBadge>(find.byType(LibCornerBadge))
          .toList();
      expect(badges.length, kCornerPatternNames.length);
      // 覆盖值原样保留，不被「当前选中图案」顶掉。
      expect(badges.map((b) => b.pattern).toList(),
          List<int>.generate(kCornerPatternNames.length, (i) => i));

      // 画出来的图案也必须是各自的：取 painter 里的 pattern。
      final painted = <int>[];
      for (final el in find.byType(CustomPaint).evaluate()) {
        final w = el.widget;
        if (w is! CustomPaint) continue;
        final p = w.painter;
        if (p == null) continue;
        painted.add(_patternOfPainter(p));
      }
      final known = painted.where((p) => p >= 0).toSet();
      expect(known.length, kCornerPatternNames.length,
          reason: '八格必须画出八个不同图案，否则用户看到的还是「都一样」');
    });

    testWidgets('未指定 pattern 时仍画当前选中图案（卡片上的真实角标）', (tester) async {
      await LibraryCornerBadge.setPattern(LibBadgeKind.top, 7);
      await tester.pumpWidget(
          host(const Center(child: LibCornerBadge(kind: LibBadgeKind.top))));
      final w = tester.widget<LibCornerBadge>(find.byType(LibCornerBadge));
      expect(w.pattern, isNull);
      final painted = <int>[];
      for (final el in find.byType(CustomPaint).evaluate()) {
        final p = el.widget is CustomPaint ? (el.widget as CustomPaint).painter : null;
        if (p == null) continue;
        painted.add(_patternOfPainter(p));
      }
      expect(painted, contains(7));
    });

    testWidgets('候选格键唯一：多格同键会让 Flutter 复用错误的状态', (tester) async {
      await tester.pumpWidget(host(Column(
        children: [
          for (var i = 0; i < kCornerPatternNames.length; i++)
            LibCornerBadge(kind: LibBadgeKind.unit, pattern: i),
        ],
      )));
      // 键挂在内部 Container 上（Widget 本身无 key）；每格必须各有一个键。
      final keys = <String>[];
      for (var i = 0; i < kCornerPatternNames.length; i++) {
        final k = ValueKey('lib-corner-badge-unit-$i');
        expect(find.byKey(k), findsOneWidget, reason: '候选格 $i 的键缺失或重复');
        keys.add('$k');
      }
      expect(keys.toSet().length, keys.length);
      // 未指定 pattern 的旧键必须保持不变（既有测试/调用点依赖）。
      await tester.pumpWidget(
          host(const Center(child: LibCornerBadge(kind: LibBadgeKind.unit))));
      expect(find.byKey(const ValueKey('lib-corner-badge-unit')), findsOneWidget);
    });

    test('设置页每个候选格都传了自己的图案编号', () {
      final src = _mainSrc();
      expect(src.contains('LibCornerBadge(kind: kind, pattern: i)'), isTrue,
          reason: '设置页候选格必须传 pattern: i，否则八格画同一个图案');
    });
  });

  group('媒体库卡片：底部是「圆点 + IP」，不是文案', () {
    final tree = buildUnitTree(
      nodes: const [
        LibNode(
            id: 'top-1',
            rel: 'T1',
            name: 'T1',
            serverBase: 'http://192.168.2.4:8090'),
      ],
      basics: [basic('b1', 'T1/x')],
    )!;

    Future<void> pump(WidgetTester t, bool? online) async {
      await t.pumpWidget(host(UnitLibraryHomeView(
        tree: tree,
        stars: const {},
        onOpenUnit: (_) {},
        onToggleUnitStar: (_) {},
        onTapBasic: (_) {},
        onOpenStars: () {},
        topCoverOf: (_) => '',
        statusOf: (_) => online,
      )));
      await t.pumpAndSettle();
    }

    testWidgets('在线绿点 / 离线红点 / 未知无点，且都不写「已连接」', (t) async {
      await pump(t, true);
      expect(find.text('已连接'), findsNothing);
      expect(find.text('已断连'), findsNothing);
      expect(_dots(t, kCardOnlineColor), 1);
      expect(_dots(t, kCardOfflineColor), 0);

      await pump(t, false);
      expect(find.text('已连接'), findsNothing);
      expect(find.text('已断连'), findsNothing);
      expect(_dots(t, kCardOfflineColor), 1);
      expect(_dots(t, kCardOnlineColor), 0);

      await pump(t, null);
      expect(_dots(t, kCardOnlineColor), 0);
      expect(_dots(t, kCardOfflineColor), 0);
      // 没有状态也仍要能看到地址。
      expect(find.text('192.168.2.4:8090'), findsOneWidget);
    });

    testWidgets('圆点与地址在同一行，地址只写主机:端口', (t) async {
      await pump(t, true);
      expect(find.text('192.168.2.4:8090'), findsOneWidget);
      expect(find.textContaining('http://'), findsNothing);
      // 圆点尺寸固定 7dp（简约），不是大图标。
      final dot = find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.color == kCardOnlineColor;
      });
      expect(t.getSize(dot).width, 7);
    });

    test('hostLabelOf 单一实现：协议、路径、查询串一律去掉', () {
      expect(hostLabelOf('http://192.168.2.4:8090'), '192.168.2.4:8090');
      expect(hostLabelOf('http://192.168.2.4:8090/a/b?c=1'), '192.168.2.4:8090');
      expect(hostLabelOf('https://nas.local:8443/x'), 'nas.local:8443');
      expect(hostLabelOf('https://nas.local'), 'nas.local');
      expect(hostLabelOf('192.168.2.4:8090'), '192.168.2.4:8090');
      expect(hostLabelOf(''), '');
      // 解析不出主机：原样返回，别把 owner 配的串吞成空白。
      expect(hostLabelOf('http://'), 'http://');
    });

    testWidgets('下级单元库卡片不画连接圆点（与连接表无关）', (t) async {
      await t.pumpWidget(host(UnitLibraryCard(
        unit: tree.children.isNotEmpty ? tree.children.first : tree,
        headers: const {},
        online: true,
      )));
      await t.pumpAndSettle();
      expect(_dots(t, kCardOnlineColor), 0);
      expect(_dots(t, kCardOfflineColor), 0);
    });
  });

  group('连接状态只有一套判定：三态布尔，不再比字符串', () {
    test('lib/ 内不得再用「已连接」文案反推在线状态', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lines = f.readAsStringSync().replaceAll('\r\n', '\n').split('\n');
        for (var i = 0; i < lines.length; i++) {
          final t = lines[i].trim();
          if (t.startsWith('//')) continue;
          if (_statusLiteral.hasMatch(t)) {
            offenders.add('${f.path.replaceAll('\\', '/')}:${i + 1}: $t');
          }
        }
      }
      expect(offenders, isEmpty, reason: offenders.join('\n'));
    });

    test('卡片状态入参是 bool?，不是文案串', () {
      final src = File('lib/unit_library_view.dart').readAsStringSync().replaceAll('\r\n', '\n');
      expect(src.contains('final bool? online;'), isTrue);
      expect(src.contains('final String connectionStatus'), isFalse,
          reason: '文案字段已删除，避免两套表达同一个事实');
      expect(src.contains('final bool? Function(UnitLibrary unit)? statusOf;'),
          isTrue);
    });
  });

  group('Windows 全屏：不为不参与 build 的标志重建整页', () {
    test('didChangeMetrics 内不得再 setState（_winResizing 不参与 build）', () {
      final src = _mainSrc();
      final start = src.indexOf('void didChangeMetrics()');
      expect(start, greaterThan(0));
      // 按花括号配平取方法体，避免把后面的方法一起扫进来（会误报）。
      final open = src.indexOf('{', start);
      var depth = 0;
      var end = open;
      for (var i = open; i < src.length; i++) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
      // 注释里会解释「为什么不 setState」，比对前先剥掉注释行。
      final body = src
          .substring(open, end + 1)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(body.contains('setState'), isFalse,
          reason: '这个标志不参与 build，setState 只会白重建视频舞台');
      expect(body.contains('_winResizing = true'), isTrue);
    });

    test('_winResizing 只在 toggleFs 里被读，不参与 build', () {
      final src = _mainSrc();
      final reads = <String>[];
      final lines = src.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final t = lines[i].trim();
        if (t.startsWith('//')) continue;
        if (!t.contains('_winResizing')) continue;
        if (t.startsWith('bool _winResizing')) continue;
        reads.add('${i + 1}: $t');
      }
      // 允许：声明、didChangeMetrics 的写、timer 里的复位、toggleFs 的读。
      expect(reads.length, lessThanOrEqualTo(4), reason: reads.join('\n'));
      expect(reads.any((r) => r.contains('_winResizing = true')), isTrue);
      expect(reads.any((r) => r.contains('Platform.isWindows && _winResizing')),
          isTrue);
    });

    test('窗口变化期间点全屏不丢弃意图，而是记进 _fsPending', () {
      final src = _mainSrc();
      // owner 2026-11-25：原断言把整段代码含缩进写死在字符串里，
      // 代码缩进一变就红（Windows runner 上还叠加了换行差异）。
      // 改为「去空白后按顺序出现」，语义不变、不再依赖排版。
      String flat(String t) => t.replaceAll(RegExp(r'\s+'), '');
      final f = flat(src);
      expect(
          f.contains(flat(
              'if (Platform.isWindows && _winResizing) { _fsPending = next; return; }')),
          isTrue,
          reason: '直接 return 会让点击静默失效');
      // 尺寸稳定后必须补执行。
      expect(src.contains('if (!_fsBusy && want != null)'), isTrue);
      expect(src.contains('if (want != fs) scheduleMicrotask(toggleFs);'), isTrue);
    });
  });
}

/// 从 painter 里读出 pattern；不是角标 painter 时返回 -1。
int _patternOfPainter(CustomPainter p) {
  try {
    final dyn = p as dynamic;
    final v = dyn.pattern;
    if (v is int) return v;
  } catch (_) {}
  return -1;
}

/// 指定颜色的圆形状态点数。
int _dots(WidgetTester t, Color want) {
  return find
      .byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.color == want;
      })
      .evaluate()
      .length;
}
