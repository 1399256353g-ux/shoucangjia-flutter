/// 「名字为空就回落 id」的唯一实现。
///
/// 0.9.351：这句判定（`x.name.trim().isEmpty ? x.id : x.name`，或只判
/// `isEmpty`）此前在**五处**各写一遍：
///
/// | 位置 | 写法 |
/// |---|---|
/// | `author_big_nodes.authorBigNodes` | `trim().isEmpty` ✅ |
/// | `author_filter_options`（顶级节点汇总） | `trim().isEmpty` ✅ |
/// | `main.LibMeta.topLabelFor` | `trim().isEmpty` ✅ |
/// | `main._topSection`（设置页分组头） | **`isEmpty`** ❌ |
/// | `main._libTile`（设置页流水行） | **`isEmpty`** ❌ |
/// | `library_rank.buildLibraryRank` | **`isEmpty`** ❌ |
///
/// 差异看起来只是「要不要去空白」，后果是**同一个库在两页显示两个名字**：
/// 服务端把某个库名下发成纯空格（或旧数据里是 `""` 加不可见字符）时，筛选
/// 面板与删除监测页回落 id（能看出是哪个库），设置页与各库排行却把一条看不
/// 见的空白画成标题——用户以为那个库没名字，或者压根没列出这个库。
///
/// 因此判定与回落只留这一处：**去空白后仍为空 → 回落 id**；否则原样返回
/// 传入的名字（本函数不改写用户看到的文字，去序号/修 emoji 是别的环节）。
library;

/// 名字为空时回落 [id]；非空（哪怕只有空格视为空）时原样返回名字。
///
/// [id] 也做去空白：调用方传进来的 id 常来自 JSON `${e['id']}`，缺字段时
/// 是字面量 `"null"` 之外的空串，这里统一 trim 一次，避免 `' '` 这种 id
/// 被当成有效回落值画到界面上。
String labelOrId(String id, String? name) {
  final n = '${name ?? ''}';
  if (n.trim().isNotEmpty) return n;
  return id.trim();
}

/// 库 id + 服务端下发的名字 → 分支标题/导航用的显示名。
///
/// 0.9.352：这条「名字去空白后仍空就宁可用 id」的判定在挂载面板里写过三份：
///  - `author_mount_sheet._libLabelOf`（遍历 `mounts.items` 找 `libName`）；
///  - `unit_author_mount_page._libLabelOf`（遍历 `unit.allBasics` 找 `name`）；
///  - `AuthorMountItem.displayLib`（裸 `isEmpty`，名字是纯空格时
///    返回一个看不见的空串，列表行开头一片空白）。
///
/// 三份都在问同一件事（「这个库在这张列表里叫什么」），却各自找不同的数据源，
/// 于是同一个库在作者页的挂载面板与单元库页的挂载面板上可能一个有名一个只剩 id。
/// 这里只保留一条规则：**去空白后仍为空 → id**，非空则原样返回。
///
/// 本函数不改写展示文字（去序号/修 emoji 属于渲染层），也不猜数据源——
/// 调用方把自己手里那份名字传进来。
String libLabelOf(String id, String? rawName) =>
    labelOrId(id, '${rawName ?? ''}');
