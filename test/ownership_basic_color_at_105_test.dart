import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/index_prefix.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/main.dart';
import 'package:shoucangjia/text_fold.dart';
import 'package:shoucangjia/work_author.dart';

/// 0.9.350 第一百零五批。
///
/// 四项都是「写的那一头升级了，读的那一头没跟上」：
///
/// | 位置 | 写的 | 读的 | 后果 |
/// |---|---|---|---|
/// | 基础库词条色 | 清键用 `removeByLibId`（清 `b` 与 `node:b`） | 读键用 `map[b]` | 传带前缀的 id 时「恢复自动」点了没反应 |
/// | `LibMeta.idFor/labelFor` | 反查有 `basicIdForPath`（认 `lib-NNN`） | 自写 `basicLibForMedia` | 库作用域写法的 `av` 认不出基础库 |
/// | 筛选归属链（基础库/单元库） | 两页各一份 | 回落规则不同 | 跨连接时同一作者两个维度两个答案 |
/// | 作者名剥 `@` | 四份 while 循环 | 其中一份只剥一层 | `@@作者` 三处三个键 |
///
/// 隐私：全部用合成 id / 名字（`lib-1` / `b1` / `@作者甲`），不读任何真实
/// 目录名，不涉及截图或媒体内容。

BasicLib _b(String id, String rel, {String bigId = ''}) => BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: bigId,
      authors: 1,
      works: 2,
    );

String _lib(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

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

  group('1. 基础库词条色：读端与写端同一条键规则', () {
    test('带 node: 前缀写入的色，读端取得到', () {
      LibraryBadge.basicCustom['node:lib-1'] = 0xFF112233;
      expect(LibraryBadge.basicColorAt('node:lib-1'), 0xFF112233,
          reason: '写的是原样键，读也必须认');
      expect(LibraryBadge.basicColorAt('lib-1'), 0xFF112233,
          reason: '同一个库的裸 rel 形式也是同一个键（lookupByLibId）');
      expect(LibraryBadge.hasOwnBasicColor('lib-1'), isTrue);
      expect(LibraryBadge.basicColorFor('lib-1', ''), 0xFF112233);
    });

    test('清除会清掉全部等价键，不再「恢复自动没反应」', () async {
      LibraryBadge.basicCustom['node:lib-2'] = 0xFF445566;
      LibraryBadge.basicCustom['lib-2'] = 0xFF445566;
      await LibraryBadge.setBasicColor('node:lib-2', null);
      expect(LibraryBadge.basicColorAt('node:lib-2'), isNull);
      expect(LibraryBadge.basicColorAt('lib-2'), isNull,
          reason: '两种写法必须一起清，否则读端还能读到旧色');
      expect(LibraryBadge.hasOwnBasicColor('lib-2'), isFalse);
    });

    test('来源表同样认等价键（写端一直在清两种键）', () {
      LibraryBadge.basicSource['node:lib-3'] = 'auto';
      expect(LibraryBadge.sourceForBasic('lib-3'), BadgeColorSource.autoAssign);
      LibraryBadge.basicSource['node:lib-4'] = 'custom';
      expect(
          LibraryBadge.sourceForBasic('lib-4'), BadgeColorSource.fixedCustom);
      expect(LibraryBadge.sourceForBasic(''), BadgeColorSource.inheritTop);
    });

    test('lib/ 内基础库色表不再有裸下标读法', () {
      final s = _lib('lib/library_badge.dart');
      // 唯一允许的取值口是 basicColorAt（内部用 lookupByLibId）。
      // 只禁止**读取**写法（`x = basicCustom[...]` / `return basicCustom[...]`）；
      // 写入 `basicCustom[basicId] = argb` 仍是合法的（新键本就是原样 id）。
      expect(RegExp(r'=\s*basicCustom\[basicId\]').hasMatch(s), isFalse,
          reason: '裸下标读法漏掉 node: 等价键');
      expect(RegExp(r'return\s+basicCustom\[').hasMatch(s), isFalse);
      expect(s.contains('static int? basicColorAt('), isTrue);
    });
  });

  group('2. LibMeta 的路径反查认「库作用域」写法', () {
    final meta = LibMeta(
      basics: [_b('lib-1', 'A/一'), _b('lib-2', 'B/二')],
      stats: const {},
    );

    test('idFor 与 basicIdForPath 是同一个答案', () {
      // 库作用域写法：前缀是基础库 id，不是目录名。
      const scoped = '/media/lib-2/@作者甲/_avatar/a.jpg';
      expect(meta.idFor(scoped), 'lib-2');
      expect(meta.idFor(scoped), meta.basicIdForPath(scoped));
      // 库内相对写法：按目录前缀匹配。
      const relative = '/media/B/二/@作者甲/_avatar/a.jpg';
      expect(meta.idFor(relative), 'lib-2');
      expect(meta.idFor('/media/ZZZ/无/@x/a.jpg'), isEmpty);
    });

    test('labelFor 与 idFor 同源，不再一个命中一个空', () {
      const scoped = '/media/lib-1/@作者甲/_avatar/a.jpg';
      expect(meta.labelFor(scoped, '兜底'), isNotEmpty);
      expect(meta.labelFor(scoped, '兜底'), isNot('兜底'),
          reason: '命中基础库时不得回落到调用方兜底名');
      expect(meta.labelFor('/media/ZZZ/@x/a.jpg', '兜底'), isEmpty);
    });

    test('lib/ 内不再有第二份「只按目录前缀」的路径反查', () {
      final s = _lib('lib/main.dart');
      // `basicLibForMedia(basics, …)` 只在 LibMeta 之外没有调用点计数意义，
      // 但 idFor/labelFor 的实现里绝不能出现。
      expect(
          RegExp(r'String idFor\(String mediaPath\) =>\s*basicIdForPath')
              .hasMatch(s),
          isTrue);
      expect(
          RegExp(r'String labelFor\(String mediaPath, String fallback\) \{\s*final b = basicById\(idFor\(mediaPath\)\)')
              .hasMatch(s),
          isTrue);
    });
  });

  group('3. 基础库 → 单元库归属链只有一个出口', () {
    // 单元库树：媒体库根（media:s1）→ 单元库 U1 → 基础库 lib-1。
    final meta = LibMeta(
      basics: [_b('lib-1', 'U1/x')],
      stats: const {},
      basicToUnit: const {'lib-1': 'U1'},
    );

    test('本份元数据认识 _bid 时直接用', () {
      final r = meta.ownershipOf(bid: 'lib-1', mediaPath: '');
      expect(r.basic, 'lib-1');
      expect(r.unit, 'U1');
    });

    test('_bid 不属于本份元数据 → 回落按路径反查（不再两个维度两个答案）', () {
      // `_bid` 是另一台服务器的库 id：basicById 查不到。
      final r = meta.ownershipOf(
          bid: 'other-server-lib', mediaPath: '/media/lib-1/@a/_avatar/x.jpg');
      expect(r.basic, 'lib-1', reason: '_bid 不认识时必须按路径反查');
      expect(r.unit, 'U1', reason: '单元库归属必须跟着基础库一起回落');
    });

    test('路径也算不出时用条目自带的 _lib 标记', () {
      final r = meta.ownershipOf(bid: '', libTag: 'lib-1', mediaPath: '');
      expect(r.basic, 'lib-1');
    });

    test('全空输入返回两个空串，不猜', () {
      final r = meta.ownershipOf();
      expect(r.basic, isEmpty);
      expect(r.unit, isEmpty);
    });

    test('两个筛选页都走 ownershipOf，不再各写一份回落', () {
      final s = _lib('lib/main.dart');
      // 一处定义 + 两处调用（作者页、搜索/推荐页）。
      expect(RegExp(r'\.ownershipOf\(').allMatches(s).length, 2,
          reason: '作者页与搜索/推荐页各一处，且都必须是它');
      expect(s.contains('({String basic, String unit}) ownershipOf({'), isTrue);
    });
  });

  group('4. 剥 `@` 前缀只有一处实现', () {
    test('多重 @ 与全角 ＠ 都剥干净', () {
      expect(stripAtPrefixes('@@作者甲'), '作者甲');
      expect(stripAtPrefixes('  @ 作者甲 '), '作者甲');
      expect(stripAtPrefixes('作者甲'), '作者甲');
      expect(stripAtPrefixes(foldFullWidthAscii('＠作者甲')), '作者甲');
      expect(stripAtPrefixes('@'), '');
    });

    test('四处调用点结果一致（索引 / 裸名 / 显示名 / 分类作者列表）', () {
      expect(authorDisplayNameFromWork({'a': '@@作者甲'}), '作者甲');
      // bareNameOf 与序号前缀交错剥：`@(1)作者甲` 剥完不能剩 `@`。
      expect(bareNameOf('@@(1)作者甲'), '作者甲');
    });

    test('lib/ 内不再有第二份 while-startsWith-@ 循环', () {
      for (final path in const [
        'lib/author_index.dart',
        'lib/index_prefix.dart',
        'lib/work_author.dart',
        'lib/main.dart',
        'lib/category_tree.dart',
      ]) {
        final s = _lib(path);
        expect(s.contains("while (t.startsWith('@'))"), isFalse,
            reason: '$path 仍在自己剥 @');
        expect(s.contains("while (s.startsWith('@'))"), isFalse,
            reason: '$path 仍在自己剥 @');
      }
      final fold = _lib('lib/text_fold.dart');
      expect(fold.contains('String stripAtPrefixes('), isTrue);
    });
  });
}
