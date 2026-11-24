/// G20：单条作品数据容错与错误隔离。
///
/// 作品列表来自服务端 JSON，个别条目可能缺字段、`m` 不是数组，或媒体
/// 文件已不存在。这里集中做不抛异常的安全取数，播放页据此展示占位卡片，
/// 同时保留 PageView 的上下滑手势，单条异常不会拖垮整列。
library;

/// 作品媒体路径列表。数据缺失/类型错误时返回空列表，绝不抛异常。
///
/// 服务端对 `m` 有两种写法：数组 `["a.jpg"]` 与单图作品直接给字符串
/// `"a.jpg"`。**只认数组**会让后者在整条链路上被判成「没有媒体」：
/// 播放页显示「作品数据损坏」占位、预载拿不到源、封面角标算 0 张、
/// 「保存到本机」与「移动到文件夹」都直接失败。所以两种写法在这里归一，
/// 凡是读作品媒体的地方都必须走本函数，不得自己 `m is List` 再解一遍。
List<String> workMediaPaths(dynamic w) {
  if (w is! Map) return const <String>[];
  final m = w['m'];
  if (m is String) {
    final one = m.trim();
    return one.isEmpty ? const <String>[] : <String>[one];
  }
  if (m is! List) return const <String>[];
  final out = <String>[];
  for (final e in m) {
    final p = '${e ?? ''}'.trim();
    if (p.isNotEmpty) out.add(p);
  }
  return out;
}

/// 作品是否有可展示内容：视频要有媒体文件，图文至少一张图片。
bool workPlayable(dynamic w) {
  if (w is! Map) return false;
  if (w['t'] != 'v' && w['t'] != 'p') return false;
  return workMediaPaths(w).isNotEmpty;
}

/// 异常作品的简短说明，用于占位卡片。
String workIssueText(dynamic w) {
  if (w is! Map) return '作品数据损坏';
  if (w['t'] == 'v') return '视频文件缺失';
  if (w['t'] != 'p') return '未知作品类型';
  return '图片列表为空';
}

/// 安全读取作品字段；非 Map 或字段缺失时返回 fallback。
dynamic workField(dynamic w, String key, [dynamic fallback]) {
  if (w is! Map) return fallback;
  return w[key] ?? fallback;
}

/// 当前条目是否可以安全作为「上一条/下一条」跳过。
/// 用于连播/自动翻页时跳过损坏条目，避免整列卡在同一条错误上。
int nextPlayableIndex({
  required int current,
  required int count,
  required bool Function(int index) playable,
  int step = 1,
}) {
  if (count <= 0) return -1;
  var i = current + step;
  while (i >= 0 && i < count) {
    if (playable(i)) return i;
    i += step;
  }
  return -1;
}
