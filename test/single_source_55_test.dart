/// 第七十八批契约（0.9.312）：
///  1. **挂载页的候选从平铺改成树枝**——owner 2026-11-27：「单元库树枝分叉
///     展开，用户自己选哪些叶子目录属于同一作者（不同名字也可以）」。
///     三处对话框（合并 / 拆出 / 编辑成员）此前各写一份 `CheckboxListTile`
///     平铺列表，现在都转发 `author_file_picker.AuthorFilePicker`；
///     分组规则（按基础库、稳定排序、去重）只有 `authorFileBranches` 一处。
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

import 'package:shoucangjia/author_file_picker.dart';
import 'package:shoucangjia/unit_author_groups.dart';

String _code(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('挂载候选：按基础库分叉（唯一实现）', () {
    AuthorGroupFile f(String lib, String dir) =>
        AuthorGroupFile(lib: lib, authorDir: dir);

    test('按 lib 分组，组内与组间都稳定有序', () {
      final files = [
        f('lib-2', '@b'),
        f('lib-1', '@z'),
        f('lib-2', '@a'),
        f('lib-1', '@y'),
      ];
      final branches = authorFileBranches(files,
          labelOf: (lib) => lib == 'lib-1' ? 'A库' : 'B库');
      expect(branches.map((b) => b.lib).toList(), ['lib-1', 'lib-2']);
      expect(branches.map((b) => b.label).toList(), ['A库', 'B库']);
      expect(branches[0].leaves.map((e) => e.authorDir).toList(), ['@y', '@z']);
      expect(branches[1].leaves.map((e) => e.authorDir).toList(), ['@a', '@b']);
    });

    test('同一成员重复传入只留一份；空 lib/空目录被丢掉', () {
      final files = [
        f('lib-1', '@a'),
        f('lib-1', '@a'),
        f('', '@x'),
        f('lib-2', '   '),
      ];
      final branches = authorFileBranches(files);
      expect(branches.length, 1);
      expect(branches.single.leaves.length, 1);
    });

    test('名称取不到时回落 id（分支标题不得为空）', () {
      final branches = authorFileBranches([f('lib-9', '@a')], labelOf: (_) => '  ');
      expect(branches.single.label, 'lib-9');
    });

    test('同名基础库之间不换位：名称相同按 lib 升序', () {
      final files = [f('lib-b', '@a'), f('lib-a', '@a')];
      final branches = authorFileBranches(files, labelOf: (_) => '同名');
      expect(branches.map((b) => b.lib).toList(), ['lib-a', 'lib-b']);
    });

    test('挂载页按基础库勾选，不再用目录树控件', () {
      // owner 2026-11-28：
      // > 「不要用文件目录的方式进行设置了，列出直属单元库下所有基础库，
      // >   让用户自己选作者作品存在于直接上级单元库下哪些基础库」
      //
      // 因此挂载页的「候选」从 `AuthorFilePicker`（目录树）换成了基础库
      // 勾选列表。作者主页的 `author_mount_sheet` 仍保留树形控件（那里是按
      // 单个作者的已有目录拆分，语义未变）。
      final page = _code('lib/unit_author_mount_page.dart');
      expect(page.contains('basicsOfUnitScope('), isTrue,
          reason: '范围必须来自所属单元库的基础库，不跨库');
      expect(page.contains('createAuthorBodies('), isTrue,
          reason: '勾选的基础库要能翻译成建目录请求');
      // 合并 / 拆出 / 编辑成员三个对话框仍共用同一个树形控件。
      expect(page.contains('AuthorFilePicker('), isTrue);
      expect(page.contains("leafKeyPrefix: 'uag-pick'"), isTrue);
      expect(page.contains("leafKeyPrefix: 'uag-split'"), isTrue);
      expect(page.contains("leafKeyPrefix: 'uag-setfiles'"), isTrue);
      // 分组规则只在 picker 里出现一次，页面不得自己按 lib 分组。
      final picker = _code('lib/author_file_picker.dart');
      expect(picker.contains('List<AuthorFileBranch> authorFileBranches('), isTrue);
      expect(page.contains('byLib'), isFalse,
          reason: '页面不得自己再按 lib 分组一次');
    });

    test('控件自带「全选/全不选」作用域限定在本分支', () {
      final picker = _code('lib/author_file_picker.dart');
      expect(picker.contains('onToggleBranch'), isTrue);
      // 只传本分支的 leaves 回去（不是整个候选池）。
      expect(picker.contains('onToggleBranch(branch.leaves'), isTrue);
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
