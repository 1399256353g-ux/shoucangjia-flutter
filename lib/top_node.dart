/// 顶级节点（＝媒体库根）的名称来源。
///
/// owner 2026-11-22 纠正：`SECRET` 只是**当前这个媒体库的根目录文件夹名**，
/// 不是内置常量。顶级节点名称必须取「所连接媒体库的根目录名」；换一个根目录
/// 名不同的媒体库连接后，顶级节点就显示它的根目录名。
///
/// 因此这里只有解析与当前值，没有任何硬编码回退文案：
/// - [nameFromRoot] 从服务端下发的库根路径取最后一段；
/// - [current] 是最近一次成功解析出的名称，供 `unitNameOf('secret')` 之类的
///   展示位使用（内部 id 仍保留 `secret`，那是标识不是文案）。
library;

/// 完全拿不到根路径时的兜底文案（仅在服务端未下发 root 时出现）。
const String kFallbackTopNodeName = 'SECRET';

class TopNodeName {
  static String _current = kFallbackTopNodeName;

  /// 当前顶级节点名称（最近一次从库根解析出的值）。
  static String get current => _current;

  /// 从库根路径解析顶级节点名称；空/无效返回空串，不猜名字。
  ///
  /// 兼容 `/vol1/名称`、`E:\media\名称`、`/vol1/名称/` 三种写法。
  static String nameFromRoot(String? root) {
    final raw = '${root ?? ''}'.trim();
    if (raw.isEmpty) return '';
    final parts = raw
        .replaceAll('\\', '/')
        .split('/')
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '';
    // Windows 盘符（`E:`）本身不是目录名。
    final last = parts.last.trim();
    if (last.length <= 2 && last.endsWith(':')) return '';
    return last;
  }

  /// 用库根路径更新名称；解析不出时保持上一个已知值（不清成空）。
  static bool setFromRoot(String? root) {
    final n = nameFromRoot(root);
    if (n.isEmpty || n == _current) return false;
    _current = n;
    return true;
  }

  /// 直接设定名称（测试与已有名称的页面用）。
  static void set(String? name) {
    final n = '${name ?? ''}'.trim();
    if (n.isNotEmpty) _current = n;
  }

  static void reset() => _current = kFallbackTopNodeName;
}
