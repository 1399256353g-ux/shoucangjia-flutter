/// 第六十九批契约（0.9.291）：**第三份实现**——同一件事已经有了一处唯一实现，
/// 但还有第三个地方照着自己的旧写法再画一遍。
///
/// 第六十七批把作者头像从两份收成一份（`author_avatar_view`），把「头像绘制」
/// 定义了唯一出处。这一批发现：
///
/// 1. 播放页信息区头像**是第三份手写渲染**：38dp 内联、`memCacheWidth` 自己算
///    `(38 * dpr).round()`（没走 `avatarDecodeWidth`）、错误占位是
///    `CircleAvatar + Icons.person`（其它四处都是首字母占位）。于是同一张头像在
///    播放页要按另一个尺寸再解码一次、且「没头像」时长相与别处不同。
/// 2. 「单元库词条 + 等级」这组小标签在基础库页作者卡上是**两个手写
///    Container**（圆角 4、无 emoji、无层级边框、等级 w600），与作者总览卡走
///    `LibBadges → LibBadgeChip` 的一套完全不同 → 同一作者在两页词条不一样。
/// 3. 作者主页收起栏的等级词条是**第三份**手写（圆角 4、18% 透明度、w700）。
///
/// 本批把「绘制」收成两处：`author_avatar_view`（头像）与
/// `author_badge_row`（词条组 + 单个词条）。任何页面都只能转发，不得自己画。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_avatar_view.dart';
import 'package:shoucangjia/author_grid.dart' show avatarDecodeWidth;
import 'package:shoucangjia/card_metrics.dart';
import 'package:shoucangjia/lib_cover.dart' show libForMediaPath;

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('播放页头像不再是第三份手写（0.9.291）', () {
    test('播放页信息区转发 AuthorAvatarView，不再自己建 CachedNetworkImage', () {
      final main = _code('lib/main.dart');
      // 播放页那段必须出现转发。
      expect(main.contains('AuthorAvatarView('), isTrue);

      // 全 lib/ 只有 author_avatar_view 允许直接建 CachedNetworkImage 画头像；
      // 播放页那块（头像 + 作者名那个 Row 内）不得再出现自算解码宽度。
      final anchor = main.indexOf('valueListenable: authorAvatarRevision');
      expect(anchor, greaterThan(0));
      final body = main.substring(anchor, anchor + 1600);
      expect(body.contains('AuthorAvatarView('), isTrue,
          reason: '播放页头像必须转发唯一实现');
      expect(body.contains('memCacheWidth:'), isFalse,
          reason: '播放页不得再自算头像解码宽度（要走 avatarDecodeWidth）');
      expect(body.contains('ClipOval('), isFalse,
          reason: '播放页不得再自己圆形裁剪头像');
      expect(body.contains('Icons.person'), isFalse,
          reason: '占位已统一为首字母，不再用人形图标');
      expect(body.contains('name: authorLabel'), isTrue,
          reason: '占位首字符必须用剥过 `@` 的名字，否则画出一个 `@`');
    });

    test('头像边长 38 只有一处，且与解码宽度规则同源', () {
      expect(kAvatarPlayerSize, 38);
      // 其它四个头像尺寸互不相等，说明它不是其中任何一个的别名（不是复制来的）。
      expect(kAvatarPlayerSize == kAvatarGridSize, isFalse);
      expect(kAvatarPlayerSize == kAvatarRankSize, isFalse);
      expect(kAvatarPlayerSize == kAvatarHeaderSize, isFalse);
      // 解码宽度仍由唯一入口算：按显示尺寸 × 像素比。
      expect(avatarDecodeWidth(displaySize: 38, devicePixelRatio: 3.0), 114);
      final main = _code('lib/main.dart');
      expect(main.contains('(38 *'), isFalse,
          reason: '38 不得再以内联字面量出现在解码宽度里');
    });
  });

  group('「路径属于哪个库」只有一个判断（0.9.291）', () {
    test('avatarLibOf：路径自带库段优先，取不到才用调用方的库', () {
      expect(avatarLibOf('/media/B/_avatar/x.jpg', fallbackLib: 'A'), 'B');
      // 绝对地址无库段 → 用调用方的库。
      expect(avatarLibOf('https://cdn.example.com/x.jpg', fallbackLib: 'A'), 'A');
      // 两边都取不到 → 空串（调用方自己决定回落）。
      expect(avatarLibOf('x.jpg'), '');
      // 前后空白不影响判定（路径解析必须自己 trim）。
      expect(avatarLibOf('  /media/B/x.jpg  ', fallbackLib: 'A'), 'B');
    });

    test('libForMediaPath：四份内联写法的唯一出口', () {
      expect(libForMediaPath('/media/B/a.jpg', fallbackLib: 'A'), 'B');
      expect(libForMediaPath('/media/', fallbackLib: 'A'), 'A');
      expect(libForMediaPath('rel/a.jpg', fallbackLib: 'A'), 'A');
      expect(libForMediaPath('rel/a.jpg'), '');
      // 回退库前后的空白不影响鉴权头查找。
      expect(libForMediaPath('rel/a.jpg', fallbackLib: ' A '), 'A');
    });

    test('main 里不再自己写「libOfMediaPath 为空就用当前库」', () {
      final main = _code('lib/main.dart');
      expect(main.contains('String _avatarLibFor('), isFalse,
          reason: '播放页的库归属判断已收进 avatarLibOf');
      expect(main.contains('libOfMediaPath(p).isEmpty'), isFalse);
      expect(main.contains('libOfMediaPath(src).isEmpty'), isFalse);
      expect(main.contains('libForMediaPath('), isTrue,
          reason: '四处同义判断必须走同一出口');
    });
  });

  group('作者词条只有一套渲染（0.9.291）', () {
    test('词条绘制只在 author_badge_row，两个调用方都转发', () {
      final row = _code('lib/author_badge_row.dart');
      // 0.9.312：`BadgeChipWrap`（不可折叠的那一份）已删除——lib/ 里零调用点，
      // 只有这条断言还在认它，属于「测试证明一个不存在的 UI」。
      // 契约意图不变：词条容器只有 author_badge_row 一处。
      expect(row.contains('class BadgeChipWrap'), isFalse);
      expect(row.contains('class CollapsibleBadgeWrap'), isTrue);
      expect(row.contains('class BadgeChipSpec'), isTrue);
      expect(row.contains('class AuthorBadgeRow'), isTrue);
      // 唯一画词条的地方：`LibBadgeChip`。
      expect(row.contains('LibBadgeChip('), isTrue);

      // 基础库页不得再自己拼词条容器。
      final basic = _code('lib/basic_lib_page.dart');
      expect(basic.contains('AuthorBadgeRow('), isTrue);
      expect(basic.contains('LibBadgeChip('), isFalse,
          reason: '基础库页必须转发 AuthorBadgeRow，不自己画词条');
      expect('circular(4)'.allMatches(basic).length, 0,
          reason: '基础库页不得再有自己算圆角的词条容器');
      // 等级不再由页面自己算颜色/圆角。
      expect(basic.contains('AuthorGrade.colorForGrade('), isFalse);
      expect(basic.contains('LibraryBadge.textColorOn('), isFalse);

      // main 的 LibBadges 也只翻译成 spec，不再自己摆 Wrap。
      final main = _code('lib/main.dart');
      final cls = main.indexOf('class LibBadges');
      expect(cls, greaterThan(0));
      final body = main.substring(cls, main.indexOf('class UnitBadges'));
      // 2026-11-26：词条行换成可折叠容器（基础库词条常态收纳）。
      // 契约的意图不变——摆词条仍然只有 author_badge_row 一处实现：
      //   · 这里只允许转发容器（BadgeChipWrap 或 CollapsibleBadgeWrap）
      //   · 不得自己写间距
      //   · 不得自己画 LibBadgeChip
      final usesContainer = body.contains('CollapsibleBadgeWrap(');
      expect(usesContainer, isTrue,
          reason: 'LibBadges 必须转发 author_badge_row 里的词条行容器');
      expect(body.contains('spacing: 3'), isFalse,
          reason: '词条间距只在 author_badge_row 一处');
      expect(body.contains('LibBadgeChip('), isFalse,
          reason: 'LibBadges 只产出 BadgeChipSpec，不自绘');
    });

    test('作者主页收起栏的等级词条不再手写', () {
      final main = _code('lib/main.dart');
      // 收起栏那段：`_headerCollapsed.value` 之后到 `return Padding(` 之前。
      final i = main.indexOf('if (_headerCollapsed.value) {');
      expect(i, greaterThan(0));
      final body = main.substring(i, i + 1600);
      expect(body.contains('AuthorBadgeRow(grade: grade)'), isTrue);
      expect(body.contains('circular(4)'), isFalse,
          reason: '等级词条不得在收起栏里再手画一遍圆角');
      expect(body.contains('withValues(alpha: 0.18)'), isFalse,
          reason: '等级词条不得自己算底色透明度');
    });

    test('基础库页词条数据来源仍是本页自己的统计（渲染统一，数据不统一）', () {
      final basic = _code('lib/basic_lib_page.dart');
      expect(basic.contains('widget.sourceLabel'), isTrue);
      expect(basic.contains('_authorStats[name]'), isTrue);
      // 预览：等级由 AuthorGrade 唯一算法给出。
      expect(basic.contains('AuthorGrade.fromStats('), isTrue);
    });
  });
}
