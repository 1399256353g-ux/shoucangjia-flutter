import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';

Map<String, dynamic> _payload() => {
      'version': 2,
      'bigLibraries': [
        {
          'id': 'big-01',
          'name': '大库一',
          'path': '/root/a',
          'authors': 12,
          'works': 217,
          'basicCount': 2,
        },
        {
          'id': 'big-02',
          'name': '大库二',
          'path': '/root/b',
          'authors': 3,
          'works': 10,
          'basicCount': 1,
        },
      ],
      'basicLibraries': [
        {
          'id': 'lib-1',
          'name': '基础一',
          'rel': 'a/基础一',
          'big_id': 'big-01',
          'authors': 5,
          'works': 100
        },
        {
          'id': 'lib-2',
          'name': '基础二',
          'rel': 'a/基础二',
          'big_id': 'big-01',
          'authors': 2,
          'works': 50
        },
        {
          'id': 'lib-3',
          'name': '基础三',
          'rel': 'b/基础三',
          'big_id': 'big-02',
          'authors': 1,
          'works': 10
        },
        {
          'id': 'lib-9',
          'name': '基础九',
          'rel': 'orphan',
          'big_id': 'big-99',
          'authors': 0,
          'works': 0
        },
      ],
    };

void main() {
  test('v1 数据返回 null，页面走旧列表兜底', () {
    expect(LibraryTree.parse({'libraries': []}), isNull);
    expect(LibraryTree.parse({'bigLibraries': []}), isNull);
  });

  test('按 big_id 归组，未归属不丢', () {
    final t = LibraryTree.parse(_payload())!;
    expect(t.bigs.length, 2);
    expect(t.bigs[0].basics.map((b) => b.id), ['lib-1', 'lib-2']);
    expect(t.bigs[1].basics.map((b) => b.id), ['lib-3']);
    expect(t.unassigned.map((b) => b.id), ['lib-9']);
    expect(
        t.bigs.fold<int>(0, (n, b) => n + b.basics.length) +
            t.unassigned.length,
        4);
    // 旧「大库描述」不再由模型生成（避免各页面再贴回该文案）。
    expect(t.bigs[0].basics.length, 2);
    expect(t.bigs[0].works, 217);
  });

  // 星标不再由 LibraryTree 持有：唯一真相是 StarStore（见 star_store_test）。

  test('切换星标：新增置顶、再次点击取消、上限 20', () {
    expect(toggleStar([], 'lib-1'), ['lib-1']);
    expect(toggleStar(['lib-1'], 'lib-2'), ['lib-2', 'lib-1']);
    expect(toggleStar(['lib-2', 'lib-1'], 'lib-1'), ['lib-2']);
    final many = List<String>.generate(21, (i) => 'l$i');
    final capped = toggleStar(many, 'new');
    expect(capped.first, 'new');
    expect(capped.length, 20);
  });

  test('按 id 取基础库；未知 id 返回 null', () {
    final t = LibraryTree.parse(_payload())!;
    expect(t.basicById('lib-3')!.name, '基础三');
    expect(t.basicById('missing'), isNull);
  });
}
