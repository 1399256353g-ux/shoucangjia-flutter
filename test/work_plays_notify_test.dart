import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/work_plays.dart';

/// 0.9.74：播放量变更按库通知。
///
/// 基准：记录 A 库的一次播放时，只有 A 库（及其上级单元库的合并通知）
/// 收到变更；B 库不应被唤醒——网格里其它库卡片不该跟着重算封面。
void main() {
  setUp(() {
    WorkPlaysStore.resetForTest();
  });

  tearDown(() {
    WorkPlaysStore.resetForTest();
  });

  test('写入 A 库只通知 A 库，不通知 B 库', () {
    var a = 0;
    var b = 0;
    final la = WorkPlaysStore.libListenable('lib-a')..addListener(() => a++);
    final lb = WorkPlaysStore.libListenable('lib-b')..addListener(() => b++);

    WorkPlaysStore.bump('lib-a', 'w1', thumb: 't.jpg', kind: 'v');

    expect(a, 1);
    expect(b, 0);
    la.removeListener(() {});
    lb.removeListener(() {});
  });

  test('libListenable 同库返回同一个通知器，空库退回全局 revision', () {
    expect(identical(WorkPlaysStore.libListenable('lib-x'),
        WorkPlaysStore.libListenable('lib-x')), isTrue);
    expect(identical(WorkPlaysStore.libListenable(''), WorkPlaysStore.revision),
        isTrue);
  });

  test('libsListenable 合并子树：子树内任一库写入都通知，子树外不通知', () {
    var merged = 0;
    final l = WorkPlaysStore.libsListenable(<String>['lib-a', 'lib-b'])
      ..addListener(() => merged++);

    WorkPlaysStore.bump('lib-a', 'w1', thumb: 't.jpg', kind: 'v');
    expect(merged, 1);

    WorkPlaysStore.bump('lib-z', 'w2', thumb: 't.jpg', kind: 'v');
    expect(merged, 1);

    WorkPlaysStore.bump('lib-b', 'w3', thumb: 't.jpg', kind: 'v');
    expect(merged, 2);
    l.removeListener(() {});
  });

  test('libsListenable 同一组库复用同一通知器', () {
    final x = WorkPlaysStore.libsListenable(<String>['b', 'a']);
    final y = WorkPlaysStore.libsListenable(<String>['a', 'b']);
    expect(identical(x, y), isTrue);
    expect(x, isA<ValueListenable<int>>());
  });

  test('全局 revision 仍然自增（兼容既有监听者）', () {
    var all = 0;
    void onAny() => all++;
    WorkPlaysStore.revision.addListener(onAny);
    WorkPlaysStore.bump('lib-a', 'w1', thumb: 't.jpg', kind: 'v');
    WorkPlaysStore.bump('lib-b', 'w2', thumb: 't.jpg', kind: 'v');
    expect(all, 2);
    WorkPlaysStore.revision.removeListener(onAny);
  });
}
