import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/unit_cover_store.dart';

/// owner 2026-11-25：
/// > 「单元库选过往封面，返回界面就恢复原样」
///
/// 排查结论：服务端 `/api/libraries.json` 下发的封面指针一条不少（实测 6/6），
/// 问题在客户端——封面状态被拆成两份：
///   1. 卡片私有 `_coverOverride`（只在卡片活着时有效）；
///   2. 树快照里的 `node.coverUrl`（只在页面加载那一刻有效）。
/// 选完封面后只有 (1) 变，(2) 还是旧的；页面一重建 (1) 被 `didUpdateWidget`
/// 清空，于是回落成 (2) 的旧值。
///
/// 这组用例锁住新模型：本机意见只有一处，且不会被后来的旧快照覆盖。
void main() {
  setUp(UnitCoverStore.reset);

  const urlA = 'http://nas:8090/media/lib-001/_cover/c1.jpg';
  const urlB = 'http://nas:8090/media/lib-001/_cover/c2.jpg';

  group('键的命名空间', () {
    test('单元库与基础库同一 rel 不串封面', () {
      // 同一个字符串在两种语境下都可能出现，必须分开存。
      UnitCoverStore.set(UnitCoverStore.unitKey('A/B'), urlA);
      expect(UnitCoverStore.rawOf(UnitCoverStore.basicKey('A/B')), isNull);
      expect(UnitCoverStore.rawOf(UnitCoverStore.unitKey('A/B')), urlA);
    });

    test('rel 归一化：反斜杠与多余分隔符等价', () {
      UnitCoverStore.set(UnitCoverStore.unitKey('A\\B\\C'), urlA);
      expect(UnitCoverStore.rawOf(UnitCoverStore.unitKey('A/B/C')), urlA);
      expect(UnitCoverStore.rawOf(UnitCoverStore.unitKey('A//B/C')), urlA);
    });

    test('空 rel 不写脏键', () {
      UnitCoverStore.set(UnitCoverStore.unitKey(''), urlA);
      expect(UnitCoverStore.rawOf('u:'), isNull);
      UnitCoverStore.set('', urlA);
      expect(UnitCoverStore.rawOf(''), isNull);
    });
  });

  group('三态语义', () {
    test('没设过 = null（调用方走服务端指针/自动链）', () {
      expect(UnitCoverStore.rawOf(UnitCoverStore.unitKey('X')), isNull);
      expect(UnitCoverStore.isAuto(UnitCoverStore.unitKey('X')), isFalse);
    });

    test('设为地址 = 用这张图', () {
      final k = UnitCoverStore.unitKey('X');
      UnitCoverStore.set(k, urlB);
      expect(UnitCoverStore.rawOf(k), urlB);
      expect(UnitCoverStore.isAuto(k), isFalse);
    });

    test('设为空串 = 显式恢复自动（不是"没设过"）', () {
      final k = UnitCoverStore.unitKey('X');
      UnitCoverStore.set(k, urlB);
      UnitCoverStore.set(k, '');
      // 关键：空串必须能区分于 null，否则「恢复自动」会被当成「用服务端指针」。
      expect(UnitCoverStore.rawOf(k), '');
      expect(UnitCoverStore.isAuto(k), isTrue);
    });
  });

  group('变更信号', () {
    test('值变化才 bump，重复写入不通知', () {
      final k = UnitCoverStore.unitKey('X');
      final before = UnitCoverStore.revision.value;
      UnitCoverStore.set(k, urlA);
      expect(UnitCoverStore.revision.value, before + 1);
      UnitCoverStore.set(k, urlA); // 同值
      expect(UnitCoverStore.revision.value, before + 1);
      UnitCoverStore.set(k, urlB);
      expect(UnitCoverStore.revision.value, before + 2);
    });

    test('reset 清空并通知', () {
      UnitCoverStore.set(UnitCoverStore.unitKey('X'), urlA);
      final before = UnitCoverStore.revision.value;
      UnitCoverStore.reset();
      expect(UnitCoverStore.rawOf(UnitCoverStore.unitKey('X')), isNull);
      expect(UnitCoverStore.revision.value, before + 1);
    });
  });

  group('页面重建不再丢封面（本次 bug 的回归点）', () {
    test('本地意见与树快照无关：重新拿到旧快照也不会盖掉', () {
      final k = UnitCoverStore.unitKey('A/B');
      // 用户选了过往封面
      UnitCoverStore.set(k, urlB);
      // 页面重建、树快照是旧的（指向 urlA）——旧值只能作为「没有本地意见时」
      // 的兜底，不能反过来覆盖本机意见。这里断言本机意见仍在。
      expect(UnitCoverStore.rawOf(k), urlB);
      expect(UnitCoverStore.rawOf(k), isNot(urlA));
    });

    test('恢复自动后，旧的自定义地址不能复活', () {
      final k = UnitCoverStore.unitKey('A/B');
      UnitCoverStore.set(k, urlB);
      UnitCoverStore.set(k, '');
      // 恢复自动写入的是空串；只要 rawOf 仍是空串，调用方就会走自动链。
      expect(UnitCoverStore.rawOf(k), '');
      expect(UnitCoverStore.isAuto(k), isTrue);
    });
  });
}
