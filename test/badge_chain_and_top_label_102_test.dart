import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_tree.dart' show BasicLib;
import 'package:shoucangjia/main.dart';
import 'package:shoucangjia/unit_library.dart';

/// 0.9.347 第一百零二批。
///
/// 四项都是「同一句规则写了好几遍，其中一遍已经漂了」：
///
/// | 位置 | 写了什么 | 后果 |
/// |---|---|---|
/// | 分发链「这层有没有色」 | 4 份逐字相同的表达式 | 漏改一份 ⇒ 顶级色分发随路径而变 |
/// | 词条弹窗的 emoji 初值 | 用了含继承的 `emojiFor` | 只改颜色保存一次就把继承写死成本层值 |
/// | 两个页面各一份 `_topLabel` | 函数体逐字相同 | 同一媒体库两页可能显示两个名字 |
/// | `topIdFor` | 先查进程级全局表 | 两台服务器同名 rel 时贴错媒体的库 |
///
/// 隐私：全部用合成 id（`T1` / `s1dir`）与合成后缀，不涉及任何真实库名。
UnitLibrary _tree() {
  BasicLib b(String id) =>
      BasicLib(id: id, name: id, rel: id, bigId: '', authors: 0, works: 0);
  LibNode n(String rel, {String? id}) =>
      LibNode(id: id ?? rel, rel: rel, name: rel);

  final mid = UnitLibrary(
    node: n('T1/MID'),
    basics: [b('b-mid')],
    children: const [],
  );
  final top = UnitLibrary(node: n('T1'), basics: const [], children: [mid]);
  return UnitLibrary(
    node: const LibNode(id: 'secret', rel: '', name: 'SECRET'),
    basics: const [],
    children: [top],
  );
}

String _code(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

/// 注册 T1 ← T1/MID 的上游关系（分发链就靠这两张结构表）。
void _wireT1() {
  LibraryBadge.topOfUnit['T1/MID'] = 'T1';
  LibraryBadge.topOfUnit['T1'] = 'T1';
  LibraryBadge.parentOfUnit['T1/MID'] = 'T1';
}

void main() {
  setUp(() {
    LibraryBadge.custom.clear();
    LibraryBadge.topCustom.clear();
    LibraryBadge.basicCustom.clear();
    LibraryBadge.emoji.clear();
    LibraryBadge.colorSource.clear();
    LibraryBadge.basicSource.clear();
    LibraryBadge.parentOfUnit.clear();
    LibraryBadge.topOfUnit.clear();
  });

  group('1. 分发链「这层有没有值」只有一个判定', () {
    test('hasColorAt 认识普通单元库色与媒体库色', () {
      expect(LibraryBadge.hasColorAt(''), isFalse);
      expect(LibraryBadge.hasColorAt('T1/MID'), isFalse);
      LibraryBadge.custom['T1/MID'] = 0xFF112233;
      expect(LibraryBadge.hasColorAt('T1/MID'), isTrue);
      expect(LibraryBadge.hasColorAt('node:T1/MID'), isTrue,
          reason: '两种 id 形式都要认');
      // 媒体库色存在另一张表：这正是四份拷贝里最容易漏掉的那一张。
      LibraryBadge.topCustom['T1'] = 0xFF445566;
      expect(LibraryBadge.hasColorAt('T1'), isTrue);
    });

    test('hasEmojiAt 只看本层，不看继承', () {
      LibraryBadge.emoji['T1'] = '🔥';
      expect(LibraryBadge.hasEmojiAt('T1'), isTrue);
      expect(LibraryBadge.hasEmojiAt('T1/MID'), isFalse);
      expect(LibraryBadge.hasEmojiAt(''), isFalse);
    });

    test('「custom + topCustom」两表合查只在一处', () {
      // 唯一取值口是 colorValueAt；hasColorAt 只是它的布尔化。
      // 判据：同一行里既查 custom 又带 topColorFor —— 那正是被复制的那半句。
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((x) => x.path.endsWith('.dart'))) {
        final lines = _code(f.path).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          final t = l.trimLeft();
          if (t.startsWith('//') || t.startsWith('///')) continue;
          if (!l.contains('lookupByLibId(custom')) continue;
          if (!l.contains('topColorFor(')) continue;
          // 只允许 colorValueAt 自己的那一行（`id.isEmpty ? null : (...)`）。
          if (l.contains('id.isEmpty ? null :')) continue;
          offenders.add('${f.path}:${i + 1}');
        }
      }
      expect(offenders, isEmpty,
          reason: '两张表一起查只允许 colorValueAt 一处：$offenders');
    });

    test('颜色/后缀/基础库颜色三条链共用同一个上游遍历', () {
      _wireT1();
      // 分发源：T1 设色，中间层设后缀 ⇒ 两者各自从最近设过的层来。
      LibraryBadge.custom['T1'] = 0xFF010203;
      LibraryBadge.emoji['T1/MID'] = '💧';
      expect(LibraryBadge.colorForUnit('T1/MID'), 0xFF010203);
      expect(LibraryBadge.emojiFor('T1/MID'), '💧',
          reason: '本层设过后缀就该用本层的');
    });

    test('来源=自动分配的层不向下传色（回归）', () {
      LibraryBadge.custom['T1'] = 0xFF010203;
      LibraryBadge.setSource('T1', BadgeColorSource.autoAssign);
      // 自动分配层的旧色不生效，下级回落到自动配色而非那个残留值。
      expect(LibraryBadge.colorForUnit('T1'), isNot(0xFF010203));
    });
  });

  group('2. 词条弹窗的 emoji 初值只认本层', () {
    test('本层没设、上级设了：emojiFor 含继承，emojiForEdit 为空', () {
      _wireT1();
      LibraryBadge.emoji['T1'] = '🔥';
      expect(LibraryBadge.emojiFor('T1/MID'), '🔥');
      expect(LibraryBadge.emojiForEdit('T1/MID'), isEmpty);
    });

    test('本层设了：两者相同', () {
      _wireT1();
      LibraryBadge.emoji['T1/MID'] = '💧';
      expect(LibraryBadge.emojiForEdit('T1/MID'), '💧');
      expect(LibraryBadge.emojiFor('T1/MID'), '💧');
    });

    test('保存路径：把初值原样写回不会破坏继承（端到端）', () async {
      _wireT1();
      LibraryBadge.emoji['T1'] = '🔥';
      // 用户在弹窗里只改了颜色，emoji 输入框初值是 emojiForEdit ⇒ 空串。
      final draft = LibraryBadge.emojiForEdit('T1/MID');
      await LibraryBadge.setEmoji('T1/MID', draft.isEmpty ? null : draft);
      expect(LibraryBadge.ownEmoji('T1/MID'), isEmpty,
          reason: '本层不该多出一条「继承来的」后缀');
      expect(LibraryBadge.emojiFor('T1/MID'), '🔥',
          reason: '继承关系必须还在：上级改后缀，下级跟着变');
      LibraryBadge.emoji['T1'] = '💧';
      expect(LibraryBadge.emojiFor('T1/MID'), '💧');
    });

    test('旧写法（用 emojiFor 当初值）会写死继承值——钉住这个差别', () async {
      _wireT1();
      LibraryBadge.emoji['T1'] = '🔥';
      // 模拟旧实现的保存：初值取 emojiFor。
      await LibraryBadge.setEmoji('T1/MID', LibraryBadge.emojiFor('T1/MID'));
      expect(LibraryBadge.ownEmoji('T1/MID'), '🔥');
      LibraryBadge.emoji['T1'] = '💧';
      expect(LibraryBadge.emojiFor('T1/MID'), '🔥',
          reason: '这正是旧版缺陷行为：继承被写成本层值后不再跟随');
    });

    test('main.dart 的弹窗初值走 emojiForEdit，不再读 emojiFor', () {
      final src = _code('lib/main.dart');
      expect(src.contains('LibraryBadge.emojiForEdit(id)'), isTrue);
      // `var currentEmoji = LibraryBadge.emojiFor(` 这种写法必须绝迹。
      expect(RegExp(r'currentEmoji\s*=\s*LibraryBadge\.emojiFor\(')
          .hasMatch(src), isFalse);
    });
  });

  group('3. 媒体库名只有一处取法', () {
    LibMeta metaOf(UnitLibrary tree) => LibMeta(
          basics: tree.allBasics,
          allBasics: tree.allBasics,
          stats: const {},
          unitTree: tree,
          units: flattenUnits(tree),
          basicToUnit: unitOfBasics(tree),
        );

    test('树里有名字就用树里的', () {
      final tree = _tree();
      expect(metaOf(tree).topLabelFor('T1'), 'T1');
    });

    test('树里名字为空回落 id，未知 id 也回落 id（不猜、不返回空）', () {
      final meta = metaOf(_tree());
      expect(meta.topLabelFor('media:s9'), 'media:s9');
      expect(meta.topLabelFor(''), '');
    });

    test('与 topNameOf 的回落规则不同是有意的', () {
      // topName 是本份元数据库根的目录名；多连接时每个媒体库根同名，
      // 拿它当兜底会让筛选条出现多条同名词条 ⇒ 筛选条一律回落 id。
      final meta = LibMeta(
        basics: const [],
        stats: const {},
        unitTree: _tree(),
        units: const [],
        topName: '同一个根目录名',
      );
      expect(meta.topNameOf('media:s9'), '同一个根目录名');
      expect(meta.topLabelFor('media:s9'), 'media:s9');
    });

    test('两处 _topLabel 都只转发，不再各写一遍遍历', () {
      final src = _code('lib/main.dart');
      expect(src.contains('_meta?.topLabelFor(id)'), isTrue);
      expect(src.contains('meta?.topLabelFor(id)'), isTrue);
      // 旧的逐字拷贝：遍历 tops 并做 `t.name.isEmpty ? id : t.name`。
      expect(src.contains('t.name.isEmpty ? id : t.name'), isFalse,
          reason: '这条回落只允许出现在 LibMeta.topLabelFor 里');
    });
  });

  group('4. topIdFor 先认本份元数据的树', () {
    UnitLibrary twoMediaRoots() {
      BasicLib b(String id, String rel) =>
          BasicLib(id: id, name: id, rel: rel, bigId: '', authors: 0, works: 0);
      UnitLibrary mediaRoot(String sid, String rel, String basicId) =>
          UnitLibrary(
            node: LibNode(id: 'media:$sid', rel: '', name: 'M$sid'),
            basics: const [],
            children: [
              UnitLibrary(
                node: LibNode(id: rel, rel: rel, name: rel),
                basics: [b(basicId, '$rel/x')],
                children: const [],
              ),
            ],
          );
      return UnitLibrary(
        node: const LibNode(id: 'secret', rel: '', name: 'SECRET'),
        basics: const [],
        children: [
          mediaRoot('s1', 's1dir/U', 'b1'),
          mediaRoot('s2', 's2dir/U', 'b2'),
        ],
      );
    }

    test('本树有媒体库层时以本树为准，不被全局表带偏', () {
      final tree = twoMediaRoots();
      final meta = LibMeta(
        basics: tree.allBasics,
        allBasics: tree.allBasics,
        stats: const {},
        unitTree: tree,
        units: flattenUnits(tree),
        basicToUnit: unitOfBasics(tree),
      );
      // 全局表（进程级、由最后一次加载覆盖）故意写错。
      LibraryBadge.topOfUnit['s2dir/U'] = 'media:s1';
      expect(meta.topIdFor('s2dir/U'), 'media:s2',
          reason: '本树里 s2dir/U 属于 media:s2，不能被全局表改答案');
      expect(meta.topIdForBasic('b2'), 'media:s2');
      expect(meta.topIdFor('media:s2'), 'media:s2');
      // 不存在的单元库不猜。
      expect(meta.topIdFor('nope/U'), '');
    });

    test('单连接旧形态（树里没有媒体库层）仍读全局表', () {
      final tree = _tree();
      final meta = LibMeta(
        basics: tree.allBasics,
        allBasics: tree.allBasics,
        stats: const {},
        unitTree: tree,
        units: flattenUnits(tree),
        basicToUnit: unitOfBasics(tree),
      );
      LibraryBadge.topOfUnit['T1/MID'] = 'T1';
      expect(meta.topIdFor('T1/MID'), 'T1');
    });
  });
}
