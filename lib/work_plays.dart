/// L5-C：作品级「App 本地播放量」计数 + 本地存储。
///
/// 只记本机播放（不上报、不联网），用途：
///  - 基础库未自定义封面时，取本机播放量最高的作品封面；
///  - 顺带记住该作品的缩略图路径，封面不必再请求服务端索引。
///
/// 与观看进度（watch_progress）相互独立：键同为 `库/作品id`，单独存一份 JSON。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'prefs_json.dart';

const String kWorkPlaysPrefsKey = 'work_plays_v2';

/// 记录条数上限，超出按「次数少」淘汰，防止无限增长。
const int kWorkPlaysLimit = 3000;

/// 记录键：`库/作品id`；任一为空时返回空串（调用方跳过）。
String workPlaysKey({required String lib, required String id}) {
  final i = id.trim();
  if (i.isEmpty) return '';
  final l = lib.trim();
  return l.isEmpty ? i : '$l/$i';
}

/// 单条播放记录：次数 + 最近一次播放的缩略图（相对库根的媒体路径）。
class WorkPlay {
  final int count;
  final String thumb;
  /// 0.9.9：作品类型（`p` 图文 / `v` 视频）；空串表示旧记录未知。
  /// 自动封面据此「有图片时优先最高播放的图文作品」。
  final String kind;
  /// 0.9.9：最近一次播放时间（毫秒时间戳）；0 表示旧记录未知。
  final int at;

  const WorkPlay({
    required this.count,
    this.thumb = '',
    this.kind = '',
    this.at = 0,
  });

  bool get isImage => kind == 'p';

  WorkPlay bump({String? thumb, String? kind, int? at}) => WorkPlay(
        count: count + 1,
        thumb: (thumb ?? '').trim().isNotEmpty ? thumb!.trim() : this.thumb,
        kind: (kind ?? '').trim().isNotEmpty ? kind!.trim() : this.kind,
        at: (at != null && at > 0) ? at : this.at,
      );

  Map<String, dynamic> toJson() => {
        'n': count,
        if (thumb.isNotEmpty) 't': thumb,
        if (kind.isNotEmpty) 'k': kind,
        if (at > 0) 'a': at,
      };

  static WorkPlay? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final n = raw['n'] is num ? (raw['n'] as num).toInt() : int.tryParse('${raw['n'] ?? ''}') ?? 0;
    if (n <= 0) return null;
    return WorkPlay(
      count: n,
      thumb: '${raw['t'] ?? ''}'.trim(),
      kind: '${raw['k'] ?? ''}'.trim(),
      at: raw['a'] is num ? (raw['a'] as num).toInt() : int.tryParse('${raw['a'] ?? ''}') ?? 0,
    );
  }
}

/// 容错解析整表；非 JSON / 非法条目直接丢弃。
Map<String, WorkPlay> parseWorkPlays(String? raw) {
  final out = <String, WorkPlay>{};
  if (raw == null || raw.trim().isEmpty) return out;
  dynamic decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return out;
  }
  if (decoded is! Map) return out;
  decoded.forEach((k, v) {
    final key = '$k'.trim();
    if (key.isEmpty) return;
    final p = WorkPlay.fromJson(v);
    if (p != null) out[key] = p;
  });
  return out;
}

/// 编码整表（键排序，输出稳定）。
String encodeWorkPlays(Map<String, WorkPlay> plays) {
  final keys = plays.keys.toList()..sort();
  return jsonEncode({for (final k in keys) k: plays[k]!.toJson()});
}

/// 记录一次播放。
Map<String, WorkPlay> bumpWorkPlay(
  Map<String, WorkPlay> plays,
  String key, {
  String? thumb,
  String? kind,
  int? at,
}) {
  if (key.isEmpty) return plays;
  final next = Map<String, WorkPlay>.from(plays);
  next[key] = (next[key] ?? const WorkPlay(count: 0))
      .bump(thumb: thumb, kind: kind, at: at);
  return next;
}

/// 超出上限时保留次数最高的 [limit] 条（同分按键名，结果稳定）。
Map<String, WorkPlay> pruneWorkPlays(
  Map<String, WorkPlay> plays, {
  int limit = kWorkPlaysLimit,
}) {
  if (limit <= 0 || plays.length <= limit) return plays;
  final entries = plays.entries.toList()
    ..sort((a, b) {
      final c = b.value.count.compareTo(a.value.count);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return {for (final e in entries.take(limit)) e.key: e.value};
}

/// 某个库的计数：作品 id → 记录。
Map<String, WorkPlay> playsOfLib(Map<String, WorkPlay> plays, String lib) {
  final l = lib.trim();
  if (l.isEmpty) return const <String, WorkPlay>{};
  final prefix = '$l/';
  final out = <String, WorkPlay>{};
  plays.forEach((k, v) {
    if (k.startsWith(prefix)) out[k.substring(prefix.length)] = v;
  });
  return out;
}

/// 本机播放量最高、且有缩略图的作品；没有则返回 null。
///
/// 0.9.9 自动封面规则：**有图片作品时优先最高播放的图文作品**，
/// 一张图片作品都没有时才用最高播放的视频帧。同分取更新的记录。
WorkPlay? topPlayed(Map<String, WorkPlay> plays) {
  WorkPlay? bestImage;
  WorkPlay? bestOther;
  plays.forEach((k, v) {
    if (v.thumb.isEmpty) return;
    if (v.isImage) {
      if (bestImage == null || _betterPlay(v, bestImage!)) bestImage = v;
    } else {
      if (bestOther == null || _betterPlay(v, bestOther!)) bestOther = v;
    }
  });
  return bestImage ?? bestOther;
}

bool _betterPlay(WorkPlay a, WorkPlay b) {
  if (a.count != b.count) return a.count > b.count;
  return a.at > b.at;
}

/// 本地播放计数仓库：内存缓存 + 延迟落盘。
class WorkPlaysStore {
  WorkPlaysStore._();

  /// 变更自增，UI 可监听刷新封面。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// 0.9.74：按库的变更通知。播放只影响该库（及其上级单元库）的封面，
  /// 不必让网格里所有库卡片一起重算封面。
  static final Map<String, ValueNotifier<int>> _libRev =
      <String, ValueNotifier<int>>{};

  /// 合并通知器缓存：键为排序后的库 id 集合（单元库封面取决于整棵子树）。
  static final Map<String, _LibsNotifier> _merged = <String, _LibsNotifier>{};

  static Map<String, WorkPlay> _items = <String, WorkPlay>{};
  static bool _loaded = false;
  static Timer? _flush;
  static String _pending = '';

  static Map<String, WorkPlay> get items => Map.unmodifiable(_items);

  /// 只加载一次；重复调用安全。
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      _items = pruneWorkPlays(parseWorkPlays(sp.getString(kWorkPlaysPrefsKey)));
    } catch (_) {
      _items = <String, WorkPlay>{};
    }
  }

  static WorkPlay? of(String lib, String id) {
    final key = workPlaysKey(lib: lib, id: id);
    return key.isEmpty ? null : _items[key];
  }

  static int plays(String lib, String id) => of(lib, id)?.count ?? 0;

  static Map<String, WorkPlay> countsFor(String lib) => playsOfLib(_items, lib);

  /// 记一次播放；落盘延迟 1.5s，退出时调用 [flush]。
  static void bump(String lib, String id,
      {String? thumb, String? kind, int? at}) {
    final key = workPlaysKey(lib: lib, id: id);
    if (key.isEmpty) return;
    _items = bumpWorkPlay(_items, key, thumb: thumb, kind: kind, at: at);
    revision.value++;
    _libRev[lib.trim()]?.value++;
    _flush ??= Timer(const Duration(milliseconds: 1500), flush);
  }

  /// 单个基础库的变更通知；空库退回到全局 [revision]。
  static ValueListenable<int> libListenable(String lib) {
    final l = lib.trim();
    if (l.isEmpty) return revision;
    return _libRev.putIfAbsent(l, () => ValueNotifier<int>(0));
  }

  /// 一组基础库（单元库整棵子树）的合并通知；空集合退回全局 [revision]。
  /// 同一组库复用同一个通知器，避免每次 build 都新建监听链。
  static ValueListenable<int> libsListenable(Iterable<String> libs) {
    final ids = <String>{
      for (final l in libs)
        if (l.trim().isNotEmpty) l.trim(),
    }.toList()
      ..sort();
    if (ids.isEmpty) return revision;
    final key = ids.join('|');
    return _merged.putIfAbsent(
        key, () => _LibsNotifier(key, [for (final i in ids) libListenable(i)]));
  }

  /// 立即落盘（测试与退出路径可用）。
  static Future<void> flush() {
    _flush?.cancel();
    _flush = null;
    final raw = encodeWorkPlays(_items);
    if (raw == _pending) return Future<void>.value();
    _pending = raw;
    return savePrefString(kWorkPlaysPrefsKey, raw);
  }

  /// 仅测试用：重置内存态。
  @visibleForTesting
  static void resetForTest({Map<String, WorkPlay>? items}) {
    _loaded = true;
    _items = Map<String, WorkPlay>.from(items ?? const {});
    _pending = '';
    _flush?.cancel();
    _flush = null;
    revision.value++;
    for (final n in _libRev.values) {
      n.value++;
    }
  }
}

/// 把一组库通知器合并成一个可监听对象（单元库封面依赖子树内所有库）。
class _LibsNotifier extends ValueNotifier<int> {
  final String _key;
  final List<ValueListenable<int>> _sources;

  _LibsNotifier(this._key, this._sources) : super(0) {
    for (final s in _sources) {
      s.addListener(_onAny);
    }
  }

  String get key => _key;

  void _onAny() {
    value++;
  }

  @override
  void dispose() {
    for (final s in _sources) {
      s.removeListener(_onAny);
    }
    super.dispose();
  }
}
