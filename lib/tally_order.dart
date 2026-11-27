/// 「按首次出现顺序计数」的**唯一实现**。
///
/// 这个形状在本项目里出现得比想象中多：
///
/// | 位置 | 计的是什么 |
/// |---|---|
/// | 作者页来源筛选条 | 作品来自哪个基础库 |
/// | 作者页顶级节点筛选条 | 作品属于哪个媒体库 |
/// | 删除监测页顶级节点条 | 删除记录属于哪个媒体库 |
/// | 作者页作者目录筛选 | 作品来自哪个 `@作者` 目录 |
///
/// 四处的代码**逐字相同**（`if (!counts.containsKey(k)) order.add(k);
/// counts[k] = (counts[k] ?? 0) + 1;`），差别只在「键怎么取」。
///
/// 为什么必须收成一处：`order` 是界面上筛选条的**显示顺序**。某一处写成
/// 「按计数降序」或「按 id 排序」时，同一个媒体库在删除监测页排第一、在
/// 作者页排第三——用户以为是两个不同的维度。而且 `counts[k] ?? 0` 这一句
/// 一旦有人写成 `counts[k]!`，空集合路径上就是一次运行时崩溃。
///
/// 只保留「保序 + 计数」这一条规则；键的取法与空键过滤留给调用方
/// （`keyOf` 返回空串表示这条不计入）。
library;

/// 按 [keyOf] 分组计数，**按首次出现顺序**返回 `(键, 条数)`。
///
/// 不排序：顺序本身就是信息（「先出现的排前面」＝与列表里看到的顺序一致）。
/// 需要排序的调用方请显式排，不要指望这里顺手排——那会让两个页面
/// 对同一份数据给出两种顺序。
List<MapEntry<String, int>> tallyInOrder<T>(
  Iterable<T> items,
  String Function(T item) keyOf,
) {
  final counts = <String, int>{};
  final order = <String>[];
  for (final it in items) {
    final k = keyOf(it);
    if (k.isEmpty) continue;
    if (!counts.containsKey(k)) order.add(k);
    counts[k] = (counts[k] ?? 0) + 1;
  }
  return [for (final k in order) MapEntry(k, counts[k] ?? 0)];
}
