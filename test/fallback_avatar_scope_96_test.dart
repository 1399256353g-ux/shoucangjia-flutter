import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// 第九十六批 · 项 2：**按连接缓存的东西都带作用域**。
//
// `_authorAvatarScope` 上一批已经把头像索引的「已加载」从进程级布尔值改成
// 作用域比较。作者卡兜底头像（`_avFallback` / `_avLookup`）是同一族里
// 剩下的最后一处：两张表只加不清，切过激活连接后新连接的作者仍在表里
// （同名同库 id 时）——「已查过」成立，兜底头像永远不拉，卡片停在首字占位。
//
// 只读 `lib/` 源码文本，不涉及任何真实作者名/目录名。
void main() {
  String codeOf(String path) => File(path)
      .readAsStringSync()
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  final main = codeOf('lib/main.dart');

  String bodyOf(String startMarker, String endMarker) {
    final start = main.indexOf(startMarker);
    expect(start, greaterThanOrEqualTo(0), reason: '找不到 $startMarker');
    final end = main.indexOf(endMarker, start);
    expect(end, greaterThan(start), reason: '找不到 $startMarker 的结尾');
    return main.substring(start, end);
  }

  group('1. 兜底头像缓存按连接作用域清空', () {
    test('作用域变化时清空两张表（不是只加不清）', () {
      final body = bodyOf('void _syncAvScope() {', 'void initState()');
      expect(body.contains('authorAvatarScopeKey'), isTrue);
      expect(body.contains('_avFallback.clear()'), isTrue,
          reason: '旧连接的兜底图必须丢掉');
      expect(body.contains('_avLookup.clear()'), isTrue,
          reason: '「已查过」必须一起作废，否则新连接永远不重查');
    });

    test('load 开头先归一作用域（唯一的清理时点）', () {
      final body = bodyOf(
          'Future<void> load({bool quiet = false}) async {',
          'final auMap = <String, Map<String, dynamic>>{};');
      expect(body.contains('_syncAvScope()'), isTrue,
          reason: '清理只在 load 开头做，不能在 build 里改表');
    });
  });

  group('2. 缓存键/写入都带发请求时那一份作用域', () {
    test('键走 node_key.scopedKey（分隔符只有一处）', () {
      final body = bodyOf(
          'Future<void> _fetchFallbackAvatar(', 'Future<void> _open(String name)');
      expect(body.contains('final scope = authorAvatarScopeKey;'), isTrue,
          reason: '取的是发请求那一刻的作用域');
      expect(RegExp(r'final key = scopedKey\(scope,').hasMatch(body), isTrue,
          reason: '键必须走唯一拼装口');
      expect(body.contains('\\u0001'), isFalse,
          reason: '分隔符不得在页面里手写');
    });

    test('请求返回后连接变了就不写（不把旧服务器的图记给新连接）', () {
      final body = bodyOf(
          'Future<void> _fetchFallbackAvatar(', 'Future<void> _open(String name)');
      expect(body.contains('if (authorAvatarScopeKey != scope) return;'), isTrue);
      // 写入必须发生在这道判定之后。
      final guard = body.indexOf('if (authorAvatarScopeKey != scope) return;');
      final write = body.indexOf('_avFallback[key] = pick');
      expect(write, greaterThan(guard));
    });

    test('卡片读取端的键带同一个作用域', () {
      final body = bodyOf('Widget _authorCell(', 'return AuthorGridCard(');
      expect(body.contains('scopedKey(authorAvatarScopeKey,'), isTrue,
          reason: '读表也必须带作用域，否则清理窗口内会串图');
    });
  });
}
