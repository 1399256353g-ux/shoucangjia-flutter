import 'emoji_text.dart';
import 'label_fallback.dart';
import 'library_badge.dart' show LibraryBadge;

/// 0.9.6 起：旧注册表（`/api/libraries`）里的「抖音收藏」不再作为展示文案。
///
/// 旧实现把这条映射成「当前媒体库」——那是单库时代的措辞。现在主页多库并列、
/// 没有任何一个库是「当前」的，这个词会让用户以为别的库没生效（owner
/// 2026-11-27：「各个地方都要适应多媒体库管理」）。映射改为回落到库 id：
/// 那是真实的标识，不带假的库状态。
const String legacyDouyinName = '抖音收藏';

/// 把库名规范成可展示文案：
/// - 修掉破碎 emoji；
/// - 空名回落到 id（判定只在 [labelOrId] 一处）；
/// - 旧版「抖音收藏」→ 库 id（其它库带同样字样时同样回落到 id）。
String displayLibraryName(String id, String? rawName) {
  // 先只做「修 emoji / 去首尾空白」，回落交给 `labelOrId`：此前这里用
  // `fixDisplayName(fallback: id)` 自己做了一次回落，而筛选面板/设置页/
  // 各库排行又各自做了两次（一个判 `trim()`、一个判裸空），三份对「名字
  // 是纯空格」给出两个答案。现在「空名 → id」全项目只有一个决定点。
  final fixed = fixDisplayName('${rawName ?? ''}', fallback: '');
  final name = labelOrId(id, fixed);
  if (name.contains(legacyDouyinName)) return id;
  return name;
}

/// 界面上「一个媒体库叫什么」的**唯一**出口：先规范化名称，再按
/// 设置里的「省略序号」开关去 `(1) ` 前缀。
///
/// 此前这条组合在两个页面各写一份、还写得不一致：
///   网络设置/库管理只调 `displayLibraryName`，目录名带 `(1) ` 时原样露出；
///   爬虫设置页套了 `LibraryBadge.stripIndex`，同一个库在两页显示两个名字。
/// 用户以为那是两个库（「为什么这边有括号那边没有」）。
String libraryDisplayName(String id, String? rawName) =>
    LibraryBadge.stripIndex(displayLibraryName(id, rawName));

/// 复制一份库列表并把每项的 `name` 换成展示文案（不改原 map）。
List<Map<String, dynamic>> librariesWithDisplayNames(
    List<Map<String, dynamic>> libs) {
  return [
    for (final l in libs)
      {
        ...l,
        // 只做名称规范化；去 `(1) ` 序号是渲染时的事（`libraryDisplayName`）。
        // 这里不能顺手剥：库列表还要按原名与其它来源比对。
        'name': displayLibraryName('${l['id']}', l['name']?.toString()),
      }
  ];
}
