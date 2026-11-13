import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/text_fit.dart';

void main() {
  const style = TextStyle(fontSize: 12);

  testWidgets('长标题在窄屏判定为截断，宽屏不截断', (tester) async {
    final title = '这是一个非常非常长的作品标题用来测试展开按钮是否出现';
    expect(willOverflowText(title, style, 180), isTrue);
    expect(willOverflowText(title, style, 800), isFalse);
  });

  testWidgets('字符数不再作为唯一阈值', (tester) async {
    // 26 个字符但屏宽足够：旧规则（>24）会误显示按钮，新逻辑不应显示。
    expect(willOverflowText('a' * 26, style, 800), isFalse);
    // 只有 10 个字符但可用宽度极窄：应显示按钮。
    expect(willOverflowText('a' * 10, style, 40), isTrue);
  });

  testWidgets('文本缩放与空文本', (tester) async {
    final title = '中等长度的作品标题内容';
    expect(willOverflowText(title, style, 260), isFalse);
    expect(
        willOverflowText(title, style, 260,
            textScaler: const TextScaler.linear(2.0)),
        isTrue);
    expect(willOverflowText('', style, 100), isFalse);
    expect(willOverflowText('abc', style, 0), isFalse);
  });
}
