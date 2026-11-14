import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/likes.dart';

void main() {
  test('workLikeKey 带库前缀且忽略空 id', () {
    expect(workLikeKey(lib: 'douyin', id: '123'), 'douyin/123');
    expect(workLikeKey(lib: '', id: '123'), '123');
    expect(workLikeKey(lib: 'douyin', id: '  '), '');
    expect(workLikeKey(lib: '', id: ''), '');
  });

  test('parseLikedKeys 去空、去重、容错 null', () {
    expect(parseLikedKeys(null), isEmpty);
    expect(parseLikedKeys([' a ', '', 'a', 'b']), {'a', 'b'});
  });

  test('updateLikedKeys 添加与取消，结果稳定排序', () {
    expect(updateLikedKeys(['b'], 'a', liked: true), ['a', 'b']);
    expect(updateLikedKeys(['a', 'b'], 'a', liked: false), ['b']);
    expect(updateLikedKeys(['a'], 'a', liked: true), ['a']);
    expect(updateLikedKeys(['a'], '', liked: true), ['a']);
  });

  test('双击判定：320ms 内且位移小于 80px', () {
    expect(
        isStageDoubleTap(
            nowMs: 200,
            lastMs: 0,
            lastPos: Offset.zero,
            pos: Offset.zero),
        isFalse);
    expect(
        isStageDoubleTap(
            nowMs: 500,
            lastMs: 300,
            lastPos: const Offset(10, 10),
            pos: const Offset(20, 20)),
        isTrue);
    expect(
        isStageDoubleTap(
            nowMs: 700,
            lastMs: 300,
            lastPos: const Offset(10, 10),
            pos: const Offset(20, 20)),
        isFalse);
    expect(
        isStageDoubleTap(
            nowMs: 500,
            lastMs: 300,
            lastPos: Offset.zero,
            pos: const Offset(100, 100)),
        isFalse);
    expect(
        isStageDoubleTap(
            nowMs: 500, lastMs: 300, lastPos: null, pos: Offset.zero),
        isFalse);
  });
}
