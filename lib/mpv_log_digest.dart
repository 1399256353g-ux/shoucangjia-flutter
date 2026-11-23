/// mpv 内部日志 → 可写日志的诊断行（纯逻辑，无 Flutter / 无播放器依赖）。
///
/// 背景（2026-11-24 设备侧实测）：装 0.9.195 后 `pause.log` 终于给出
/// `failure:network detail=Failed to open <url>` —— 这说明失败发生在
/// **mpv 打不开媒体**这一层，而不是之前怀疑的解码器层。但「打不开」仍然
/// 只有一句话：没有 HTTP 状态、没有协议错误、没有鉴权失败，四类原因在日志里
/// 长得完全一样。这正是 owner 明令禁止的「用分类名掩盖真实原因」。
///
/// mpv 内部会通过 `Player.stream.log` 抛 `prefix` + `level` + `text`
/// （`ffmpeg` / `tcp` / `stream` / `vd` / `cplayer` …），配合 level 就能
/// 区分「HTTP 401」「404」「协议不支持」「解码器初始化失败」。本文件只做
/// 两件可单测的事：把一条日志整理成**一行脱敏诊断**，以及维护一个去重的
/// 环形尾部。
///
/// 隐私红线（AGENTS.md）：日志里绝不允许出现媒体地址、库名、文件名。
/// 脱敏复用 `playback_error.dart` 的 `sanitizePlaybackErrorForLog`，
/// 不另写一套剥离规则（同一问题不允许出现第二个兜底实现）。
library;

import 'playback_error.dart';

/// 单条诊断行的正文上限（字符）。
const int kMpvDigestMax = 120;

/// 环形尾部保留条数上限：只留最近几条，避免日志被 mpv 噪音灌满。
const int kMpvLogTailMax = 6;

/// 失败时最多落盘几条 mpv 诊断行。
const int kMpvTailReportMax = 4;

String _strip(Object? raw) => sanitizePlaybackErrorForLog(raw);

/// 剥掉脱敏后残留的占位符；只剩占位符就视为「没有可行动信息」。
///
/// `sanitizePlaybackErrorForLog` 会把地址换成 `<url>`、路径换成 `<path>`。
/// 一条日志如果本来就是纯地址，剩下来的就是这两个占位符，它既不说明哪一层
/// 失败，又会让日志里堆满无意义行，所以直接丢弃。
String _meaningful(String body) {
  final s = body
      .replaceAll(RegExp(r'<url>|<path>'), ' ')
      .replaceAll(RegExp(r'[\s:,\-]+'), ' ')
      .trim();
  return s.isEmpty ? '' : s;
}

/// 把一条 mpv 日志归类成「哪一层、哪一类」，不含任何地址。
///
/// 返回空串表示没有可归纳的类别（仍然会写正文，只是没有标签）。
/// 只认**可行动**的类别：鉴权、不存在、超时、协议、解码、打不开。
String mpvLogTag(String body) {
  final s = body.toLowerCase();
  // 鉴权必须排在「不存在」之前：`403 Forbidden` 与 `401` 是服务端拒绝，
  // 不是路径写错，提示与排查方向完全不同。
  if (s.contains('401') ||
      s.contains('403') ||
      s.contains('unauthorized') ||
      s.contains('forbidden') ||
      s.contains('authentication')) {
    return 'auth';
  }
  if (s.contains('404') || s.contains('not found') || s.contains('no such file')) {
    return 'notfound';
  }
  if (s.contains('timed out') || s.contains('timeout') || s.contains('time out')) {
    return 'timeout';
  }
  if (s.contains('protocol') || s.contains('scheme')) return 'protocol';
  if (s.contains('decoder') ||
      s.contains('codec') ||
      s.contains('decode') ||
      s.contains('unsupported format')) {
    return 'decoder';
  }
  if (s.contains('failed to open') ||
      s.contains('could not open') ||
      s.contains('cannot open')) {
    return 'open';
  }
  return '';
}

/// 一条 mpv 日志 → 一行脱敏诊断；不值得记录时返回 null。
///
/// 只留 `error` / `warn` / `fatal`：mpv 的 info/v 级会把每帧的时钟都吐出来，
/// 落盘等于把日志淹掉。`text` 剥完地址后为空（纯 URL 的日志）也丢弃——那种
/// 行不含任何可行动信息，只会把媒体地址的形状带进上下文。
String? mpvLogDigest({
  required String prefix,
  required String level,
  required Object? text,
}) {
  final lv = level.trim().toLowerCase();
  if (lv != 'error' && lv != 'warn' && lv != 'fatal') return null;
  final body = _strip(text);
  if (body == 'no-detail') return null;
  // 纯地址/纯路径的行：脱敏后只剩占位符，不含任何可行动信息，丢掉。
  if (_meaningful(body).isEmpty) return null;
  final p = prefix.trim().isEmpty ? 'mpv' : prefix.trim();
  final tag = mpvLogTag(body);
  final core = body.length > kMpvDigestMax
      ? body.substring(0, kMpvDigestMax)
      : body;
  return '$p/$lv${tag.isEmpty ? '' : '<$tag>'}: $core';
}

/// 往环形尾部追加一行：相邻重复直接丢弃（mpv 会连抛同一条错误），
/// 超过 [max] 条时丢最旧的。返回新列表，便于测试与不可变使用。
List<String> pushMpvDigest(
  List<String> tail,
  String? line, {
  int max = kMpvLogTailMax,
}) {
  if (line == null || line.isEmpty) return tail;
  if (tail.isNotEmpty && tail.last == line) return tail;
  final next = List<String>.of(tail)..add(line);
  if (max <= 0) return <String>[];
  while (next.length > max) {
    next.removeAt(0);
  }
  return next;
}

/// 媒体地址的**形状**指标：只记长度与字符类别计数，不含任何内容。
///
/// 用途：判断「mpv 打不开」是否源于地址形态（例如未转义的空格 / 非 ASCII
/// 字节 / 编码层叠），而这一判断不需要看到地址本身。
class UrlShape {
  final int length;
  final int nonAscii;
  final int spaces;
  final int escapes;
  final String scheme;
  final int port;

  const UrlShape({
    required this.length,
    required this.nonAscii,
    required this.spaces,
    required this.escapes,
    required this.scheme,
    required this.port,
  });
}

UrlShape urlShapeOf(String url) {
  final s = url.trim();
  var nonAscii = 0;
  var spaces = 0;
  var escapes = 0;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c > 0x7f) nonAscii++;
    if (c == 0x20) spaces++;
    if (c == 0x25) escapes++; // '%'
  }
  final uri = Uri.tryParse(s);
  final scheme = (uri?.scheme ?? '').isEmpty
      ? 'none'
      : (uri!.scheme == 'http' || uri.scheme == 'https' ? uri.scheme : 'other');
  final port = uri?.port ?? 0;
  return UrlShape(
    length: s.length,
    nonAscii: nonAscii,
    spaces: spaces,
    escapes: escapes,
    scheme: scheme,
    port: port,
  );
}

/// 形状指标 → 一行日志（不含地址、不含库名/文件名）。
String describeUrlShape(UrlShape s) =>
    'len=${s.length} nonascii=${s.nonAscii} space=${s.spaces}'
    ' pct=${s.escapes} scheme=${s.scheme} port=${s.port}';
