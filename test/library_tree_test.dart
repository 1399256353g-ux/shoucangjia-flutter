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
        {'id': 'lib-1', 'name': '基础一', 'rel': 'a/基础一', 'big_id': 'big-01', 'authors': 5, 'works': 100},
        {'id': 'lib-2', 'name': '基础二', 'rel': 'a/基础二', 'big_id': 'big-01', 'authors': 2, 'works': 50},
        {'id': 'lib-3', 'name': '基础三', 'rel': 'b/基础三', 'big_id': 'big-02', 'authors': 1, 'works': 10},
        {'id': 'lib-9', 'name': '基础九', 'rel': 'orphan', 'big_id': 'big-99', 'authors': 0, 'works': 0},
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
    expect(t.totalBasics, 4);
    // 旧「大库描述」不再由模型生成（避免各页面再贴回该文案）。
    expect(t.bigs[0].basics.length, 2);
    expect(t.bigs[0].works, 217);
  });

  test('星标按标记顺序置顶，无效 id 忽略，不重复', () {
    final t = LibraryTree.parse(_payload(), stars: ['lib-3', 'nope', 'lib-3', 'lib-1'])!;
    expect(t.starred.map((b) => b.id), ['lib-3', 'lib-1']);
    expect(t.visibleBasics(t.bigs[0]).map((b) => b.id), ['lib-2']);
    expect(t.visibleBasics(t.bigs[1]), isEmpty);
  });

  test('切换星标：新增置顶、再次点击取消、上限 20', () {
    expect(toggleStar([], 'lib-1'), ['lib-1']);
    expect(toggleStar(['lib-1'], 'lib-2'), ['lib-2', 'lib-1']);
    expect(toggleStar(['lib-2', 'lib-1'], 'lib-1'), ['lib-2']);
    final many = List<String>.generate(21, (i) => 'l$i');
    final capped = toggleStar(many, 'new');
    expect(capped.first, 'new');
    expect(capped.length, 20);
  });

  test('数字格式化与 withStars 重建', () {
    final t = LibraryTree.parse(_payload())!;
    final t2 = t.withStars(['lib-2']);
    expect(t2.starred.single.id, 'lib-2');
    expect(t2.bigs[0].basics.length, 2); // 结构不变
    expect(t.basicById('lib-3')!.name, '基础三');
    expect(t.basicById('missing'), isNull);
  });
}
