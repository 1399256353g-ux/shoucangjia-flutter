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

/// 服务端遗留的「注册库」记录：`douyin` 是旧收藏夹同步时代的元数据库
/// （`dir` 指向 `/home/zzx/.local/share/gallery`，不在库根下）。
///
/// owner 2026-11-28：「当前根本就没有这个媒体库，douyin 现在就是个普通的
/// 单元库而已」——它出现在爬虫设置分节标题、各库排行列表、诊断「当前连接」
/// 后面，被当成了一个媒体库名字。
///
/// 判据只看结构（id 且 `base` 不是库根下的真实目录都算遗留），不看名字文本：
/// 这里沿用旧 id 判定（与 `main.dart` 既有 `!= 'douyin'` 同一口径），
/// 但出口收在这一个函数，新增入口不能各自再写一遍。
bool isLegacyMetaLibrary(Map<String, dynamic> lib) =>
    '${lib['id'] ?? ''}'.trim() == 'douyin';

/// 去掉遗留元数据库后的注册库列表（展示与统计都用它）。
List<Map<String, dynamic>> visibleLibraries(
    List<Map<String, dynamic>> libs) =>
    [
      for (final l in libs)
        if (!isLegacyMetaLibrary(l)) l
    ];

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

/// 卡片标题 / 页面标题里的库名：**去序号 + 名字空则回落 id**。
///
/// 0.9.352：各处原来直接写 `stripIndex(name)`——`stripIndex` 只做两件事
/// （按开关去掉 `(1) ` 前缀、trim），**名字为空时返回空串**。服务端没下发名字
/// 的基础库/单元库于是：卡片标题空白、页面标题只剩 emoji 后缀，而同一个库在
/// 词条里（`LibraryBadge.labels` → `labelOrId`）显示的是 id。同一个库两处两个
/// 样子，其中一处看起来像「没有名字的卡片」。
///
/// 与 [libraryDisplayName] 的分工：那个用于「库」这一层（含旧「抖音收藏」
/// 收敛与破碎 emoji 修复）；本函数用于**目录节点**（单元库/基础库）的标题，
/// 只做去序号与回落 id，不改变任何现有显示文字。
String libEntryTitle(String id, String? rawName) =>
    LibraryBadge.stripIndex(labelOrId(id, rawName));

/// 名字 → 词条/标题上的展示文字：**只做去序号与空白折叠，不回落 id**。
///
/// 0.9.354：`source_lib.basicLibLabel` 此前用 `normalizeLibLabel`，而那个函数
/// 走的是 `stripIndexPrefix`——**无条件**去序号，与设置里的「省略编号」开关
/// 无关。于是关掉开关后出现两个说法：卡片标题显示 `(1) 名称`，同一页的筛选
/// 面板/作者卡词条显示 `名称`；用户以为那是两个库。
///
/// 现在去序号这件事只由 [LibraryBadge.stripIndex] 一处判断（它读开关），
/// 空白折叠仍在这里做一次（`( 14 )  擦边` 这种名字里有多余空格）。
String libDisplayName(String? rawName) {
  final s = LibraryBadge.stripIndex('${rawName ?? ''}');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// 复制一份库列表并把每项的 `name` 换成展示文案（不改原 map）。
///
/// 遗留元数据库（[isLegacyMetaLibrary]）在入口就滤掉，不让它被当成媒体库。
List<Map<String, dynamic>> librariesWithDisplayNames(
    List<Map<String, dynamic>> libs) {
  return [
    for (final l in visibleLibraries(libs))
      {
        ...l,
        // 只做名称规范化；去 `(1) ` 序号是渲染时的事（`libraryDisplayName`）。
        // 这里不能顺手剥：库列表还要按原名与其它来源比对。
        'name': displayLibraryName('${l['id']}', l['name']?.toString()),
      }
  ];
}
