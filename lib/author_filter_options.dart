/// 作者筛选面板的选项来源（**唯一实现**）。
///
/// 为什么单独一个文件（0.9.319）：推荐页与搜索页各写了一套
/// `_filterBasics` / `_filterBigs` / `_filterUnits` / `_filterTops` 加四个
/// `<维度>Names` 映射，共 8 个 getter × 2 页 = 16 份「从 meta 汇总筛选项」
/// 的代码。两处只在「输入是一份 meta 还是多份」上不同，其余（去重、排序、
/// 名称回落）本该完全一致：
///
/// ```
/// 推荐页：for (final b in meta.filterBasics)      ← 单份
/// 搜索页：for (final m in metas.values) …          ← 多份
/// ```
///
/// 两份写法的后果不是报错，而是同一个库在两页的筛选面板里可能显示不同名
/// （一份取 `meta.bigNames`，一份取 `metas` 里第一个非空值），用户会以为
/// 那是两个库。更隐蔽的是「哪个维度用哪份 meta」这个决定被复制了四遍，
/// 改一处就有一处继续按旧口径算（顶级节点只从当前 meta 取，跨连接就少一项）。
///
/// 本文件只做纯计算，不依赖 `main.dart`：输入是基础库/单元库/名称表本身，
/// 调用方按自己的作用域（单份 meta 或多份 meta 合并）传入。
library;

import 'author_filter.dart';
import 'author_big_nodes.dart';
import 'basic_lib.dart';
import 'lib_names.dart';
import 'source_lib.dart' show basicLibLabel;
import 'unit_library.dart';

/// 一次汇总的结果：面板直接吃这四个列表，摘要直接吃这四个名称表。
class AuthorFilterOptions {
  final List<AuthorLibNode> basics;
  final List<AuthorBigNode> bigs;
  final List<AuthorLibNode> units;
  final List<AuthorLibNode> tops;

  const AuthorFilterOptions({
    this.basics = const [],
    this.bigs = const [],
    this.units = const [],
    this.tops = const [],
  });

  Map<String, String> get basicNames => {for (final b in basics) b.id: b.name};
  Map<String, String> get bigNames => {for (final b in bigs) b.id: b.name};
  Map<String, String> get unitNames => {for (final u in units) u.id: u.name};
  Map<String, String> get topNames => {for (final t in tops) t.id: t.name};

  /// 四个维度全空 → 面板显示「暂无可筛选的库信息」。
  bool get isEmpty =>
      basics.isEmpty && bigs.isEmpty && units.isEmpty && tops.isEmpty;
}

/// 由结构原料汇总筛选项。
///
/// - [basics]：基础库（已按调用方作用域筛好；跨连接时可直接拼多份）；
/// - [units] / [tops]：单元库与顶级节点（＝媒体库根），可来自多份 meta；
/// - [bigNames]：旧「历史分组」名称表，缺失时回落 id；
/// - [unitNameOf]：单元库名称解析（`LibMeta.unitNameOf`；省略时用 `UnitLibrary.name`）。
///   传它是因为 `secret` 这一层的名字来自 `TopNodeName`，不是节点自身字段。
///
/// 传空输入时返回空选项：不猜、不造假条目。
AuthorFilterOptions authorFilterOptionsFrom({
  required Iterable<BasicLib> basics,
  Iterable<UnitLibrary> units = const <UnitLibrary>[],
  Iterable<UnitLibrary> tops = const <UnitLibrary>[],
  Map<String, String> bigNames = const {},
  String Function(String unitId)? unitNameOf,
}) {
  // 基础库：同一 id 可能出现多份（跨连接聚合），`authorLibNodes` 去重。
  final basicNodes = <AuthorLibNode>[
    for (final b in basics)
      AuthorLibNode(id: b.id, name: basicLibLabel(b, b.name), bigId: b.bigId),
  ];

  // 旧「历史分组」维度：名称来自 `bigNames`，都没有就回落 id（不猜）。
  final bigNodes = authorBigNodes(basicNodes, nameOf: (id) {
    final n = bigNames[id];
    return (n == null || n.isEmpty) ? id : n;
  });

  // 单元库：id 唯一，名称由 [unitNameOf] 决定（同一 id 先到先得）。
  final unitNodes = <AuthorLibNode>[];
  final unitSeen = <String>{};
  for (final u in units) {
    if (u.id.isEmpty || !unitSeen.add(u.id)) continue;
    // 解析器优先，但它给空串时用节点自身的名字（`LibMeta.unitNameOf` 只在
    // 认识这个 id 时才非空；`secret` 之外的一律回落节点名），最后才回落 id。
    final resolved = unitNameOf?.call(u.id) ?? '';
    final name = resolved.trim().isNotEmpty ? resolved : u.name;
    unitNodes.add(AuthorLibNode(id: u.id, name: libEntryTitle(u.id, name)));
  }

  // 顶级节点（＝媒体库根）：同上，跨连接聚合后可能来自不同 meta。
  final topNodes = <AuthorLibNode>[];
  final topSeen = <String>{};
  for (final t in tops) {
    if (t.id.isEmpty || !topSeen.add(t.id)) continue;
    topNodes.add(AuthorLibNode(id: t.id, name: libEntryTitle(t.id, t.name)));
  }

  return AuthorFilterOptions(
    basics: authorLibNodes(basicNodes),
    bigs: bigNodes,
    units: authorLibNodes(unitNodes),
    tops: authorLibNodes(topNodes),
  );
}

/// 基础库 id → 单元库 id：按给定的映射表查，缺失返回空串（不猜）。
///
/// 面板在 `matches` 里要按「单元库维度」判断，而作者/作品条目只带基础库 id。
String unitIdOfBasic(Map<String, String> basicToUnit, String basicId) =>
    basicId.isEmpty ? '' : (basicToUnit[basicId] ?? '');

/// 筛选摘要（工具栏那一行）：四个名称表都来自同一份 [options]。
///
/// 页面此前写成
/// `f.summary(basicNames: _options.basicNames, bigNames: _options.bigNames, …)`
/// ——同一个 getter 被求值四次，每次都要重新汇总四个维度并排序。
/// 这里把「求值一次、传四张表」收成一句，页面只提供 [options]。
String authorFilterSummary(AuthorFilterState f, AuthorFilterOptions options) =>
    f.summary(
      basicNames: options.basicNames,
      bigNames: options.bigNames,
      unitNames: options.unitNames,
      topNames: options.topNames,
    );
