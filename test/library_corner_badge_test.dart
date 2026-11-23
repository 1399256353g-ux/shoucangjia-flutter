import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/library_corner_badge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LibraryCornerBadge.resetDefaults();
  });

  test('层级判定只认结构事实，不看任何文本', () {
    expect(LibraryCornerBadge.kindOf(isTop: true, isUnit: true),
        LibBadgeKind.top);
    expect(LibraryCornerBadge.kindOf(isTop: false, isUnit: true),
        LibBadgeKind.unit);
    expect(LibraryCornerBadge.kindOf(isTop: false, isUnit: false),
        LibBadgeKind.basic);
  });

  test('四种层级默认图案互不相同（可区分）', () {
    final kinds = [LibBadgeKind.top, LibBadgeKind.unit, LibBadgeKind.basic];
    final patterns = kinds.map(LibraryCornerBadge.patternFor).toList();
    expect(patterns.toSet().length, 3);
  });

  test('图案 id 越界回落到该层级默认值', () {
    expect(LibraryCornerBadge.clampPattern(LibBadgeKind.top, 99),
        kDefaultCornerPattern[LibBadgeKind.top]);
    expect(LibraryCornerBadge.clampPattern(LibBadgeKind.top, -1),
        kDefaultCornerPattern[LibBadgeKind.top]);
    expect(LibraryCornerBadge.clampPattern(LibBadgeKind.top, 3), 3);
  });

  test('设置图案/颜色会持久化并可重新读回', () async {
    await LibraryCornerBadge.setPattern(LibBadgeKind.basic, 4);
    await LibraryCornerBadge.setColor(LibBadgeKind.basic, 0xFFAB12CD);
    expect(LibraryCornerBadge.patternFor(LibBadgeKind.basic), 4);
    expect(LibraryCornerBadge.colorFor(LibBadgeKind.basic), 0xFFAB12CD);

    LibraryCornerBadge.resetDefaults();
    expect(LibraryCornerBadge.patternFor(LibBadgeKind.basic),
        kDefaultCornerPattern[LibBadgeKind.basic]);

    await LibraryCornerBadge.load();
    expect(LibraryCornerBadge.patternFor(LibBadgeKind.basic), 4);
    expect(LibraryCornerBadge.colorFor(LibBadgeKind.basic), 0xFFAB12CD);
  });

  test('恢复默认只影响指定层级', () async {
    await LibraryCornerBadge.setPattern(LibBadgeKind.top, 7);
    await LibraryCornerBadge.setPattern(LibBadgeKind.unit, 6);
    await LibraryCornerBadge.resetKind(LibBadgeKind.top);
    expect(LibraryCornerBadge.patternFor(LibBadgeKind.top),
        kDefaultCornerPattern[LibBadgeKind.top]);
    expect(LibraryCornerBadge.patternFor(LibBadgeKind.unit), 6);
  });

  test('序列化容错：非法图案/颜色不炸，越界图案夹回默认', () {
    LibraryCornerBadge.applyJson({
      'pattern': {'top': 42, 'unit': 'oops'},
      'color': {'top': 0xFF00FF00, 'unit': 'zz'},
    });
    expect(LibraryCornerBadge.patternFor(LibBadgeKind.top),
        kDefaultCornerPattern[LibBadgeKind.top]);
    expect(LibraryCornerBadge.patternFor(LibBadgeKind.unit),
        kDefaultCornerPattern[LibBadgeKind.unit]);
    expect(LibraryCornerBadge.colorFor(LibBadgeKind.top), 0xFF00FF00);
  });

  testWidgets('角标四层级形状与尺寸完全一致，只有图案不同', (tester) async {
    final sizes = <String, Size>{};
    for (final kind in LibBadgeKind.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(child: LibCornerBadge(kind: kind)),
        ),
      );
      final box = tester.getSize(find.byType(LibCornerBadge));
      sizes[kind.name] = box;
    }
    expect(sizes.values.map((s) => s.width).toSet().length, 1);
    expect(sizes.values.map((s) => s.height).toSet().length, 1);
    expect(sizes[LibBadgeKind.top.name], const Size(kCornerBadgeSize, kCornerBadgeSize));
  });
}
