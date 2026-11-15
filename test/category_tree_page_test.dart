import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/category_tree_page.dart';
import 'package:shoucangjia/library_tree.dart';

BasicLib basic() => const BasicLib(
      id: 'lib-001',
      name: '测试库',
      rel: 'A/B',
      bigId: 'big-01',
      authors: 3,
      works: 10,
    );

Widget host() => MaterialApp(
      home: CategoryTreePage(
        basic: basic(),
        urlOf: (path, {lib}) => Uri.parse('http://127.0.0.1:1$path'),
        headersOf: ([lib]) => const {},
        onOpenAuthor: (_) {},
      ),
    );

void main() {
  testWidgets('页面骨架：标题、筛选框、刷新按钮', (tester) async {
    await tester.pumpWidget(host());
    expect(find.textContaining('分类'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('请求失败时展示错误而不是崩溃', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('HTTP'), findsWidgets);
  });
}
