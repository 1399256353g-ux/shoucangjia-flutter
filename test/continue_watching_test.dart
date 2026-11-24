import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/continue_watching.dart';

ContinueItem item({
  String lib = 'douyin',
  String id = '1',
  int idx = 3,
  String collection = '收藏夹',
  int pos = 30000,
  int dur = 120000,
  int updated = 1000,
}) =>
    ContinueItem(
      lib: lib,
      id: id,
      idx: idx,
      collection: collection,
      title: '标题$id',
      author: '作者$id',
      thumb: '/media/x/$id.jpg',
      type: 'v',
      positionMs: pos,
      durationMs: dur,
      updatedAt: updated,
    );

void main() {
  test('候选判定：太靠前、已看完、接近片尾都不显示', () {
    expect(isContinueCandidate(item(pos: 500)), isFalse);
    expect(isContinueCandidate(item(pos: 30000, dur: 120000)), isTrue);
    expect(isContinueCandidate(item(pos: 117000, dur: 120000)), isFalse);
    expect(isContinueCandidate(item(pos: 115000, dur: 120000)), isFalse);
    expect(isContinueCandidate(item(pos: 30000, dur: 0)), isTrue);
  });

  test('插入按最近观看时间降序，同库同作品覆盖而非重复', () {
    var list = upsertContinueItems([], item(id: '1', updated: 1000));
    list = upsertContinueItems(list, item(id: '2', updated: 2000));
    expect(list.map((e) => e.id), ['2', '1']);
    list = upsertContinueItems(list, item(id: '1', pos: 60000, updated: 3000));
    expect(list.length, 2);
    expect(list.first.id, '1');
    expect(list.first.positionMs, 60000);
  });

  test('已看完的条目会被移出列表', () {
    var list = upsertContinueItems([], item(id: '1'));
    list = upsertContinueItems(
        list, item(id: '1', pos: 119000, dur: 120000, updated: 2000));
    expect(list, isEmpty);
  });

  test('上限截断与移除', () {
    var list = <ContinueItem>[];
    for (var i = 1; i <= kContinueLimit + 3; i++) {
      list = upsertContinueItems(list, item(id: '$i', updated: i));
    }
    expect(list.length, kContinueLimit);
    expect(list.first.id, '${kContinueLimit + 3}');
    final removed = removeContinueItem(list, 'douyin', list.first.id);
    expect(removed.length, kContinueLimit - 1);
    expect(removed.any((e) => e.id == list.first.id), isFalse);
  });

  test('解析容错：坏 JSON、非法条目、重复 key', () {
    expect(parseContinueItems(null), isEmpty);
    expect(parseContinueItems('not json'), isEmpty);
    expect(parseContinueItems('{"a":1}'), isEmpty);
    final raw = '[{"l":"douyin","i":"1","p":5000,"d":10000,"u":1},'
        '{"l":"douyin","i":"1","p":9000,"d":10000,"u":2},'
        '{"i":"","p":1000},{"i":"2","p":-5}]';
    final list = parseContinueItems(raw);
    expect(list.length, 1);
    expect(list.first.positionMs, 5000);
    expect(list.first.label, '未命名作品');
  });

  test('编码后可原样解析', () {
    final list = [item(id: '1'), item(id: '2', updated: 2000)];
    final back = parseContinueItems(encodeContinueItems(list));
    expect(back.length, 2);
    expect(back.first.id, '1');
    expect(back.first.collection, '收藏夹');
  });

  test('写盘节流：同作品同收藏夹小位移跳过，换收藏夹/换作品不跳过', () {
    final prev = item(pos: 30000);
    expect(shouldSkipContinueRecord(prev, item(pos: 30500)), isTrue);
    expect(
        shouldSkipContinueRecord(prev, item(pos: 30000 + kContinueThrottleMs)),
        isFalse);
    expect(
        shouldSkipContinueRecord(prev, item(pos: 30200, collection: '另一个收藏夹')),
        isFalse);
    expect(shouldSkipContinueRecord(prev, item(id: '2', pos: 30200)), isFalse);
  });

  test('Store.record：换收藏夹立即落库，同收藏夹小位移被节流', () {
    ContinueWatchingStore.resetForTest();
    ContinueWatchingStore.record(item(pos: 30000, updated: 1), force: true);
    expect(ContinueWatchingStore.items.single.collection, '收藏夹');

    // 同收藏夹、位置只前进 500ms → 节流，不写。
    ContinueWatchingStore.record(item(pos: 30500, updated: 2));
    expect(ContinueWatchingStore.items.single.positionMs, 30000);

    // 换收藏夹（换条）即使位移很小也要立刻记录。
    ContinueWatchingStore.record(
        item(pos: 30600, collection: '另一个收藏夹', updated: 3));
    expect(ContinueWatchingStore.items.single.collection, '另一个收藏夹');
    expect(ContinueWatchingStore.items.single.positionMs, 30600);
    ContinueWatchingStore.resetForTest();
  });
}
