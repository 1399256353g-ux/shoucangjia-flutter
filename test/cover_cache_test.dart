import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_cache.dart';

void main() {
  tearDown(() {
    DiziCache.maxMb = DiziCache.defaultMaxMb;
    DiziCache.keepDays = DiziCache.defaultKeepDays;
    DiziCache.autoClean = DiziCache.defaultAutoClean;
    DiziCache.rootDir = '';
  });

  test('字节格式化', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(1024), '1.0 KB');
    expect(formatBytes(1024 * 1024), '1.0 MB');
    expect(formatBytes(1536 * 1024), '1.5 MB');
  });

  test('上限与条目数由设置推导', () {
    DiziCache.maxMb = 128;
    expect(DiziCache.maxBytes, 128 * 1024 * 1024);
    expect(DiziCache.objectLimit, 512);
    DiziCache.maxMb = 2048;
    expect(DiziCache.objectLimit, 8192);
  });

  test('Windows 缓存目录固定在 E 盘', () {
    expect(kWindowsCacheDir.startsWith(r'E:\'), isTrue);
    expect(kWindowsCacheDir.toLowerCase().contains('c:'), isFalse);
  });

  test('关闭自动清理时 sweep 不删任何文件', () async {
    final dir = await Directory.systemTemp.createTemp('dizi_cache_test');
    DiziCache.rootDir = dir.path;
    DiziCache.autoClean = false;
    final f = File('${dir.path}/a.bin');
    await f.writeAsBytes(List<int>.filled(32, 0));
    DiziCache.maxMb = 128;
    final freed = await DiziCache.sweep();
    expect(freed, 0);
    expect(await f.exists(), isTrue);
    await dir.delete(recursive: true);
  });

  test('超容量按最久未使用淘汰', () async {
    final dir = await Directory.systemTemp.createTemp('dizi_cache_lru');
    DiziCache.rootDir = dir.path;
    DiziCache.autoClean = true;
    DiziCache.keepDays = 30;
    DiziCache.maxMb = 128; // 128 MB
    final old = File('${dir.path}/old.bin');
    await old.writeAsBytes(List<int>.filled(16, 0));
    // 造一个超过上限的大文件（128MB + 1）
    final big = File('${dir.path}/big.bin');
    await big.writeAsBytes(List<int>.filled(128 * 1024 * 1024 + 1, 0));
    await old.setLastModified(DateTime.now().subtract(const Duration(days: 40)));
    final freed = await DiziCache.sweep();
    expect(freed, greaterThan(0));
    expect(await big.exists(), isFalse);

    final usage = await DiziCache.measure();
    expect(usage.bytes, lessThanOrEqualTo(DiziCache.maxBytes));
    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
