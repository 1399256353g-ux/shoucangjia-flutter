import 'emoji_text.dart';

/// 0.9.6 起：旧注册表（`/api/libraries`）里的「抖音收藏」不再作为展示文案。
///
/// 旧实现把这条映射成「当前媒体库」——那是单库时代的措辞。现在主页多库并列、
/// 没有任何一个库是「当前」的，这个词会让用户以为别的库没生效（owner
/// 2026-11-27：「各个地方都要适应多媒体库管理」）。映射改为回落到库 id：
/// 那是真实的标识，不带假的库状态。
const String legacyDouyinName = '抖音收藏';

/// 把库名规范成可展示文案：
/// - 修掉破碎 emoji；
/// - 空名回落到 id；
/// - 旧版「抖音收藏」→ 库 id（其它库带同样字样时同样回落到 id）。
String displayLibraryName(String id, String? rawName) {
  final name = fixDisplayName('${rawName ?? ''}', fallback: id);
  if (name.contains(legacyDouyinName)) return id;
  return name;
}

/// 复制一份库列表并把每项的 `name` 换成展示文案（不改原 map）。
List<Map<String, dynamic>> librariesWithDisplayNames(
    List<Map<String, dynamic>> libs) {
  return [
    for (final l in libs)
      {
        ...l,
        'name': displayLibraryName('${l['id']}', l['name']?.toString()),
      }
  ];
}
