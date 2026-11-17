import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/home_action.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';

BasicLib basic(String id, String rel) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 3,
      works: 30,
    );

void main() {
  final tree = buildUnitTree(
    nodes: const [LibNode(id: 'big-01', rel: '(1) A', name: '(1) A')],
    basics: [basic('l1', '(1) A/x')],
  )!;
  final unit = tree.children.first;

  testWidgets('播放页返回主页按钮：从任意深页面一步回到根路由', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  body: Center(
                    child: Builder(
                      builder: (inner) => ElevatedButton(
                        onPressed: () => Navigator.of(inner).push(
                          MaterialPageRoute(
                              builder: (_) => const Scaffold(
                                  body: Center(child: HomeOverlayButton()))),
                        ),
                        child: const Text('更深一层'),
                      ),
                    ),
                  ),
                ),
              )),
              child: const Text('首页'),
            ),
          ),
        ),
      ),
    ));

    await t.tap(find.text('首页'));
    await t.pumpAndSettle();
    await t.tap(find.text('更深一层'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-overlay-btn')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('home-overlay-btn')));
    await t.pumpAndSettle();
    // 直接回到根路由（首页），中间层不残留。
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('更深一层'), findsNothing);
    expect(find.byKey(const ValueKey('home-overlay-btn')), findsNothing);
  });

  testWidgets('单元库卡片与基础库卡片：圆角/渐变/信息层级一致', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            height: 150,
            child: UnitLibraryCard(unit: unit, onTap: () {}),
          ),
        ),
      ),
    ));

    final unitMat = t.widget<Material>(find
        .ancestor(
            of: find.byKey(ValueKey('unit-card-${unit.id}')),
            matching: find.byType(Material))
        .first);
    expect(unitMat.borderRadius, BorderRadius.circular(kLibCardRadius));
    // 卡片不再自带外边距：整卡铺满调用方给的 300 宽网格单元。
    expect(t.getSize(find.byKey(ValueKey('unit-card-${unit.id}'))).width, 300);

    final unitInfo = t.widget<LibCardInfo>(find.byType(LibCardInfo));
    expect(unitInfo.dense, isFalse);
    final unitTitle = t.widget<Text>(find.text('A')).style!.fontSize!;
    final unitStats =
        t.widget<Text>(find.textContaining('3 作者 · 30 作品')).style!.fontSize!;

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 220,
            height: 230,
            child: BasicLibCard(
                basic: basic('l1', '(1) A/x'),
                unitLabel: 'U',
                unitKey: 'u1',
                onTap: () {}),
          ),
        ),
      ),
    ));

    final basicMat = t.widget<Material>(find
        .ancestor(
            of: find.byKey(const ValueKey('basic-card-l1')),
            matching: find.byType(Material))
        .first);
    expect(basicMat.borderRadius, BorderRadius.circular(kLibCardRadius));
    // 基础库卡片同样不带外边距。
    expect(t.getSize(find.byKey(const ValueKey('basic-card-l1'))).width, 220);

    final basicInfo = t.widget<LibCardInfo>(find.byType(LibCardInfo));
    expect(basicInfo.dense, isTrue);
    final basicTitle = t.widget<Text>(find.text('x')).style!.fontSize!;
    final basicStats =
        t.widget<Text>(find.textContaining('3 作者 · 30 作品')).style!.fontSize!;

    // 统计行（次级信息）两类卡片完全一致；标题按卡片面积缩一档但不换层级。
    expect(basicStats, unitStats);
    expect(basicTitle, lessThan(unitTitle));
    expect(unitInfo.server, isEmpty);
    expect(
        kLibCardGradient.colors, const [Color(0x00000000), Color(0xC7000000)]);
  });
}
