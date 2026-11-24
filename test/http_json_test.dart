import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shoucangjia/http_json.dart';

void main() {
  group('jsonOfBytes 按 UTF-8 解，不看响应头', () {
    test('中文 JSON 正常解析', () {
      final bytes = utf8.encode('{"name":"作者甲","n":3}');
      final j = jsonOfBytes(bytes) as Map;
      expect(j['name'], '作者甲');
      expect(j['n'], 3);
    });

    test('text/html 头下 Response.body 会乱码，jsonOf 仍然正确', () {
      // 这不是假想：`http` 包的 Response.body 只在 content-type 为
      // application/json（且无 charset）时才走 utf8，其余一律 latin1。
      // 服务端换一个 content-type，整片中文就会变成 ä½èè…
      final bytes = utf8.encode('{"name":"作者甲"}');
      final asHtml = http.Response.bytes(bytes, 200,
          headers: {'content-type': 'text/html; charset=iso-8859-1'});
      final asOctet = http.Response.bytes(bytes, 200,
          headers: {'content-type': 'application/octet-stream'});

      // 旧写法（.body）在这两种头下都读不出中文。
      expect(asHtml.body.contains('作者甲'), isFalse);
      expect(asOctet.body.contains('作者甲'), isFalse);

      // 新写法不受任何头影响。
      expect((jsonOf(asHtml) as Map)['name'], '作者甲');
      expect((jsonOf(asOctet) as Map)['name'], '作者甲');
    });

    test('application/json 头下两条路径结果一致（回归基准）', () {
      final bytes = utf8.encode('{"name":"作者甲"}');
      final ok = http.Response.bytes(bytes, 200,
          headers: {'content-type': 'application/json'});
      expect(ok.body.contains('作者甲'), isTrue);
      expect((jsonOf(ok) as Map)['name'], '作者甲');
    });

    test('非 UTF-8 字节当场抛错，不静默替换成 U+FFFD', () {
      // 0xFF 在 UTF-8 里非法。用 allowMalformed 会变成 '\uFFFD'，
      // 于是坏数据看起来像正常数据——宁可抛。
      expect(() => jsonOfBytes([0x7B, 0xFF, 0x7D]),
          throwsA(isA<FormatException>()));
    });

    test('jsonMapOf 返回 Map，非对象时报错而不是返回空 Map', () {
      final obj = http.Response.bytes(utf8.encode('{"a":1}'), 200);
      expect(jsonMapOf(obj)['a'], 1);
      final arr = http.Response.bytes(utf8.encode('[1,2]'), 200);
      expect(() => jsonMapOf(arr), throwsA(isA<TypeError>()));
    });

    test('jsonObjectOrEmpty 失败时给空 Map，不把解析异常抛给调用方', () {
      expect(
          jsonObjectOrEmpty(
              http.Response.bytes(utf8.encode('{"a":1}'), 200))['a'],
          1);
      // 非对象 / 坏字节 / 空体：一律空 Map（调用方据此回落到状态码文案）。
      expect(jsonObjectOrEmpty(http.Response.bytes(utf8.encode('[1,2]'), 200)),
          isEmpty);
      expect(jsonObjectOrEmpty(http.Response.bytes([0x7B, 0xFF, 0x7D], 500)),
          isEmpty);
      expect(jsonObjectOrEmpty(http.Response('', 502)), isEmpty);
      // 合法对象照常返回（哪怕 ok:false —— 判定交给 apiFailureText）。
      final m = jsonObjectOrEmpty(http.Response('{"ok":false}', 400));
      expect(m['ok'], false);
      m['x'] = 1; // 可写，不抛
      expect(jsonObjectOrEmpty(http.Response('{"a":1}', 200)),
          isA<Map<String, dynamic>>());
    });
  });

  group('apiFailureText：写接口收尾的唯一判定', () {
    test('200 + ok:true 才算成功（null）', () {
      expect(apiFailureText(200, {'ok': true}), isNull);
      expect(apiFailureText(200, {'ok': true, 'u': '/x.jpg'}), isNull);
    });

    test('ok 缺失/为假/false 字符串都算失败', () {
      expect(apiFailureText(200, {'ok': false}), isNotNull);
      expect(apiFailureText(200, {'ok': 'true'}), isNotNull);
      expect(apiFailureText(200, {}), isNotNull);
      expect(apiFailureText(200, null), isNotNull);
      expect(apiFailureText(200, [1, 2]), isNotNull);
    });

    test('服务端 error 文案优先，且必须是非空字符串', () {
      expect(apiFailureText(400, {'ok': false, 'error': '文件名非法'}), '文件名非法');
      expect(apiFailureText(400, {'ok': false, 'error': '   '}), '请求格式不对');
      // 非字符串的 error 不得被插值成 `{code: 500}` 之类贴到界面上。
      expect(
          apiFailureText(400, {
            'ok': false,
            'error': {'code': 500}
          }),
          '请求格式不对');
      expect(apiFailureText(400, {'ok': false, 'error': 500}), '请求格式不对');
    });

    test('没有 error 时按状态码归类（与 httpErrorText 同源）', () {
      expect(apiFailureText(400, {'ok': false}), '请求格式不对');
      expect(apiFailureText(413, null), '图片过大');
      expect(apiFailureText(500, {'ok': false}), '服务端写入失败');
      expect(apiFailureText(401, {'ok': false}), 'HTTP 401');
      expect(apiFailureText(418, null), 'HTTP 418');
    });

    test('业务可覆盖状态码文案（如头像 404 特指）', () {
      expect(
        apiFailureText(404, {'ok': false},
            statusText: (s) => s == 404 ? '基础库或头像文件不存在' : 'HTTP $s'),
        '基础库或头像文件不存在',
      );
      // 服务端自带 error 时仍然优先，不被覆盖函数顶掉。
      expect(
        apiFailureText(404, {'ok': false, 'error': '服务端说的原因'},
            statusText: (_) => '兜底文案'),
        '服务端说的原因',
      );
    });

    test('非 200 但 body 带 ok:true 仍算失败（状态码是硬门槛）', () {
      expect(apiFailureText(500, {'ok': true}), '服务端写入失败');
      expect(apiFailureText(302, {'ok': true}), 'HTTP 302');
    });
  });

  group('requireOk:false —— 读接口的老契约（只认「没显式说失败」）', () {
    test('200 且缺 ok 字段算成功（写接口语义下会误报）', () {
      // 这两条是同一个函数在同一种响应上的两种结论：老读接口根本不发 ok，
      // 用写接口的口径会把每一次成功的 GET 都变成「未知失败」。
      expect(apiFailureText(200, {'path': '/x'}, requireOk: false), isNull);
      expect(apiFailureText(200, {'path': '/x'}), isNotNull);
      expect(apiFailureText(200, null, requireOk: false), isNull);
    });

    test('显式 ok:false / 非 200 仍然失败', () {
      expect(apiFailureText(200, {'ok': false}, requireOk: false), isNotNull);
      expect(apiFailureText(404, {'path': '/'}, requireOk: false), 'HTTP 404');
      expect(
          apiFailureText(500, {'ok': false, 'error': '写盘失败'},
              requireOk: false),
          '写盘失败');
    });

    test('body 不是 Map 时不炸（旧写法 j[error] 会抛 NoSuchMethodError）', () {
      expect(apiFailureText(200, <int>[1, 2], requireOk: false), isNull);
      expect(apiFailureText(502, 'plain text', requireOk: false), 'HTTP 502');
    });
  });

  group('throwIfApiFailed：读接口的 throw 出口', () {
    test('成功不抛，失败抛 Exception 且 message 可直接展示', () {
      expect(() => throwIfApiFailed(200, {'path': '/'}), returnsNormally);
      expect(
        () => throwIfApiFailed(404, {'path': '/'}),
        throwsA(isA<Exception>()
            .having((e) => e.toString(), 'message', contains('HTTP 404'))),
      );
    });

    test('error 非字符串时给出状态码文案，而不是把对象贴到界面', () {
      Object? caught;
      try {
        throwIfApiFailed(400, {'ok': false, 'error': {'code': 400}});
      } catch (e) {
        caught = e;
      }
      expect('$caught', contains('请求格式不对'));
      expect('$caught', isNot(contains('code:')));
    });
  });
}
