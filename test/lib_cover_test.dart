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
      expect(coverPointerRel('(1) A/x'), '(1) A/x/_cover/current');
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

  group('封面选择', () {
    test('自定义版本优先于作品封面', () {
      final p = pickBasicCover(
        rel: '(1) A/x',
        version: 'v9',
        ext: 'png',
        bestThumb: '/media/lib/th.jpg',
      );
      expect(p.custom, isTrue);
      expect(p.path, '(1) A/x/_cover/v9.png');
    });

    test('无自定义时用播放量最高作品的缩略图', () {
      final p = pickBasicCover(rel: '(1) A/x', bestThumb: '/media/lib/th.jpg');
      expect(p.custom, isFalse);
      expect(p.path, '/media/lib/th.jpg');
    });

    test('都没有时为空（显示默认图）', () {
      expect(pickBasicCover(rel: '(1) A/x').isEmpty, isTrue);
    });

    test('单元库只用自定义封面', () {
      expect(pickUnitCover(rel: '(1) A').isEmpty, isTrue);
      final p = pickUnitCover(rel: '(1) A', version: 'v1');
      expect(p.path, '(1) A/_cover/v1.jpg');
      expect(p.custom, isTrue);
    });
  });
}
