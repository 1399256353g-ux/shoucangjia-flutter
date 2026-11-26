/// 第五十八批契约：**「同一组判定」的第三份写法藏在两个不同文件里**。
///
/// 前几批修的是「同一条规则两个实现」，形态越来越隐蔽：
/// 第五十七批是同一段字符串读写两侧各解析一遍；这一批是**同一组规则被拆成
/// 两种载体**——一处写成正则、一处写成常量表；一处是「服务端能吃吗」、
/// 一处是「能显示吗」，而调用点按需要各挑一个。
///
/// 本批修掉的四处（修复前实测）：
///
///  1. 「服务端能处理这个图片格式吗」有两个实现：`media_resize._imageExt`
///     （`RegExp(r'\.(jpe?g|png|webp)$')`，决定加不加 `?w=`）与
///     `author_avatar_store.isServerAvatarFileName` 里的同义正则（决定能不能
///     注册头像）。同一组四个扩展名写两遍，服务端加/减一种格式时必然漏一处。
///  2. `hostLabelOf` 自己写 `raw.contains('://') ? raw : 'http://$raw'`——
///     这是「这个串有没有协议」的第三份实现（前两份是 `normalizeBase` 与
///     `api_url.baseForJoin`），而且**比它们窄**：全角冒号 `nas：8090` 被当成
///     主机名，卡片底部露出 `nas%EF%BC%9A8090`。
///  3. 服务端 `ok` 字段的判定在 9 处各写一遍（`j['ok'] == true` / `!= true` /
///     `!= false`），写接口的「严格」与老读接口的「宽松」两种语义混在调用点。
///  4. 「往已拼好的地址追加查询参数」两处各写一遍，其中一处假设 base 里
///     没有查询串——带口令的网关地址会把 path 整段塞进查询串。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/api_url.dart';
import 'package:shoucangjia/author_avatar_store.dart';
import 'package:shoucangjia/cover_ext.dart';
import 'package:shoucangjia/http_json.dart';
import 'package:shoucangjia/media_resize.dart';
import 'package:shoucangjia/unit_library_view.dart';

String _lib(String name) => File('lib/$name').readAsStringSync();

/// 去掉整行注释后的源码（契约扫描只看真代码）。
String _code(String name) => _lib(name)
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('服务端能处理的图片格式只有一条判定', () {
    test('四个扩展名 + 大小写 + 后缀剥除', () {
      for (final p in <String>[
        '/a.jpg',
        '/a.JPG',
        '/a.jpeg',
        '/a.jpeg?w=480',
        '/a.png#poster',
        'a.webp',
      ]) {
        expect(isServerImagePath(p), isTrue, reason: '$p 服务端能吃');
      }
      for (final p in <String>[
        '/a.gif',
        '/a.heic',
        '/a.avif',
        '/a.bmp',
        '/a.mp4',
        '/a',
        '',
      ]) {
        expect(isServerImagePath(p), isFalse, reason: '$p 服务端不吃');
      }
    });

    test('缩图参数与头像注册对同一路径给出同一答案', () {
      // 三个调用点必须一致：加不加 `?w=`、能不能注册成头像。
      for (final p in <String>['/a.jpg', '/a.png', '/a.gif', '/a.heic']) {
        final resized = withImageWidth(p, 480);
        final registered = isServerAvatarFileName(p.split('/').last);
        expect(resized.contains('w=480'), isServerImagePath(p),
            reason: '$p：缩图通道与服务端格式判定必须同源');
        expect(registered, isServerImagePath(p),
            reason: '$p：头像注册与服务端格式判定必须同源');
      }
    });

    test('契约：`(jpe?g|png|webp)` 只允许出现在 cover_ext', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('cover_ext.dart')) continue;
        if (_code(f.path.substring(4)).contains('jpe?g|png|webp')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: '服务端图片格式白名单又抄了一份：$offenders');
      // 白名单成员仍然只有一份（`kCoverExts`），判定只有一份。
      final ce = _code('cover_ext.dart');
      expect(ce.contains('bool isServerImagePath(String p)'), isTrue);
      expect(RegExp(r'kCoverExts\.contains\(e\)').allMatches(ce).length, 2,
          reason: '白名单判定只允许「显式 e」与「文件名里的 e」两处');
    });
  });

  group('主机标注走连接地址的同一条归一', () {
    test('全角冒号/全角数字与大写协议都能归一出主机', () {
      // 修复前：`nas：8090` → `nas%EF%BC%9A8090`；`http://NAS:８０９０` → 整串回落。
      expect(hostLabelOf('nas：8090'), 'nas:8090');
      expect(hostLabelOf('http://NAS:８０９０'), 'nas:8090');
      expect(hostLabelOf('HTTP://nas:8090'), 'nas:8090');
      expect(hostLabelOf('http://nas:8090/路径'), 'nas:8090');
    });

    test('归不出可连接地址时原样返回，不吞掉用户配的串', () {
      expect(hostLabelOf(''), '');
      expect(hostLabelOf('   '), '');
      expect(hostLabelOf('http://'), 'http://');
      expect(hostLabelOf('//nas:8090'), '//nas:8090');
    });

    test('契约：hostLabelOf 不得自己判协议', () {
      final src = _code('unit_library_view.dart');
      expect(src.contains("contains('://') ? raw : 'http://\$raw'"), isFalse,
          reason: '「有没有协议」的判定必须走 normalizeBase/baseForJoin');
      expect(src.contains('baseForJoin(raw)'), isTrue);
    });
  });

  group('服务端 ok 字段的判定只有一处', () {
    test('严格：只有真 true 才算成功', () {
      expect(serviceSaidOk({'ok': true}), isTrue);
      for (final v in <dynamic>[{'ok': 1}, {'ok': 'true'}, {}, null, 'ok']) {
        expect(serviceSaidOk(v), isFalse, reason: '严格判定不接受 $v');
      }
    });

    test('宽松：只有显式 false 才算失败（老读接口契约）', () {
      expect(serviceSaidFail({'ok': false}), isTrue);
      for (final v in <dynamic>[{'ok': true}, {'ok': 0}, {}, null]) {
        expect(serviceSaidFail(v), isFalse, reason: '老契约不把 $v 当失败');
      }
    });

    test('apiFailureText 两种契约与这两个函数完全同步', () {
      for (final v in <dynamic>[
        {'ok': true},
        {'ok': false},
        {'ok': 'true'},
        {},
      ]) {
        expect(apiFailureText(200, v) == null, serviceSaidOk(v),
            reason: '严格契约：$v');
        expect(apiFailureText(200, v, requireOk: false) == null,
            !serviceSaidFail(v),
            reason: '宽松契约：$v');
      }
    });

    test('契约：lib/ 里不再出现裸的 ok 布尔比较', () {
      final bad = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('http_json.dart')) continue;
        final c = _code(f.path.substring(4));
        if (RegExp(r"\['ok'\]\s*[!=]=\s*(true|false)").hasMatch(c)) {
          bad.add(f.path);
        }
      }
      expect(bad, isEmpty, reason: 'ok 判定又写回去了：$bad');
    });
  });

  group('往已拼好的地址追加参数只有一处', () {
    test('base 自带查询串时保留它，path 不被塞进查询串', () {
      // 修复前：`http://nas:8090/?token=x` + `/api/settings`
      //        → `http://nas:8090/?token=x/api/settings`（路径整段进了查询串）。
      expect(joinApiUrl('http://nas:8090/?token=x', '/api/settings'),
          'http://nas:8090/api/settings?token=x');
      expect(
          joinApiUrl('http://nas:8090/?token=x', '/api/settings',
              query: {'lib': 'a b'}),
          'http://nas:8090/api/settings?token=x&lib=a+b');
    });

    test('追加参数：`?`/`&` 自动选，键值都编码', () {
      expect(withQueryParam('http://h:1/api/x', 'k', 'v'), 'http://h:1/api/x?k=v');
      expect(withQueryParam('http://h:1/api/cover/versions?lib=A', 'unitRel', '(2) 丝'),
          'http://h:1/api/cover/versions?lib=A&unitRel=%282%29+%E4%B8%9D');
      expect(withQueryParam('http://h:1/a', '', 'v'), 'http://h:1/a');
    });

    test('契约：分隔符判定不得在调用点各写一遍', () {
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('api_url.dart')) continue;
        final c = _code(f.path.substring(4));
        if (c.contains("contains('?') ? '&' : '?'")) offenders.add(f.path);
      }
      expect(offenders, isEmpty, reason: '查询串分隔符又写了一遍：$offenders');
      // 集合同步设置不能假设 base 里没有查询串
      expect(_code('collection_sync_panel.dart').contains('_settingsUri'),
          isTrue);
      expect(_code('collection_sync_panel.dart').contains("/api/settings\$q"),
          isFalse,
          reason: '`\$base/api/settings\$q` 在 base 带查询串时会把路径塞进查询串');
    });
  });

  group('头像目录里的非白名单格式必须给出可见提示', () {
    test('目录判定认 `.avatars` 与百分号编码的变体', () {
      expect(isServerAvatarDirPath('/media/lib/.avatars/a.jpg'), isTrue);
      expect(isServerAvatarDirPath('/media/lib/%2Eavatars/a.jpg'), isTrue);
      expect(isServerAvatarDirPath('/media/lib/@作者/_avatar/a.jpg'), isFalse);
      expect(isServerAvatarDirPath(''), isFalse);
      expect(isServerAvatarDirPath(null), isFalse);
    });

    test('候选「目录里但注册不了」的判定与白名单同源', () {
      // gif 在 `.avatars` 里能显示（`isAvatarImagePath` 收），但注册不了。
      const gif = '/media/lib/.avatars/a.gif';
      expect(isServerAvatarDirPath(gif), isTrue);
      expect(isServerAvatarFileName('a.gif'), isFalse,
          reason: '这一对正是「点了没反应」的来源，现在有提示分支');
    });
  });
}
