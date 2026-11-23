import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_history.dart';

void main() {
  group('parseCoverVersions', () {
    test('按服务端顺序取最多 5 个，过滤非法版本与空地址', () {
      final json = {
        'ok': true,
        'versions': [
          {'v': 'c20261123120000', 'e': 'jpg', 'u': '/media/l1/_cover/c20261123120000.jpg', 'at': 1, 'current': true},
          {'v': '..', 'e': 'jpg', 'u': '/media/l1/_cover/../x.jpg'},
          {'v': 'c2', 'e': 'webp', 'u': 'https://evil/x.webp'},
          {'v': 'c20261123110000', 'e': 'png', 'u': '/media/l1/_cover/c20261123110000.png', 'at': 2},
          {'v': 'c20261123100000', 'e': 'jpeg', 'u': '/media/l1/_cover/c20261123100000.jpeg', 'at': 3},
          {'v': 'c20261123090000', 'e': 'jpg', 'u': '/media/l1/_cover/c20261123090000.jpg', 'at': 4},
          {'v': 'c20261123080000', 'e': 'jpg', 'u': '/media/l1/_cover/c20261123080000.jpg', 'at': 5},
          {'v': 'c20261123070000', 'e': 'jpg', 'u': '/media/l1/_cover/c20261123070000.jpg', 'at': 6},
        ],
      };
      final out = parseCoverVersions(json);
      expect(out.length, 5);
      expect(out.first.version, 'c20261123120000');
      expect(out.first.current, isTrue);
      expect(out.map((e) => e.version), isNot(contains('..')));
      expect(out.every((e) => e.url.startsWith('/media/')), isTrue);
    });

    test('去重同版本同扩展，非法扩展回落 jpg', () {
      final out = parseCoverVersions({
        'versions': [
          {'v': 'v1', 'e': 'gif', 'u': '/media/l/_cover/v1.jpg'},
          {'v': 'v1', 'e': 'jpg', 'u': '/media/l/_cover/v1.jpg'},
        ],
      });
      expect(out.length, 1);
      expect(out.single.ext, 'jpg');
    });

    test('空/坏数据返回空列表', () {
      expect(parseCoverVersions(null), isEmpty);
      expect(parseCoverVersions({'versions': 'x'}), isEmpty);
      expect(parseCoverVersions(const <String, dynamic>{}), isEmpty);
    });
  });

  group('错误文案', () {
    test('404 提示服务端未升级，未知只报数字', () {
      expect(coverActionErrorText(404), contains('未升级'));
      expect(coverActionErrorText(400), '请求格式不对');
      expect(coverActionErrorText(500), '服务端写入失败');
      expect(coverActionErrorText(418), 'HTTP 418');
    });
  });
}
