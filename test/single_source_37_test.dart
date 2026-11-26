/// 第五十七批契约：**同一条字符串的「键值对」与「网络地址」各有两套判法**。
///
/// 第五十六批修的是「同一条字符串被两处以不同顺序切分」；这一批是同一个根因
/// 换了个外套：规则本身已经存在，但**读写两侧各解析了一遍**、或者
/// **只认了这个协议形态的一半**。
///
/// 本批修掉的三处（修复前实测）：
///
///  1. `w=` 的「键名 + 值」在 `media_resize` 里解析了两遍：写侧
///     `_queryWithWidth` 两个闭包（`isWidthKey` / `usable`）、读侧
///     `requestedImageWidth` 又一个循环里的 `indexOf('=')` + `tryParse`。
///     两份对同一段字符给出不同结论，就会出现「加了宽度的请求被读侧判成没加」
///     ——原图在缓存里存 14 天。
///  2. `playback_error._looksLikeMediaFile` 自己写 `split(RegExp(r'[?&#]'))`
///     取第一段，与 `media_path.stripMediaSuffix` 是同一条规则的第三份抄写。
///  3. **协议相对地址**（`//cdn/x.jpg`）既不算绝对、也不算根相对：
///     `libraryMediaPath('lib','//cdn/x.jpg')` → `/media/lib/cdn/x.jpg`，
///     爬虫封面永远 404，而地址本身完全可用。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/media_path.dart';
import 'package:shoucangjia/media_resize.dart';
import 'package:shoucangjia/playback_error.dart';

String _lib(String name) => File('lib/$name').readAsStringSync();

void main() {
  group('w= 的键值解析只有一处实现', () {
    test('widthParamOf 三态：不是 w / 是 w 但不可用 / 可用', () {
      expect(widthParamOf('v=1').isWidthKey, isFalse);
      expect(widthParamOf('v=1').width, isNull);

      expect(widthParamOf('w').isWidthKey, isTrue);
      expect(widthParamOf('w').width, isNull, reason: '裸键没有值，不算可用宽度');

      for (final bad in <String>['w=', 'w=0', 'w=-5', 'w=abc', 'w=480px']) {
        expect(widthParamOf(bad).isWidthKey, isTrue, reason: '$bad 仍是 w 键');
        expect(widthParamOf(bad).width, isNull, reason: '$bad 的值不可用');
      }

      expect(widthParamOf('w=480').width, 480);
      expect(widthParamOf('W=480').width, 480, reason: '键名忽略大小写');
      expect(widthParamOf(' W = 720 ').width, 720, reason: '键与值两侧空白要吃掉');
      expect(widthParamOf('w=12000').width, 12000, reason: '不再有四位上限');
    });

    test('widthInQuery 取第一个可用值，跳过不可用的同名项', () {
      expect(widthInQuery(''), isNull);
      expect(widthInQuery('v=1&x=2'), isNull);
      expect(widthInQuery('w=&w=440').widthOrNull, 440);
      expect(widthInQuery('W=440&w=999').widthOrNull, 440);
    });

    test('读侧（requestedImageWidth）与写侧对同一段字符同一结论', () {
      for (final q in <String>['w=480', 'W=480', ' W = 480 ']) {
        final url = '/a.jpg?$q';
        expect(requestedImageWidth(url), 480, reason: url);
        // 写侧认为「已经有了可用宽度」→ 原样返回（不追加第二个）。
        expect(withImageWidth(url, 640), url, reason: '$url 不该被加第二个 w');
      }
      for (final q in <String>['w=', 'w=0', 'w=-5', 'w=abc']) {
        final url = '/a.jpg?$q';
        expect(requestedImageWidth(url), isNull, reason: url);
        // 写侧把它换成一个可用值（不是再追加一个）。
        final out = withImageWidth(url, 640);
        expect(out, '/a.jpg?w=640', reason: '$url 应被替换而不是追加');
        expect(requestedImageWidth(out), 640, reason: '写进去要能被读侧读回');
      }
    });

    test('契约：`w=` 的键值解析不得再出现第二份', () {
      final src = _lib('media_resize.dart');
      // 只扫代码行：注释里会引用 `indexOf('=')` 作为说明，那不是实现。
      final code = src
          .split('\n')
          .where((l) =>
              !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
          .join('\n');
      // 允许两处：`widthParamOf` 本体与查询串切分（`split('&')`）。
      final indexOfEq = RegExp(r"indexOf\('='\)").allMatches(code).length;
      expect(indexOfEq, 1,
          reason: '`indexOf(\'=\')` 只能出现在 widthParamOf 里（现在是 $indexOfEq 处）');
      final tryParse = RegExp(r'int\.tryParse').allMatches(code).length;
      expect(tryParse, 1,
          reason: '整数的解析只能有一处（现在是 $tryParse 处）');
    });
  });

  group('脱敏判定接上唯一后缀剥除', () {
    test('带查询串/片段的媒体文件名仍能被识别（否则脱敏漏一段路径）', () {
      // 结论层：脱敏后原文件名不得残留。
      for (final raw in <String>[
        'open failed: /media/lib/a.mp4?x=1',
        'open failed: /media/lib/a.mp4#t=3',
        'open failed: /media/lib/a.webp#poster',
      ]) {
        final out = sanitizePlaybackErrorForLog(raw);
        expect(out.contains('a.mp4'), isFalse, reason: out);
        expect(out.contains('a.webp'), isFalse, reason: out);
        expect(out.contains('<path>'), isTrue, reason: out);
      }
    });

    test('契约：playback_error 不得再自己按字符集切后缀', () {
      final src = _lib('playback_error.dart');
      final code = src
          .split('\n')
          .where((l) =>
              !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'))
          .join('\n');
      expect(code.contains("split(RegExp(r'[?&#]'))"), isFalse,
          reason: '后缀剥除只能走 media_path.stripMediaSuffix');
    });
  });

  group('协议相对地址（//cdn/x.jpg）不再被当成库内相对路径', () {
    test('判定与补协议', () {
      expect(isProtocolRelativeUrl('//cdn/x.jpg'), isTrue);
      expect(isProtocolRelativeUrl(' //cdn/x.jpg '), isTrue);
      expect(isProtocolRelativeUrl('/media/x.jpg'), isFalse);
      expect(isProtocolRelativeUrl('//'), isFalse, reason: '太短不算');
      expect(isProtocolRelativeUrl('http://cdn/x.jpg'), isFalse);

      expect(resolveProtocolRelative('http://nas:8090', '//cdn/x.jpg'),
          'http://cdn/x.jpg');
      expect(resolveProtocolRelative('HTTPS://NAS:8090', '//cdn/x.jpg'),
          'https://cdn/x.jpg', reason: '协议名沿用服务器写法的大小写口径');
      expect(resolveProtocolRelative('nas:8090', '//cdn/x.jpg'),
          'https://cdn/x.jpg', reason: '解析不出协议时回落 https，不拼出 `//cdn` 裸地址');
      // 幂等：非协议相对地址原样返回。
      expect(resolveProtocolRelative('http://nas', '/media/x.jpg'), '/media/x.jpg');
    });

    test('libraryMediaPath / absoluteMediaUrl 不再补 /media/<lib>/', () {
      expect(libraryMediaPath('lib', '//cdn/x.jpg'), '//cdn/x.jpg');
      final url = absoluteMediaUrl('http://nas:8090', lib: 'lib', path: '//cdn/x.jpg');
      expect(url, 'http://cdn/x.jpg', reason: '补协议后走绝对地址分支');
      expect(url.contains('/media/'), isFalse);
    });

    test('带协议与协议相对的外链走同一条路径转义', () {
      // 查询串必须原样保留（不能被转成 `%3F`），路径段里的空格必须转义。
      // 两种写法（带协议 / 协议相对）应给出同一条地址，只差协议来源。
      const src = 'cdn/a b.jpg?w=480';
      final a = absoluteMediaUrl('http://nas', lib: 'l', path: 'http://$src');
      final b = absoluteMediaUrl('http://nas', lib: 'l', path: '//$src');
      expect(a.contains('?w=480'), isTrue, reason: a);
      expect(b, a, reason: '协议相对地址补完协议后应与带协议的走完全同一条路径');
    });

    test('契约：绝对/协议相对判定不得再各自写 startsWith', () {
      final cover = _lib('lib_cover.dart');
      expect(cover.contains("startsWith('//')"), isFalse);
      expect(cover.contains('isNetworkMediaUrl(p)'), isTrue);
    });
  });
}

extension on int? {
  int? get widthOrNull => this;
}
