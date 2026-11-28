/// 稳定排序（**唯一实现**）。
///
/// Dart 的 `List.sort` **不保证稳定**（用的是内省排序）。这一点在本项目里
/// 直接表现成「刷新一下，同名的卡片换了位置」：
///
///  - `unit_library.build` 里 `kids.sort((a,b) => a.name.compareTo(b.name))`
///    ——同一层有两个同名单元库（不同路径、不同 rel）时，两者顺序每次重建
///    都可能变；
///  - `category_tree` 对分类子节点按名称排序，同名目录（`A/新建` 与
///    `B/新建` 在各自父下同名）在父列表里顺序不定；
///  - `main` 里两处 `_filterBigs` 与搜索页的分组下拉同理，`bigNames`
///    里出现重名时下拉项会自行跳动。
///
/// 这些地方都**没有**真正的次序依据（名称相同），所以正确做法不是再加一个
/// 排序键（那是编造语义），而是让排序对相等元素保持输入顺序——输入顺序本身
/// 是确定的（磁盘遍历/注册顺序），于是结果也就是确定的。
///
/// 实现用「下标作为第二排序键」：先按比较函数比，相等时比原始下标。
/// 这等价于稳定排序，且不需要自己写归并。
library;

/// 稳定排序：相等元素的相对顺序与 [items] 中一致。原地排序并返回同一列表。
List<T> stableSort<T>(List<T> items, int Function(T a, T b) compare) {
  if (items.length < 2) return items;
  final indexed = List<int>.generate(items.length, (i) => i);
  indexed.sort((ia, ib) {
    final c = compare(items[ia], items[ib]);
    return c != 0 ? c : ia.compareTo(ib);
  });
  final out = <T>[for (final i in indexed) items[i]];
  // 用 setAll 而不是逐个下标赋值：调用方传进来的可能是 fixed-length 列表
  // （`const []` 派生或 `List.filled`），逐个赋值会抛 UnsupportedError。
  items.setAll(0, out);
  return items;
}

/// 按名称升序稳定排序（同名的保持输入顺序）。
///
/// [nameOf] 取比较用的名称；调用方传的应是**已规范化**的名称（去序号、
/// 修 emoji），不要在比较函数里再做一次解析——否则每次比较都多算一遍。
List<T> stableSortByName<T>(List<T> items, String Function(T) nameOf) =>
    stableSort<T>(items, (a, b) => nameOf(a).compareTo(nameOf(b)));
