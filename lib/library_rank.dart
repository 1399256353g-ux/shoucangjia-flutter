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
library;

import 'http_json.dart';
import 'json_num.dart';

class LibraryRankRow {
  final String id;
  final String name;
  final int plays;
  final int drops;
  final bool online;
  /// 是否是服务端注册表里的**默认库**（`/api/libraries` 的 `default`）。
  ///
  /// 0.9.317：字段原名 `current`，界面写「当前」——那是单库时代的说法。
  /// 多库里没有任何一个库是「当前」，只有服务端指定的默认库；口径统一后
  /// 词条文字与网络设置/库管理的「默认」一致。
  final bool isDefault;
  final int rank;

  const LibraryRankRow({
    required this.id,
    required this.name,
    required this.plays,
    required this.drops,
    required this.online,
    required this.isDefault,
    required this.rank,
  });

  int score(String metric) => metric == 'drop' ? drops : plays;
}

/// 库在线判定：`baseOk` / `indexOk` 任一为假即离线。
///
/// 不能写 `== false`：服务端把这两个字段发成 `0` / `"false"` / `"no"` 时
/// 裸比较一个都不认，离线库会被当成在线去请求 author_stats，排行榜里显示
/// 0 播放（看起来像「数据丢了」）。三态解析只有 `json_num.boolOrNull` 一份。
bool libraryOnline(Map<String, dynamic> lib) {
  final base = boolOrNull(lib['baseOk']);
  if (base != null && !base) return false;
  final index = boolOrNull(lib['indexOk']);
  if (index != null && !index) return false;
  return true;
}


/// 从一份 author_stats 响应中取出 authors 映射。
Map<String, dynamic> statsAuthors(dynamic raw) {
  final m = mapOrNull(raw);
  if (m == null) return const {};
  return mapOrNull(m['authors']) ?? const {};
}

/// 汇总单个库的播放/水滴。
///
/// 用饱和加法（[addSat]）：服务端把某个作者的计数写成 int 上限时，
/// 两个库条目相加就能让总播放量变成负数（实测 `max + max = -2`），
/// 排行榜把该库排到最后并显示负值。
///
/// **负值不参与累加**：服务端下发 `p: -100` 这类条目时（计数器重置出错、
/// 占位值），旧实现直接相加，一个 `-100` 就能把整库的总播放量拉成
/// 负数（实测 `{'p': -100} + {'p': 50}` → `-50`），排行榜那行读作
/// 「-50 播放」，看起来像「播放量被扣掉了」。计数单价不存在负数，
/// 负条目按 0 计，与 `json_num.sumSat` / `AuthorGrade.score` 同一条口径。
({int plays, int drops}) libraryTotals(Map<String, dynamic> stats) {
  var plays = 0, drops = 0;
  for (final v in stats.values) {
    if (v is! Map) continue;
    final p = intOf(v['p']);
    final d = intOf(v['dr']);
    if (p > 0) plays = addSat(plays, p);
    if (d > 0) drops = addSat(drops, d);
  }
  return (plays: plays, drops: drops);
}

List<LibraryRankRow> buildLibraryRank({
  required List<Map<String, dynamic>> libs,
  required Map<String, Map<String, dynamic>> stats,
  required String metric,
  String? defaultLib,
}) {
  final rows = <LibraryRankRow>[];
  final seen = <String>{};
  for (final lib in libs) {
    final id = '${lib['id'] ?? ''}';
    if (id.isEmpty) continue;
    // 同一个库 id 出现两次（聚合时两台服务端报同一个库、或旧格式重注册）
    // 会产出两行**完全等键**的记录：`score`/`plays`/`name`/`id` 四项全相等，
    // 而 `List.sort` 不保证稳定——同一份数据刷两次，两行名次岔开（1/2 变 2/1）。
    // 库 id 是唯一标识，重复项按第一条计入（与 `lib_id` 去重同一口径）。
    if (!seen.add(id)) continue;
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
      isDefault: defaultLib != null && defaultLib == id,
      rank: 0,
    ));
  }
  // 排序规则（**唯一**）：指标分降序 → 播放量降序 → 库名升序 → id 升序。
  // 四级键里最后一级（id）保证唯一（上面已按 id 去重），所以结果与 libs 的
  // 入参顺序无关；不要去掉 id 这一级——只到库名为止时，两个同名库
  // （`(8) 🦶` 与 `(9) 🦶` 去序号后同名）名次会随服务端下发顺序变。
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
      isDefault: r.isDefault,
      rank: i + 1,
    ));
  }
  return out;
}
