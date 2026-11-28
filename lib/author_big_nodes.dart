/// 作者筛选里的旧分组（`big_id`，即第一层单元库）选项列表（**唯一实现**）。
///
/// 这段逻辑此前在两个页面里各写一份、而且写法不同：
///
///  作者总览 / 排行 —— 先全部收集、再 `removeWhere` 去重，名称取
///    `meta?.bigNames[id] ?? id`；
///  推荐 / 搜索 —— 遍历时 `seen.add` 去重，名称遍历 `metas.values` 找第一个
///    非空值。
///
/// 两者只在「名称到哪去找」上不同（一个是单份 meta，一个是多份合并），
/// 去重与排序本该是同一条规则。分歧的后果是同一个单元库在两个页面的筛选
/// 下拉里可能显示不同名字（一个回落到 id，一个拿到别名）。
///
/// 这里只保留结构：调用方传一个 `nameOf(bigId)`，去重与排序都在本文件。
/// 排序必须**稳定**（同名单元库之间没有次序依据），并带 id 作为最终键，
/// 这样同一份数据在两个页面上的顺序也一致——否则用户切页面会发现下拉项
/// 位置自己变了。
library;

import 'author_filter.dart';
import 'lib_names.dart';
import 'stable_order.dart';

/// 由基础库列表汇总出旧分组（第一层单元库）筛选项。
///
/// - 只保留 `bigId` 非空的条目，按 `bigId` 首次出现去重；
/// - 名称由 [nameOf] 决定（回落到 id 由调用方负责，本文件不猜）；
/// - 排序：名称升序，同名再按 id 升序（完全确定，与输入顺序无关）。
List<AuthorBigNode> authorBigNodes(
  Iterable<AuthorLibNode> basics, {
  required String Function(String bigId) nameOf,
}) {
  final out = <AuthorBigNode>[];
  final seen = <String>{};
  for (final b in basics) {
    final id = b.bigId.trim();
    if (id.isEmpty || !seen.add(id)) continue;
    // 回落规则只有 [labelOrId] 一处（去空白后仍空才回落 id）：
    // 写成 `trim().isEmpty` 与 `isEmpty` 的两个调用点，在「名字是纯空格」
    // 那条数据上会给出两个答案。
    out.add(AuthorBigNode(id: id, name: libEntryTitle(id, nameOf(id))));
  }
  return stableSort<AuthorBigNode>(out, (a, b) {
    final c = a.name.compareTo(b.name);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
}
