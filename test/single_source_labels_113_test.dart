import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_upload.dart';
import 'package:shoucangjia/level_names.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/unit_author_groups.dart';

// 0.9.360 第一百一十三批：**同一个量有两个家**，这次落在「标题文案」上。
//
// 四项都是同一种形状：同一个字符串/判定被抄了几份，改了其中一处就分叉。
// 判据只用源码文本与纯函数返回值，不涉及目录名、文件名或媒体内容。

String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('1. 页面里的层级标题读同一份 levelName', () {
    test('作者筛选面板的分节标题不再写死三个字面量', () {
      final ui = _code('lib/author_filter_ui.dart');
      for (final lit in <String>["_section('媒体库'", "_section('单元库'", "_section('基础库'"]) {
        expect(ui.contains(lit), isFalse, reason: '面板又写死了 $lit');
      }
      for (final kind in <LibEntryKind>[
        LibEntryKind.top,
        LibEntryKind.unit,
        LibEntryKind.basic,
      ]) {
        expect(ui.contains('_section(levelName(LibEntryKind.${kind.name})'),
            isTrue,
            reason: '${kind.name} 分节标题必须读 levelName');
      }
    });

    test('首页标题与「N 个」计数同源', () {
      final view = _code('lib/unit_library_view.dart');
      expect(view.contains('Text(levelName(LibEntryKind.top)'), isTrue);
      expect(
          view.contains("'\${units.length} 个\${levelName(LibEntryKind.top)}'"),
          isTrue,
          reason: '计数文案若自立门户，改名后会出现「媒体库 … 3 个单元库」');
      expect(view.contains("'当前连接下没有可显示的\${levelName(LibEntryKind.top)}"),
          isTrue);
      // 展开分组标题（单元库 / 基础库）同样读表。
      expect(view.contains('child: Text(levelName(LibEntryKind.basic)'), isTrue);
    });

    test('库词条配色页的分组标题读表', () {
      final main = _code('lib/main.dart');
      expect(main.contains('child: Text(levelName(LibEntryKind.unit)'), isTrue);
      expect(
          main.contains("'\${levelName(LibEntryKind.basic)}（优先级最高）'"),
          isTrue);
    });
  });

  group('2. 「其它（不属于任何媒体库）」只有一个出处', () {
    test('常量值是界面上的那句话', () {
      expect(kOtherSectionTitle, '其它（不属于任何媒体库）');
    });

    test('crawler_sections 与 main.dart 都读常量，不再各写一份', () {
      for (final path in <String>[
        'lib/crawler_sections.dart',
        'lib/main.dart',
      ]) {
        final src = _code(path);
        expect(src.contains("'其它（不属于任何媒体库）'"), isFalse,
            reason: '$path 又写了一遍那句标题');
      }
      expect(_code('lib/crawler_sections.dart').contains('?? kOtherSectionTitle'),
          isTrue);
      expect('kOtherSectionTitle'.allMatches(_code('lib/main.dart')).length,
          greaterThanOrEqualTo(2),
          reason: '配色页与爬虫设置页都该用常量');
    });
  });

  group('3. 长按菜单：动作是枚举，文案只是显示', () {
    test('枚举顺序与文案就是菜单那一列', () {
      expect(
          [for (final a in StageMenuAction.values) a.label],
          <String>['不感兴趣', '保存到本机', '复制文案', '举报']);
      expect(kStageMenuLabels, [for (final a in StageMenuAction.values) a.label]);
    });

    test('分发与控件键都不再绑中文串', () {
      final main = _code('lib/main.dart');
      expect(main.contains('Future<void> _onStageMenuAction(StageMenuAction action)'),
          isTrue);
      // 旧写法：`switch (label) { case '不感兴趣': … }`。
      expect(RegExp(r"case\s*'[^']*'\s*:").allMatches(main.substring(
              main.indexOf('_onStageMenuAction'))).length,
          0,
          reason: '菜单分发又回到了按文案 switch');
      expect(main.contains("Key('stage-menu-\${a.name}')"), isTrue,
          reason: '控件键该用枚举名，否则改名就改键');
      expect(main.contains("for (final a in StageMenuAction.values)"), isTrue);
    });
  });

  group('4. 图片字节的三条判定只有一处', () {
    test('空 / 超限 / 魔数不对，各给一句话', () {
      expect(imageBytesError(const <int>[]), '图片为空');
      expect(
          imageBytesError(List<int>.filled(kCoverUploadMaxBytes + 1, 0)),
          '图片超过 12MB，请先压缩');
      expect(imageBytesError(List<int>.filled(16, 0)), '只支持 JPG/PNG/WebP 图片');
      // 合法 JPEG 头不应报错。
      expect(
          imageBytesError(<int>[0xFF, 0xD8, 0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]),
          isNull);
    });

    test('lib/ 内这三句只在 cover_upload.dart 出现', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('cover_upload.dart')) continue;
        final src = _code(f.path);
        if (src.contains("'图片超过 12MB，请先压缩'") ||
            src.contains("'只支持 JPG/PNG/WebP 图片'") ||
            src.contains("_toast('图片为空')")) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty, reason: '判定被第二处抄了：${offenders.join(', ')}');
    });

    test('封面两处入口都走同一判定', () {
      final src = _code('lib/cover_upload.dart');
      expect('imageBytesError(bytes)'.allMatches(src).length, 2,
          reason: '封面选图与封面直传各一次');
      expect(src.contains('isSupportedCoverBytes(bytes)'), isTrue,
          reason: '判定本体仍在这里');
    });
  });

  group('5. 建目录结果文案只有一个出口', () {
    test('三种计数与全零时的措辞', () {
      expect(authorCreateSummary(made: 2, existed: 1, failed: 0),
          '新建 2 个 · 已存在 1 个');
      expect(authorCreateSummary(made: 0, existed: 0, failed: 3), '失败 3 个');
      expect(authorCreateSummary(made: 1, existed: 0, failed: 1),
          '新建 1 个 · 失败 1 个');
      expect(authorCreateSummary(made: 0, existed: 0, failed: 0), '未创建任何目录');
    });

    test('三个页面都调用它，不再各拼 parts 列表', () {
      for (final path in <String>[
        'lib/basic_lib_page.dart',
        'lib/unit_author_mount_page.dart',
      ]) {
        final src = _code(path);
        expect(src.contains('authorCreateSummary('), isTrue, reason: path);
        expect(src.contains("'新建 \$made 个'"), isFalse,
            reason: '$path 又自己拼了一遍汇总');
      }
      // 作者页是单库路径，措辞另有「该作者目录已存在」分支，不算重复。
      expect(_code('lib/unit_author_groups.dart').contains("'新建 \$made 个'"),
          isTrue);
    });
  });
}
