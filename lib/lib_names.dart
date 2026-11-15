import 'emoji_text.dart';

/// 0.9.6 起：旧注册表（`/api/libraries`）里的「抖音收藏」不再作为展示文案。
/// 库列表/标题里的名称统一走这里，旧条目按 id 显示为「默认库」。
const String legacyDouyinName = '抖音收藏';

/// 把库名规范成可展示文案：
/// - 修掉破碎 emoji；
/// - 空名回落到 id；
/// - 旧版「抖音收藏」→「默认库」（其它库若带同样字样则直接显示 id）。
String displayLibraryName(String id, String? rawName) {
  final name = fixDisplayName('${rawName ?? ''}', fallback: id);
  if (name.contains(legacyDouyinName)) {
    return id == 'douyin' ? '默认库' : id;
  }
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
