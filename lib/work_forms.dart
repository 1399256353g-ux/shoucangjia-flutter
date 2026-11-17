/// J5：作品形态与视频合集章节。
///
/// 索引约定（服务端 `gen_lib_index.py` 生成）：
///   `kind`: single / chapters / post / album
///   `ch`:   视频合集章节列表，每项 `{ti, m, du, th}`
/// 单视频、单图、图文、图片合集沿用原有 `t` + `m` 字段，播放器无需改协议；
/// 视频合集额外提供 `ch`，播放页按章节切换 `m`/`du` 即可。
library;

/// 章节是否为图片（混合合集里图片章节排在最后）。
bool chapterIsImage(dynamic chapter) {
  if (chapter is! Map) return false;
  final t = '${chapter['t'] ?? ''}'.trim();
  if (t == 'p' || t == 'i') return true;
  if (t == 'v') return false;
  final m = chapter['m'];
  if (m is List && m.isNotEmpty) {
    final u = '${m.first}'.toLowerCase();
    return !(u.endsWith('.mp4') ||
        u.endsWith('.webm') ||
        u.endsWith('.mov') ||
        u.endsWith('.m4v'));
  }
  return false;
}

/// 章节列表；没有合集时返回空列表。
///
/// 同一作品文件夹同时有视频和图片时按「合集」处理，视频章节在前、
/// 图片章节排在最后（owner 2026-11-17 规则）。
List<Map<String, dynamic>> workChapters(dynamic work) {
  if (work is! Map) return const <Map<String, dynamic>>[];
  final raw = work['ch'];
  if (raw is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  if (out.length > 1) {
    final vids = <Map<String, dynamic>>[];
    final pics = <Map<String, dynamic>>[];
    for (final c in out) {
      (chapterIsImage(c) ? pics : vids).add(c);
    }
    return <Map<String, dynamic>>[...vids, ...pics];
  }
  return out;
}

int workChapterCount(dynamic work) => workChapters(work).length;

/// 作品形态：single / chapters / post / album。
/// 旧数据没有 `kind` 时按 `t` + 媒体数量推断（视频=单视频，多图=图文）。
String workKind(dynamic work) {
  if (work is! Map) return 'single';
  final k = '${work['kind'] ?? ''}'.trim();
  if (k == 'single' || k == 'chapters' || k == 'post' || k == 'album') {
    return k;
  }
  if (work['t'] == 'v') return workChapterCount(work) > 1 ? 'chapters' : 'single';
  final m = work['m'];
  if (work['t'] == 'p') return (m is List && m.length > 1) ? 'post' : 'single';
  return 'single';
}

/// 网格/列表右上角形态标签。
String workTypeLabel(dynamic work) {
  switch (workKind(work)) {
    case 'chapters':
      return '合集';
    case 'album':
      // E2：图片合集与筛选口径一致，统一显示「合集」（不再单独写「图片」）。
      return '合集';
    case 'post':
      return '图文';
    default:
      return (work is Map && work['t'] == 'v') ? '视频' : '图片';
  }
}

/// 章节显示名：优先索引里的标题，缺失时回退「第 N 集」。
String chapterLabel(dynamic chapter, int index) {
  if (chapter is Map) {
    final t = '${chapter['ti'] ?? ''}'.trim();
    if (t.isNotEmpty) return t;
  }
  return '第 ${index + 1} 集';
}

/// 合集内切到第 [index] 章时返回叠加后的作品 Map。
/// 非合集或索引越界时原样返回。
Map<String, dynamic> workWithChapter(dynamic work, int index) {
  if (work is! Map) return <String, dynamic>{};
  final base = Map<String, dynamic>.from(work);
  // 图片合集（kind=album）本质是「一组图片」，缺 t 时按图片播放。
  if ('${base['kind'] ?? ''}' == 'album' && '${base['t'] ?? ''}'.isEmpty) {
    base['t'] = 'p';
  }
  final chs = workChapters(work);
  if (chs.length <= 1) return base;
  final i = index.clamp(0, chs.length - 1);
  final c = chs[i];
  // 混合合集：图片章节切回图片模式，视频章节切回视频模式。
  final ct = '${c['t'] ?? ''}'.trim();
  if (ct == 'p' || ct == 'v') base['t'] = ct;
  final m = c['m'];
  if (m is List && m.isNotEmpty) base['m'] = m;
  if (c['du'] != null) base['du'] = c['du'];
  base['c'] = i;
  return base;
}

/// 观看进度/继续观看的作品键：合集按章节区分，避免不同章节互相覆盖。
String workWatchKeyFor(dynamic work, int chapter) {
  final id = '${(work is Map ? work['id'] : null) ?? ''}';
  if (workChapterCount(work) <= 1) return id;
  final i = chapter.clamp(0, workChapterCount(work) - 1);
  return '$id#c${i + 1}';
}

/// 合集总时长（秒，仅统计有 `du` 的章节）；无数据返回 0。
num workTotalDuration(dynamic work) {
  num asNum(dynamic v) {
    if (v is num && v > 0) return v;
    if (v is String) return num.tryParse(v.trim()) ?? 0;
    return 0;
  }

  final chs = workChapters(work);
  if (chs.length > 1) {
    num total = 0;
    for (final c in chs) {
      total += asNum(c['du']);
    }
    return total;
  }
  return work is Map ? asNum(work['du']) : 0;
}

/// J6：作者主页作品筛选分类。
/// 视频=单视频，图片=单张图片，合集=视频合集/图片合集，图文=多图图文。
const String workFilterVideo = 'video';
const String workFilterPost = 'post';
const String workFilterCollection = 'collection';
const String workFilterPicture = 'picture';

const List<String> workFilterOrder = [
  workFilterVideo,
  workFilterPicture,
  workFilterCollection,
  workFilterPost,
];

String workFilterLabel(String type) {
  switch (type) {
    case workFilterVideo:
      return '视频';
    case workFilterPost:
      return '图文';
    case workFilterCollection:
      return '合集';
    case workFilterPicture:
      return '图片';
    default:
      return '其他';
  }
}

String workFilterType(dynamic work) {
  if (work is! Map) return 'other';
  switch (workKind(work)) {
    case 'chapters':
    case 'album':
      return workFilterCollection;
    case 'post':
      return workFilterPost;
    default:
      if (work['t'] == 'v') return workFilterVideo;
      if (work['t'] == 'p') return workFilterPicture;
      return 'other';
  }
}

/// 空集合表示不过滤；多选时并按命中。
List<dynamic> filterWorksByType(List<dynamic> works, Set<String> selected) {
  if (selected.isEmpty) return List<dynamic>.from(works);
  return works
      .where((w) => selected.contains(workFilterType(w)))
      .toList(growable: false);
}

/// 各分类数量（按筛选栏顺序，全部返回，含 0）。
Map<String, int> workTypeCounts(List<dynamic> works) {
  final out = {for (final t in workFilterOrder) t: 0};
  for (final w in works) {
    final t = workFilterType(w);
    out[t] = (out[t] ?? 0) + 1;
  }
  return out;
}
