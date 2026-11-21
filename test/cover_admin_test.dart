import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_admin.dart';

void main() {
  group('CoverRequest', () {
    test('设置：请求体带 lib 与 work', () {
      final r = CoverRequest.set(lib: 'lib-001', work: '7401');
      expect(r.op, CoverOp.set);
      expect(r.toBody(), {'lib': 'lib-001', 'work': '7401'});
      expect(r.valid, isTrue);
      expect(r.doneText, contains('已设为该库封面'));
      expect(r.failText, '设置封面失败');
    });

    test('视频：请求体带当前播放秒数（0 秒也要带上）', () {
      final r = CoverRequest.set(lib: 'lib-001', work: 'w1', at: 12.5);
      expect(r.toBody(), {'lib': 'lib-001', 'work': 'w1', 'at': 12.5});
      expect(CoverRequest.set(lib: 'lib-001', work: 'w1', at: 0).toBody()['at'], 0);
    });

    test('图文/单图：请求体带当前图片序号', () {
      final r = CoverRequest.set(lib: 'lib-001', work: 'w2', index: 3);
      expect(r.toBody(), {'lib': 'lib-001', 'work': 'w2', 'index': 3});
      expect(r.toBody().containsKey('at'), isFalse);
    });

    test('清除：即使带 at/index 也不发', () {
      final r = CoverRequest.clear(lib: 'lib-001');
      expect(r.toBody(), {'lib': 'lib-001', 'clear': true});
    });

    test('清除：只带 clear 标记，不带 work', () {
      final r = CoverRequest.clear(lib: 'lib-001');
      expect(r.op, CoverOp.clear);
      expect(r.toBody(), {'lib': 'lib-001', 'clear': true});
      expect(r.toBody().containsKey('work'), isFalse);
      expect(r.valid, isTrue);
      expect(r.doneText, contains('恢复自动封面'));
      expect(r.failText, '清除封面失败');
    });

    test('缺库或缺作品 id 时不发请求', () {
      expect(const CoverRequest.clear(lib: '  ').valid, isFalse);
      expect(CoverRequest.set(lib: 'lib-001', work: '').valid, isFalse);
      expect(CoverRequest.set(lib: '', work: '7401').valid, isFalse);
    });

    test('状态码翻译：已知给原因，未知只报数字', () {
      expect(coverErrorText(404), contains('没有可用图片'));
      expect(coverErrorText(400), '请求格式不对');
      expect(coverErrorText(500), '服务端写入失败');
      expect(coverErrorText(418), 'HTTP 418');
    });
  });
}
