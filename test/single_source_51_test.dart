/// 第七十二批契约（0.9.298）：**同一个参数名，两处两种含义**。
///
/// 前几批抓的是「同一段代码抄多份」「同一记录两个模型」「同一数字两种说法」
/// 「页面自己办了一件本该有名字的事」——它们都有第二个副本可对比。
/// 这一批抓的是更静默的一类：**两处都能跑，参数名还一样，含义却不同**。
///
/// 1. 预热配额：`prefetchLibCovers` 的 `limit` 数的是「看过的卡片」，
///    `prefetchThumbItems` / `prefetchWorkCovers` 数的是「真正入队的图片」。
///    首屏有两张卡没有封面时，库卡片那一页少预热两张可见封面——末两张仍然
///    逐张请求、先露底色，而三个入口「各自都算对了」。
/// 2. 页面内边距：`GridView` 不传 `padding` 时 `ScrollView` 自补 `MediaQuery`
///    竖向安全区，而预热侧传的是 `EdgeInsets.zero`——首屏行数多算，末行预热
///    的是屏幕外那张。基础库页则是 `EdgeInsets.all(10)` 写了两遍。
/// 3. 作品卡尺寸的那张 provider（`w=kWorkImageWidth` + `workCardDecodeWidth`）
///    在播放页三处各展开一遍（预载 / 海报底图 / 图文底图）。
/// 4. `resolveFirstWorkCover`（「第一张作品封面」兜底）零调用、零测试。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/grid_spec.dart';
import 'package:shoucangjia/lib_card_prefetch.dart';
import 'package:shoucangjia/work_cover.dart';

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('预热配额的语义在三个入口上一致（0.9.298）', () {
    test('库卡片：空封面不占配额，可见的几张都排上队', () {
      final reqs = libCoverPrefetchRequests(
        const [
          (cover: '', headers: <String, String>{}),
          (cover: '/a.jpg', headers: <String, String>{}),
          (cover: '   ', headers: <String, String>{}),
          (cover: '/b.jpg', headers: <String, String>{}),
        ],
        limit: 2,
      );
      expect(reqs.length, 2, reason: '两张空封面不能吃掉两张可见封面的配额');
      expect(reqs.map((r) => r.url).toList(),
          ['/a.jpg?w=480', '/b.jpg?w=480']);
    });

    test('库卡片：同一张封面出现两次只排一次', () {
      final reqs = libCoverPrefetchRequests(
        const [
          (cover: '/a.jpg', headers: <String, String>{}),
          (cover: '/a.jpg', headers: <String, String>{}),
          (cover: '/b.jpg', headers: <String, String>{}),
        ],
        limit: 3,
      );
      expect(reqs.length, 2);
    });

    test('库卡片：limit 为 0/负数返回空表，不抛', () {
      expect(
          libCoverPrefetchRequests(
            const [(cover: '/a.jpg', headers: <String, String>{})],
            limit: 0,
          ),
          isEmpty);
      expect(
          libCoverPrefetchRequests(
            const [(cover: '/a.jpg', headers: <String, String>{})],
            limit: -3,
          ),
          isEmpty);
    });

    test('三个入口的配额都数「入队的张数」（不再有 seen 计数器）', () {
      final lib = _code('lib/lib_card_prefetch.dart');
      expect(RegExp(r'\bseen\b').hasMatch(lib), isFalse,
          reason: '库卡片预热又用「看过几张」当配额，与另两个入口语义不同');
      expect(lib.contains('if (urls.length >= n)'), isFalse);
      // 唯一实现仍只在这里排队。
      expect(lib.contains('ThumbPrefetch.instance.run('), isTrue);
      // 预热请求构造抽成了纯函数，页面/测试都能直接断言。
      expect(lib.contains('List<ThumbPrefetchItem> libCoverPrefetchRequests('),
          isTrue);
    });
  });

  group('作品网格的 padding 只有一处（0.9.298）', () {
    testWidgets('workGridPadding 就是 MediaQuery 的竖向安全区', (t) async {
      late EdgeInsets got;
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(
              padding: EdgeInsets.only(top: 24, bottom: 34, left: 0, right: 0)),
          child: Builder(builder: (c) {
            got = workGridPadding(c);
            return const SizedBox.shrink();
          }),
        ),
      ));
      // 只取竖向：左右留白由页面自己的 `padding` 管，网格不在这里加水平边距。
      expect(got.top, 24);
      expect(got.bottom, 34);
      expect(got.left, 0);
      expect(got.right, 0);
    });

    test('没有 MediaQuery 时退化为 0，不抛', () {
      // 直接验证「拿不到 MediaQuery → EdgeInsets.zero」这条分支的形态。
      final src = _code('lib/grid_spec.dart');
      expect(src.contains('MediaQuery.maybePaddingOf(context)'), isTrue);
      expect(src.contains('if (p == null) return EdgeInsets.zero;'), isTrue);
    });

    test('WorkGrid 的网格与预热读同一个 padding', () {
      final src = _code('lib/main.dart');
      expect(RegExp(r'padding: workGridPadding\(context\)').allMatches(src).length,
          2,
          reason: '一处是 GridView，一处是 _prefetchFirstScreen');
      // 预热侧不得再写 `EdgeInsets.zero` 顶替安全区。
      expect(RegExp(r'grid: kWorkGrid,\s*padding: EdgeInsets\.zero').hasMatch(src),
          isFalse);
    });

    test('基础库页的作品网格 padding 也只有一个常量', () {
      final page = _code('lib/basic_lib_page.dart');
      expect(page.contains('EdgeInsets.all(10)'), isFalse,
          reason: '网格与预热各写一遍 all(10)，改一处另一处不跟');
      expect(
          RegExp(r'kBasicWorkGridPadding').allMatches(page).length, 2,
          reason: '声明在 grid_spec，页面只有网格 + 预热两处引用');
      expect(kBasicWorkGridPadding, const EdgeInsets.all(10));
    });
  });

  group('作品卡尺寸的 provider 只有一个入口（0.9.298）', () {
    test('播放页不再自己拼 kWorkImageWidth + workCardDecodeWidth', () {
      final src = _code('lib/main.dart');
      expect(src.contains('withImageWidth(img.cover, kWorkImageWidth)'), isFalse,
          reason: '预载/底图必须走 gridImageProvider');
      expect(src.contains('thumbImageProvider('), isFalse,
          reason: '播放页不再直接构造缩略图 provider');
      expect(RegExp(r'gridImageProvider\(').allMatches(src).length, 3,
          reason: '邻页预载 d==0、_posterPreview、_picPreview 回退支三处');
    });

    test('入口带 w=kWorkImageWidth 与作品卡解码宽度', () {
      final src = _code('lib/player_image.dart');
      expect(src.contains('ImageProvider gridImageProvider('), isTrue);
      expect(src.contains('withImageWidth(cover, kWorkImageWidth)'), isTrue);
      expect(src.contains('decodeWidth: workCardDecodeWidth(devicePixelRatio)'),
          isTrue);
      // 空封面不得拼出服务器根地址（与 PlayerImage.url 同一条守卫）。
      expect(src.contains("cover.isEmpty ? '' : withImageWidth"), isTrue);
    });
  });

  group('作品封面地址拼装只有一个入口（0.9.298）', () {
    test('standardCoverUrls 把 lib 绑到两个闭包上', () {
      final urls = standardCoverUrls(
        lib: 'lib-9',
        mediaUrlOf: (path, {lib}) => 'M:$lib:$path',
        urlOf: (path, {lib}) => Uri.parse('http://h/$lib/$path'),
      );
      final work = {'th': 'A/B/thumb.jpg'};
      expect(workCoverUrl(work, lib: 'lib-9', urls: urls), 'M:lib-9:A/B/thumb.jpg');
    });

    test('接口地址走 rawUrl，不套 /media/<lib>/', () {
      final urls = standardCoverUrls(
        lib: 'lib-9',
        mediaUrlOf: (path, {lib}) => 'M:$lib:$path',
        urlOf: (path, {lib}) => Uri.parse('http://h/$lib$path'),
      );
      final work = {'th': '/api/thumb/lib-9/123'};
      expect(workCoverUrl(work, lib: 'lib-9', urls: urls),
          'http://h/lib-9/api/thumb/lib-9/123');
    });

    test('lib/ 内只剩 standardCoverUrls 一处调用工厂', () {
      for (final f in Directory('lib').listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final src = _code(f.path);
        final hits = RegExp(r'WorkCoverUrls\.standard\(').allMatches(src).length;
        if (f.path.endsWith('work_cover.dart')) {
          // 工厂自身定义（1）+ standardCoverUrls 转一次（1）。
          expect(hits, lessThanOrEqualTo(2), reason: f.path);
        } else {
          expect(hits, 0, reason: '${f.path} 又自己拼了一遍作品封面地址');
        }
      }
    });
  });

  group('零引用死实现保持清零（0.9.298）', () {
    test('resolveFirstWorkCover 已删除', () {
      final lib = _code('lib/lib_cover.dart');
      expect(lib.contains('resolveFirstWorkCover'), isFalse);
      expect(lib.contains('CoverHit resolveBasicCover('), isTrue);
      expect(lib.contains('CoverHit resolveUnitCover('), isTrue);
    });
  });
}
