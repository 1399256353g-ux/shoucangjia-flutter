// 排行榜「按库看」的归属判定（纯函数，便于单测）。
//
// 为什么单独一个文件：这里是本轮之前**唯一**把两种 id 当成同一种用的地方。
//
// 「各库排行」页列的是注册库（`/api/libraries` 的 `libraries`，如 `douyin`），
// 点进去却把那个 id 当**历史分组 id**（`basicLibraries[].big_id`，如 `big-05`）
// 去比：
//
// ```
// RankPage(initialLib: r.id)
//   → _visibleRows: meta.bigIdFor(avatar) == sel
// ```
//
// 两个 id 分属不同命名空间，正常数据下永远不相等——点「某库」进去得到的是
// 「本期还没有播放记录」，看起来像那个库根本没有播放数据。而服务端
// `/api/rank?lib=all` 每行本来就带 `libs`（作者出现在哪些基础库）与 `lib`
// （首个来源库），归属判定应该用它，不需要第二套反查。
//
// 但 `libs` 里是**基础库 id**，`sel` 可能是**注册库 id**：所以判断前先把
// 「选中的库」展开成它包含的基础库集合（`LibMeta.basics`），再比对。
library;

/// 作者是否属于被选中的库。
///
/// - [memberBasics]：选中库包含的基础库 id 集合；空集合表示「这个库没有可
///   归属的基础库」，此时**不匹配任何作者**（不猜、不退回全量——退回全量会
///   让用户以为筛选没生效）。
/// - [basicId]：作者头像/媒体路径反查出的基础库 id（`LibMeta.basicIdForPath`，
///   全 App 唯一那条反查链）。
/// - [rowLibs]：榜单行自带的来源基础库列表（服务端 `lib=all` 下发）。
bool authorInLibrary({
  required Set<String> memberBasics,
  required String basicId,
  required List<String> rowLibs,
}) {
  if (memberBasics.isEmpty) return false;
  if (basicId.isNotEmpty && memberBasics.contains(basicId)) return true;
  for (final l in rowLibs) {
    if (l.isNotEmpty && memberBasics.contains(l)) return true;
  }
  return false;
}
