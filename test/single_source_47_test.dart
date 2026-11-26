/// 第六十七批契约（0.9.290）：**两处都能画出来，所以没人发现其中一处画错了**。
///
/// 前几批抓的是「同段代码抄多份」「同一记录两个模型」「同一数字两种说法」
/// 「页面自己办了一件本该有名字的事」。这一批抓的是更隐蔽的一类：
/// **两份实现写在不同文件里、外观略有差异**——谁都不会报错，于是差异被当成
/// 设计。
///
/// 1. 作者头像有两份渲染：`main.AuthorAvatar` 与 `basic_lib_page._authorAvatar`。
///    后者**不监听** `AuthorAvatarStore`，于是「在作者主页手动设的头像，进基础
///    库页作者 tab 还是旧图」——这是真缺陷，不是外观问题。
/// 2. 基础库页作者 tab 是唯一没有预热入口的头像列表：首屏逐张请求。
/// 3. 播放页提示条的 `horizontal: 24` / `circular(999)` / 14,7 / 13 是内联
///    数字，与 `kPlayerNoticeTop` 同属「提示条自身尺寸」却分居两处。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_avatar_view.dart';
import 'package:shoucangjia/author_index.dart'
    show
        basicAuthorGridPadding,
        authorGridPadRight,
        kAuthorGridPadLeft,
        kAuthorGridPadRight,
        kAuthorIndexBarWidth,
        kAuthorIndexBarGap;
import 'package:shoucangjia/card_metrics.dart';
import 'package:shoucangjia/grid_spec.dart';
import 'package:shoucangjia/player_controls.dart';

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('作者头像渲染只有一个实现（0.9.290）', () {
    test('头像绘制只在 author_avatar_view，两个调用方都转发', () {
      final view = _code('lib/author_avatar_view.dart');
      expect(view.contains('class AuthorAvatarView'), isTrue);
      expect(view.contains('CachedNetworkImage('), isTrue);
      expect(view.contains('ClipOval('), isTrue);
      expect(view.contains('kAvatarImageWidth'), isTrue);
      expect(view.contains('avatarDecodeWidth('), isTrue);
      // 占位也在这里，不再由调用方各算一份。
      expect(view.contains('AvatarLetterPlaceholder('), isTrue);

      // 基础库页不得再自己画头像（此前它在页面里内联 CachedNetworkImage）。
      final basic = _code('lib/basic_lib_page.dart');
      expect(basic.contains('CachedNetworkImage'), isFalse,
          reason: '基础库页作者头像必须转发 AuthorAvatarView');
      expect(basic.contains('AuthorAvatarView('), isTrue);

      // main 的 AuthorAvatar 只做「挑路径 + 转发」，自己不画。
      final main = _code('lib/main.dart');
      expect(main.contains('AuthorAvatarView('), isTrue);
    });

    test('两份渲染不再各算一套解码宽度与占位样式', () {
      final main = _code('lib/main.dart');
      // `AuthorAvatar` 类体内不得再出现解码头像的写法。
      final cls = main.indexOf('class AuthorAvatar ');
      expect(cls, greaterThan(0));
      final body = main.substring(cls, main.indexOf('class AuthorBadges'));
      expect(body.contains('memCacheWidth:'), isFalse);
      expect(body.contains('withImageWidth('), isFalse);
      expect(body.contains('AvatarLetterPlaceholder('), isFalse);
    });
  });

  group('手动头像在基础库页也生效（真缺陷契约）', () {
    test('基础库页监听 AuthorAvatarStore，不用一次性读取', () {
      final basic = _code('lib/basic_lib_page.dart');
      expect(basic.contains('AuthorAvatarStore.instance'), isTrue);
      // 必须包在 AnimatedBuilder 里：只读一次的话，从作者主页设完返回仍是旧图。
      final i = basic.indexOf('Widget _authorAvatar({');
      final body = basic.substring(i, basic.indexOf('void _prefetchAuthors()'));
      expect(body.contains('AnimatedBuilder('), isTrue);
      expect(body.contains('animation: AuthorAvatarStore.instance'), isTrue);
    });

    test('优先级合成只有一处：resolveAvatarSource', () {
      final view = _code('lib/author_avatar_view.dart');
      expect(view.contains('({String path, String? lib}) resolveAvatarSource('),
          isTrue);
      // 两个调用方都必须走它，不能各自判 manual 是否为空。
      for (final f in ['lib/main.dart', 'lib/basic_lib_page.dart']) {
        expect(_code(f).contains('resolveAvatarSource('), isTrue, reason: f);
      }
    });

    test('手动路径来自别的库时，库归属按路径前缀取', () {
      // 覆盖图在 B 库，调用方只知道自己属于 A 库：必须按 B 取鉴权，
      // 否则带错 Authorization → 401 → 头像永远空白。
      final r = resolveAvatarSource(
        manual: '/media/B/_avatar/x.jpg',
        fallback: '/media/A/av.jpg',
        fallbackLib: 'A',
      );
      expect(r.path, '/media/B/_avatar/x.jpg');
      expect(r.lib, 'B');

      // 没有覆盖时用兜底，库归属仍由调用方给。
      final f = resolveAvatarSource(
        manual: '   ',
        fallback: '/media/A/av.jpg',
        fallbackLib: 'A',
      );
      expect(f.path, '/media/A/av.jpg');
      expect(f.lib, 'A');

      // 覆盖图取不出库段时回落到调用方的库，不返回空串。
      final g = resolveAvatarSource(
        manual: 'https://cdn.example.com/x.jpg',
        fallback: '/media/A/av.jpg',
        fallbackLib: 'A',
      );
      expect(g.lib, 'A');
    });
  });

  group('基础库页作者头像首屏预热（此前是唯一没有预热入口的列表）', () {
    test('预热走 avatar_prefetch，几何来自 kBasicAuthorGrid', () {
      final basic = _code('lib/basic_lib_page.dart');
      expect(basic.contains('void _prefetchAuthors()'), isTrue);
      final i = basic.indexOf('void _prefetchAuthors()');
      final body = basic.substring(i, i + 2000);
      expect(body.contains('prefetchAvatarItems('), isTrue);
      expect(body.contains('kBasicAuthorGrid.prefetchCount('), isTrue);
      // 不得自己挑张数/自己拼 w=。
      expect(body.contains('firstScreenThumbCount('), isFalse);
      expect(body.contains('withImageWidth('), isFalse);
      // 显示尺寸与卡片同源。
      expect(body.contains('displaySize: kAvatarBasicAuthorSize'), isTrue);
    });

    test('切到作者 tab 才预热，作品 tab 不白占解码额度', () {
      final basic = _code('lib/basic_lib_page.dart');
      expect(basic.contains('void _onTabChanged()'), isTrue);
      expect(basic.contains('_tabs.addListener(_onTabChanged)'), isTrue);
      expect(basic.contains('_tabs.removeListener(_onTabChanged)'), isTrue);
      final i = basic.indexOf('void _onTabChanged()');
      final body = basic.substring(i, i + 200);
      expect(body.contains('_tabs.index == 1'), isTrue);
    });

    test('几何与真实网格同源（padding 只来自 author_index 的同一份定义）', () {
      final basic = _code('lib/basic_lib_page.dart');
      final i = basic.indexOf('void _prefetchAuthors()');
      final body = basic.substring(i, i + 2000);
      // 0.9.292：预热与网格 `GridView.padding` 读同一个 `basicAuthorGridPadding`，
      // 本页不再自己拼左/右/上下三个数（它仍是同一份定义里的 12/12）。
      expect(body.contains('basicAuthorGridPadding(hasIndexBar:'), isTrue);
      expect(body.contains('EdgeInsets.fromLTRB('), isFalse,
          reason: '预热不得再自己拼内边距（与网格各写一份就会分叉）');
      // 定义本身仍由 `authorGridPadRight` 决定右边缘（索引条让位）。
      final pad = basicAuthorGridPadding(hasIndexBar: true);
      expect(pad.left, kAuthorGridPadLeft);
      expect(pad.right, authorGridPadRight(hasIndexBar: true));
      expect(pad.right, kAuthorIndexBarWidth + kAuthorIndexBarGap);
      expect(basicAuthorGridPadding(hasIndexBar: false).right,
          kAuthorGridPadRight);
      // 右侧让出索引条后，预热列数才与真实排布一致。
      expect(kBasicAuthorGrid.maxCrossAxisExtent, 180);
    });
  });

  group('播放页提示条自身尺寸只有一个出处（0.9.290）', () {
    test('24 / 999 不再是内联数字', () {
      final main = _code('lib/main.dart');
      final i = main.indexOf('class _PlayerTopNotice');
      expect(i, greaterThan(0));
      final body = main.substring(i, main.indexOf('class RecommendPage'));
      expect(body.contains('horizontal: 24'), isFalse,
          reason: '提示条左右留白必须走 kPlayerNoticeMarginX');
      expect(body.contains('circular(999)'), isFalse,
          reason: '提示条圆角必须走 kPlayerNoticeRadius');
      expect(body.contains('kPlayerNoticeMarginX'), isTrue);
      expect(body.contains('kPlayerNoticeRadius'), isTrue);
      expect(body.contains('kPlayerNoticePaddingX'), isTrue);
      expect(body.contains('kPlayerNoticePaddingY'), isTrue);
      expect(body.contains('kPlayerNoticeFontSize'), isTrue);
    });

    test('常量表齐全且与提示条下移量同源', () {
      expect(kPlayerNoticeMarginX, 24);
      expect(kPlayerNoticePaddingX, 14);
      expect(kPlayerNoticePaddingY, 7);
      expect(kPlayerNoticeRadius, 999);
      expect(kPlayerNoticeFontSize, 13);
      // 下移量仍是三个数的合成（上一批收的），这一批不重复定义。
      expect(
          kPlayerNoticeTop,
          kStageToolbarTopOffset +
              kStageToolbarRowHeight +
              kStageToolbarRowGap);
    });

    test('基础库页作者头像尺寸仍与作者总览同值（不因重构分叉）', () {
      expect(kAvatarBasicAuthorSize, kAvatarGridSize);
    });
  });
}
