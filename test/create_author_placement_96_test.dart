import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 第九十六批：**「新建作者目录」只属于作者页**。
//
// owner 2026-11-27 原话：
//   「新建作者塞到挂载设置里面，你咋想的」
//   「当然是放到作者页啊，不是我说一句你做一个的时候了」
//
// 缺陷不是「功能坏了」，而是**归属放错**：挂载页解决的是「已有文件夹怎么
// 归类」，建目录是在作者容器里造新作者。两件事放一个页面里，用户会在
// 挂载设置里看到一个跟「挂载」无关的动作，而作者页反而没有入口。
//
// 这里只读 `lib/` 源码文本，不涉及任何真实作者名/目录名/媒体内容。
void main() {
  String codeOf(String path) => File(path)
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('1. 新建作者目录的入口只有作者页', () {
    test('挂载页不再有「新建作者目录」区块与回调', () {
      final page = codeOf('lib/unit_author_mount_page.dart');
      expect(page.contains('新建作者'), isFalse,
          reason: '挂载页又出现了建作者入口；这属于作者页');
      expect(page.contains('_openCreate'), isFalse,
          reason: '挂载页的建目录实现应整段删除，不是藏起来');
      // 请求体字段 `name` 只在建目录时出现；挂载页手拼它就是复活了这条链路。
      expect(page.contains("'name':"), isFalse,
          reason: '挂载页不该再拼建目录的请求体');
    });

    test('作者页保留唯一入口，并走 unit_author_groups 的地址与目录规则', () {
      final main = codeOf('lib/main.dart');
      expect(main.contains('Future<void> _createAuthor()'), isTrue,
          reason: '作者页的建目录入口被删了，功能就没了');
      expect(main.contains('unitAuthorCreateUrl('), isTrue,
          reason: '地址必须来自 unit_author_groups.dart（唯一出处）');
      expect(main.contains('authorDirForName('), isTrue);
      expect(main.contains('authorDirError('), isTrue);
      // 建目录这一段不得自己判 @ 前缀（改名规则只该有一处）。
      // 只看 `_createAuthor` 的函数体：`main` 别处还有一个与建目录无关的
      // `startsWith('@')`（播放页作者名去 @），不能用整份文件去判。
      final start = main.indexOf('Future<void> _createAuthor() async {');
      expect(start, greaterThanOrEqualTo(0));
      final body = main.substring(start, main.indexOf('Future<void> loadLibs()', start));
      expect(body.contains("startsWith('@')"), isFalse,
          reason: '建目录自己判 @ 前缀；用 authorDirError');
    });

    test('接口路径仍然只出现在 unit_author_groups.dart', () {
      final libs = Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final offenders = <String>[];
      for (final f in libs) {
        if (f.path.endsWith('unit_author_groups.dart')) continue;
        if (codeOf(f.path).contains('/api/unit/authors/create')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '建目录地址被第二处手拼了：${offenders.join(', ')}');
    });
  });

  group('2. 作者页的元数据回落只有一处', () {
    test('「当前库优先 → 任意一份」只写在一个函数里', () {
      final main = codeOf('lib/main.dart');
      // 原形态：两处各写一遍 `metas[cfg.lib] ?? (metas.isEmpty ? null : …)`。
      expect(
          RegExp(r'metas\[cfg\.lib\]\s*\?\?\s*\(metas\.isEmpty').allMatches(main).length,
          1,
          reason: '回落表达式必须在 `_metaForAuthorPage` 里只出现一次');
      expect(main.contains('LibMeta? _metaForAuthorPage()'), isTrue);
      // 两个使用点都走它。
      expect('_metaForAuthorPage()'.allMatches(main).length, greaterThanOrEqualTo(3),
          reason: '定义 1 处 + 使用 2 处（建目录下拉 / 作者卡词条）');
    });
  });
}
