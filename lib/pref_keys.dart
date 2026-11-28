/// 本机偏好键名（客户端侧）的唯一定义处。
///
/// 为什么需要它：这些键此前**各自定义在自己那一个文件里**——
/// `hidden_works_v1` 在 `main.dart`、`folder_unlocked_v1` 在
/// `folder_structure_page.dart`、`lib_tree_stars_v1` 在 `star_store.dart`。
/// 单看每一处都没问题，但它们同属**一件配置资产**（owner 的「本机偏好」）：
/// 导配置、清缓存、迁移、以及任何一次「列出我存过什么」都必须把这三把键
/// 一起读到。散在三个文件里时，加第四把键的人没有地方可抄，也不知道
/// 还有没有人需要跟着加——上一批 `hidden_works_v1` 的「写一处、读另一处」
/// 就是从这里长出来的。
///
/// 口径：
/// - 这里只放**变量名 → 键名**，不放任何读写逻辑（读写仍只有
///   `prefs_json` 一处）；
/// - 服务端的连接类键（`servers_v1` / `lib_bindings_v1` / …）不在这里，
///   它们在 `multi_server.dart` 的 `ConnPrefsKeys`——那几把要连服务端判读，
///   与「纯本机 UI 偏好」不是同一件东西。
library;

/// 不感兴趣的作品 id 集合（首页列表过滤）。
const String kHiddenWorksPrefsKey = 'hidden_works_v1';

/// 文件结构页已解锁的目录 id 列表。
const String kFolderUnlockedPrefsKey = 'folder_unlocked_v1';

/// 星标单元库 id 列表（保持标记顺序）。
const String kStarredLibsPrefsKey = 'lib_tree_stars_v1';

/// 全部本机 UI 偏好键（新增键必须同时加进这里）。
const List<String> kLocalPrefKeys = <String>[
  kHiddenWorksPrefsKey,
  kFolderUnlockedPrefsKey,
  kStarredLibsPrefsKey,
];
