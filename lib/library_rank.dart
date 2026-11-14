// 「各库总播放量/水滴数排行榜」聚合逻辑（纯函数，便于测试）。
//
// 输入：
//  - libs:  /api/libraries 返回的 libraries 列表（含 id/name/baseOk/indexOk）
//  - stats: 以库 id 为键的作者统计（/api/author_stats.json 的 authors 或整份内容）
//  - metric: 'play' 或 'drop'
//
// 规则：
//  - 离线库（baseOk/indexOk 明确为 false）不参与排行
//  - 没有取到统计的库（stats 缺失）同样不参与，避免把网络失败当成 0
//  - 总播放量 = 作者 p 之和；总水滴数 = 作者 dr 之和
//  - 按所选指标降序，同分按库名、id 稳定排序

class LibraryRankRow {
  final String id;
  final String name;
  final int plays;
  final int drops;
  final bool online;
  final bool current;
  final int rank;

  const LibraryRankRow({
    required this.id,
    required this.name,
    required this.plays,
    required this.drops,
    required this.online,
    required this.current,
    required this.rank,
  });

  int score(String metric) => metric == 'drop' ? drops : plays;
}

bool libraryOnline(Map<String, dynamic> lib) {
  if (lib['baseOk'] == false) return false;
  if (lib['indexOk'] == false) return false;
  return true;
}

int _num(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

/// 从一份 author_stats 响应中取出 authors 映射。
Map<String, dynamic> statsAuthors(dynamic raw) {
  if (raw is Map && raw['authors'] is Map) {
    return Map<String, dynamic>.from(raw['authors'] as Map);
  }
  return const {};
}

/// 汇总单个库的播放/水滴。
({int plays, int drops}) libraryTotals(Map<String, dynamic> stats) {
  var plays = 0, drops = 0;
  for (final v in stats.values) {
    if (v is! Map) continue;
    plays += _num(v['p']);
    drops += _num(v['dr']);
  }
  return (plays: plays, drops: drops);
}

List<LibraryRankRow> buildLibraryRank({
  required List<Map<String, dynamic>> libs,
  required Map<String, Map<String, dynamic>> stats,
  required String metric,
  String? currentLib,
}) {
  final rows = <LibraryRankRow>[];
  for (final lib in libs) {
    final id = '${lib['id'] ?? ''}';
    if (id.isEmpty) continue;
    final online = libraryOnline(lib);
    if (!online) continue;
    final st = stats[id];
    if (st == null) continue; // 统计不可用，视为离线
    final t = libraryTotals(st);
    rows.add(LibraryRankRow(
      id: id,
      name: '${lib['name'] ?? id}'.trim().isEmpty ? id : '${lib['name'] ?? id}',
      plays: t.plays,
      drops: t.drops,
      online: online,
      current: currentLib != null && currentLib == id,
      rank: 0,
    ));
  }
  rows.sort((a, b) {
    final c = b.score(metric).compareTo(a.score(metric));
    if (c != 0) return c;
    final p = b.plays.compareTo(a.plays);
    if (p != 0) return p;
    final n = a.name.compareTo(b.name);
    if (n != 0) return n;
    return a.id.compareTo(b.id);
  });
  final out = <LibraryRankRow>[];
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    out.add(LibraryRankRow(
      id: r.id,
      name: r.name,
      plays: r.plays,
      drops: r.drops,
      online: r.online,
      current: r.current,
      rank: i + 1,
    ));
  }
  return out;
}
