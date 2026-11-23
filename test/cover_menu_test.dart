import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_history.dart';
import 'package:shoucangjia/cover_menu.dart';
import 'package:shoucangjia/cover_upload.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library_view.dart';

BasicLib basic(String id, String rel) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 2,
    );

CoverMenuActions actions({
  required VoidCallback onAuto,
  required VoidCallback onClear,
  void Function(CoverVersion v)? onRestore,
  List<CoverVersion>? versions,
  VoidCallback? onChanged,
}) {
  return CoverMenuActions(
    libId: 'l1',
    urlOf: (p) => 'http://127.0.0.1:8091$p',
    pickLocal: () async =>
        const CoverUploadResult(true, '封面已更新', url: '/media/l1/_cover/v9.jpg'),
    listVersions: () async => CoverListResult(true, '',
        versions: versions ??
            const [
              CoverVersion(
                  version: 'v2',
                  ext: 'jpg',
                  url: '/media/l1/_cover/v2.jpg',
                  current: true),
              CoverVersion(
                  version: 'v1', ext: 'jpg', url: '/media/l1/_cover/v1.jpg'),
            ]),
    restore: (v) async {
      onRestore?.call(v);
      return CoverActionResult(true, '已切换到该封面', url: v.url);
    },
    restoreAuto: () async {
      onAuto();
      return const CoverActionResult(true, '已恢复自动封面');
    },
    clearAll: () async {
      onClear();
      return const CoverActionResult(true, '已清除自定义封面');
    },
    onChanged: onChanged,
  );
}

void main() {
  final oneBasic = basic('l1', '(1) A/x');

  Future<void> openMenu(WidgetTester t, CoverMenuActions a) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BasicLibCard(basic: oneBasic, onTap: () {}, coverMenu: a),
      ),
    ));
    await t.tap(find.byKey(const ValueKey('basic-cover-btn-l1')));
    await t.pumpAndSettle();
  }

  testWidgets('封面入口一个按钮，弹出四项菜单', (t) async {
    await openMenu(t, actions(onAuto: () {}, onClear: () {}));
    expect(find.byKey(const ValueKey('cover-menu-local')), findsOneWidget);
    expect(find.byKey(const ValueKey('cover-menu-history')), findsOneWidget);
    expect(find.byKey(const ValueKey('cover-menu-auto')), findsOneWidget);
    expect(find.byKey(const ValueKey('cover-menu-clear')), findsOneWidget);
  });

  testWidgets('恢复自动封面：调用服务端动作并提示', (t) async {
    var autos = 0;
    var changed = 0;
    await openMenu(t,
        actions(onAuto: () => autos++, onClear: () {}, onChanged: () => changed++));
    await t.tap(find.byKey(const ValueKey('cover-menu-auto')));
    await t.pumpAndSettle();
    expect(autos, 1);
    expect(changed, 1);
    expect(find.text('已恢复自动封面'), findsOneWidget);
  });

  testWidgets('清除自定义封面：必须二次确认', (t) async {
    var clears = 0;
    await openMenu(t, actions(onAuto: () {}, onClear: () => clears++));
    await t.tap(find.byKey(const ValueKey('cover-menu-clear')));
    await t.pumpAndSettle();
    expect(find.text('清除自定义封面？'), findsOneWidget);
    expect(clears, 0);
    await t.tap(find.widgetWithText(FilledButton, '清除'));
    await t.pumpAndSettle();
    expect(clears, 1);
  });

  testWidgets('过往封面：列出缩略图并切回旧版本', (t) async {
    CoverVersion? restored;
    await openMenu(
        t,
        actions(
          onAuto: () {},
          onClear: () {},
          onRestore: (v) => restored = v,
        ));
    await t.tap(find.byKey(const ValueKey('cover-menu-history')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('cover-version-v1.jpg')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('cover-version-v2.jpg')),
        findsOneWidget);
    await t.tap(find.byKey(const ValueKey('cover-version-v1.jpg')));
    await t.pumpAndSettle();
    expect(restored?.version, 'v1');
    expect(find.text('已切换到该封面'), findsOneWidget);
  });

  testWidgets('旧入口未提供菜单时仍可直接选图（兼容）', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BasicLibCard(
          basic: oneBasic,
          onTap: () {},
          onSetCover: () => taps++,
        ),
      ),
    ));
    await t.tap(find.byKey(const ValueKey('basic-cover-btn-l1')));
    expect(taps, 1);
  });
}
