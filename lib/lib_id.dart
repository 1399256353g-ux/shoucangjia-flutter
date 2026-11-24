/// 库 / 单元库 id 的**唯一**书写规则。
///
/// 同一个库在代码里有两种 id 形式：
///   - `node:<rel>`：主页节点树（`LibNode.id`）与 `UnitLibrary` 树用；
///   - `<rel>`       ：`LibMeta`、基础库→单元库映射、配色落盘用。
///
/// 这个「去前缀」动作此前在 14 处各写一遍（`library_badge.dart` 10 处、
/// `main.dart` 1 处、`unit_library.dart` 2 处，再加上各处 `'node:$rel'`
/// 拼回去），并且**查询顺序并不一致**：有的先查 `id` 再查 `rel`，
/// 有的只查 `rel`，删除时有的只删两种键、有的删三种。
/// 结果同一份配色/emoji 设置会出现「设置页显示自定义、卡片上还是自动色」
/// 这种两边都自洽却不一致的状态。
///
/// 现在这里只保留两条规则：怎么归一、怎么列出全部等价键。
library;

/// `node:rel` → `rel`；已经是 `rel` 就原样返回。
///
/// 只剥一层：`node:node:x` 这种构造没有语义，不猜。
String relOf(String id) {
  final s = id.trim();
  if (s.isEmpty) return '';
  return s.startsWith('node:') ? s.substring(5) : s;
}

/// 同一库的全部等价键，**按查询优先级**排列：调用方写的那个 id 最优先，
/// 然后是裸 `rel`，最后是带前缀形式。
///
/// 顺序固定是这条规则唯一被允许的「优先级」表达；不要在调用点再写
/// `m[a] ?? m[b] ?? m[c]` —— 三处写过之后就会有一处顺序写反。
List<String> idFormsOf(String id) {
  final s = id.trim();
  if (s.isEmpty) return const <String>[];
  final rel = relOf(s);
  if (rel.isEmpty) return <String>[s];
  final prefixed = 'node:$rel';
  final out = <String>[s];
  if (rel != s) out.add(rel);
  if (!out.contains(prefixed)) out.add(prefixed);
  // 裸 rel 必须排在带前缀之前（否则 `node:x` 的裸写法会被前缀写法盖住），
  // 上面的构造已保证；这里只做去重后的稳定性收尾。
  return out;
}

/// 按 [id] 的全部等价形式在 [m] 里查值，命中第一个非空即返回。
///
/// 返回 `null` 表示「这个库没设过」，与「设成空」区分开。
T? lookupByLibId<T>(Map<String, T> m, String id) {
  for (final k in idFormsOf(id)) {
    final v = m[k];
    if (v != null) return v;
  }
  return null;
}

/// 把同一库的所有等价键从 [m] 里删掉（改设置/清设置时的统一动作）。
///
/// 返回实际删掉的键数，便于测试断言「三种形式一起清掉」。
int removeByLibId<T>(Map<String, T> m, String id) {
  var n = 0;
  for (final k in idFormsOf(id)) {
    if (m.remove(k) != null) n++;
  }
  return n;
}
