// 第九十五批（0.9.336）契约：
//
// 1. `lib=all` 是**激活连接**的聚合视图，而 `cfg.headers` 是**当前库**那条
//    连接的账号。用户切过连接但没切库时两者分属两台机器：地址打 A、密码是 B
//    的 → 401，或两台恰好同账号时静默读到另一台的作者/推荐/排行。
//    已收成 `Cfg.aggregate(path)`（地址与鉴权一起返回），四个调用点全部改走
//    它。本文件钉住：四个调用点零 `lib: 'all'` 配 `cfg.headers`，且返回形状
//    不允许调用方只取一半。
//
// 2. 作者头像索引的「已加载」是**进程级布尔值**：切过激活连接后仍为 true，
//    新连接的作者全部停在旧服务器的头像/首字占位，直到重启 App。
//    现在标记带作用域（`<base>␁<user>`），连接一变就当作没加载过。
//
// 3. `emojiChoices` 里 `🌟` 出现两次（66 项 / 65 个唯一值），选择器同一格
//    图案相邻出现两次——点哪一格都「没反应」（其实选中了同样的后缀）。
//
// 4. 键归属判定（`key == id || key.startsWith('<id>␁')`）在 `metaKeyIsFor`
//    与 `authorTypeCacheKeyIsFor` 里**逐字节相同**。两处各写一份，其中一处
//    后来补了「不误伤 `lib-10`」而另一处没跟，表现是「刷新了库 1，库 10 的
//    旧数据还在」，而两处单看都自洽。现在只有 `node_key.scopedKeyIsFor`。
//
// 隐私：本文件只读 `lib/` 源码文本，不涉及任何真实目录名、文件名或媒体内容。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/node_key.dart';
// `unit_library` / `unit_cover_store` / `author_dir_filter` 三个 import 在本批
// 收口后已无引用（断言改成扫源码文本），留着会让 analyze 一直有 3 条 warning
// ——warning 长期不红，就没人记得哪一条是新的。

/// 去掉整行注释后的源码（注释里引用旧写法是在解释为什么改）。
String _code(String path) {
  final raw = File(path).readAsStringSync().replaceAll('\r\n', '\n');
  final out = StringBuffer();
  for (final line in raw.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    out.writeln(line);
  }
  return out.toString();
}

/// 取某段源码（从 [startMark] 到 [endMark]）。
String _body(String src, String startMark, String endMark) {
  final s = src.indexOf(startMark);
  expect(s, greaterThanOrEqualTo(0), reason: '找不到起点：$startMark');
  final e = src.indexOf(endMark, s);
  expect(e, greaterThan(s), reason: '找不到终点：$endMark');
  return src.substring(s, e);
}

void main() {
  group('1. lib=all 聚合请求的地址与鉴权同源', () {
    final main = _code('lib/main.dart');

    test('aggregate 是同源出口，返回地址+头一件东西', () {
      final body = _body(main, '({Uri uri, Map<String, String> headers}) aggregate(',
          'String media(String p, {String? lib}) {');
      expect(body.contains("lib: 'all'"), isTrue,
          reason: '聚合视图就是 lib=all');
      expect(body.contains('basicAuthHeader(user, pass)'), isTrue,
          reason: '鉴权必须取与 base 同源的激活连接凭据');
      expect(body.contains('cfg.headers'), isFalse,
          reason: 'cfg.headers 是当前库那条连接的账号');
    });

    test('四个聚合调用点都走 aggregate，不再自己拼 lib=all + cfg.headers', () {
      // 旧形态就是这一行：`cfg.u('/api/x', lib: 'all'), headers: cfg.headers`
      expect(RegExp(r"lib: 'all'\),\s*headers: cfg\.headers").hasMatch(main),
          isFalse,
          reason: '地址按激活连接、账号按当前库 → 401 或串库');
      // 唯一一处 `lib: 'all'` 只允许出现在 aggregate 内部。
      expect("lib: 'all'".allMatches(main).length, 1,
          reason: "聚合请求的 lib=all 只由 aggregate 写一次");
      expect('cfg.aggregate('.allMatches(main).length, greaterThanOrEqualTo(4),
          reason: '头像索引 / 排行榜 / 作者总览 / 推荐池都要走同一个出口');
    });

    test('每个聚合调用点都用返回的 uri + headers 两件', () {
      for (final anchor in <String>[
        "final scope = cfg.aggregate('/api/authors.json');",
        "final scope = cfg.aggregate('/api/rank?period=\$period&metric=\$metric');",
        "final arScope = cfg.aggregate('/api/authors.json');",
        "final scope = cfg.aggregate('/api/recommend?n=\$n&seed=\$seed');",
      ]) {
        final at = main.indexOf(anchor);
        expect(at, greaterThan(0), reason: '找不到调用点：$anchor');
        final seg = main.substring(at, at + 240);
        expect(seg.contains('.get(scope.uri, headers: scope.headers)') ||
            seg.contains('.get(arScope.uri, headers: arScope.headers)'), isTrue,
            reason: '必须同时用同源的两件：$anchor');
      }
    });
  });

  group('2. 作者头像索引按连接作用域重载', () {
    final main = _code('lib/main.dart');

    test('「已加载」不是进程级布尔值，而是作用域比较', () {
      final body = _body(main, 'bool get _authorAvatarLoaded =>',
          'final ValueNotifier<int> authorAvatarRevision');
      expect(body.contains('_authorAvatarScope == authorAvatarScopeKey'), isTrue,
          reason: '连接一变就必须当作没加载过');
      expect(RegExp(r'bool _authorAvatarLoaded = (true|false);').hasMatch(main),
          isFalse,
          reason: '进程级布尔值会让新连接的作者一直停在旧服务器的头像');
    });

    test('作用域键由 node_key.scopedKey 拼（分隔符只有一处）', () {
      final body = _body(main, 'String get authorAvatarScopeKey =>',
          'bool get _authorAvatarLoaded');
      expect(body.contains('scopedKey(cfg.base, cfg.user)'), isTrue);
      expect(body.contains(r'\u0001'), isFalse,
          reason: '再写一份分隔符字面量就回到了第八/九十四批修掉的问题');
    });

    test('加载前清旧索引、成功后记发请求时那一份作用域', () {
      final body = _body(main, 'Future<void> ensureAuthorAvatarsLoaded() async {',
          'final navKey = GlobalKey<NavigatorState>();');
      expect(body.contains('authorAvatarIndex.clear()'), isTrue,
          reason: '旧连接的同名作者头像必须消失，否则串头像');
      expect(body.contains('_authorAvatarScope = scopeKey;'), isTrue,
          reason: '作用域要记发请求时那一份，不能记「此刻」的（请求途中可能又切了）');
      // 失败时不得把作用域写成成功：否则下一次会直接跳过重试。
      // 全函数只有一处 `_authorAvatarScope = <值>`（成功分支里那一行）；
      // 清空用的是 `authorAvatarIndex.clear()`，不靠写作用域。
      final scopeWrites =
          RegExp(r'_authorAvatarScope = [^;]').allMatches(body).length;
      expect(scopeWrites, 1,
          reason: 'catch 分支再写一次 = 请求失败被记成已加载，永远不重试');
    });
  });

  group('3. emoji 选择器里没有重复项', () {
    test('66 项全唯一（0.9.336 之前 🌟 出现两次）', () {
      expect(LibraryBadge.emojiChoicesAreUnique, isTrue,
          reason: '重复项会让同一格图案相邻出现两次，点哪一格都“没反应”');
      final star = LibraryBadge.emojiChoices.where((e) => e == '🌟').length;
      expect(star, 1);
    });

    test('列表本身不被静默去重，重复即红', () {
      // 「静默去重」会让新增的重复项在界面上看不出来；判定必须能被断言。
      expect(LibraryBadge.emojiChoices.toSet().length,
          LibraryBadge.emojiChoices.length);
      expect(LibraryBadge.emojiChoices.contains('🔥'), isTrue);
    });
  });

  group('4. 键归属判定只有一处实现', () {
    test('scopedKeyIsFor 的行为：裸键、作用域键、前缀相近都不误伤', () {
      expect(scopedKeyIsFor('lib-1', 'lib-1'), isTrue);
      expect(scopedKeyIsFor('lib-1\u0001s1', 'lib-1'), isTrue);
      expect(scopedKeyIsFor(' lib-1 ', 'lib-1'), isFalse,
          reason: '键本身不做 trim：拼装时已 trim，读的时候再 trim 会掩盖脏键');
      expect(scopedKeyIsFor('lib-10', 'lib-1'), isFalse);
      expect(scopedKeyIsFor('lib-10\u0001s1', 'lib-1'), isFalse);
      expect(scopedKeyIsFor('lib-1', ''), isFalse);
      expect(scopedKeyIsFor('lib-1', '  '), isFalse,
          reason: '空标识不能认领任何键');
    });

    test('两个上层判定都只转发，不再自己写前缀比较', () {
      final meta = _code('lib/meta_source.dart');
      final metaBody =
          _body(meta, 'bool metaKeyIsFor(String key, String lib)', '\n');
      expect(metaBody.contains('scopedKeyIsFor(key, lib)'), isTrue);
      expect(metaBody.contains('startsWith('), isFalse);

      final main = _code('lib/main.dart');
      final typeBody = _body(
          main, 'bool authorTypeCacheKeyIsFor(String key, String lib)',
          'typedef AuthorTypeScope');
      expect(typeBody.contains('scopedKeyIsFor(key, lib)'), isTrue);
      expect(typeBody.contains('startsWith('), isFalse);
    });

    test('lib/ 内只有 node_key 一处实现前缀判定', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final name = f.uri.pathSegments.last;
        if (name == 'node_key.dart') continue;
        final src = _code(f.path);
        if (src.contains(r"startsWith('$l$kNodeKeySep')") ||
            src.contains(r"key.startsWith('$i$kNodeKeySep')")) {
          offenders.add(name);
        }
      }
      expect(offenders, isEmpty, reason: '键归属判定又写成了第二份：$offenders');
    });
  });
}
