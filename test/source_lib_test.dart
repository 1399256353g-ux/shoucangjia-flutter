import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/source_lib.dart';

void main() {
  const base = '/vol1/1000/NAS1/Secret/(2) douyin';
  final libraries = {
    'basicLibraries': [
      {
        'id': 'lib-008',
        'name': '(1) 其他',
        'path': '$base/(1) 其他',
      },
      {
        'id': 'lib-016',
        'name': '(8) 🦶',
        'path': '$base/(8) 🦶',
      },
      {
        'id': 'lib-099',
        'name': '(1) 其他',
        'path': '/vol1/1000/NAS1/Secret/other/(1) 其他',
      },
      {
        'id': 'lib-100',
        'name': '(4) 南宁',
        'path': '$base/(4) 南宁/子目录',
      },
    ],
  };

  test('normalizeLibLabel 去掉编号前缀并折叠空白', () {
    expect(normalizeLibLabel('(8) 🦶'), '🦶');
    expect(normalizeLibLabel('( 14 )  擦边 '), '擦边');
    expect(normalizeLibLabel('无前缀'), '无前缀');
    expect(normalizeLibLabel(''), '');
  });

  test('decodeMediaRel 解码且去掉查询串', () {
    expect(
        decodeMediaRel('/media/(1)%20%E5%85%B6%E4%BB%96/@a/x.jpg?t=1'),
        '(1) 其他/@a/x.jpg');
    expect(decodeMediaRel('/media/%E5%A5%BD'), '好');
    // 非法编码不抛异常
    expect(decodeMediaRel('/media/%E5'), isA<String>());
  });

  test('basicsUnderBase 只保留注册库根下并排除同名的其他库', () {
    final list = basicsUnderBase(libraries, base);
    expect(list.map((e) => e.id), ['lib-008', 'lib-100', 'lib-016']);
    expect(list.first.rel, '(1) 其他');
    expect(list.any((e) => e.id == 'lib-099'), isFalse);
  });

  test('basicLibForMedia 使用最长前缀匹配基础库', () {
    final list = basicsUnderBase(libraries, base);
    final a = basicLibForMedia(
        list, '/media/(1)%20%E5%85%B6%E4%BB%96/@%E4%BD%9C%E8%80%85/_avatar/x.jpg');
    expect(a?.id, 'lib-008');
    final b = basicLibForMedia(
        list, '/media/(4)%20%E5%8D%97%E5%AE%81/%E5%AD%90%E7%9B%AE%E5%BD%95/@a/v.mp4');
    expect(b?.id, 'lib-100');
    expect(basicLibForMedia(list, '/media/unknown/@a/x.jpg'), isNull);
  });

  test('basicsUnderBase 保留服务端 fc', () {
    final libs = {
      'basicLibraries': [
        {
          'id': 'lib-029',
          'name': '(5) 强奸',
          'path': '$base/(5) 强奸',
          'fc': '/media/lib-029/%40%E8%BF%B7/VID/cover.jpg',
        },
      ],
    };
    final refs = basicsUnderBase(libs, base);
    expect(refs.single.firstCover, '/media/lib-029/%40%E8%BF%B7/VID/cover.jpg');
  });

  test('basicLibLabel 去掉编号并支持空名回落', () {
    final list = basicsUnderBase(libraries, base);
    final shoe = list.firstWhere((e) => e.id == 'lib-016');
    expect(basicLibLabel(shoe, 'douyin'), '🦶');
    expect(basicLibLabel(null, 'douyin'), 'douyin');
  });
}
