/// J5：作品形态与视频合集章节。
///
/// 索引约定（服务端 `gen_lib_index.py` 生成）：
///   `kind`: single / chapters / post / album
///   `ch`:   视频合集章节列表，每项 `{ti, m, du, th}`
/// 单视频、单图、图文、图片合集沿用原有 `t` + `m` 字段，播放器无需改协议；
/// 视频合集额外提供 `ch`，播放页按章节切换 `m`/`du` 即可。
library;

import 'work_safety.dart';
import 'json_num.dart';
import 'media_path.dart';
import 'time_labels.dart';

/// 章节是否为图片（混合合集里图片章节排在最后）。
bool chapterIsImage(dynamic chapter) {
  if (chapter is! Map) return false;
  final t = '${chapter['t'] ?? ''}'.trim();
  if (t == 'p' || t == 'i') return true;
  if (t == 'v') return false;
  // 没有显式 `t` 时按第一个媒体文件的扩展名判断。视频清单只有
  // `media_path` 一处（此前这里少列 mkv/avi，`.mkv` 章节会被排到图片末尾）。
  final paths = workMediaPaths(chapter);
  if (paths.isEmpty) return false;
  return !isVideoMediaPath(paths.first);
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
  // `m` 可能是数组也可能是单图字符串：读侧只走 workMediaPaths，
  // 否则单图作品永远被判成 `single`（图数 1 → 恰好也一样），
  // 但多图字符串形式（含分隔）与「有媒体/无媒体」的判定会分叉。
  if (work['t'] == 'p') {
    return workMediaPaths(work).length > 1 ? 'post' : 'single';
  }
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
///
/// [index] 越界（负数/超出章节数）时按 0 / 末项算：旧写法直接
/// `index + 1`，索引为 -5 时界面渲染成「**第 -4 集**」（实测），
/// 在章节菜单上是一行看起来像坏了的数据。调用方传进来的是「当前第几章」，
/// 重算后可能落在列表外（列表刷新、切条与章节数变化跨帧），这不是脏数据，
/// 只是需要一个合法的展示名。
String chapterLabel(dynamic chapter, int index) {
  if (chapter is Map) {
    final t = '${chapter['ti'] ?? ''}'.trim();
    if (t.isNotEmpty) return t;
  }
  return '第 ${(index < 0 ? 0 : index) + 1} 集';
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
  // 章节的 `m` 同样可能是单图字符串：只认 List 会让切到该章节时不换媒体，
  // 停在上一章的画面上。归一后统一写成数组交给播放器。
  final cm = workMediaPaths(c);
  if (cm.isNotEmpty) base['m'] = cm;
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
  final chs = workChapters(work);
  if (chs.length > 1) {
    num total = 0;
    for (final c in chs) {
      final d = numOrNull(c['du']);
      if (d != null && d > 0) total += d;
    }
    return total;
  }
  final d = work is Map ? numOrNull(work['du']) : null;
  return (d != null && d > 0) ? d : 0;
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

/// 基础库作品页的排序方式（owner 2026-11-19：默认入库时间，新的在前）。
enum WorkSort { ingest, plays, title }

/// 排序选择器展示顺序：入库时间、播放量、标题。
const List<WorkSort> workSortOrder = [
  WorkSort.ingest,
  WorkSort.plays,
  WorkSort.title,
];

String workSortLabel(WorkSort sort) {
  switch (sort) {
    case WorkSort.ingest:
      return '入库时间';
    case WorkSort.plays:
      return '播放量';
    case WorkSort.title:
      return '标题';
  }
}


/// 时间戳归一到毫秒；无法识别或超出可表示范围返回 0。
///
/// 两档都要过范围校验：
///  - 秒级走 [msFromEpochSeconds]（`n * 1000` 越界会静默回绕成负数）；
///  - 毫秒级也必须过 [isValidEpochMs]：`9.2e16` 看起来“就是毫秒”，
///    但它已经超出 `DateTime` 的 ±8.64e15，后续拿去构造会在 build 阶段抛。
int _msOf(dynamic v) {
  final n = intOf(v);
  if (n <= 0) return 0;
  if (n >= 100000000000) return isValidEpochMs(n) ? n : 0; // 毫秒级（约 1e12）
  if (n >= 1000000000) return msFromEpochSeconds(n); // 秒级（约 1e9）
  return 0;
}

/// 作品「入库时间」（毫秒）：`srcAt` → `scanAt`/`updatedAt` → 日期字符串。
///
/// 服务端 `/api/lib/<id>/works.json` 的 `srcAt` 由爬虫/手动记录生成；
/// 索引里只有日期（`d`，形如 `2026-11-17`）时按当天 0 点计，
/// 两者都缺失时返回 0，由排序保持原始（服务端）顺序，不抖动。
int workIngestMs(dynamic work) {
  if (work is! Map) return 0;
  for (final key in const ['srcAt', 'scanAt', 'updatedAt']) {
    final ms = _msOf(work[key]);
    if (ms > 0) return ms;
  }
  final d = '${work['d'] ?? work['date'] ?? ''}'.trim();
  if (d.isNotEmpty) {
    final m = RegExp(r'^(\d{4})[-/.]?(\d{2})[-/.]?(\d{2})').firstMatch(d);
    if (m != null) {
      // 走 msFromDateParts：`2026-13-45` 会被 DateTime 静默滚成 2027-02-14，
      // 而 `275761-01-01` 直接在比较函数里抛 ArgumentError（整张列表崩）。
      final ms = msFromDateParts(
          intOf(m[1]), intOf(m[2]), intOf(m[3]));
      if (ms != null) return ms;
    }
  }
  return 0;
}

/// 作品播放量：`pl` 优先，其次 `plays`。
int workPlayCount(dynamic work) {
  if (work is! Map) return 0;
  final n = intOf(work['pl']);
  return n > 0 ? n : intOf(work['plays']);
}

String workTitle(dynamic work) =>
    work is Map ? '${work['ti'] ?? ''}' : '';

/// 返回排好序的新列表（不改动入参）。
///
/// 同值时保持服务端原始顺序（用原下标兜底），避免每次 build 重排后
/// 没有时间戳的条目来回跳动。
List<dynamic> sortWorks(List<dynamic> works, WorkSort sort) {
  final indexed = <MapEntry<int, dynamic>>[
    for (var i = 0; i < works.length; i++) MapEntry(i, works[i]),
  ];
  int cmp(dynamic a, dynamic b) {
    switch (sort) {
      case WorkSort.ingest:
        return workIngestMs(b).compareTo(workIngestMs(a));
      case WorkSort.plays:
        return workPlayCount(b).compareTo(workPlayCount(a));
      case WorkSort.title:
        return workTitle(a).compareTo(workTitle(b));
    }
  }

  indexed.sort((a, b) {
    final c = cmp(a.value, b.value);
    return c != 0 ? c : a.key.compareTo(b.key);
  });
  return <dynamic>[for (final e in indexed) e.value];
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
