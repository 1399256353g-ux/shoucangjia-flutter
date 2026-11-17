// 0.9.28 缩图缓存统计解析（纯函数，不联网）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/resize_cache_api.dart';

void main() {
  test('解析 /api/cache/stats 的完整字段', () {
    final s = ResizeCacheStats.fromJson({
      'files': 728,
      'bytes': 33044212,
      'maxBytes': 1610612736,
      'hit': 90,
      'miss': 10,
      'gen': 12,
      'fail': 1,
      'savedBytes': 500000,
      'servedBytes': 200000,
      'warmQueue': 4,
      'warmActive': 2,
      'hitRate': 0.9,
      'prune': {'runs': 3, 'deleted': 17, 'freed': 1234567},
    })!;
    expect(s.files, 728);
    expect(s.bytes, 33044212);
    expect(s.hitRate, closeTo(0.9, 1e-9));
    expect(s.hitRateText, '90.0%');
    expect(s.usedPercent, 2);
    expect(s.pruneDeleted, 17);
    expect(s.usageText, contains('31.5 MB'));
    expect(s.usageText, contains('1.50 GB'));
    expect(s.countersText, contains('命中 90'));
    expect(s.countersText, contains('预热队列 4'));
  });

  test('字段缺失不抛异常，命中率按 hit/miss 计算', () {
    final s = ResizeCacheStats.fromJson({'hit': 3, 'miss': 1})!;
    expect(s.files, 0);
    expect(s.maxBytes, 0);
    expect(s.hitRate, closeTo(0.75, 1e-9));
    expect(s.usedPercent, isNull); // 上限未知
    expect(s.usageText, '0 B');
    expect(s.countersText, contains('命中 3'));
  });

  test('非对象 JSON 返回 null', () {
    expect(ResizeCacheStats.fromJson(null), isNull);
    expect(ResizeCacheStats.fromJson('nope'), isNull);
    expect(ResizeCacheStats.fromJson([1, 2]), isNull);
  });

  test('字节格式化边界', () {
    expect(ResizeCacheStats.bytesText(0), '0 B');
    expect(ResizeCacheStats.bytesText(-5), '0 B');
    expect(ResizeCacheStats.bytesText(512), '512 B');
    expect(ResizeCacheStats.bytesText(2048), '2.0 KB');
    expect(ResizeCacheStats.bytesText(5 * 1024 * 1024), '5.0 MB');
    expect(ResizeCacheStats.bytesText(3 * 1024 * 1024 * 1024), '3.00 GB');
  });
}
