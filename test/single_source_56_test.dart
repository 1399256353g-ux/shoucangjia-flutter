/// 第七十九批契约（0.9.313）：**作者页按挂载的作者文件夹筛选**。
///
/// owner 2026-11-27：「作者页可按挂载的作者文件夹筛选显示」。
///
/// 合并后的作者把多个 `@作者` 目录的作品并成一列，但「这条来自哪个目录」
/// 界面上没有出口——只能靠来源库粗筛，同一个库里挂了两处目录时仍分不开。
///
/// 这一批只做「取目录 / 按目录筛」的纯逻辑 + 页面接线，判据全部可单测。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_dir_filter.dart';

/// 去掉整行注释后再做「有没有第二个来源」的扫描。
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

Map<String, dynamic> _work(String lib, String path, {String id = 'w'}) => {
      'id': id,
      '_lib': lib,
      't': 'p',
      'm': [path],
    };

void main() {
  group('作者目录段：只认 `@` 开头的路径段', () {
    test('普通媒体路径取到作者目录', () {
      expect(
          authorDirOfWork(_work('lib-a', '/media/lib-a/A/@小林/1.jpg')), '@小林');
      // 反斜杠路径同样归一（relSegments 唯一实现）。
      expect(
          authorDirOfWork(_work('lib-a', r'/media/lib-a/A/@小林/1.jpg')), '@小林');
      // 单图作品的 `m` 是字符串也要认（workMediaPaths 归一）。
      expect(
          authorDirOfWork({'id': 'x', 't': 'p', 'm': '/media/lib-a/@阿花/2.jpg'}),
          '@阿花');
    });

    test('没有 @ 段 / 坏数据返回空串，不抛', () {
      expect(authorDirOfWork(_work('lib-a', '/media/lib-a/A/B/1.jpg')), '');
      expect(authorDirOfWork(_work('lib-a', '')), '');
      expect(authorDirOfWork(const <String, dynamic>{}), '');
      expect(authorDirOfWork(null), '');
      expect(authorDirOfWork('不是作品'), '');
    });

    test('取第一个 @ 段（嵌套目录也只认最外层作者目录）', () {
      expect(authorDirOfWork(_work('l', '/media/l/@作者/子/@二层/1.jpg')), '@作者');
    });
  });

  group('按库 + 目录筛选作品', () {
    final works = [
      _work('lib-a', '/media/lib-a/A/@小林/1.jpg', id: 'a1'),
      _work('lib-a', '/media/lib-a/B/@小林/2.jpg', id: 'a2'),
      _work('lib-b', '/media/lib-b/@小林/3.jpg', id: 'b1'),
      _work('lib-a', '/media/lib-a/A/@阿花/4.jpg', id: 'a3'),
      {'id': 'no-media', 't': 'v'},
    ];

    test('两个条件同时生效', () {
      final only = filterWorksByAuthorDir(works,
          lib: 'lib-a', authorDir: '@小林', fallbackLib: 'lib-a');
      expect(only.map((e) => e['id']), ['a1', 'a2']);
    });

    test('只给目录时跨库命中（同名目录在两库里都算）', () {
      final only = filterWorksByAuthorDir(works, authorDir: '@小林');
      expect(only.map((e) => e['id']), ['a1', 'a2', 'b1']);
    });

    test('只给库时退化为来源库筛选（目录不限）', () {
      final only = filterWorksByAuthorDir(works, lib: 'lib-a');
      expect(only.map((e) => e['id']), ['a1', 'a2', 'a3']);
    });

    test('都为空时原样返回（复制，不改入参）', () {
      final all = filterWorksByAuthorDir(works);
      expect(all.length, works.length);
      expect(identical(all, works), isFalse);
    });

    test('空目录不当「匹配所有目录」', () {
      // 目录为空串 = 不过滤；但目录非空而作品不在任何 @ 目录下必须被排掉。
      final only = filterWorksByAuthorDir(works,
          lib: 'lib-a', authorDir: '@不存在', fallbackLib: 'lib-a');
      expect(only, isEmpty);
    });

    test('坏条目（非 Map / 无媒体）不会被抛异常', () {
      expect(
          () => filterWorksByAuthorDir(<dynamic>[
                null,
                3,
                'x',
                {'id': 'y'},
                _work('l', '/m/l/@a/1.jpg')
              ], authorDir: '@a'),
          returnsNormally);
    });
  });

  group('筛选项：由作品反推（只收有作品的目录）', () {
    test('按首次出现顺序，计数正确，带库信息', () {
      final opts = authorDirOptionsOfWorks([
        _work('lib-a', '/media/lib-a/A/@小林/1.jpg'),
        _work('lib-b', '/media/lib-b/@阿花/2.jpg'),
        _work('lib-a', '/media/lib-a/B/@小林/3.jpg'),
      ]);
      expect(opts.length, 2);
      expect(opts[0].option.lib, 'lib-a');
      expect(opts[0].option.authorDir, '@小林');
      expect(opts[0].count, 2);
      expect(opts[1].option.lib, 'lib-b');
      expect(opts[1].option.authorDir, '@阿花');
      expect(opts[1].count, 1);
    });

    test('同一目录在两个库里是两个选项（跨库不能混成一个）', () {
      final opts = authorDirOptionsOfWorks([
        _work('lib-a', '/media/lib-a/@小林/1.jpg'),
        _work('lib-b', '/media/lib-b/@小林/2.jpg'),
      ]);
      expect(opts.length, 2);
      expect({for (final o in opts) o.option.key}.length, 2);
    });

    test('没有 @ 目录时返回空（页面据此不显示整行）', () {
      expect(
          authorDirOptionsOfWorks([
            _work('l', '/media/l/A/B/1.jpg'),
          ]),
          isEmpty);
    });

    test('挂载项去重：同一 (库,目录) 只留一条，空目录排掉', () {
      final opts = authorDirOptions(const [
        (lib: 'l1', authorDir: '@a'),
        (lib: 'l1', authorDir: '@a'),
        (lib: 'l1', authorDir: '  '),
        (lib: 'l2', authorDir: '@a'),
      ]);
      expect(opts.length, 2);
    });

    test('authorDirCounts 只保留命中 ≥1 条的选项', () {
      final opts = authorDirOptions(const [
        (lib: 'l1', authorDir: '@a'),
        (lib: 'l1', authorDir: '@空'),
      ]);
      final counted = authorDirCounts(
        [_work('l1', '/media/l1/@a/1.jpg')],
        opts,
      );
      expect(counted.length, 1);
      expect(counted.first.option.authorDir, '@a');
      expect(counted.first.count, 1);
    });
  });

  group('页面接线：作者页只在这里算一次、不重复实现目录名规则', () {
    test('作者页用 author_dir_filter，不再自己 split 找 @ 段', () {
      final src = _code('lib/main.dart');
      expect(src.contains("import 'author_dir_filter.dart';"), isTrue);
      expect(src.contains('authorDirOptionsOfWorks(works'), isTrue,
          reason: '筛选项必须由编辑器外的纯逻辑给出');
      expect(src.contains('filterWorksByAuthorDir('), isTrue);
      // 页面不得再自己写「左右切 '@'」的第二次实现。
      expect(src.contains('authorDirOfWork('), isFalse,
          reason: '取目录段的实现只允许在 author_dir_filter 里');
      // 筛选项要缓存，不能在 build 里每帧重扫全部作品的媒体路径。
      expect(src.contains('_dirChoices'), isTrue);
    });

    test('筛选项为空串时清库选择（两个选中词条不得互相矛盾）', () {
      final src = _code('lib/main.dart');
      final body = src.substring(src.indexOf('void _setDirFilter('),
          src.indexOf('void _setDirFilter(') + 400);
      expect(body.contains('libFilter = \'\''), isTrue);
      expect(body.contains('_refreshFilter()'), isTrue);
    });

    test('单库时不带库名前缀（避免两条同名词条）', () {
      final src = _code('lib/main.dart');
      expect(src.contains('bool get _dirsSpanLibs'), isTrue);
      expect(src.contains('showLib: _dirsSpanLibs'), isTrue);
    });

    test('切换/刷新作者页时目录筛选归零（旧目录可能已不存在）', () {
      final src = _code('lib/main.dart');
      // 作者页 load() 的筛选归零段：以「libFilter/topFilter 归零」为锚点。
      final at = src.indexOf("    libFilter = '';\n    topFilter = '';");
      expect(at, isNonNegative, reason: '找不到作者页 load() 的筛选归零处');
      expect(src.substring(at, at + 300).contains("dirFilter = '';"), isTrue);
    });
  });
}
