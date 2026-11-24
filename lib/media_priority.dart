/// 0.9.9：头像/封面取图优先级（纯函数，便于单测）。
///
/// 统一规则（严格按此实现）：
///  - 头像：手动设置 > 爬虫脚本获取 > 自动生成；
///  - 封面：手动设置 > 爬虫脚本 > 自动生成；
///  - 同一层级有多个候选时，**新的优先于旧的**（[at] 越大越优先）。
///
/// 「清除手动设置」只需不再提供该层候选，自动索引会继续向下取图，
/// 因此调用方不需要额外的恢复逻辑。
///
/// 自动生成：
///  - 单元库：取其子树内本机播放量最高的基础库，再取该基础库的封面
///    （基础库封面 = 最高播放作品的封面）；
///  - 基础库：取本机播放量最高的作品封面；有图片作品时优先最高播放的
///    图文作品图片，没有图片作品时才取最高播放视频的帧。
library;

import 'cover_ext.dart';

/// 取图来源层级，数值越小优先级越高。
enum MediaTier {
  manual(0),
  crawler(1),
  auto(2);

  const MediaTier(this.rank);
  final int rank;
}

/// 一个候选图：[path] 为库内相对路径或媒体路径；空串视为无图。
class MediaCandidate {
  final String path;
  final MediaTier tier;

  /// 该候选的产生时间（毫秒时间戳）；0 表示未知，排序时视为最旧。
  final int at;

  const MediaCandidate(this.path, this.tier, {this.at = 0});

  bool get valid => path.trim().isNotEmpty;

  @override
  String toString() => 'MediaCandidate(${tier.name},$path,$at)';
}

/// 按「层级优先、同级新图优先」挑一张；无候选返回 null。
MediaCandidate? pickMediaCandidate(Iterable<MediaCandidate> candidates) {
  MediaCandidate? best;
  for (final c in candidates) {
    if (!c.valid) continue;
    if (best == null) {
      best = c;
      continue;
    }
    if (c.tier.rank < best.tier.rank) {
      best = c;
    } else if (c.tier.rank == best.tier.rank && c.at > best.at) {
      best = c;
    }
  }
  return best;
}

/// 便捷版：只返回路径，无候选返回空串。
String pickMediaPath(Iterable<MediaCandidate> candidates) =>
    pickMediaCandidate(candidates)?.path.trim() ?? '';

/// 头像取图：手动 > 爬虫 > 自动；同级按时间新→旧。
///
/// [manualAt] / [crawlerAt] / [autoAt] 用于同级比较，未知传 0。
String pickAvatarPath({
  String manual = '',
  String crawler = '',
  String auto = '',
  int manualAt = 0,
  int crawlerAt = 0,
  int autoAt = 0,
}) =>
    pickMediaPath([
      MediaCandidate(manual, MediaTier.manual, at: manualAt),
      MediaCandidate(crawler, MediaTier.crawler, at: crawlerAt),
      MediaCandidate(auto, MediaTier.auto, at: autoAt),
    ]);

/// 封面必须是图片：视频文件（mp4/mov…）当封面会渲染失败，
/// 表现成「库封面从来没显示过」。
/// 判定落在 [isCoverImagePath]（唯一定义在 `cover_ext.dart`）。

/// 封面取图：手动 > 爬虫 > 自动；同级按时间新→旧。
///
/// 非图片路径（例如服务端 `fc` 指向的 mp4）直接剔除，不参与竞争。
String pickCoverPath({
  String manual = '',
  String crawler = '',
  String auto = '',
  int manualAt = 0,
  int crawlerAt = 0,
  int autoAt = 0,
}) {
  final candidates = <MediaCandidate>[
    MediaCandidate(manual, MediaTier.manual, at: manualAt),
    MediaCandidate(crawler, MediaTier.crawler, at: crawlerAt),
    MediaCandidate(auto, MediaTier.auto, at: autoAt),
  ].where((c) => isCoverImagePath(c.path)).toList();
  return pickMediaPath(candidates);
}
