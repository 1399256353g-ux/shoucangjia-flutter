import 'cover_cache.dart';
import 'decode_plan.dart';
import 'media_resize.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 全站唯一的工作（作品）卡片样式。
///
/// 规则（owner 定稿）：
///  - 封面铺满，圆角统一 10
///  - 标题最多 2 行，类型紧跟标题，二者都叠在封面上，不额外占位
///  - 底部半透明渐变保证可读性
///  - 时长 / 张数 / 已完成 / 进度统一画在这一处
///
/// 所有页面（作者主页、作品页、收藏夹、搜索、基础库）都必须用这个组件，
/// 不允许各自再写一套卡片。
class WorkCard extends StatefulWidget {
  static const double radius = 10;
  static const double aspect = 3 / 4;

  final String title;
  final String typeLabel;
  final String coverUrl;
  final Map<String, String> headers;
  final VoidCallback? onTap;
  /// 右下角：时长 / 图片张数。
  final String? badge;
  /// 左上角：已看完。
  final bool done;
  /// 底部进度条：0–1；<=0 不显示。
  final double progress;

  const WorkCard({
    super.key,
    required this.title,
    required this.typeLabel,
    required this.coverUrl,
    this.headers = const {},
    this.onTap,
    this.badge,
    this.done = false,
    this.progress = 0,
  });

  @override
  State<WorkCard> createState() => _WorkCardState();
}

class _WorkCardState extends State<WorkCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
      onTap: w.onTap,
      borderRadius: BorderRadius.circular(WorkCard.radius),
      // 悬停只做外圈描边，不铺色，避免盖住底部标题/类型。
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(WorkCard.radius),
        child: Stack(fit: StackFit.expand, children: [
          if (w.coverUrl.isEmpty)
            Container(color: Colors.black26)
          else
            CachedNetworkImage(
              cacheManager: DiziCache.manager,
              // 0.9.24：卡片只显示 110–180dp，向服务端要 440px 缩图即可，
              // 不再整张原图拉下来再解码（「封面加载慢」的主要来源）。
              imageUrl: withImageWidth(w.coverUrl, kWorkImageWidth),
              httpHeaders: w.headers,
              // 卡片最大约 220 逻辑像素：解码宽度全站统一（见 decode_plan），
              // 列表卡和预热用同一个值，缓存键一致 → 命中后不再二次解码。
              memCacheWidth:
                  workCardDecodeWidth(MediaQuery.devicePixelRatioOf(context)),
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              errorWidget: (_, __, ___) => Container(color: Colors.black26),
            ),
          // 标题 + 类型：压在封面底部
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 18, 6, 5),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      w.title.trim().isEmpty ? '未命名' : w.title.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
                          color: Colors.white,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      w.typeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 9.5,
                          color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (w.badge != null && w.badge!.isNotEmpty)
            Positioned(
              right: 4,
              bottom: 4,
              child: Text(w.badge!,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white70)),
            ),
          if (w.done)
            Positioned(
              left: 4,
              top: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('已看完',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          if (w.progress > 0.01)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                    value: w.progress,
                    backgroundColor: Colors.black26,
                    minHeight: 2),
              ),
            ),
          // 桌面端悬停指示：只画一圈描边，不覆盖信息区
          if (_hover)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(WorkCard.radius),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary,
                        width: 2),
                  ),
                ),
              ),
            ),
        ]),
      ),
    ));
  }
}
