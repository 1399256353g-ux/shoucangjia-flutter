/// G10：播放记忆与「已看完」标记（纯逻辑 + 本地存储）。
///
/// 只有本机记忆，不上报服务端：
/// - 播放中周期性记录「库/作品」的观看位置与时长；
/// - 退出播放页/切后台/切下一条时立即落盘；
/// - 再次打开同一作品时从上次位置续播；
/// - 位置到达片尾（剩余不足 4s 或进度 ≥95%）即视为「已看完」，列表打标；
/// - 重新从头观看后标记自动消失（按最新位置实时判定）。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 键：整个观看记录表存在一个 JSON 字符串里。
const String kWatchProgressPrefsKey = 'watch_progress_v1';

/// 记录条数上限，超出按更新时间淘汰最旧的（防止无限增长）。
const int kWatchStoreLimit = 800;

/// 距片尾不足该毫秒数即视为看完。
const int kWatchedTailMs = 4000;

/// 或者播放进度达到该比例也视为看完。
const double kWatchedFraction = 0.95;

/// 小于该位置不记忆（开头几秒没有续播意义）。
const int kMinResumeMs = 4000;

/// 单条作品的观看记录。
class WatchProgress {
  final int positionMs;
  final int durationMs;
  final bool done;
  final int updatedAt;

  const WatchProgress({
    required this.positionMs,
    required this.durationMs,
    required this.done,
    required this.updatedAt,
  });

  /// 0–1 的观看进度；时长为 0 时返回 0。
  double get fraction {
    if (durationMs <= 0) return 0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'p': positionMs,
        'd': durationMs,
        'f': done ? 1 : 0,
        't': updatedAt,
      };

  /// 容错解析：任何字段类型不对都按 0/false 处理。
  static WatchProgress? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    int n(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
    final p = n(raw['p']);
    final d = n(raw['d']);
    if (p < 0 || d < 0) return null;
    if (d == 0 && p == 0) return null;
    return WatchProgress(
      positionMs: p,
      durationMs: d,
      done: raw['f'] == 1 || raw['f'] == true,
      updatedAt: n(raw['t']),
    );
  }
}

/// 生成作品观看记录的存储键；作品 id 为空时返回空串（调用方应跳过）。
String watchProgressKey({required String lib, required String id}) {
  final i = id.trim();
  if (i.isEmpty) return '';
  final l = lib.trim();
  return l.isEmpty ? i : '$l/$i';
}

/// 位置是否已看完：剩余不足 [kWatchedTailMs] 或进度 ≥ [kWatchedFraction]。
bool watchedDone({required int positionMs, required int durationMs}) {
  if (durationMs <= 0) return false;
  if (positionMs <= 0) return false;
  if (durationMs - positionMs <= kWatchedTailMs) return true;
  return positionMs / durationMs >= kWatchedFraction;
}

/// 续播位置：无记录 / 已看完 / 太靠前时返回 0（从头播放）。
int resumeMs(WatchProgress? p) {
  if (p == null || p.done) return 0;
  if (p.positionMs < kMinResumeMs) return 0;
  if (p.durationMs > 0 && p.positionMs >= p.durationMs) return 0;
  // 回退 1 秒，避免从解码边界起播卡住
  return p.positionMs > 1000 ? p.positionMs - 1000 : p.positionMs;
}

/// 容错解析整表；非法 JSON / 非法条目直接丢弃。
Map<String, WatchProgress> parseWatchProgress(String? raw) {
  final out = <String, WatchProgress>{};
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
    final p = WatchProgress.fromJson(v);
    if (p != null) out[key] = p;
  });
  return out;
}

/// 编码整表（按键排序，输出稳定）。
String encodeWatchProgress(Map<String, WatchProgress> items) {
  final keys = items.keys.toList()..sort();
  final map = <String, dynamic>{};
  for (final k in keys) {
    map[k] = items[k]!.toJson();
  }
  return jsonEncode(map);
}

/// 超出上限时淘汰最久未更新的条目。
Map<String, WatchProgress> pruneWatchProgress(
  Map<String, WatchProgress> items, {
  int limit = kWatchStoreLimit,
}) {
  if (items.length <= limit || limit <= 0) return items;
  final entries = items.entries.toList()
    ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));
  return {for (final e in entries.take(limit)) e.key: e.value};
}

/// 本地观看记录仓库：内存缓存 + 延迟落盘 + 变更通知（列表角标自动刷新）。
class WatchProgressStore {
  WatchProgressStore._();

  /// 每次变更自增，列表用 ValueListenableBuilder 监听即可刷新角标。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Map<String, WatchProgress> _items = <String, WatchProgress>{};
  static bool _loaded = false;
  static Timer? _flush;
  static final Map<String, int> _lastWriteAt = <String, int>{};

  static Map<String, WatchProgress> get items => Map.unmodifiable(_items);

  /// 只加载一次；页面初始化时调用，重复调用安全。
  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      _items = pruneWatchProgress(
          parseWatchProgress(sp.getString(kWatchProgressPrefsKey)));
      revision.value++;
    } catch (_) {
      _items = <String, WatchProgress>{};
    }
  }

  static WatchProgress? of(String lib, String id) {
    final key = watchProgressKey(lib: lib, id: id);
    if (key.isEmpty) return null;
    return _items[key];
  }

  static bool isDone(String lib, String id) => of(lib, id)?.done ?? false;

  /// 记录一次播放位置；[force] 为 false 时同一条作品最快 3 秒写一次内存。
  static void record({
    required String lib,
    required String id,
    required int positionMs,
    required int durationMs,
    bool force = false,
  }) {
    final key = watchProgressKey(lib: lib, id: id);
    if (key.isEmpty || positionMs < 0) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _items[key];
    final shouldWrite = force ||
        prev == null ||
        (now - (_lastWriteAt[key] ?? 0) >= 3000) ||
        (positionMs - prev.positionMs).abs() >= 3000 ||
        (durationMs > 0 && prev.durationMs == 0);
    if (!shouldWrite) return;
    _lastWriteAt[key] = now;
    _items[key] = WatchProgress(
      positionMs: positionMs,
      durationMs: durationMs > 0 ? durationMs : (prev?.durationMs ?? 0),
      done: watchedDone(positionMs: positionMs, durationMs: durationMs),
      updatedAt: now,
    );
    revision.value++;
    _scheduleFlush();
  }

  /// 显式标记看完（播放器 completed 事件，位置可能停在片尾前一点）。
  static void markDone({required String lib, required String id}) {
    final key = watchProgressKey(lib: lib, id: id);
    if (key.isEmpty) return;
    final prev = _items[key];
    final dur = prev?.durationMs ?? 0;
    _items[key] = WatchProgress(
      positionMs: dur > 0 ? dur : (prev?.positionMs ?? 0),
      durationMs: dur,
      done: true,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    revision.value++;
    _scheduleFlush(immediate: true);
  }

  /// 清除单条记录（重新观看后重置场景）。
  static void remove(String lib, String id) {
    final key = watchProgressKey(lib: lib, id: id);
    if (key.isEmpty || !_items.containsKey(key)) return;
    _items.remove(key);
    revision.value++;
    _scheduleFlush();
  }

  static void _scheduleFlush({bool immediate = false}) {
    if (immediate) {
      _flush?.cancel();
      _flush = null;
      unawaited(flush());
      return;
    }
    _flush?.cancel();
    _flush = Timer(const Duration(milliseconds: 600), () {
      _flush = null;
      unawaited(flush());
    });
  }

  /// 立即落盘。
  static Future<void> flush() async {
    try {
      _items = pruneWatchProgress(_items);
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kWatchProgressPrefsKey, encodeWatchProgress(_items));
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest() {
    _items = <String, WatchProgress>{};
    _loaded = false;
    _lastWriteAt.clear();
    _flush?.cancel();
    _flush = null;
    revision.value++;
  }
}
