import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/main.dart';

/// 项 6「索引问题」：非默认库必须把 `lib` 带进 `/api/a/*` 与 `/api/authors.json`
/// 请求，服务端据此解析 libidx/<lib>/a/<g*>.json；否则作者页会串到默认库。
void main() {
  group('cfg.u 带库参数', () {
    setUp(() {
      cfg.base = 'http://192.168.2.4:8090';
      cfg.user = 'u';
      cfg.pass = 'p';
      cfg.lib = 'douyin';
      cfg.bindLibrary('itest-a', 'http://192.168.2.4:8090',
          user: 'libuser', pass: 'libpass');
    });

    tearDown(() {
      cfg.base = '';
      cfg.user = 'zzx';
      cfg.pass = '';
      cfg.lib = '';
      cfg.libName = '';
    });

    test('默认库：/api/a/<i>.json 带 lib=douyin', () {
      final u = cfg.u('/api/a/1.json');
      expect(u.host, '192.168.2.4');
      expect(u.path, '/api/a/1.json');
      expect(u.queryParameters['lib'], 'douyin');
    });

    test('非默认库：显式 lib 打到该库连接并带 lib 参数', () {
      final u = cfg.u('/api/a/gaa8e04cdd023e37.json', lib: 'itest-a');
      expect(u.path, '/api/a/gaa8e04cdd023e37.json');
      expect(u.queryParameters['lib'], 'itest-a');
      final au = cfg.u('/api/authors.json', lib: 'itest-a');
      expect(au.queryParameters['lib'], 'itest-a');
      expect(cfg.headersFor('itest-a')['Authorization'], isNotNull);
      expect(cfg.headersFor('itest-a')['Authorization'],
          isNot(cfg.headersFor('douyin')['Authorization']));
    });

    test('未绑定的库回落当前连接但仍带 lib 参数', () {
      final u = cfg.u('/api/authors.json', lib: 'lib-008');
      expect(u.host, '192.168.2.4');
      expect(u.queryParameters['lib'], 'lib-008');
    });
  });
}
