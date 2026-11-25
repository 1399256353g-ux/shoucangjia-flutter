/// 第五十六批契约：**规则对了一半，另一半在调用点里按另一种顺序重算**。
///
/// 前两批修的是「后缀剥除只做一半」「公共出口对了、调用点自己抄了个更窄的」。
/// 这一批是同一个模式的第三种形态：**切分顺序**与**同一条字符串的两处偏移**。
/// 这类缺口不会在正常输入上出现，只在「片段里带 `?`」「前导空白」「相对段
/// 以斜杠开头」这类真实输入上翻车。
///
/// 本批修掉的五处（修复前实测）：
///
///  1. `joinRel('A', '/B')` → **`'A//B'`**；`coverImageRel('A/./B','v1')`
///     → **`'A/./B/_cover/v1.jpg'`**。拼出的地址服务端按字面找不到文件。
///  2. `coverPointerOf({'v':'v1.png'})` → **ext `jpg`**（只看 `raw is String`
///     的版本名扩展名），`coverPointerOf({'v':'v1.png','e':'gif'})` 也回 `jpg`
///     ——明明有 `png` 可用，请求的却是另一个文件。
///  3. `withImageWidth('/a.jpg#f?w=1', 640)` → **`'/a.jpg?w=640#f?w=1'`**：
///     先找 `#` 再找 `?`，查询串从片段里长出来，同地址
///     `requestedImageWidth` 却返回 null（同一段字符两种切法）。
///  4. `libOfMediaPath('\t/media/lib-7/a.jpg')`：`isMediaPath` 判的是 trim
///     后的串、`substring(7)` 切的是原串——这条规则在四个文件里各写一遍。
///  5. `restoreCoverVersion(version: '.png', ext: 'PNG?w=1')` 原样写进请求体，
///     读取侧早已归一、写入侧没有：指针与磁盘文件名不是同一个名字。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_avatar_store.dart';
import 'package:shoucangjia/cover_history.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/media_path.dart';
import 'package:shoucangjia/media_resize.dart';
import 'package:shoucangjia/source_lib.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 只保留非注释行，避免文档里的「旧写法」被契约扫描当成现役代码。
String _lib(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///');
    })
    .join('\n');

String _libAll() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map((f) => _lib(f.path))
    .join('\n');

void main() {
  group('相对路径拼接：分隔符与点段只有一份规则', () {
    test('第二段的前导斜杠不再留下双斜杠', () {
      expect(joinRel('A', '/B'), 'A/B');
      expect(joinRel('A', ' /B'), 'A/B');
      expect(joinRel('A/', '/B/'), 'A/B');
    });

    test('点段与多余分隔符被消掉（与 normalizeRelPath 同一条链）', () {
      expect(joinRel('A/./B', 'C'), 'A/B/C');
      expect(joinRel('A//B', 'C'), 'A/B/C');
      expect(joinRel(r'A\B', 'C'), 'A/B/C');
      expect(coverImageRel('A/./B', 'v1'), 'A/B/_cover/v1.jpg');
    });

    test('空段不产生幽灵路径', () {
      expect(joinRel('', '_cover'), '_cover');
      expect(joinRel(' ', '_cover'), '_cover');
      expect(joinRel('.', '_cover'), '_cover');
      expect(coverDirRel(''), '_cover');
      expect(coverDirRel('/'), '_cover');
    });
  });

  group('封面指针：显式 e > 版本名自带扩展名 > jpg', () {
    test('Map 里版本名带扩展名时用它（旧写法回落 jpg）', () {
      expect(coverPointerOf({'v': 'v1.png'}).ext, 'png');
      expect(coverPointerOf({'v': 'v1.webp'}).ext, 'webp');
      expect(coverPointerOf({'v': 'v1.webp', 'version': 'x'}).ext, 'webp');
    });

    test('显式 e 合法时优先于版本名', () {
      expect(coverPointerOf({'v': 'v1.png', 'e': 'jpeg'}).ext, 'jpeg');
      expect(coverPointerOf({'v': 'v1', 'e': 'PNG'}).ext, 'png');
    });

    test('显式 e 非法（不在白名单）时回落到版本名，而不是硬兜 jpg', () {
      expect(coverPointerOf({'v': 'v1.png', 'e': 'gif'}).ext, 'png');
      expect(coverPointerOf({'v': 'v1.webp', 'e': 'png?w=480'}).ext, 'png');
    });

    test('两处都没说才回落 jpg；裸版本名不算扩展名', () {
      expect(coverPointerOf({'v': 'v1'}).ext, 'jpg');
      expect(coverPointerOf({'v': 'v1', 'e': ''}).ext, 'jpg');
      // `2026.11.15` 是一个版本名，不是「扩展名 15」
      expect(coverPointerOf('2026.11.15').version, '');
      expect(coverPointerOf({'v': 'v1', 'e': 'gif'}).ext, 'jpg');
    });

    test('字符串写法（v1.PNG?w=480）仍取到 png', () {
      expect(coverPointerOf('v1.PNG?w=480').ext, 'png');
      expect(coverPointerOf('v1.JPEG').ext, 'jpeg');
    });

    test('版本名本身非法时整条不认，扩展名不单独生效', () {
      expect(coverPointerOf({'v': '..', 'e': 'png'}).version, '');
      expect(coverPointerOf({'v': '', 'e': 'png'}).version, '');
    });
  });

  group('查询串/片段切分：唯一实现，读写同一条', () {
    test('片段里带 ? 时先切 # 再在 # 之前找 ?', () {
      // 修复前：'/a.jpg?w=640#f?w=1'（查询串从片段里长出来）
      expect(withImageWidth('/a.jpg#f?w=1', 640), '/a.jpg?w=640#f?w=1');
      expect(requestedImageWidth('/a.jpg#f?w=1'), isNull);
      // 修好之后两侧对同一个地址的结论一致：加完宽度，读到的就是新宽度。
      expect(requestedImageWidth(withImageWidth('/a.jpg#f', 640)), 640);
    });

    test('splitMediaSuffix 三段切分（先 # 后 ?）', () {
      final a = splitMediaSuffix('/a.jpg?w=1#f');
      expect(a.path, '/a.jpg');
      expect(a.query, 'w=1');
      expect(a.fragment, '#f');

      final b = splitMediaSuffix('/a.jpg#f?w=1');
      expect(b.path, '/a.jpg');
      expect(b.query, '');
      expect(b.fragment, '#f?w=1');

      final c = splitMediaSuffix('/a.jpg');
      expect(c.path, '/a.jpg');
      expect(c.query, '');
      expect(c.fragment, '');

      // stripMediaSuffix 是同一实现的「丢后缀」特例
      for (final u in ['/a.jpg?w=1#f', '/a.jpg#f?w=1', '/a.jpg']) {
        expect(stripMediaSuffix(u), splitMediaSuffix(u).path, reason: u);
      }
    });

    test('绝对地址转义的切分也走同一出口', () {
      expect(
          absoluteMediaUrl('http://nas:8090',
              lib: 'l', path: 'http://cdn/x.jpg?a=1#f'),
          'http://cdn/x.jpg?a=1#f');
      expect(
          absoluteMediaUrl('http://nas:8090',
              lib: 'l', path: 'http://cdn/x.jpg#f?a=1'),
          'http://cdn/x.jpg#f?a=1');
    });

    test('媒体层里不存在第二处 indexOf("#") 手写切分', () {
      final src = _lib('lib/media_resize.dart');
      expect(src.contains("indexOf('#')"), isFalse,
          reason: 'requestedImageWidth / withImageWidth 又各自切了一遍后缀');
      expect(src.contains('splitMediaSuffix'), isTrue);
    });
  });

  group('/media/ 前缀：判定与切片同一个出口', () {
    test('前导空白时库段不被切掉一个字符', () {
      expect(libOfMediaPath('\t/media/lib-7/a.jpg'), 'lib-7');
      expect(libOfMediaPath('  /media/lib-7/a.jpg'), 'lib-7');
      expect(decodeMediaRel('\t/media/lib-7/a.jpg'), 'lib-7/a.jpg');
      expect(serverAvatarFileFromPath('\t/media/l/.avatars/a.png'),
          (lib: 'l', file: 'a.png'));
    });

    test('mediaRelOrNull 区分「不是媒体路径」与「尾部为空」', () {
      expect(mediaRelOrNull('/media/'), '');
      expect(mediaRelOrNull('/media'), isNull);
      expect(mediaRelOrNull('/mediax/a.jpg'), isNull);
      expect(mediaRel('/media/lib/a.jpg'), 'lib/a.jpg');
      expect(mediaRel('/other/a.jpg'), '');
      expect(isMediaPath(' /media/x'), isTrue);
    });

    test('lib/ 里不再手写 substring(7)', () {
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          // 唯一实现本身就在 media_path.dart（前缀长度只能在那里出现一次）。
          .where((f) => !f.path.endsWith('media_path.dart'))
          .where((f) => _lib(f.path).contains('substring(7)'))
          .map((f) => f.path.replaceAll('\\', '/'))
          .toList();
      expect(offenders, isEmpty,
          reason: '/media/ 前缀长度又抄了一份：$offenders');
      final all = _libAll();
      expect(
          RegExp(r"String\? mediaRelOrNull\(").allMatches(all).length, 1);
    });
  });

  group('恢复封面：写入侧与读取侧同一对归一函数', () {
    Future<Map<String, dynamic>> postBody({
      required String version,
      required String ext,
    }) async {
      Map<String, dynamic>? body;
      final client = MockClient((r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response('{"ok":true,"u":"/media/l/_cover/v1.png"}', 200);
      });
      final r = await restoreCoverVersion(
        url: Uri.parse('http://nas/api/cover/restore'),
        headers: const {},
        libId: 'l',
        version: version,
        ext: ext,
        client: client,
      );
      expect(r.ok, isTrue);
      return body!;
    }

    test('版本名与扩展名都归一后再发', () async {
      final b = await postBody(version: '_cover/v1.png?w=480', ext: 'PNG');
      expect(b['v'], 'v1');
      expect(b['e'], 'png');
    });

    test('扩展名不在白名单时回落 jpg（服务端只落四种）', () async {
      final b = await postBody(version: 'v1', ext: 'gif');
      expect(b['e'], 'jpg');
    });

    test('版本名非法时直接拒绝，不发请求', () async {
      var hit = 0;
      final client = MockClient((r) async {
        hit++;
        return http.Response('{}', 200);
      });
      final r = await restoreCoverVersion(
        url: Uri.parse('http://nas/api/cover/restore'),
        headers: const {},
        libId: 'l',
        version: '../etc',
        ext: 'jpg',
        client: client,
      );
      expect(r.ok, isFalse);
      expect(hit, 0);
    });
  });
}
