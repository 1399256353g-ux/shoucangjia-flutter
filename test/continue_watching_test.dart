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
  test('位置文案：分秒/时分秒，时长缺失时只显示位置', () {
    expect(formatContinueDuration(0), '');
    expect(formatContinueDuration(83000), '1:23');
    expect(formatContinueDuration(3723000), '1:02:03');
    expect(formatContinueLabel(83000, 310000), '1:23 / 5:10');
    expect(formatContinueLabel(83000, 0), '1:23');
    expect(formatContinueLabel(0, 310000), '5:10');
  });

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

  test('续播位置回退 1 秒并夹紧', () {
    expect(continueResumeMs(item(pos: 500)), 500);
    expect(continueResumeMs(item(pos: 30000)), 29000);
    expect(continueResumeMs(item(pos: 0)), 0);
    expect(continueResumeMs(item(pos: 120000, dur: 120000)), 0);
  });
}
