/// 封面截取框页面：固定宽高比（库卡片比例）、可拖动/缩放，
/// 确认后返回归一化 `[x, y, w, h]`（0..1）。
///
/// 结构性做法（无兜底）：
///  - 预览图直接就是「即将被截取的那一帧」——视频用播放器当前帧截图，
///    图文用当前这张图；因此选框里看到什么，服务端 ffmpeg `crop` 就出什么；
///  - 比例常量和卡片共用 [kLibraryCoverAspect]，入库后卡片 `BoxFit.cover`
///    刚好铺满、不会再被裁一次；
///  - 几何全在 [CoverCropBox] 纯函数里，页面只负责把指针增量喂进去。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'cover_crop.dart';

/// 确认结果：`rect` 为 null 表示「整帧使用」。
class CoverCropResult {
  final List<double>? rect;
  const CoverCropResult(this.rect);
}

class CoverCropPage extends StatefulWidget {
  /// 预览图（视频当前帧 / 图文当前图 / 封面兜底）。
  final ImageProvider image;
  final double aspect;
  final String title;

  const CoverCropPage({
    super.key,
    required this.image,
    this.aspect = kLibraryCoverAspect,
    this.title = '截取封面',
  });

  @override
  State<CoverCropPage> createState() => _CoverCropPageState();
}

class _CoverCropPageState extends State<CoverCropPage> {
  ui.Image? _image;
  Object? _error;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  CoverCropBox? _box;
  Size _displaySize = Size.zero;

  @override
  void initState() {
    super.initState();
    final s = widget.image.resolve(const ImageConfiguration());
    _stream = s;
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() => _image = info.image);
      },
      onError: (e, _) {
        if (mounted) setState(() => _error = e);
      },
    );
    s.addListener(_listener!);
  }

  @override
  void dispose() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    super.dispose();
  }

  void _ensureBox(Size display) {
    if (display == _displaySize && _box != null) return;
    _displaySize = display;
    _box = CoverCropBox.initial(display, widget.aspect);
  }

  void _move(Offset delta, Size display) {
    setState(() => _box = (_box ?? CoverCropBox.initial(display, widget.aspect))
        .moved(delta, display));
  }

  void _resize(CropCorner corner, Offset delta, Size display) {
    setState(() => _box = (_box ?? CoverCropBox.initial(display, widget.aspect))
        .resized(corner, delta, display));
  }

  void _confirm() {
    final display = _displaySize;
    final box = _box;
    Navigator.of(context).pop(
      CoverCropResult(box == null ? null : box.normalized(display)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const CoverCropResult(null)),
            child: const Text('整帧使用'),
          ),
        ],
      ),
      body: _error != null
          ? const Center(
              child: Text('预览图加载失败，可直接「整帧使用」',
                  style: TextStyle(color: Colors.white70)))
          : img == null
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white38))
              : LayoutBuilder(builder: (ctx, cons) {
                  // 预留左右 12 与底部操作条（约 104）的高度，避免选框压在按钮上。
                  final area = Size(
                    (cons.maxWidth - 24) < 1 ? 1.0 : cons.maxWidth - 24,
                    (cons.maxHeight - 24 - 104) < 1
                        ? 1.0
                        : cons.maxHeight - 24 - 104,
                  );
                  final imageRect = _containRect(
                    Size(img.width.toDouble(), img.height.toDouble()),
                    area,
                  ).translate(12, 12);
                  if (imageRect.isEmpty) {
                    return const Center(
                        child: Text('画面尺寸异常',
                            style: TextStyle(color: Colors.white70)));
                  }
                  _ensureBox(imageRect.size);
                  final box = _box!;
                  final origin = imageRect.topLeft;
                  return Stack(children: [
                    Positioned.fromRect(
                      rect: imageRect,
                      child: RawImage(image: img, fit: BoxFit.fill),
                    ),
                    Positioned.fromRect(
                      rect: imageRect,
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CropDimPainter(box.rect),
                        ),
                      ),
                    ),
                    Positioned(
                      left: origin.dx + box.rect.left,
                      top: origin.dy + box.rect.top,
                      width: box.rect.width,
                      height: box.rect.height,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onPanUpdate: (d) => _move(d.delta, imageRect.size),
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: CustomPaint(
                              painter: _CropGridPainter(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (final c in CropCorner.values)
                      _handle(c, box, origin, imageRect.size),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('拖动框内移动 · 拖四角缩放',
                            style:
                                TextStyle(color: Colors.white70, fontSize: 12)),
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white38)),
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _confirm,
                              child: const Text('按此框设置'),
                            ),
                          ),
                        ]),
                      ]),
                    ),
                  ]);
                }),
    );
  }

  Widget _handle(CropCorner c, CoverCropBox box, Offset origin, Size display) {
    const hs = 28.0; // 命中尺寸（视觉上是 12px 圆点）
    final east = c == CropCorner.topRight || c == CropCorner.bottomRight;
    final south = c == CropCorner.bottomRight || c == CropCorner.bottomLeft;
    final x = origin.dx + (east ? box.rect.right : box.rect.left);
    final y = origin.dy + (south ? box.rect.bottom : box.rect.top);
    return Positioned(
      left: x - hs / 2,
      top: y - hs / 2,
      width: hs,
      height: hs,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (d) => _resize(c, d.delta, display),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black54),
            ),
          ),
        ),
      ),
    );
  }

  /// `BoxFit.contain` 的显示矩形（在给定可用区域内居中）。
  static Rect _containRect(Size src, Size area) {
    if (src.width <= 0 || src.height <= 0) return Rect.zero;
    if (area.width <= 0 || area.height <= 0) return Rect.zero;
    final scale = math_min(area.width / src.width, area.height / src.height);
    final w = src.width * scale;
    final h = src.height * scale;
    return Rect.fromLTWH((area.width - w) / 2, (area.height - h) / 2, w, h);
  }

  static double math_min(double a, double b) => a < b ? a : b;
}

/// 选框外侧压暗（内部保持原亮度）。
class _CropDimPainter extends CustomPainter {
  final Rect crop;
  _CropDimPainter(this.crop);

  @override
  void paint(Canvas canvas, Size size) {
    final full = Offset.zero & size;
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRect(crop);
    canvas.drawPath(
        path, Paint()..color = Colors.black.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(covariant _CropDimPainter old) => old.crop != crop;
}

/// 三分线（构图参考）。
class _CropGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final dx = size.width * i / 3;
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), p);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
