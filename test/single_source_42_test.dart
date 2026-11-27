/// 第六十二批契约：**同一条记录被建模两份，其中一份装不下全字段**。
///
/// 前几批抓的是「同一段代码抄多份」。这一批的形态更隐蔽：字段有名字、
/// 解析也有，但**同一份服务端记录有两个模型**——
///
/// ```
/// library_tree.BasicLib    9 字段：id/name/rel/bigId/authors/works/
///                          coverVersion/coverExt/crawlerCover/firstCover/…
/// source_lib.BasicLibRef  7 字段：上面**少了 coverVersion/coverExt/crawlerCover**
/// ```
///
/// 两者之间只有 `basicLibFromRef` 一个转换点。于是单元库树
/// （`basicsUnderBase` → `basicLibFromRef`）里每个基础库都丢掉了自定义封面
/// 指针与爬虫封面，而首页（`LibraryTree.parse`，全字段）留着——同一个基础库
/// 在两个页面取到不同的封面，两处「各自都算对了」。
///
/// 修法：模型与解析各只留一份（`basic_lib.BasicLib` /
/// `basic_lib.basicLibFromJson`），`basicsUnderBase` 与 `LibraryTree.parse`
/// 都转发它，转换点消失。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/media_path.dart';
import 'package:shoucangjia/source_lib.dart';

String _src(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

Map<String, dynamic> _raw({
  Map<String, dynamic> cover = const {'v': 'v1', 'e': 'png'},
  String cv = '/media/lib-1/A/cv.jpg',
  String fc = '/media/lib-1/A/fc.jpg',
}) =>
    <String, dynamic>{
      'id': 'lib-1',
      'name': 'A',
      'rel': 'A',
      'path': '/root/A',
      'big_id': 'big-1',
      'authors': 3,
      'works': 8,
      'cover': cover,
      'cv': cv,
      'fc': fc,
    };

void main() {
  group('基础库只有一个模型（0.9.284）', () {
    test('模型只有一处定义：BasicLib 在 basic_lib.dart', () {
      final dir = Directory('lib');
      final definitions = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = _src(f.path);
        if (RegExp(r'^class BasicLib\b', multiLine: true).hasMatch(s) ||
            RegExp(r'^class BasicLibRef\b', multiLine: true).hasMatch(s)) {
          definitions.add(f.path);
        }
      }
      expect(definitions, hasLength(1),
          reason: '同一份服务端记录不允许有两个模型：${definitions.join(', ')}');
      expect(definitions.single, endsWith('basic_lib.dart'));
    });

    test('解析只有一个入口：basicLibFromJson', () {
      final dir = Directory('lib');
      final callers = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('basic_lib.dart')) continue;
        final s = _src(f.path);
        // 「第二份解析」的判据：自己 `BasicLib(...)` 并传封面字段。
        // （`coverPointerOf` 本身是 `lib_cover` 的公共函数，被调用不算
        // 第二份解析——只有「自己造对象、自己读 raw 字段」才算。）
        final ctor = RegExp(
            r'BasicLib\([\s\S]*?\b(coverVersion|crawlerCover)\s*:',
            multiLine: true);
        if (ctor.hasMatch(s)) callers.add(f.path);
      }
      expect(callers, isEmpty,
          reason: '封面指针与 cv 的读取只允许在 basic_lib.dart：${callers.join(', ')}');
    });

    test('basicsUnderBase 不再需要转换点（返回值就是 BasicLib）', () {
      final libs = basicsUnderBase(<String, dynamic>{
        'basicLibraries': <dynamic>[_raw()],
      }, '/root');
      expect(libs.single.coverVersion, 'v1');
      expect(libs.single.coverExt, 'png');
      expect(libs.single.crawlerCover, '/media/lib-1/A/cv.jpg');
      expect(libs.single.firstCover, '/media/lib-1/A/fc.jpg');
      expect(libs.single.authors, 3, reason: '统计字段不再由调用方补 0');
      expect(libs.single.works, 8);
      expect(libs.single.rel, 'A');
    });

    test('单元库树与首页对同一条记录给出完全相同的字段', () {
      final tree = LibraryTree.parse(<String, dynamic>{
        'bigLibraries': <dynamic>[
          <String, dynamic>{'id': 'big-1', 'name': 'A', 'path': '/root/A'},
        ],
        'basicLibraries': <dynamic>[_raw()],
      })!;
      final fromTree = tree.allBasics.single;
      final fromRef = basicsUnderBase(<String, dynamic>{
        'basicLibraries': <dynamic>[_raw()],
      }, '/root').single;
      expect(fromTree.coverVersion, fromRef.coverVersion);
      expect(fromTree.coverExt, fromRef.coverExt);
      expect(fromTree.crawlerCover, fromRef.crawlerCover);
      expect(fromTree.firstCover, fromRef.firstCover);
      expect(fromTree.authors, fromRef.authors);
      expect(fromTree.works, fromRef.works);
      expect(fromTree.path, fromRef.path);
    });

    test('封面指针缺省时两侧都退化成「没有自定义封面」，不伪造 jpg', () {
      final raw = _raw(cover: const <String, dynamic>{}, cv: '', fc: '');
      final a = LibraryTree.parse(<String, dynamic>{
        'bigLibraries': <dynamic>[
          <String, dynamic>{'id': 'big-1', 'name': 'A', 'path': '/root/A'},
        ],
        'basicLibraries': <dynamic>[raw],
      })!
          .allBasics
          .single;
      final b = basicsUnderBase(<String, dynamic>{
        'basicLibraries': <dynamic>[raw],
      }, '/root').single;
      expect(a.coverVersion, isEmpty);
      expect(b.coverVersion, isEmpty);
      expect(a.crawlerCover, isEmpty);
      expect(b.crawlerCover, isEmpty);
    });

    test('非法封面扩展名两侧都回落到 jpg（同一套归一）', () {
      final raw = _raw(cover: const <String, dynamic>{'v': 'v2', 'e': 'gif'});
      final libs = basicsUnderBase(<String, dynamic>{
        'basicLibraries': <dynamic>[raw],
      }, '/root');
      expect(libs.single.coverVersion, 'v2');
      expect(libs.single.coverExt, 'jpg');
    });

    test('契约：旧符号 basicLibFromRef 不得复活', () {
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (_src(f.path).contains('basicLibFromRef')) offenders.add(f.path);
      }
      expect(offenders, isEmpty);
    });

    test('`/media/<lib>/` 前缀只有一处拼装（库段编码也在那里）', () {
      expect(libMediaPrefix('lib-1', 'a/b.jpg'), '/media/lib-1/a/b.jpg');
      expect(libMediaPrefix('lib-1', '/a/b.jpg'), '/media/lib-1/a/b.jpg',
          reason: '前导斜杠必须吃掉，否则拼出 /media/lib-1//a');
      expect(libMediaPrefix('', 'a/b.jpg'), '/media/a/b.jpg');
      expect(libMediaPrefix('lib-1', '  '), '/media/lib-1/');
      // 中文/空格库名走同一次编码：两侧不可能出现 %25E4 这种二次编码。
      expect(libMediaPrefix('中文 库', 'a.jpg'),
          '/media/${Uri.encodeComponent('中文 库')}/a.jpg');
      // 卡片侧（lib_cover）与作品侧（Cfg.media）都转发到它。
      expect(libraryMediaPath('lib-1', 'a/b.jpg'),
          libMediaPrefix('lib-1', 'a/b.jpg'));
      expect(libraryMediaPath('lib-1', '/media/lib-9/a.jpg'),
          '/media/lib-9/a.jpg', reason: '已带库段不再套一层');
    });

    test('契约：`/media/<lib>/` 的拼装只剩 media_path 一处', () {
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('media_path.dart')) continue;
        final s = _src(f.path);
        if (s.contains(r"'/media/${Uri.encodeComponent")) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: '库段编码的第二份拷贝：${offenders.join(', ')}');
    });

    test('契约：五个 intOf 私有转发别名全部消失', () {
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final s = _src(f.path);
        if (RegExp(r'\bint _\w+\s*\(dynamic \w+(\s*,\s*\[?int \w+[^\]]*\]?)?\)\s*=>\s*intOf\(')
            .hasMatch(s)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '私有别名只是噪音，且让「一次转换」变成 N 次：${offenders.join(', ')}');
    });
  });
}
