// 0.9.75：库卡片封面改为「按需计算」。
//
// 背景：主页网格原来把封面地址算好后当字符串传进卡片，播放量一变只能靠
// `LibraryPage` 监听全局 revision 后整页 `setState` 重建整个网格。现在卡片
// 接收 `coverUrlOf` 回调，在自己的按库监听里重新求值——播放某库后只有那张
// 卡重算封面，网格其余卡片不重建。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';
import 'package:shoucangjia/work_plays.dart';

BasicLib basic(String id, String rel, {int authors = 1, int works = 10}) =>
    BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: authors,
      works: works,
    );

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  AppSettings.stripLibIndex = true;

  final tree = buildUnitTree(
    nodes: const [
      LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
      LibNode(id: 'big-01-sub', rel: '(1) A/sub', name: 'sub'),
    ],
    basics: [
      basic('l1', '(1) A/x'),
      basic('l2', '(1) A/sub/y'),
    ],
  )!;
  final unit = tree.children.first;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WorkPlaysStore.resetForTest(items: const {});
  });
  tearDown(() => WorkPlaysStore.resetForTest(items: const {}));

  testWidgets('基础库卡片：coverUrlOf 优先于静态地址', (t) async {
    await t.pumpWidget(host(BasicLibCard(
      basic: unit.basics.first,
      onTap: () {},
      coverUrl: 'http://static/old.jpg',
      coverUrlOf: (_) => 'http://lazy/new.jpg',
    )));
    await t.pump();
    expect(find.byKey(const ValueKey('basic-cover-l1')), findsOneWidget);
  });

  testWidgets('基础库卡片：本库播放量变化时重新求值封面（无需重建父节点）',
      (t) async {
    final b = unit.basics.first;
    var calls = 0;
    await t.pumpWidget(host(BasicLibCard(
      basic: b,
      onTap: () {},
      coverUrlOf: (_) {
        calls++;
        return '';
      },
    )));
    await t.pump();
    final before = calls;
    expect(before, greaterThanOrEqualTo(1));

    // 走真实写入路径：只自增该库的通知器。
    WorkPlaysStore.bump(b.id, 'w1', thumb: 'th.jpg');
    await WorkPlaysStore.flush();
    await t.pump();
    expect(calls, greaterThan(before),
        reason: '播放量写入后，卡片应自己重算封面地址');
  });

  testWidgets('基础库卡片：别的库播放不触发本卡重算', (t) async {
    final b = unit.basics.first;
    var calls = 0;
    await t.pumpWidget(host(BasicLibCard(
      basic: b,
      onTap: () {},
      coverUrlOf: (_) {
        calls++;
        return '';
      },
    )));
    await t.pump();
    final before = calls;

    // 只写别的库：本卡的通知器不应被唤醒。
    WorkPlaysStore.bump('l2', 'w9', thumb: 'other.jpg');
    await WorkPlaysStore.flush();
    await t.pump();
    expect(calls, before);
  });

  testWidgets('单元库卡片：子树内播放量变化时重新求值封面', (t) async {
    var calls = 0;
    await t.pumpWidget(host(UnitLibraryCard(
      unit: unit,
      onTap: () {},
      coverUrlOf: (_) {
        calls++;
        return '';
      },
    )));
    await t.pump();
    final before = calls;

    WorkPlaysStore.bump('l2', 'w1', thumb: 'y/th.jpg');
    await WorkPlaysStore.flush();
    await t.pump();
    expect(calls, greaterThan(before));
  });
}
