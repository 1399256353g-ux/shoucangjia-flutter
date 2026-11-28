/// 第七十八批契约（0.9.312）：
///  1. **挂载候选只剩「基础库」这一层**——owner 2026-11-28 两次要求把
///     「按文件夹勾选」整套删掉（「原来的那些设置逻辑特别混乱啊根本没法用，
///     删掉啊还留着干嘛」）。先是挂载设置页（0.9.372），再是作者页挂载面板
///     （0.9.374）；两处都不再有目录树，于是 `author_file_picker.dart` 与
///     `unit_author_groups` 里只为它服务的三个函数（`authorFileBranches` /
///     `authorGroupFilesFromItems` / `mergeableFiles` / `unitAuthorsAllUrl`）
///     一并删除，本文件的这一组改成「钉住它们不复活」。
///  2. **删除监测必须走该单元库自己的连接**——此前 `_openDeletedWork` /
///     `_retryDeleted` / `_loadAuthorIdx` / `_loadMeta` 用的是全局 `cfg.base`
///     与 `cfg.lib`。从另一个服务端的单元库进来时，请求打到了默认注册库那台
///     机器：作品明明在本地也只会得到 404（提示「未同步到本地」），
///     「当前媒体库」词条整排消失。
///  3. **零调用点的死实现**——`BadgeChipWrap`（不可折叠那一份）在 lib/ 里
///     零调用点，只有一条旧断言在认它。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/unit_author_groups.dart';

String _code(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('挂载候选只剩基础库这一层（目录树那套已整体删除）', () {
    test('按目录勾选的控件与它专用的解析函数都不得复活', () {
      // owner 2026-11-28：
      // > 「挂载还是不行，原来的那些设置逻辑特别混乱啊根本没法用，删掉啊还留着干嘛」
      //
      // 0.9.372 删的是挂载设置页的目录树，0.9.374 删的是作者页挂载面板的
      // 目录树；两个入口都不再有「按文件夹勾选」，`AuthorFilePicker` 从此
      // 零调用点。零调用的控件留着只会让下一个人以为还有人在用它。
      expect(File('lib/author_file_picker.dart').existsSync(), isFalse,
          reason: '按目录勾选的控件已无调用点，不得复活');

      final groups = _code('lib/unit_author_groups.dart');
      for (final gone in const [
        'authorFileBranches',
        'authorGroupFilesFromItems',
        'mergeableFiles',
        'unitAuthorsAllUrl',
      ]) {
        expect(groups.contains(gone), isFalse,
            reason: '为目录树服务的 $gone 已无调用点，必须一起删掉');
      }

      // 两个挂载入口都不许再引用它。
      for (final f in const [
        'lib/unit_author_mount_page.dart',
        'lib/author_mount_sheet.dart',
      ]) {
        expect(_code(f).contains('AuthorFilePicker'), isFalse,
            reason: '$f 又用回目录树了');
      }
    });

    test('两个入口的候选都来自「直属单元库的基础库」', () {
      final page = _code('lib/unit_author_mount_page.dart');
      expect(page.contains('basicsOfUnitScope('), isTrue,
          reason: '范围必须来自所属单元库的基础库，不跨库');
      expect(page.contains('createAuthorBodies('), isTrue,
          reason: '勾选的基础库要能翻译成建目录请求');
      // 新结构：按基础库勾选 + 按基础库拆出。
      expect(page.contains("'uag-scope-"), isTrue);
      expect(page.contains('uag-split-lib-'), isTrue);

      final sheet = _code('lib/author_mount_sheet.dart');
      expect(sheet.contains('ams-split-lib-'), isTrue,
          reason: '作者页拆出也必须按基础库勾选');
    });
  });

  group('删除监测走单元库自己的连接（0.9.312）', () {
    test('四个读/写点不再直接用全局 cfg.base / cfg.lib', () {
      final main = _code('lib/main.dart');
      final start = main.indexOf('class DeletedMonitorPage');
      // 到下一个类为止（`UnitCrawlerPage` 在另一个文件里）。
      final end = main.indexOf('class _StripIndexTile');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final body = main.substring(start, end);
      expect(body.contains('deletedWorkUri(cfg.base'), isFalse,
          reason: '打开作品必须用该记录所属连接');
      expect(body.contains('syncRetryUri(cfg.base'), isFalse,
          reason: '重试必须用该记录所属连接');
      expect(body.contains('LibMeta.load(cfg.lib)'), isFalse,
          reason: '元数据必须按单元库自己的基础库读');
      expect(body.contains("cfg.u('/api/authors.json')"), isFalse,
          reason: '作者索引必须用作用域内的连接');
      // 走作用域的两个出口。
      expect(body.contains('Map<String, String> _headersFor(String libId)'), isTrue);
      expect(body.contains('String get _metaLib'), isTrue);
      expect(body.contains('deletedWorkUri(_base, e)'), isTrue);
      expect(body.contains('syncRetryUri(_base)'), isTrue);
    });

    test('有作用域时鉴权头固定用该连接（不按库路由）', () {
      final main = _code('lib/main.dart');
      final i = main.indexOf('Map<String, String> _headersFor(String libId)');
      final body = main.substring(i, i + 420);
      expect(body.contains('if (widget.headers.isNotEmpty) return widget.headers;'),
          isTrue);
      expect(body.contains('cfg.headersFor(libId)'), isTrue);
    });
  });

  group('零调用点死实现', () {
    test('BadgeChipWrap 已删除，词条容器只剩可折叠那一份', () {
      final row = _code('lib/author_badge_row.dart');
      expect(row.contains('class BadgeChipWrap'), isFalse);
      expect(row.contains('class CollapsibleBadgeWrap'), isTrue);
      // 其余 lib 也不得再引用它。
      for (final name in Directory('lib').listSync().whereType<File>()) {
        if (!name.path.endsWith('.dart')) continue;
        final src = _code(name.path);
        expect(src.contains('BadgeChipWrap('), isFalse,
            reason: '${name.path} 仍在引用已删除的 BadgeChipWrap');
      }
    });
  });
}
