import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/lib_cover.dart';

void main() {
  group('版本号合法化', () {
    test('正常版本号保留', () {
      expect(normalizeCoverVersion('v1'), 'v1');
      expect(normalizeCoverVersion(' 20261115T101500_01 '), '20261115T101500_01');
    });

    test('带目录与扩展名的写法被拆开', () {
      expect(normalizeCoverVersion('_cover/v2.jpg'), 'v2');
      expect(normalizeCoverVersion(r'_cover\v3.png'), 'v3');
    });

    test('非法版本号返回空串', () {
      expect(normalizeCoverVersion(''), '');
      expect(normalizeCoverVersion('..'), '');
      expect(normalizeCoverVersion('../etc/passwd'), '');
      expect(normalizeCoverVersion('a b'), '');
      expect(normalizeCoverVersion('中文'), '');
    });

    test('超长版本号截断到 40 字符', () {
      final long = 'a' * 80;
      expect(normalizeCoverVersion(long).length, 40);
    });
  });

  test('扩展名白名单', () {
    expect(normalizeCoverExt('PNG'), 'png');
    expect(normalizeCoverExt('.webp'), 'webp');
    expect(normalizeCoverExt('gif'), 'jpg');
    expect(normalizeCoverExt(''), 'jpg');
  });

  group('路径拼接', () {
    test('_cover 目录与指针文件', () {
      expect(coverDirRel('(1) A/x'), '(1) A/x/_cover');
      expect(coverDirRel(''), '_cover');
    });

    test('版本图路径', () {
      expect(coverImageRel('(1) A/x', 'v2'), '(1) A/x/_cover/v2.jpg');
      expect(coverImageRel('(1) A/x', 'v2', ext: 'png'),
          '(1) A/x/_cover/v2.png');
      expect(coverImageRel('(1) A/x', ''), '');
      expect(coverImageRel('(1) A/x', '../x'), '');
    });
  });

  group('封面指针解析', () {
    test('字符串写法', () {
      final p = coverPointerOf('v3');
      expect(p.version, 'v3');
      expect(p.ext, 'jpg');
    });

    test('字符串带扩展名', () {
      final p = coverPointerOf('v3.png');
      expect(p.version, 'v3');
      expect(p.ext, 'png');
    });

    test('对象写法', () {
      final p = coverPointerOf({'v': 'v4', 'e': 'webp'});
      expect(p.version, 'v4');
      expect(p.ext, 'webp');
    });

    test('缺失 / 非法写法', () {
      expect(coverPointerOf(null).version, '');
      expect(coverPointerOf('').version, '');
      expect(coverPointerOf('..').version, '');
    });
  });

  group('封面选择：基础库落在库根，单元库落在节点目录', () {
    test('基础库自定义封面在库根（不拼 rel）', () {
      final h = resolveBasicCover(
        version: 'v9',
        ext: 'png',
        bestThumb: '/media/lib/th.jpg',
      );
      expect(h.source, CoverSource.custom);
      expect(h.path, '_cover/v9.png');
      expect(CoverPick.of(h).custom, isTrue);
    });

    test('无自定义时用播放量最高作品的缩略图', () {
      final h = resolveBasicCover(bestThumb: '/media/lib/th.jpg');
      expect(CoverPick.of(h).custom, isFalse);
      expect(h.path, '/media/lib/th.jpg');
    });

    test('都没有时为空（显示默认图）', () {
      expect(CoverPick.of(resolveBasicCover()).isEmpty, isTrue);
      expect(resolveUnitCover(unitRel: '(1) A').path, '');
    });

    test('单元库：自定义封面在节点目录', () {
      final h = resolveUnitCover(unitRel: '(1) A', version: 'v1');
      expect(h.path, '(1) A/_cover/v1.jpg');
      expect(CoverPick.of(h).custom, isTrue);
    });

    test('单元库：无自定义时用子树内播放量最高的作品封面', () {
      final h = resolveUnitCover(
          unitRel: '(1) A', bestThumb: '/media/lib-01/a/th.jpg');
      expect(CoverPick.of(h).custom, isFalse);
      expect(h.path, '/media/lib-01/a/th.jpg');
    });

    test('爬虫封面优先于自动生成的最高播放缩略图', () {
      final b = resolveBasicCover(
        crawlerThumb: '/media/lib-01/x/cover.jpg',
        bestThumb: '/media/lib-01/x/thumb.jpg',
      );
      expect(b.path, '/media/lib-01/x/cover.jpg');
      expect(CoverPick.of(b).custom, isFalse);
      final u = resolveUnitCover(
        unitRel: '(1) A',
        crawlerThumb: '/media/lib-01/x/cover.jpg',
        bestThumb: '/media/lib-01/x/thumb.jpg',
      );
      expect(u.path, '/media/lib-01/x/cover.jpg');
    });

    test('手动封面仍优先于爬虫封面', () {
      final h = resolveBasicCover(
        version: 'v2',
        crawlerThumb: '/media/lib-01/x/cover.jpg',
      );
      expect(CoverPick.of(h).custom, isTrue);
      expect(h.path, '_cover/v2.jpg');
    });

    test('封面目录作用域只有一处判定', () {
      expect(coverScopeRel(CoverScopeDir.basic), kLibRootCoverRel);
      expect(coverScopeRel(CoverScopeDir.basic, unitRel: 'A/B'), '');
      expect(coverScopeRel(CoverScopeDir.unit, unitRel: 'A/B'), 'A/B');
      expect(coverScopeRel(CoverScopeDir.unit), '');
      expect(coverScopeRel(CoverScopeDir.unit, unitRel: '/'), '');
      expect(coverScopeRel(CoverScopeDir.unit, unitRel: r'A\B'), 'A/B');
      // 节点目录 + `_cover` 才是封面目录：传给 resolveCover 的是前者。
      expect(coverDirRel('A/B'), 'A/B/_cover');
    });
  });

  group('媒体地址', () {
    test('媒体路径已带 /media/ 时原样返回', () {
      expect(libraryMediaPath('lib-01', '/media/lib-01/a.jpg'),
          '/media/lib-01/a.jpg');
      expect(libraryMediaPath('lib-01', '/a/b.jpg'), '/media/lib-01/a/b.jpg');
      expect(libraryMediaPath('', '/a/b.jpg'), '/media/a/b.jpg');
      expect(libraryMediaPath('lib-01', ''), '');
      // 绝对地址是自描述的（爬虫封面可能是外链），不得再补 /media/<lib>/
      // ——否则拼出 `…/media/lib-01/http://cdn/x.jpg`，服务端必然 404。
      expect(libraryMediaPath('lib-01', 'http://cdn.example.com/a.jpg'),
          'http://cdn.example.com/a.jpg');
      expect(libraryMediaPath('lib-01', 'https://cdn.example.com/a.jpg?w=2'),
          'https://cdn.example.com/a.jpg?w=2');
    });

    test('绝对地址拼接（去掉 base 尾部斜杠）', () {
      expect(
          absoluteMediaUrl('http://nas:8090/',
              lib: 'lib-01', path: '/media/lib-01/a.jpg'),
          'http://nas:8090/media/lib-01/a.jpg');
      expect(
          absoluteMediaUrl('http://nas:8090',
              lib: 'lib-01', path: 'a.jpg'),
          'http://nas:8090/media/lib-01/a.jpg');
      expect(absoluteMediaUrl('', lib: 'lib-01', path: 'a.jpg'), '');
      expect(absoluteMediaUrl('http://nas:8090', lib: 'lib-01', path: ''), '');
    });
  });
}
