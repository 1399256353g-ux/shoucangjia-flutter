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
  });
}
