import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart' show BasicLib;
import 'package:shoucangjia/unit_library.dart';

// 0.9.344 第九十九批：**词条的 emoji 后缀与颜色必须是同一条分发链**。
//
// owner 2026-11-27 的原话是「上级结构生成的词条要分发给下级啊」。颜色在
// 0.9.342 已改成「从直接上级逐级上行、第一个设过的那层是分发源」，但
// `emojiFor` 仍然只查「本层 → 媒体库根」：
//   - 中间层设的后缀谁都拿不到（被跳过）；
//   - 同一层「颜色分发了、后缀没分发」，而设置页并排显示这两项。
// 现在遍历只有 `_upstreamOf` 一处，颜色 / 后缀 / 基础库后缀三处共用。
//
// 隐私：全部用合成 id（`T1` / `T1/MID`）与合成后缀，不涉及任何真实库名。

UnitLibrary _tree() {
  BasicLib b(String id) =>
      BasicLib(id: id, name: id, rel: id, bigId: '', authors: 0, works: 0);
  LibNode n(String rel) => LibNode(id: rel, rel: rel, name: rel);

  final leaf = UnitLibrary(
    node: n('T1/MID/LEAF'),
    basics: [b('b-leaf')],
    children: const [],
  );
  final mid = UnitLibrary(
    node: n('T1/MID'),
    basics: [b('b-mid')],
    children: [leaf],
  );
  final top = UnitLibrary(node: n('T1'), basics: const [], children: [mid]);
  return UnitLibrary(
    node: const LibNode(id: 'secret', rel: '', name: 'SECRET'),
    basics: const [],
    children: [top],
  );
}

void _reset() {
  LibraryBadge.custom.clear();
  LibraryBadge.topCustom.clear();
  LibraryBadge.basicCustom.clear();
  LibraryBadge.emoji.clear();
  LibraryBadge.colorSource.clear();
  LibraryBadge.basicSource.clear();
  LibraryBadge.topOfUnit.clear();
  LibraryBadge.parentOfUnit.clear();
}

void main() {
  setUp(_reset);

  group('后缀与颜色同一分发源', () {
    test('中间层设的后缀要传给下级单元库（此前被跳过）', () {
      UnitBadgeRegistry.setFrom(_tree());
      LibraryBadge.emoji['T1/MID'] = '🔥';

      expect(LibraryBadge.emojiFor('T1/MID/LEAF'), '🔥');
      expect(LibraryBadge.emojiFor('T1/MID'), '🔥');
    });

    test('更近的一层设后缀时以更近的为准（与颜色同规则）', () {
      UnitBadgeRegistry.setFrom(_tree());
      LibraryBadge.emoji['T1'] = '⭐';
      LibraryBadge.emoji['T1/MID'] = '🔥';

      expect(LibraryBadge.emojiFor('T1/MID/LEAF'), '🔥');
      expect(LibraryBadge.emojiFor('T1/MID'), '🔥');
    });

    test('同一层：颜色分发给下级时，后缀也从同一层取出', () {
      UnitBadgeRegistry.setFrom(_tree());
      LibraryBadge.custom['T1/MID'] = 0xFF123456;
      LibraryBadge.emoji['T1/MID'] = '💧';

      // 颜色分发源 = T1/MID
      expect(LibraryBadge.colorForUnit('T1/MID/LEAF'), 0xFF123456);
      // 后缀也必须来自同一层，而不是退回「有没有顶级设置」
      expect(LibraryBadge.emojiFor('T1/MID/LEAF'), '💧');
    });

    test('中间层选「自动分配」后不向下传色、也不向下传后缀', () {
      UnitBadgeRegistry.setFrom(_tree());
      LibraryBadge.custom['T1/MID'] = 0xFF123456;
      LibraryBadge.emoji['T1/MID'] = '💧';
      LibraryBadge.colorSource['T1/MID'] = 'auto';

      expect(LibraryBadge.colorForUnit('T1/MID/LEAF'), isNot(0xFF123456));
      expect(LibraryBadge.emojiFor('T1/MID/LEAF'), isNot('💧'));
    });

    test('一路都没有设置时不编造后缀', () {
      UnitBadgeRegistry.setFrom(_tree());
      expect(LibraryBadge.emojiFor('T1/MID/LEAF'), '');
    });

    test('上级关系出现环时不会拿本层自己的值当继承值', () {
      // 病态数据：A 的上级是 B、B 的上级是 A。
      LibraryBadge.parentOfUnit['A'] = 'B';
      LibraryBadge.parentOfUnit['B'] = 'A';
      LibraryBadge.emoji['A'] = '🔥';
      // 「A 的后缀必须是自己的」，不能因为环把 B 的（空）或 A 自己被算成继承。
      expect(LibraryBadge.emojiFor('A'), '🔥');
      expect(LibraryBadge.emojiFor('B'), '🔥');
    });
  });

  group('基础库后缀只有一条取法', () {
    test('基础库自己设过后缀时用自己的（不再丢）', () {
      UnitBadgeRegistry.setFrom(_tree());
      LibraryBadge.emoji['b-leaf'] = '🎯';
      LibraryBadge.emoji['T1/MID'] = '🔥';

      expect(LibraryBadge.basicEmojiFor('b-leaf', 'T1/MID/LEAF'), '🎯');
    });

    test('基础库没设过时继承所属单元库那条上行链', () {
      UnitBadgeRegistry.setFrom(_tree());
      LibraryBadge.emoji['T1/MID'] = '🔥';

      expect(LibraryBadge.basicEmojiFor('b-leaf', 'T1/MID/LEAF'), '🔥');
    });

    test('基础库自己设过后缀时，颜色来源=自动也不影响自己的后缀', () {
      // 后缀表与色表是两张表：用户给库选了「自动分配颜色」，不代表
      // 他要丢掉自己刚设的后缀。这条只钉「两张表不互相连坐」。
      UnitBadgeRegistry.setFrom(_tree());
      LibraryBadge.emoji['b-leaf'] = '🎯';
      LibraryBadge.basicSource['b-leaf'] = 'auto';

      expect(LibraryBadge.basicEmojiFor('b-leaf', 'T1/MID/LEAF'), '🎯');
    });

    test('ownEmoji 只返回本层设置，不回传继承值', () {
      UnitBadgeRegistry.setFrom(_tree());
      LibraryBadge.emoji['T1/MID'] = '🔥';

      expect(LibraryBadge.ownEmoji('T1/MID'), '🔥');
      // 下级实际生效是 '🔥'，但它自己没设过 —— 设置页的「已自定义 N 项」
      // 不能把它算成自定义项，否则一个顶层后缀会让整棵子树都变成「已自定义」。
      expect(LibraryBadge.emojiFor('T1/MID/LEAF'), '🔥');
      expect(LibraryBadge.ownEmoji('T1/MID/LEAF'), '');
    });
  });

  group('契约扫描：后缀只有一条渲染路径', () {
    test('基础库卡片不再自己拼后缀（交给 chip 的 emoji 参数）', () {
      final src = File('lib/unit_library_view.dart').readAsStringSync();
      // 基础库卡片此前把后缀拼进文字、再把 chip 的 unitId 置空，
      // 于是基础库自己的后缀永远不出现。现在它必须把已算好的后缀
      // 交给 chip（`emoji:`），而不是自己拼到 label 上。
      final badge = src.substring(src.indexOf('Widget _badge()'));
      final body = badge.substring(0, badge.indexOf('Widget build'));
      expect(body.contains('labelWithEmoji'), isFalse,
          reason: '基础库词条必须走 basicEmojiFor，不再自己拼后缀');
      expect(body.contains('basicEmojiFor('), isTrue);
      expect(body.contains('emoji:'), isTrue);
    });

    test('lib/ 内不再有第二份「逐级上行找分发源」的循环', () {
      final files = Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      var hits = 0;
      for (final f in files) {
        final src = f.readAsStringSync();
        if (src.contains('parentOfUnit, cursor') ||
            src.contains('parentOfUnit, unitId') ||
            src.contains('parentOfUnit, startId')) {
          hits++;
        }
      }
      // 只有 library_badge._upstreamOf 一处允许向上爬。
      expect(hits, 1, reason: '分发链遍历必须只有一处实现');
    });
  });
}
