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
class WorkCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(fit: StackFit.expand, children: [
          if (coverUrl.isEmpty)
            Container(color: Colors.black26)
          else
            CachedNetworkImage(
              imageUrl: coverUrl,
              httpHeaders: headers,
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
                      title.trim().isEmpty ? '未命名' : title.trim(),
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
                      typeLabel,
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
          if (badge != null && badge!.isNotEmpty)
            Positioned(
              right: 4,
              bottom: 4,
              child: Text(badge!,
                  style: const TextStyle(
                      fontSize: 10, color: Colors.white70)),
            ),
          if (done)
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
          if (progress > 0.01)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.black26,
                    minHeight: 2),
              ),
            ),
        ]),
      ),
    );
  }
}
