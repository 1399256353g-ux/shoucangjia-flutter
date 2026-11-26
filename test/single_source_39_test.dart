/// 第五十九批契约：**同一张表被抄成四份、同一条链被排成四处**。
///
/// 前几批抓的是「同一条规则两个实现」。这一批的三处都不是「写错了」，
/// 而是**同一件事有多个版本，各自都自洽**：
///
///  1. 媒体扩展名清单四份互不相等（`media_path.kVideoExts` 6 种、
///     `playback_error._kRedactExts` 视频 7 种、`cover_ext.kCoverImageExts`
///     7 种、`author_avatar.kAvatarImageExts` 7 种），服务端 `gen_lib_index.py`
///     只有三张表。服务端下发的 `.ts` 视频在客户端不算视频，`.avif` 封面
///     能显示却不能当封面。
///  2. `/media/<lib>/<rel>` 的「取第一段当库 id」写了三遍
///     （`libOfMediaPath` / `Cfg.media` / `authorPrefixOfMedia`），每遍自带
///     一个 `indexOf('/')` 和三行切片。
///  3. 封面优先级链（手动 > 自定义 `_cover/` > 爬虫 `cv` > 最高播放 > 首张）
///     在四处各排一遍，其中 `unitCoverUrl` 漏了爬虫一级——同一张单元库卡片
///     首页有封面、单元库页是灰的。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_avatar.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/media_path.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';
import 'package:shoucangjia/work_plays.dart';

String _code(String name) => File('lib/$name')
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

Iterable<File> _libFiles() sync* {
  for (final f in Directory('lib').listSync()) {
    if (f is File && f.path.endsWith('.dart')) yield f;
  }
}

BasicLib _basic(String id, String rel,
        {String serverBase = '',
        String crawlerCover = '',
        String firstCover = '',
        String coverVersion = ''}) =>
    BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 10,
      serverBase: serverBase,
      crawlerCover: crawlerCover,
      firstCover: firstCover,
      coverVersion: coverVersion,
    );

void main() {
  group('媒体类型只有一张分类表（与服务端三张表同源）', () {
    test('视频：服务端会下发的 .ts/.wmv/.3gp/.flv 也算视频', () {
      for (final p in <String>[
        '/a.mp4',
        '/a.MOV',
        '/a.m4v',
        '/a.mkv',
        '/a.webm',
        '/a.avi',
        // 服务端 VIDEO_EXT 有而客户端旧清单没有的四种：
        '/a.ts',
        '/a.wmv',
        '/a.3gp',
        '/a.flv',
        '/a.mp4?x=1#t=2',
      ]) {
        expect(mediaKindOf(p), MediaKind.video, reason: '$p 应判为视频');
        expect(isVideoMediaPath(p), isTrue, reason: '$p 应判为视频');
        expect(isMediaFilePath(p), isTrue);
      }
    });

    test('图片：heic / heif / avif 都是图片（旧四份表各有缺项）', () {
      for (final p in <String>[
        '/a.jpg',
        '/a.jpeg',
        '/a.png',
        '/a.webp',
        '/a.gif',
        '/a.bmp',
        '/a.heic',
        '/a.heif',
        '/a.avif',
        '/a.jpg?w=480',
        '/a.png#poster',
      ]) {
        expect(mediaKindOf(p), MediaKind.image, reason: '$p 应判为图片');
        expect(isCoverImagePath(p), isTrue, reason: '$p 可作封面');
        expect(isAvatarImagePath(p), isTrue, reason: '$p 可作头像');
        expect(isVideoMediaPath(p), isFalse);
      }
    });

    test('音频与非媒体文件', () {
      for (final p in <String>['/a.mp3', '/a.m4a', '/a.aac', '/a.wav', '/a.flac', '/a.ogg']) {
        expect(mediaKindOf(p), MediaKind.audio, reason: '$p 应判为音频');
        expect(isMediaFilePath(p), isTrue);
        expect(isCoverImagePath(p), isFalse);
      }
      for (final p in <String>['', '/a', '/简介.txt', '/a.json', '/dir/']) {
        expect(mediaKindOf(p), MediaKind.other, reason: '$p 不是媒体文件');
        expect(isMediaFilePath(p), isFalse);
      }
    });

    test('分类表只允许出现在 media_path（四份旧表不得复活）', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final name = f.path.split('/').last;
        if (name == 'media_path.dart') continue;
        final src = _code(name);
        // 旧四处各留一张成员表：任何一处再出现 4 个以上扩展名字面量就算复活。
        final hits = RegExp(r"'\.(mp4|mov|mkv|webm|avi|ts|jpg|jpeg|png|webp|gif|heic|avif)'")
            .allMatches(src)
            .length;
        if (hits >= 4) offenders.add(f.path);
      }
      expect(offenders, isEmpty, reason: '媒体扩展名清单又抄了一份：$offenders');
      final mp = _code('media_path.dart');
      for (final decl in <String>[
        'const List<String> kVideoExts',
        'const List<String> kImageExts',
        'const List<String> kAudioExts',
        'MediaKind mediaKindOf(String path)',
      ]) {
        expect(mp.contains(decl), isTrue, reason: '缺唯一出口：$decl');
      }
      // 各调用点必须是转发，不得自己再列循环。
      expect(_code('cover_ext.dart').contains('isImageMediaPath(p)'), isTrue);
      expect(_code('author_avatar.dart').contains('isImageMediaPath(path)'), isTrue);
      expect(_code('playback_error.dart').contains('isMediaFilePath(token)'),
          isTrue);
    });
  });

  group('`/media/<lib>/<rel>` 只拆一次', () {
    test('库段 + 其余，库段解码（中文库名与非法百分号）', () {
      expect(mediaLibSplitOrNull('/media/lib-008/a/b.jpg'),
          (lib: 'lib-008', rel: 'a/b.jpg'));
      expect(mediaLibSplitOrNull('/media/%E4%B8%AD/a.jpg'),
          (lib: '中', rel: 'a.jpg'));
      expect(mediaLibSplitOrNull(' /media/lib-001/x.png '),
          (lib: 'lib-001', rel: 'x.png'));
      // 只有库段、没有文件段
      expect(mediaLibSplitOrNull('/media/lib-008'),
          (lib: 'lib-008', rel: ''));
      // 非法百分号不抛，原样返回
      expect(mediaLibSplitOrNull('/media/100%成品/a.jpg')?.lib, '100%成品');
      // 不是媒体路径
      expect(mediaLibSplitOrNull('/api/thumb/a'), isNull);
      expect(mediaLibSplitOrNull('/media/'), isNull);
      expect(mediaLibSplitOrNull(''), isNull);
    });

    test('libOfMediaPath 与拆分同结论', () {
      expect(libOfMediaPath('/media/lib-008/a/b.jpg'), 'lib-008');
      expect(libOfMediaPath('/media/lib-008'), '', reason: '没有文件段不算有库段');
      expect(libOfMediaPath('/media/%E4%B8%AD/a.jpg'), '中');
    });

    test('契约：取第一段的写法只有 media_path 一处', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final name = f.path.split('/').last;
        if (name == 'media_path.dart') continue;
        final src = _code(name);
        if (src.contains('mediaRelOrNull(') && src.contains("indexOf('/')")) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '又在自己切 /media/ 尾部取库段：$offenders');
      expect(_code('lib_cover.dart').contains('mediaLibSplitOrNull('), isTrue);
      expect(_code('main.dart').contains('mediaLibSplitOrNull('), isTrue);
    });
  });

  group('封面优先级链只有一张表', () {
    test('五级顺序与命中来源', () {
      expect(kCoverSourceOrder,
          [CoverSource.manual, CoverSource.custom, CoverSource.crawler, CoverSource.best, CoverSource.first]);

      // 全给：手动赢
      var hit = resolveCover(
        manualUrl: '/media/l1/m.jpg',
        rel: 'r',
        version: 'v1',
        crawlerThumb: '/media/l1/cv.jpg',
        bestThumb: '/media/l1/best.jpg',
        firstThumb: '/media/l1/fc.jpg',
      );
      expect(hit.source, CoverSource.manual);
      expect(hit.path, '/media/l1/m.jpg');

      // 去掉手动：自定义 _cover 赢
      hit = resolveCover(
        rel: 'r',
        version: 'v1',
        crawlerThumb: '/media/l1/cv.jpg',
        bestThumb: '/media/l1/best.jpg',
        firstThumb: '/media/l1/fc.jpg',
      );
      expect(hit.source, CoverSource.custom);
      expect(hit.path, 'r/_cover/v1.jpg');

      // 去掉自定义：爬虫赢（旧 unitCoverUrl 缺这一级）
      hit = resolveCover(
        rel: 'r',
        crawlerThumb: '/media/l1/cv.jpg',
        bestThumb: '/media/l1/best.jpg',
        firstThumb: '/media/l1/fc.jpg',
      );
      expect(hit.source, CoverSource.crawler);
      expect(hit.path, '/media/l1/cv.jpg');

      // 只剩最高播放与首张：最高播放赢
      hit = resolveCover(
        bestThumb: '/media/l1/best.jpg',
        firstThumb: '/media/l1/fc.jpg',
      );
      expect(hit.source, CoverSource.best);

      // 只有首张
      hit = resolveCover(firstThumb: '/media/l1/fc.jpg');
      expect(hit.source, CoverSource.first);

      // 都没有
      expect(resolveCover().path, '');
    });

    test('视频路径不进封面链（渲染不出来只会转圈）', () {
      final hit = resolveCover(
        crawlerThumb: '/media/l1/cv.mp4',
        bestThumb: '/media/l1/best.mp4',
        firstThumb: '/media/l1/a.jpg',
      );
      expect(hit.source, CoverSource.first);
      expect(hit.path, '/media/l1/a.jpg');
    });

    test('ignoreManual / ignoreCustom 关掉对应层级后继续向下取', () {
      final hit = resolveCover(
        manualUrl: '/media/l1/m.jpg',
        rel: 'r',
        version: 'v1',
        firstThumb: '/media/l1/fc.jpg',
        ignoreManual: true,
        ignoreCustom: true,
      );
      expect(hit.source, CoverSource.first);
    });

    test('单元库封面包含爬虫一级（首页与单元库页同一结论）', () {
      WorkPlaysStore.resetForTest(items: const {});
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
        ],
        basics: [
          _basic('l1', '(1) A/x',
              serverBase: 'http://nas:8090',
              crawlerCover: '/media/l1/x/cover.jpg'),
        ],
      )!;
      expect(unitCoverUrl(tree.children.first),
          'http://nas:8090/media/l1/x/cover.jpg',
          reason: '单元库页的封面解析必须和首页一样认爬虫封面');
      WorkPlaysStore.resetForTest(items: const {});
    });

    test('契约：优先级链只在 lib_cover 定义', () {
      final decl =
          RegExp(r'kCoverSourceOrder').allMatches(_code('lib_cover.dart')).length;
      expect(decl, greaterThanOrEqualTo(2), reason: '声明与使用都应在 lib_cover');
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final name = f.path.split('/').last;
        if (name == 'lib_cover.dart') continue;
        final src = _code(name);
        // 手写「自定义 → 爬虫 → 最高播放 → 首张」的顺序，特征是同时提到
        // crawlerCover 与 firstCover 并各拼一次 pick*Cover。
        if (src.contains('crawlerCover') &&
            src.contains('firstCover') &&
            src.contains('pickBasicCover(')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty, reason: '封面链又被排了一遍：$offenders');
      expect(_code('unit_library_view.dart').contains('resolveCover('), isTrue);
      expect(_code('main.dart').contains('resolveCover('), isTrue);
    });
  });
}
