/// 播放设置的持久化（owner 2026-11-24）。
///
/// 需求原文：「添加设置记忆功能，重进播放界面记住沿用上次的播放设置」。
///
/// 之前 `speed` / `LoopLink` / `shuffle` 都只存在播放页内存里，退出播放页
/// 就回到默认值（1.0x、连播开、循环关、乱序关）。这里把三组状态落到
/// SharedPreferences，进播放页时先读回。
///
/// 设计要点：
/// - 纯数据 + 纯函数，便于单测；落盘走 `prefs_json` 的唯一入口；
/// - 坏数据一律回落默认值，不抛异常、不阻塞进页面；
/// - 倍速夹在 0.5–3.0（与 `setSpeed` 的钳制范围一致）。
library;

import 'dart:convert';

import 'loop_link.dart';
import 'prefs_json.dart';

/// 播放设置的完整快照。
class PlaybackPrefs {
  /// 播放倍速，0.5–3.0。
  final double speed;

  /// 循环/连播联动状态（含「打开循环前的连播」记忆值）。
  final LoopLink link;

  /// 是否乱序播放。
  final bool shuffle;

  const PlaybackPrefs({
    this.speed = 1.0,
    this.link = const LoopLink(),
    this.shuffle = false,
  });

  static const PlaybackPrefs defaults = PlaybackPrefs();

  PlaybackPrefs copyWith({double? speed, LoopLink? link, bool? shuffle}) =>
      PlaybackPrefs(
        speed: speed ?? this.speed,
        link: link ?? this.link,
        shuffle: shuffle ?? this.shuffle,
      );

  Map<String, dynamic> toJson() => {
        // 版本只写在**键名**（`playback_prefs_v1`）里。此前这里还多写一份
        // `'v': 1`，但 `fromJson` 从不读它——两份版本号，改结构时改一处
        // 就漂移。键名已经承担了迁移职责，payload 里不再重复。
        'speed': speed,
        'loopOne': link.loopOne,
        'autoplay': link.autoplay,
        'restoreAutoplay': link.restoreAutoplay,
        'shuffle': shuffle,
      };

  /// 容错解析：任何字段坏了只影响它自己，其余照常恢复。
  static PlaybackPrefs fromJson(dynamic raw) {
    if (raw is! Map) return defaults;
    final speedRaw = raw['speed'];
    var speed = 1.0;
    if (speedRaw is num && speedRaw.isFinite) {
      speed = speedRaw.toDouble().clamp(0.5, 3.0).toDouble();
    }
    bool boolOf(dynamic v, bool d) => v is bool ? v : d;
    final loopOne = boolOf(raw['loopOne'], false);
    final autoplay = boolOf(raw['autoplay'], true);
    final restore = boolOf(raw['restoreAutoplay'], autoplay);
    return PlaybackPrefs(
      speed: speed,
      link: LoopLink(
        loopOne: loopOne,
        autoplay: autoplay,
        restoreAutoplay: restore,
      ),
      shuffle: boolOf(raw['shuffle'], false),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackPrefs &&
      other.speed == speed &&
      other.link == link &&
      other.shuffle == shuffle;

  @override
  int get hashCode => Object.hash(speed, link, shuffle);
}

/// 落盘键（版本化，日后改结构可换键名平滑迁移）。
const String kPlaybackPrefsKey = 'playback_prefs_v1';

/// 读回上次的播放设置；无记录或坏数据返回 [PlaybackPrefs.defaults]。
Future<PlaybackPrefs> loadPlaybackPrefs() async {
  final raw = await readPrefString(kPlaybackPrefsKey);
  if (raw == null || raw.trim().isEmpty) return PlaybackPrefs.defaults;
  try {
    return PlaybackPrefs.fromJson(jsonDecode(raw));
  } catch (_) {
    return PlaybackPrefs.defaults;
  }
}

/// 保存播放设置；写失败不影响播放（下次进页面回落默认值）。
Future<void> savePlaybackPrefs(PlaybackPrefs p) async {
  try {
    await savePrefString(kPlaybackPrefsKey, jsonEncode(p.toJson()));
  } catch (_) {
    // 编码失败也不阻塞播放。
  }
}
