import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_cache.dart';

void main() {
  group('DiziCache 按库登记（快速刷新第 3 步）', () {
    test('按库登记后能精确淘汰，不同库互不干扰', () async {
      DiziCache.noteUrl('lib-001', 'http://h/api/media/lib-001/a.jpg?w=480');
      DiziCache.noteUrl('lib-001', 'http://h/api/media/lib-001/b.jpg?w=480');
      DiziCache.noteUrl('lib-002', 'http://h/api/media/lib-002/c.jpg?w=480');
      // 真实路径消费的事实是「按库淘汰时能删掉几条」，不再是一个只读计数 getter。
      expect(await DiziCache.evictLib('lib-002'), 1);
      expect(await DiziCache.evictLib('lib-999'), 0);
    });

    test('同一 URL 重复登记不会重复计数（淘汰只删一次）', () async {
      const u = 'http://h/api/media/lib-003/x.jpg?w=480';
      DiziCache.noteUrl('lib-003', u);
      DiziCache.noteUrl('lib-003', u);
      expect(await DiziCache.evictLib('lib-003'), 1);
      expect(await DiziCache.evictLib('lib-003'), 0);
    });

    test('空库 id / 空 URL 被忽略（不产生垃圾桶）', () async {
      DiziCache.noteUrl('', 'http://h/x.jpg');
      DiziCache.noteUrl('lib-004', '   ');
      expect(await DiziCache.evictLib('lib-004'), 0);
    });

    test('URL 改属另一个库时从旧库桶里移除', () async {
      const u = 'http://h/api/media/moved.jpg?w=480';
      DiziCache.noteUrl('lib-005', u);
      DiziCache.noteUrl('lib-006', u);
      expect(await DiziCache.evictLib('lib-005'), 0);
      expect(await DiziCache.evictLib('lib-006'), 1);
    });
  });
}
