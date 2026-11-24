import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/main.dart';

void main() {
  group('K2 多选集合', () {
    test('toggleWorkSelection 选中/取消/去重', () {
      var s = <String>{};
      s = toggleWorkSelection(s, 'a');
      expect(s, {'a'});
      s = toggleWorkSelection(s, 'a');
      expect(s, isEmpty);
      s = toggleWorkSelection(s, 'a');
      s = toggleWorkSelection(s, 'b');
      s = toggleWorkSelection(s, 'a');
      expect(s, {'b'});
      // 空 id 不影响集合
      expect(toggleWorkSelection(s, ''), {'b'});
      // 不修改入参
      final origin = <String>{'x'};
      toggleWorkSelection(origin, 'y');
      expect(origin, {'x'});
    });

    test('allWorksSelected 与空列表', () {
      expect(allWorksSelected({}, []), isFalse);
      expect(allWorksSelected({}, ['']), isFalse);
      expect(allWorksSelected({'a'}, ['a', 'a']), isTrue);
      expect(allWorksSelected({'a'}, ['a', 'b']), isFalse);
    });

    test('toggleSelectAllWorks 全选 / 取消', () {
      final ids = ['a', 'b', 'c', 'b'];
      var s = toggleSelectAllWorks(<String>{}, ids);
      expect(s, {'a', 'b', 'c'});
      s = toggleSelectAllWorks(s, ids);
      expect(s, isEmpty);
      // 部分选中时点全选 → 全选
      s = toggleSelectAllWorks(<String>{'a'}, ids);
      expect(s, {'a', 'b', 'c'});
    });

    test('按钮可用条件', () {
      expect(canBatchDelete(<String>{}), isFalse);
      expect(canBatchDelete({'a'}), isTrue);
      expect(canBatchMove({'a'}, null), isFalse);
      expect(canBatchMove({'a'}, '  '), isFalse);
      expect(canBatchMove({'a'}, '作者/合集'), isTrue);
      expect(canBatchMove(<String>{}, '作者/合集'), isFalse);
    });

    test('确认文案包含数量', () {
      expect(batchDeleteConfirmText(3, 7), contains('3 个作品'));
      expect(batchDeleteConfirmText(3, 7), contains('7 个文件'));
      expect(batchMoveConfirmText(2, 'A/B'), contains('2 个作品'));
      expect(batchMoveConfirmText(2, 'A/B'), contains('A/B'));
    });
  });

  group('K3 手动来源', () {
    test('来源文案优先级：手动 > 爬虫', () {
      expect(workSourceLabel(manual: true), '手动');
      expect(workSourceLabel(manual: false), '爬虫');
    });
  });

  group('K7 单元库标记剪枝', () {
    test('pruneUnitMarks 去掉不存在的、保留顺序并去重', () {
      expect(pruneUnitMarks(['a', 'b'], ['b', 'c', 'a', 'b']), ['b', 'a']);
      expect(pruneUnitMarks(<String>[], ['a']), isEmpty);
      expect(pruneUnitMarks(['a'], <String>[]), isEmpty);
      expect(pruneUnitMarks(['a'], ['', 'a']), ['a']);
    });

    test('unitMarksNeedPrune 判断是否需要写回', () {
      expect(unitMarksNeedPrune(['a'], ['a']), isFalse);
      expect(unitMarksNeedPrune(['a'], ['a', 'gone']), isTrue);
      expect(unitMarksNeedPrune(['a'], ['a', 'a']), isTrue);
      expect(unitMarksNeedPrune(['a', 'b'], ['b', 'a']), isFalse);
      expect(unitMarksNeedPrune(<String>[], <String>[]), isFalse);
    });
  });

  group('K2 移动目标候选', () {
    test('authorPrefixOfMedia 取 VID/PIC 之前的段', () {
      expect(authorPrefixOfMedia('/media/lib/@甲/VID/1.mp4'), '@甲');
      expect(authorPrefixOfMedia('/media/lib/@甲/PIC/2.jpg'), '@甲');
      expect(authorPrefixOfMedia('/media/lib/@甲/合集/VID/1.mp4'), '@甲/合集');
      expect(authorPrefixOfMedia(''), '');
    });

    test('moveTargetCandidates 只保留作者前缀下的目录', () {
      final tree = {
        'dirs': [
          {'rel': '@甲', 'dirs': [
            {'rel': '@甲/合集1', 'dirs': []},
            {'rel': '@甲/合集2', 'dirs': []},
          ]},
          {'rel': '@乙', 'dirs': []},
        ],
      };
      expect(moveTargetCandidates(tree, '@甲'),
          ['@甲', '@甲/合集1', '@甲/合集2']);
      expect(moveTargetCandidates(tree, ''), [
        '@甲',
        '@甲/合集1',
        '@甲/合集2',
        '@乙',
      ]);
      expect(moveTargetCandidates(null, ''), isEmpty);
    });
  });
}
