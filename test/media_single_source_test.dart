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
  });

  group('单图作品：m 可能是字符串，不得直接 as List', () {
    test('workMediaPaths 认字符串形式的 m', () {
      expect(workMediaPaths({'t': 'p', 'm': '/a/b.jpg'}).isEmpty, isTrue,
          reason: '当前实现只认 List（此断言记录事实，改动时须同步产品决定）');
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
