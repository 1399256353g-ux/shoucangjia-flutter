/// J12：作者头像兜底。
///
/// 作者没有现成头像（`_avatar/` 里没有图、`av` 为空）时，从该作者的作品图片里
/// 自动挑一张最像「清晰正面照」的：优先图文作品的原始大图（不是缩略图），
/// 尺寸已知时优先够大、接近方形的图；播放页/作者页统一用 `BoxFit.cover`
/// 做中心裁剪，保证头像是正中的正方形取景。
///
/// 只做纯逻辑，不碰网络与磁盘，方便单测。
library;

import 'package:flutter/material.dart';

/// 头像候选图。`width/height` 未知时填 0（列表接口通常不给尺寸）。
class AvatarCandidate {
  final String path;
  /// 'pic'（图文原图）或 'video'（视频封面/缩略图）。
  final String kind;
  final int width;
  final int height;
  /// 作品在列表里的顺序（0 为最新），用于同分时优先新作品。
  final int order;

  const AvatarCandidate({
    required this.path,
    this.kind = 'pic',
    this.width = 0,
    this.height = 0,
    this.order = 0,
  });

  bool get valid => path.trim().isNotEmpty;
  bool get hasDims => width > 0 && height > 0;
  double get aspect => hasDims ? width / height : 0;
  bool get isGif {
    final p = path.toLowerCase();
    return p.endsWith('.gif') || p.contains('.gif?');
  }

  @override
  String toString() => 'AvatarCandidate($kind,$path,${width}x$height)';
}

/// 小于这个边长的图不当作头像（放大会糊）。
const int avatarMinPixels = 200;

/// 候选图打分：越大越好，越方越好，图文原图优于视频缩略图。
int avatarCandidateScore(AvatarCandidate c) {
  if (!c.valid) return -1 << 30;
  var s = 0;
  s += c.kind == 'pic' ? 40 : 12;

  if (c.hasDims) {
    final minSide = c.width < c.height ? c.width : c.height;
    if (minSide < avatarMinPixels) {
      s -= 120;
    } else if (minSide >= 960) {
      s += 45;
    } else if (minSide >= 640) {
      s += 32;
    } else if (minSide >= 400) {
      s += 18;
    } else {
      s += 6;
    }
    final a = c.aspect;
    if (a >= 0.72 && a <= 1.05) {
      // 接近正方形/轻微竖图：最适合方形头像
      s += 36;
    } else if (a >= 0.55 && a < 0.72) {
      s += 20;
    } else if (a > 1.05 && a <= 1.35) {
      s += 10;
    } else if (a > 1.35 && a <= 2.0) {
      s -= 18;
    } else if (a > 2.0) {
      s -= 45;
    } else if (a < 0.4) {
      s -= 35;
    } else {
      s += 4;
    }
  }

  // 动图当头像会闪，除非没有别的选择。
  if (c.isGif) s -= 25;
  // 同分时优先更新的作品（最多扣 12，避免压过清晰度判断）。
  final decay = c.order * 0.5;
  s -= decay > 12 ? 12 : decay.round();
  return s;
}

/// 从候选里挑出最合适的一张；没有可用候选返回 null。
///
/// 动图（gif）永远排在静态图之后：只有当没有静态候选时才用动图。
AvatarCandidate? pickFallbackAvatarScored(Iterable<AvatarCandidate> list) {
  final valid = list.where((c) => c.valid).toList();
  if (valid.isEmpty) return null;
  final statics = valid.where((c) => !c.isGif).toList();
  final pool = statics.isEmpty ? valid : statics;
  AvatarCandidate? best;
  var bestScore = -1 << 30;
  for (final c in pool) {
    final s = avatarCandidateScore(c);
    if (s > bestScore) {
      best = c;
      bestScore = s;
    }
  }
  return best;
}

/// 只要路径的便捷版本。
String? pickFallbackAvatar(Iterable<AvatarCandidate> list) =>
    pickFallbackAvatarScored(list)?.path;

/// 从作品列表构造候选（`/api/a/<i>.json` 的 `works`）。
///
/// 图文作品优先用 `m` 里的原始大图（第一张通常是封面/主图），
/// 视频作品用 `thumb.jpg` 封面；没有图的条目跳过。
List<AvatarCandidate> avatarCandidatesFromWorks(Iterable<Map> works) {
  final out = <AvatarCandidate>[];
  var order = 0;
  for (final w in works) {
    final kind = '${w['t'] ?? ''}';
    final th = '${w['th'] ?? ''}'.trim();
    final pics = <String>[];
    final raw = w['m'];
    if (raw is List) {
      for (final e in raw) {
        final p = '$e'.trim();
        if (p.isNotEmpty) pics.add(p);
      }
    }
    final picsOnly = pics.where(isAvatarImagePath).toList();
    if (kind == 'p' && picsOnly.isNotEmpty) {
      for (var i = 0; i < picsOnly.length && i < 3; i++) {
        out.add(AvatarCandidate(
            path: picsOnly[i], kind: 'pic', order: order++));
      }
    } else if (th.isNotEmpty && isAvatarImagePath(th)) {
      out.add(AvatarCandidate(path: th, kind: 'video', order: order++));
    } else if (picsOnly.isNotEmpty) {
      out.add(AvatarCandidate(
          path: picsOnly.first, kind: 'pic', order: order++));
    }
  }
  return out;
}

/// 可当头像/封面的图片扩展名（含服务端缩图参数前的原始名）。
const List<String> kAvatarImageExts = <String>[
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.bmp',
  '.avif',
];

/// 路径是否指向图片：去掉 `?w=200` 之类的查询串后再判断扩展名。
/// 非图片（视频、文本、无扩展名）一律返回 false，避免把 mp4 当头像去请求。
bool isAvatarImagePath(String path) {
  var p = path.trim().toLowerCase();
  if (p.isEmpty) return false;
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  final h = p.indexOf('#');
  if (h >= 0) p = p.substring(0, h);
  return kAvatarImageExts.any(p.endsWith);
}

/// 播放页作者头像的兜底图路径（纯逻辑，便于单测）。
///
/// `th` 优先，但只接受图片路径；没有可用 `th` 时取 `m` 里第一张
/// 图片（图文原图）；都拿不到返回空串，由调用方显示首字母占位。
String workAvatarFallbackPath(dynamic work) {
  if (work is! Map) return '';
  final t = '${work['th'] ?? ''}'.trim();
  if (isAvatarImagePath(t)) return t;
  final m = work['m'];
  if (m is List) {
    for (final x in m) {
      final u = '$x'.trim();
      if (isAvatarImagePath(u)) return u;
    }
  }
  return '';
}

/// 把 [works] 中「尚未记录作者」的第一张缩略图写进 [target]（就地更新），
/// 返回新增的作者数。
///
/// 列表分页追加时只处理新批次即可，避免每次都全量重扫（O(n²)）。
int addFirstThumbPerAuthor(
  Map<String, String> target,
  Iterable<dynamic> works, {
  required String Function(dynamic work) thumbOf,
}) {
  var added = 0;
  for (final w in works) {
    if (w is! Map) continue;
    final a = '${w['a'] ?? ''}';
    if (a.isEmpty || target.containsKey(a)) continue;
    final th = thumbOf(w).trim();
    if (th.isEmpty) continue;
    target[a] = th;
    added++;
  }
  return added;
}

/// 作者 → 头像兜底图（`th` › 图文第一张非视频图）。
Map<String, String> authorFallbackThumbs(Iterable<dynamic> works) {
  final out = <String, String>{};
  addFirstThumbPerAuthor(out, works, thumbOf: workAvatarFallbackPath);
  return out;
}

/// 方形中心裁剪取景框（以图宽高的比例表示），竖图略微上移对准人脸。
class AvatarCropBox {
  final double left;
  final double top;
  final double size; // 正方形边长，相对较短边的比例（1 = 铺满短边）

  const AvatarCropBox({this.left = 0, this.top = 0, this.size = 1});

  /// [w]/[h] 为原图像素尺寸，返回裁剪框的像素矩形。
  (double x, double y, double side) toPixels(int w, int h) {
    final short = w < h ? w : h;
    final side = short * size.clamp(0.2, 1.0);
    final maxX = w - side;
    final maxY = h - side;
    var x = left * maxX;
    var y = top * maxY;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x > maxX) x = maxX;
    if (y > maxY) y = maxY;
    return (x, y, side);
  }

  /// 标准方形头像的默认取景：横向居中，竖向略偏上（人脸通常在画面 40% 处）。
  static AvatarCropBox centerFace({double size = 1.0}) =>
      AvatarCropBox(left: 0.5, top: 0.38, size: size);
}

/// 头像首字母：空名返回 `?`；按 rune 取第一个完整字符，
/// 避免 emoji / 代理对被截成半个而显示空白。
String avatarInitial(String name) {
  final t = name.trim();
  if (t.isEmpty) return '?';
  return String.fromCharCode(t.runes.first);
}

/// 没有可用头像路径时必须显示首字母占位（不能返回空白）。
bool needsAvatarPlaceholder(String path) => path.trim().isEmpty;

/// 首字母圆形占位：
/// - 无头像（`mediaPath` 为空）时直接显示；
/// - 有头像时作为 `CachedNetworkImage` 的 `placeholder`/`errorWidget`，
///   加载期间与加载失败都不会出现空白区域。
class AvatarLetterPlaceholder extends StatelessWidget {
  const AvatarLetterPlaceholder({
    super.key,
    required this.name,
    required this.size,
    this.color,
  });

  /// 与 `AuthorAvatar` 的蓝灰色占位保持一致。
  static const Color defaultColor = Color(0xFF546E7A);

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = size <= 0 ? 1.0 : size;
    return Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color ?? defaultColor,
        shape: BoxShape.circle,
      ),
      child: Text(
        avatarInitial(name),
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(fontSize: s * 0.4, color: Colors.white),
      ),
    );
  }
}
