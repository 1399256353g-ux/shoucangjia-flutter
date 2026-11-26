/// 第七十一批契约（0.9.293）：**同一组三个参数，五处各拼一遍**。
///
/// 第七十批修的是「量出来的尺寸 vs 猜出来的数字」，收口了 `screenDecodeWidth`。
/// 但即使公式唯一了，**用它的地方**仍是五处各自展开：
///
/// | 位置 | 一行 |
/// |---|---|
/// | `_prefetchNeighborCovers` | `withImageWidth(cover, kPlayerImageWidth)` + `memW` |
/// | `_NeighborPage` 渲染 | 同三件套，另存三个 field |
/// | `_picPreview` | 同三件套（含回退到作品卡宽度的那一支） |
/// | 舞台海报 | 同三件套内联在 `CachedNetworkImage(` 里 |
/// | `_cropAndApplyCover` | 同三件套 |
///
/// 每一项单独看都对。但它们是同一个判定的五个副本：任何一处改了宽度来源、
/// 或忘了带鉴权头，缓存键就分叉，预载拉回来的图在真正渲染时「没命中」，
/// 再下一次再解码一次——**不报错、也没有第二份实现可对比**。
///
/// 另外 `_neighborPages` 的键此前是手拼字符串
/// `'$i|${it['id']}|$lib|$cover|$memW'`，读取侧又用 `indexOf('|')` +
/// `substring` 拆回索引：同一组数据的两种说法，封面路径里一旦出现 `|`
/// 就拆错索引，邻页缓存会命中到**别的作品**上。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/player_image.dart';
import 'package:shoucangjia/media_resize.dart' show kPlayerImageWidth;

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//');
    })
    .join('\n');

void main() {
  group('PlayerImage 是播放页大图的唯一出参（0.9.293）', () {
    test('地址带 w=kPlayerImageWidth，空封面产出空串', () {
      const img = PlayerImage(
        cover: '/media/lib/a/cover.jpg',
        lib: 'lib',
        headers: {'Authorization': 'Basic x'},
        decodeWidth: 1170,
      );
      expect(img.isEmpty, isFalse);
      expect(img.url, '/media/lib/a/cover.jpg?w=$kPlayerImageWidth');

      const empty = PlayerImage(
        cover: '',
        lib: 'lib',
        headers: {},
        decodeWidth: 1170,
      );
      expect(empty.isEmpty, isTrue);
      expect(empty.url, '', reason: '空封面不得拼出服务器根地址');
    });

    test('相等性只看 url/宽度/库：同图不同头算同一张', () {
      const a = PlayerImage(
        cover: '/media/lib/a/c.jpg',
        lib: 'lib',
        headers: {'Authorization': 'Basic x'},
        decodeWidth: 1080,
      );
      const b = PlayerImage(
        cover: '/media/lib/a/c.jpg',
        lib: 'lib',
        headers: {'Authorization': 'Basic y'},
        decodeWidth: 1080,
      );
      const c = PlayerImage(
        cover: '/media/lib/a/c.jpg',
        lib: 'lib',
        headers: {'Authorization': 'Basic x'},
        decodeWidth: 720,
      );
      expect(a, b, reason: '同一地址同一宽度同一库 → 同一个缓存键');
      expect(a == c, isFalse, reason: '宽度不同就是两个缓存键');
    });

    test('lib/main.dart 只剩一处产出 url+headers+decodeWidth 三元组', () {
      final main = _code('lib/main.dart');
      // 五处旧写法都必须归零。
      expect(main.contains('withImageWidth(cover, kPlayerImageWidth)'), isFalse,
          reason: '地址拼装只能在 player_image 内');
      // 播放页海报的地址不再内联拼装（头像候选格那一处是另一个语义，
      // 走 `kAvatarImageWidth`，不属于播放页大图）。
      final posterInline = RegExp(
              r'imageUrl: withImageWidth\(\s*posterCover')
          .allMatches(main)
          .length;
      expect(posterInline, 0);
      // `_playerImageFor` 与裁切预览各一次构造，此外不得再有。
      final ctor = RegExp(r'PlayerImage\(').allMatches(main).length;
      expect(ctor, 2,
          reason: '唯一出口 _playerImageFor + 裁切预览（非当前条）');
      // 舞台海报、邻页、图文底图都转发它的三项。
      expect(main.contains('posterImg.url'), isTrue);
      expect(main.contains('posterImg.headers'), isTrue);
      expect(main.contains('posterImg.decodeWidth'), isTrue);
      expect(main.contains('memCacheWidth: _posterDecodeWidth(context)'), isFalse,
          reason: '解码宽度不再内联到渲染点');
    });

    test('预载与邻页渲染共用同一个 provider 形状', () {
      final main = _code('lib/main.dart');
      final i = main.indexOf('void _prefetchNeighborCovers()');
      expect(i, greaterThan(0));
      final body = main.substring(i, i + 1600);
      expect(body.contains('img.provider('), isTrue);
      expect(body.contains('memW'), isFalse,
          reason: '局部变量 memW 已由 PlayerImage.decodeWidth 取代');
      expect(body.contains('cfg.headersFor(lib)'), isFalse,
          reason: '鉴权头随 PlayerImage 走，不在这里另取');
    });
  });

  group('邻页缓存的键是结构化对象（0.9.293）', () {
    test('键不再手拼字符串，也不再手拆索引', () {
      final main = _code('lib/main.dart');
      expect(main.contains("'\$i|\${it['id'] ?? ''}|\$lib|\$cover|\$memW'"), isFalse,
          reason: '手拼键已删');
      expect(main.contains('_neighborPages.keys.any((k) => k.index == i)'),
          isTrue,
          reason: '按结构化字段取索引');
      expect(
          RegExp(r"_neighborPages\.keys\.any\(\(k\) \{\s*final bar = k\.indexOf")
              .hasMatch(main),
          isFalse,
          reason: '不得再手拆字符串');
      expect(main.contains('Map<_NeighborKey, Widget> _neighborPages'), isTrue);
    });

    test('裁剪只按 index 判定，保留当前 ±2', () {
      final main = _code('lib/main.dart');
      expect(
          main.contains(
              '_neighborPages.removeWhere((k, _) => k.index < cur - 2 || k.index > cur + 2);'),
          isTrue);
    });
  });
}
