import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';

void main() {
  setUp(() => LibraryBadge.custom.clear());

  test('自动配色按库注册顺序分配且不同库不同色', () {
    final a = LibraryBadge.colorFor('douyin', order: ['douyin', 'second']);
    final b = LibraryBadge.colorFor('second', order: ['douyin', 'second']);
    expect(a, LibraryBadge.palette[0]);
    expect(b, LibraryBadge.palette[1]);
    expect(a, isNot(b));
  });

  test('自定义颜色优先，恢复自动后回到调色板', () {
    final auto = LibraryBadge.colorFor('douyin', order: ['douyin']);
    LibraryBadge.custom['douyin'] = 0xFF123456;
    expect(LibraryBadge.colorFor('douyin', order: ['douyin']), 0xFF123456);
    LibraryBadge.custom.remove('douyin');
    expect(LibraryBadge.colorFor('douyin', order: ['douyin']), auto);
  });

  test('未知库按 id 稳定散列，同一 id 颜色恒定', () {
    final c1 = LibraryBadge.colorFor('unknown-lib');
    final c2 = LibraryBadge.colorFor('unknown-lib', order: ['x', 'y']);
    expect(c1, c2);
    expect(LibraryBadge.palette, contains(c1));
  });

  test('词条文字颜色按底色亮度取黑或白', () {
    expect(LibraryBadge.textColorOn(0xFFFFFFFF), 0xFF111827);
    expect(LibraryBadge.textColorOn(0xFF000000), 0xFFFFFFFF);
    expect(LibraryBadge.textColorOn(0xFF2563EB), 0xFFFFFFFF);
  });

  test('词条折叠：最多两个，多余显示 +N，去重且忽略空 id', () {
    expect(LibraryBadge.labels(['a', 'b', 'c'], names: {'a': '抖音', 'b': '备份'}),
        ['抖音', '备份', '+1']);
    expect(LibraryBadge.labels(['a', 'a', '']), ['a']);
    expect(LibraryBadge.labels([]), isEmpty);
  });

  test('颜色设置解析容错并支持 #RRGGBB 文本', () {
    expect(LibraryBadge.parse('not json'), isEmpty);
    expect(LibraryBadge.parse('{"douyin": "#ff8800"}')['douyin'], 0xFFFF8800);
    expect(LibraryBadge.parse('{"douyin": 4278255360}')['douyin'], 4278255360);
    expect(LibraryBadge.parse('{"bad": "zzz"}').containsKey('bad'), false);
  });

  test('设置序列化可往返', () {
    final m = {'douyin': 0xFF112233, 'other': 0xFF445566};
    final raw = LibraryBadge.encode(source: m);
    expect(LibraryBadge.parse(raw), m);
  });
}
