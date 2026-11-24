// 第三十八批（0.9.231）：媒体地址转义单一实现 / 单图作品 `m` 为字符串 /
// 失败原因不得直插对象。
//
// 这三条都是「同一个问题两套实现，其中一套漏了修复」：
//  1. `encodeMediaPath` 只在 `Cfg.mediaUrl` 里执行，`lib_cover.absoluteMediaUrl`
//     （库卡片封面主路径）直拼 → 同一个带 `#` 的文件作品列表能开、卡片 404；
//  2. 播放页自动轮播 / 方向键把 `w['m']` 直接 `as List`，单图作品（`m` 是
//     字符串）当场 CastError，定时器里没人接，整页卡死；
//  3. `j?['error']` 被原样插值，服务端给对象（`{code:500}`）时贴到界面上。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/http_json.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/media_path.dart';
import 'package:shoucangjia/work_cover.dart';
import 'package:shoucangjia/work_safety.dart';

String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('媒体地址转义：唯一实现，库卡片封面也走它', () {
    test('带 # / ? 的文件名转义后 Uri.parse 不再断成 fragment/query', () {
      final u = absoluteMediaUrl('http://nas:8090',
          lib: 'lib-01', path: '/media/lib-01/1#花絮.mp4');
      // 中文不转义（交给 Uri 自己编码），只把 `#` / `?` / 空格断成
      // fragment/query 的字符转义掉。
      expect(u, 'http://nas:8090/media/lib-01/1%23花絮.mp4');
      final parsed = Uri.parse(u);
      expect(parsed.fragment, isEmpty);
      expect(parsed.query, isEmpty);
      expect(parsed.pathSegments.last, '1#花絮.mp4');
    });

    test('已编码的 %XX 不被二次编码（库段是百分号编码的）', () {
      final u = absoluteMediaUrl('http://nas:8090',
          lib: 'lib-01', path: '/media/lib-01/%E4%B8%AD/x.jpg');
      expect(u, 'http://nas:8090/media/lib-01/%E4%B8%AD/x.jpg');
    });

    test('绝对地址原样返回（不重复补服务器前缀）', () {
      expect(
          encodeMediaPath('https://cdn.example.com/a%23b.jpg'),
          'https://cdn.example.com/a%23b.jpg');
      expect(isAbsoluteMediaUrl('http://x/y'), isTrue);
      expect(isAbsoluteMediaUrl('/media/x/y'), isFalse);
    });

    test('接口地址判定只有一处：work_cover 转发到 media_path', () {
      expect(isApiThumbPath('/api/thumb/lib/id'), isTrue);
      expect(isApiThumbPath('/media/lib/api/x.jpg'), isFalse);
      final src = _code('lib/work_cover.dart');
      expect(src.contains('isApiMediaPath(p)'), isTrue,
          reason: 'isApiThumbPath 自己又判了一遍前缀（第二套实现）');
      expect(RegExp(r"return\s+t\.startsWith\('/api/'\)").hasMatch(src), isFalse,
          reason: 'isApiThumbPath 恢复了第二份前缀判定');
    });

    test('契约：lib/ 里不得再有第二个 encodeMediaPath 实现', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final defs = <String>[];
      for (final f in files) {
        final src = _code(f.path);
        if (RegExp(r'^String encodeMediaPath\(', multiLine: true)
            .hasMatch(src)) {
          defs.add(f.path);
        }
      }
      expect(defs, ['lib/media_path.dart'],
          reason: 'encodeMediaPath 出现了多份实现：$defs');
    });

    test('绝对地址不得被套上 /media/<lib>/（爬虫封面外链）', () {
      // 0.9.232 前 libraryMediaPath 只判 `/media/` 前缀，`http(s)://`
      // 会被当成相对路径补前缀 → `…/media/lib-01/http://cdn/x.jpg` → 404。
      expect(libraryMediaPath('lib-01', 'http://cdn.example.com/a.jpg'),
          'http://cdn.example.com/a.jpg');
      expect(absoluteMediaUrl('http://nas:8090',
              lib: 'lib-01', path: 'https://cdn.example.com/a.jpg'),
          'https://cdn.example.com/a.jpg');
      final parsed =
          Uri.parse('https://cdn.example.com/a.jpg');
      expect(parsed.host, 'cdn.example.com');
    });

    test('接口地址不被套 /media/<lib>/（th 已是 /api/thumb 的作品）', () {
      // 0.9.233：`workCoverPath` 会把 `th` 原样交给 `urls.mediaUrl`，而库卡片
      // 走的是 `libraryMediaPath`。后者此前只判 `/media/` 与 `http(s)://`，
      // `/api/thumb/<lib>/<id>` 被当成相对路径 → `…/media/lib-019/api/thumb/…`
      // → 服务端把 `api` 当库内子目录，2288 条图文作品的卡片永远只有底色。
      expect(libraryMediaPath('lib-019', '/api/thumb/lib-019/g1'),
          '/api/thumb/lib-019/g1');
      expect(
          absoluteMediaUrl('http://nas:8090',
              lib: 'lib-019', path: '/api/thumb/lib-019/g1?v=2'),
          'http://nas:8090/api/thumb/lib-019/g1?v=2');
      // `?v=` 是抽帧版本参数，不能被转义成 `%3F`（服务端会收到另一个路径）。
      expect(encodeMediaPath('/api/thumb/lib-019/g1?v=2'),
          '/api/thumb/lib-019/g1?v=2');
      // 相对媒体路径仍然要补前缀，别把修复变成「全都不补」。
      expect(libraryMediaPath('lib-019', 'a/b.jpg'), '/media/lib-019/a/b.jpg');
    });

    test('契约：/media/ 前缀判定只有 media_path 一处', () {
      // 这条判定此前在 6 个文件里各写一遍裸 startsWith('/media/')。
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('media_path.dart')) continue;
        final src = _code(f.path);
        if (src.contains("startsWith('/media/')")) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: '前缀判定又出现第二份（服务端改前缀时要改六处）：$offenders');
      expect(isMediaPath('/media/x/y'), isTrue);
      expect(isMediaPath('/api/x'), isFalse);
    });

    test('百分号解码只有 media_path 一处，且非法编码不抛', () {
      expect(decodeComponentOrRaw('%E4%B8%AD'), '中');
      expect(decodeComponentOrRaw('100%成品'), '100%成品'); // 孤立 % 不能抛
      expect(decodeComponentOrRaw('%zz'), '%zz');
      expect(decodeComponentOrRaw(''), '');
      expect(libOfMediaPath('/media/%E4%B8%AD/a.jpg'), '中');
      expect(libOfMediaPath('/media/100%成品/a.jpg'), '100%成品');
    });

    test('契约：视频扩展名清单只有 media_path 一处', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      final offenders = <String>[];
      for (final f in files) {
        if (f.path.endsWith('media_path.dart')) continue;
        final src = _code(f.path);
        // 任何再次列出的视频扩展名字面量（至少 3 个成员）都视为第二份清单。
        for (final lit in RegExp(r"const\s+\w*\s*=\s*\[([^\]]*)\]")
            .allMatches(src)) {
          final body = lit.group(1) ?? '';
          final hits = RegExp(r"'\s*\.?(?:mp4|mov|m4v|webm|mkv|avi)\s*'")
              .allMatches(body)
              .length;
          if (hits >= 3) {
            offenders.add('${f.path}: $body');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '视频扩展名清单出现了第二份（chapterIsImage 曾少列 mkv/avi，'
              '同一个 .mkv 在封面判定里是视频、在合集排序里是图片）：\n'
              '${offenders.join('\n')}');
    });
  });

  group('单图作品：m 可能是字符串，不得直接 as List', () {
    test('workMediaPaths 认字符串形式的 m', () {
      // 0.9.232：字符串形式此前被当成「没有媒体」，单图作品在播放页
      // 显示「数据损坏」占位、预载无源、角标 0 张。读侧已归一。
      expect(workMediaPaths({'t': 'p', 'm': '/a/b.jpg'}), ['/a/b.jpg']);
      expect(workMediaPaths({'t': 'p', 'm': ['/a/b.jpg']}), ['/a/b.jpg']);
      expect(workMediaPaths({'t': 'v'}), isEmpty);
      expect(workMediaPaths('junk'), isEmpty);
    });

    test('播放页不得再对 m 做裸 List 转换', () {
      final src = _code('lib/main.dart');
      expect(RegExp(r"\(w\['m'\] as List\)\.length").hasMatch(src), isFalse,
          reason: '`m` 为字符串时会抛 CastError，自动轮播/方向键直接崩');
      // 真实路径仍在：切图数量走唯一的安全取数。
      expect(RegExp(r'final n = workMediaPaths\(w\)\.length;').allMatches(src).length,
          greaterThanOrEqualTo(2),
          reason: '切图数量没有走 workMediaPaths');
    });

    test('契约：读作品媒体的地方不得自己写 `m is List` / `m is! List`', () {
      // 0.9.232：单图作品的 `m` 是字符串。谁自己判一次 `is List`，谁就把
      // 这类作品判成「没有媒体」——预载无源、角标 0 张、保存/移动失败、
      // 头像候选空、合集章节排序错。取数只有 workMediaPaths 一个入口。
      final offenders = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        if (f.path.endsWith('work_safety.dart')) continue; // 归一实现本身
        if (f.path.endsWith('app_settings.dart')) continue; // 按键 combo 的 m
        final src = _code(f.path);
        for (final m in RegExp(r'''\[['"]m['"]\]''').allMatches(src)) {
          // 取该行上下文，命中「is List」即视为自行解析媒体数组。
          final lineStart = src.lastIndexOf('\n', m.start) + 1;
          final lineEnd = src.indexOf('\n', m.end);
          final line = src.substring(
              lineStart, lineEnd < 0 ? src.length : lineEnd);
          if (RegExp(r'\bis\s+!?\s*List\b').hasMatch(line)) {
            offenders.add('${f.path}: ${line.trim()}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: '这些地方自行判断 m 的类型，单图作品会被当成没有媒体：\n'
              '${offenders.join('\n')}');
    });
  });

  group('失败原因：对象型 error 不得贴到界面', () {
    test('serverErrorText 只接受非空字符串', () {
      expect(serverErrorText({'error': '写盘失败'}), '写盘失败');
      expect(serverErrorText({'error': '  '}), isNull);
      expect(serverErrorText({'error': {'code': 500}}), isNull);
      expect(serverErrorText({'error': 500}), isNull);
      expect(serverErrorText('not a map'), isNull);
      expect(serverErrorText(null), isNull);
    });

    test('契约：lib/ 内不得再插值 j?[error] / r?[error]', () {
      final offenders = <String>[];
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        if (f.path.endsWith('http_json.dart')) continue;
        final src = _code(f.path);
        if (RegExp(r"\$\{(?:j|r|dry)\?\['error'\]").hasMatch(src)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '对象型 error 会被插值成 `{code: 500}` 贴到界面：$offenders');
    });
  });
}
