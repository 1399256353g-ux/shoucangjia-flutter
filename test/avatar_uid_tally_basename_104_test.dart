/// 第一百零四批契约：**「同一条规则在四个地方各写一遍，其中三处漏了一级」**。
///
/// 这一批抓的不是算法错，而是**读取路径漏档**：
///
///  1. 手动头像从 0.9.331 起「有 uid 时按 `uid:` 键写」，而读取只有作者主页
///     传了 uid —— 作者总览卡、播放页、基础库页作者 tab 三处只按名字查。
///     作者在平台改名后，作者页还认得头像、卡片与播放页全退回爬虫图。
///  2. 「按首次出现顺序计数」这个八行循环在四个地方逐字相同（来源库条、
///     顶级节点条 ×2、作者目录条）。顺序是筛选条的**显示顺序**，任何一处
///     改成排序或 `counts[k]!` 都会让两个页面对同一份数据给出两种答案。
///  3. 路径末段的取法写了三份（`rel_path.lastRelName`、`unit_crawler`、
///     删除监测页自带的 `_basename`），对 `A\B` / `A//B` 给出不同结果。
///
/// 全部用合成名字（`作者甲` / `lib-1` / `TOP`），不碰任何真实目录名。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shoucangjia/author_avatar_store.dart';
import 'package:shoucangjia/author_merge.dart';
import 'package:shoucangjia/author_uid_index.dart';
import 'package:shoucangjia/rel_path.dart';
import 'package:shoucangjia/tally_order.dart';

String _src(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthorAvatarStore.instance.debugSeed({});
    clearAuthorUidIndex();
  });

  group('1. 手动头像：写按 uid、读也必须能按 uid', () {
    test('名字→uid 索引按两种写法登记，带不带 @ 都查得到', () {
      rebuildAuthorUidIndex([
        MapEntry('@作者甲', <String, Object?>{'uid': 'u-123'}),
        MapEntry('作者乙', <String, Object?>{'uid': 'u-456'}),
      ], 'base|user');

      expect(authorUidFor('作者甲'), 'u-123', reason: '索引里带 @，传裸名要能命中');
      expect(authorUidFor('@作者甲'), 'u-123', reason: '带 @ 传进来也要命中');
      expect(authorUidFor(' 作者甲 '), 'u-123', reason: '首尾空白不影响');
      expect(authorUidFor('作者乙'), 'u-456');
      expect(authorUidFor('@作者乙'), 'u-456');
      expect(authorUidFor('没有这个人'), '');
    });

    test('没有 uid 字段的作者不进表（旧服务端行为不变）', () {
      rebuildAuthorUidIndex([
        MapEntry('作者甲', <String, Object?>{'av': '/media/lib-1/a/x.jpg'}),
        MapEntry('作者乙', <String, Object?>{'uid': '  '}),
      ], 'base|user');
      expect(authorUidFor('作者甲'), '', reason: '没有 uid 就是没有，不猜');
      expect(authorUidFor('作者乙'), '');
    });

    test('改名后手动头像仍能取到：名字键已不存在，uid 键还在', () {
      // 设置头像时作者叫「旧名字」，写入用的是 uid 键。
      AuthorAvatarStore.instance.debugSeed({
        'uid:u-123': '/media/lib-1/@旧名字/_avatar/a.jpg',
      });
      rebuildAuthorUidIndex([
        MapEntry('新名字', <String, Object?>{'uid': 'u-123'}),
      ], 'base|user');

      // 只按名字查（四处的旧写法）什么都拿不到 —— 这就是原缺陷。
      expect(AuthorAvatarStore.instance.pathFor('新名字'), isNull);

      // 统一读法能拿到。
      expect(manualAvatarFor('新名字'), '/media/lib-1/@旧名字/_avatar/a.jpg');
      expect(manualAvatarFor('@新名字'), '/media/lib-1/@旧名字/_avatar/a.jpg');
    });

    test('名字键优先于 uid 键（与 pathFor 同一优先级）', () {
      AuthorAvatarStore.instance.debugSeed({
        '作者甲': '/media/lib-1/@作者甲/_avatar/by-name.jpg',
        'uid:u-123': '/media/lib-1/@作者甲/_avatar/by-uid.jpg',
      });
      rebuildAuthorUidIndex([
        MapEntry('作者甲', <String, Object?>{'uid': 'u-123'}),
      ], 'base|user');
      expect(manualAvatarFor('作者甲'),
          endsWith('by-name.jpg'), reason: '名字键是更明确的那一条');
    });

    test('作废索引后不再跨连接串 uid', () {
      rebuildAuthorUidIndex([
        MapEntry('作者甲', <String, Object?>{'uid': 'u-A'}),
      ], 'conn-a|user');
      expect(authorUidIndexLoadedFor('conn-a|user'), isTrue);
      expect(authorUidIndexLoadedFor('conn-b|user'), isFalse);

      clearAuthorUidIndex();
      expect(authorUidFor('作者甲'), '');
    });

    test('作用域为空时不写入（请求途中切连接的那一份结果作废）', () {
      rebuildAuthorUidIndex([
        MapEntry('作者甲', <String, Object?>{'uid': 'u-123'}),
      ], '');
      expect(authorUidFor('作者甲'), '');
    });

    test('四个读取入口都走 manualAvatarFor，不再直连 pathFor(name)', () {
      // lib/ 内 `pathFor(` 只允许出现在「写路径」与「统一读法」里：
      //  - author_avatar_store.dart 自己；
      //  - author_uid_index.dart 的 manualAvatarFor（唯一读法）；
      //  - 作者主页（它按 uid 写入/清除，读写都要 uid）。
      final files = <String>[
        'lib/main.dart',
        'lib/basic_lib_page.dart',
      ];
      for (final f in files) {
        // 只扫**代码行**：注释里出现 `pathFor(name)` 是在解释为什么不能那样
        // 写（本批的改动注释就提到它），不该被当成违规。
        final code = _src(f)
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        // 允许的形态：`pathFor(widget.name, uid: platformUid)`（作者主页，
        // 它本来就带 uid）。裸 `pathFor(<name>)` 一个都不许留。
        final bare = RegExp(r'pathFor\((?!widget\.name)');
        expect(bare.hasMatch(code), isFalse,
            reason: '$f 里还有裸 pathFor(...)——改名后的手动头像在那里查不到');
      }
    });

    test('authors.json 的键按裸名归一：@作者 与 作者 是同一个人', () {
      // 索引写入端在 `ensureAuthorAvatarsLoaded` 里对每个键跑
      // `authorNameForms`，所以两种写法都会命中。这里钉住「归一规则本身」。
      expect(authorNameForms('@作者甲'), <String>['@作者甲', '作者甲']);
      expect(authorNameForms(' 作者甲 '), <String>['作者甲']);
      expect(authorNameForms('@@作者甲'), <String>['@@作者甲', '作者甲']);
      expect(authorNameForms('   '), isEmpty);
    });

    test('头像索引的读写同一条归一规则（不再一处原样、一处裸名）', () {
      final main = _src('lib/main.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      // 读出侧只允许走 `_authorAvatarOf`，不得再出现直查。
      expect(main.contains('authorAvatarIndex[name]'), isFalse,
          reason: '直查名字在服务端键为 @作者 时永远落空');
      expect(main.contains('_authorAvatarOf('), isTrue);
      expect(
          RegExp(r"authorAvatarIndex\['\$\{e\.key\}'\]").hasMatch(main), isFalse,
          reason: '写入端必须按两种写法各记一条');
    });

    test('authors.json 的 uid 与 av 由同一次响应重建（不各拉一遍）', () {
      final s = _src('lib/main.dart');
      expect(s.contains('rebuildAuthorUidIndex(m.entries, scopeKey)'), isTrue,
          reason: 'uid 索引必须与头像索引同一个循环、同一个作用域');
      expect(s.contains('clearAuthorUidIndex()'), isTrue,
          reason: '切连接/刷新作者时要一起作废');
    });
  });

  group('2. 「按首次出现顺序计数」只有一个实现', () {
    test('保序、计数、空键跳过', () {
      final out = tallyInOrder<String>(
          <String>['b', '', 'a', 'b', '', 'c', 'a', 'b'], (s) => s);
      expect(out.map((e) => e.key).toList(), ['b', 'a', 'c'],
          reason: '顺序＝首次出现顺序，不是字典序');
      expect(out.map((e) => e.value).toList(), [3, 2, 1]);
    });

    test('空输入返回空（不抛）', () {
      expect(tallyInOrder<int>(const <int>[], (_) => ''), isEmpty);
      expect(tallyInOrder<int>(const <int>[], (i) => '$i'), isEmpty);
    });

    test('libFilterOptions 仍按首次出现顺序（行为不变）', () {
      final opts = libFilterOptions([
        {'_lib': 'lib-2'},
        {'_lib': 'lib-1'},
        {'_lib': 'lib-2'},
        {'nope': 1},
        {'_lib': ''},
      ]);
      expect(opts.map((e) => e.key).toList(), ['lib-2', 'lib-1']);
      expect(opts.map((e) => e.value).toList(), [2, 1]);
    });

    test('lib/ 内只剩一处 `counts[` 的「先见先排」写法', () {
      // 判据：四个点都必须走 tallyInOrder，且不得各自再写
      // `if (!counts.containsKey(...)) order.add(...)`。
      final files = <String>[
        'lib/main.dart',
        'lib/author_merge.dart',
        'lib/author_dir_filter.dart',
      ];
      for (final f in files) {
        final s = _src(f);
        expect(s.contains('counts.containsKey('), isFalse,
            reason: '$f 还在自己写「先见先排」的计数循环');
      }
      // 唯一实现文件里保留那八行。
      final tally = _src('lib/tally_order.dart');
      expect(tally.contains('if (!counts.containsKey(k)) order.add(k);'), isTrue);
    });

    test('四个调用点都真的用了 tallyInOrder', () {
      expect(_src('lib/author_merge.dart').contains('tallyInOrder<dynamic>'),
          isTrue);
      expect(_src('lib/author_dir_filter.dart').contains('tallyInOrder<Map>'),
          isTrue);
      final main = _src('lib/main.dart');
      // 删除监测的媒体库条 + 作者页的媒体库条。
      expect(RegExp(r'tallyInOrder<').allMatches(main).length, 2,
          reason: '两处（_topOptions / _topFilterOptions）都要走同一实现');
    });
  });

  group('3. 路径末段只有一处实现', () {
    test('反斜杠与重复分隔符都按同一规则归一', () {
      expect(lastRelName(r'A\B'), 'B');
      expect(lastRelName('A//B'), 'B');
      expect(lastRelName('A/B/'), 'B', reason: '尾部斜杠不算一段');
      expect(lastRelName(''), '');
    });

    test('删除监测页不再自带 _basename', () {
      final s = _src('lib/main.dart');
      expect(s.contains('static String _basename('), isFalse,
          reason: '那份 `replaceAll(\\\\, /)` + lastIndexOf 是第三份实现');
      expect(s.contains('lastRelName(widget.unitRel)'), isTrue);
    });

    test('lib/ 内 `lastIndexOf(\'/\')` 不再用来取末段', () {
      // `lib_cover.dart` 的注释里提到过这个写法（说明为什么不用它），
      // 所以只扫**代码行**：去掉 `//` 与 `///` 注释后再判。
      for (final f in <String>[
        'lib/main.dart',
        'lib/unit_crawler.dart',
        'lib/rel_path.dart',
      ]) {
        final code = _src(f)
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains("lastIndexOf('/')"), isFalse,
            reason: '$f 里又手写了取末段');
      }
    });
  });
}
