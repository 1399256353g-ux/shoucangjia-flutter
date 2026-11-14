/// G11：播放页长按菜单的显示项（纯逻辑，便于单测）。
///
/// 「从头播放」永远显示（这也是唯一入口的兜底：没有记录时也能强制重播）；
/// 「继续观看」只在视频有可续播位置时显示；
/// 「标记为已看完」只在视频且尚未看完时显示；
/// 「清除观看记录」只在确实存在记录时显示。
library;

import 'watch_progress.dart';

class PlaybackMenuModel {
  /// 视频是否可续播，以及续播位置（毫秒）。
  final bool canResume;
  final int resumeAtMs;

  /// 是否可标记为已看完。
  final bool canMarkDone;

  /// 是否显示「清除观看记录」。
  final bool canClear;
  final bool hasRecord;

  const PlaybackMenuModel({
    required this.canResume,
    required this.resumeAtMs,
    required this.canMarkDone,
    required this.canClear,
    required this.hasRecord,
  });
}

/// 根据作品类型与本地观看记录，计算长按菜单需要展示的条目。
PlaybackMenuModel buildPlaybackMenu({
  required bool isVideo,
  WatchProgress? progress,
}) {
  final has = progress != null;
  final at = isVideo ? resumeMs(progress) : 0;
  return PlaybackMenuModel(
    canResume: at > 0,
    resumeAtMs: at,
    canMarkDone: isVideo && has && !progress.done,
    canClear: has,
    hasRecord: has,
  );
}

/// 毫秒格式化为 mm:ss（超过 1 小时为 h:mm:ss），菜单副标题使用。
String formatMenuPosition(int ms) {
  final total = ms < 0 ? 0 : ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
