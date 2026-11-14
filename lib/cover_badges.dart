/// G13：网格封面角标——视频显示时长，图文显示图片张数。
///
/// 时长优先读索引里的 `du`（秒，服务端 ffprobe 生成）；缺省时不显示，
/// 避免用 0:00 误导。图文张数直接取媒体列表长度。

/// 把秒数格式化成 `m:ss`（超过 1 小时为 `h:mm:ss`）。
/// 非法/非正数返回空串，调用方据此隐藏角标。
String formatBadgeDuration(num? seconds) {
  if (seconds == null) return '';
  final total = seconds.toDouble();
  if (total.isNaN || total.isInfinite || total < 1) return '';
  final s = total.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

num? _asSeconds(dynamic raw) {
  if (raw is num) return raw;
  if (raw is String) return num.tryParse(raw.trim());
  return null;
}

/// 作品在封面右下角显示的角标文字；无可用信息时返回 null。
String? workCoverBadge(dynamic work) {
  if (work is! Map) return null;
  final type = '${work['t'] ?? ''}';
  if (type == 'p') {
    final media = work['m'];
    final n = media is List ? media.length : 0;
    return n > 0 ? '$n 图' : null;
  }
  if (type == 'v') {
    final d = formatBadgeDuration(_asSeconds(work['du']));
    return d.isEmpty ? null : d;
  }
  return null;
}
