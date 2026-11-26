import 'media_path.dart' show isMediaFilePath;
import 'text_clip.dart';

/// G12：播放失败分类与提示文案。
///
/// 弱网、超时、解码失败在界面上给出不同标题/说明，并统一提供重试入口。
/// 纯逻辑，方便单元测试；不依赖 Flutter 与播放器实现。
///
/// `missing` / `denied` 与 `network` 分开：传输层已经明确告诉我们
/// 「服务端没有这个文件」（404/410）或「拒绝了这次取流」（401/403）时，
/// 再说「请检查网络」就是把用户引到错误的排查方向上。
enum PlaybackFailureKind {
  network,
  decode,
  timeout,
  data,
  missing,
  denied,
  unknown,
}

class PlaybackFailure {
  final PlaybackFailureKind kind;
  final String title;
  final String detail;

  const PlaybackFailure(this.kind, this.title, this.detail);

  /// 重试是否有意义：数据异常、文件不存在、鉴权被拒都重试不出结果，
  /// 反复点只会白等一轮超时。
  bool get retryable =>
      kind != PlaybackFailureKind.data &&
      kind != PlaybackFailureKind.missing &&
      kind != PlaybackFailureKind.denied;

  @override
  String toString() => 'PlaybackFailure($kind, $title, $detail)';
}

/// 加载超过该时长且仍无时长信息，判定为超时（弱网/服务端无响应）。
const Duration playbackLoadTimeout = Duration(seconds: 15);

/// 缓冲超过该时长才提示「网络较慢」，避免正常起播时闪一下。
const Duration slowBufferThreshold = Duration(milliseconds: 1500);

const PlaybackFailure networkFailure = PlaybackFailure(
    PlaybackFailureKind.network, '网络连接失败', '无法连接服务器，请检查网络后重试');

const PlaybackFailure decodeFailure = PlaybackFailure(
    PlaybackFailureKind.decode, '播放失败', '视频解码失败或文件损坏，可重试或切换下一条');

const PlaybackFailure timeoutFailure = PlaybackFailure(
    PlaybackFailureKind.timeout, '加载超时', '网络较慢或服务器无响应，请稍后重试');

const PlaybackFailure unknownFailure = PlaybackFailure(
    PlaybackFailureKind.unknown, '加载失败', '播放出错了，请重试');

/// 服务端明确回答「没有这个文件」（404/410）：不是网络问题，重试也没用。
const PlaybackFailure mediaMissingFailure = PlaybackFailure(
    PlaybackFailureKind.missing,
    '媒体文件不存在',
    '服务器上没有这个文件（可能已被移动或删除），上滑查看其他作品');

/// 服务端拒绝取流（401/403）：连接凭据失效或该文件不可读。
const PlaybackFailure mediaDeniedFailure = PlaybackFailure(
    PlaybackFailureKind.denied, '无权访问该媒体', '服务端拒绝了这次取流，请重新连接或稍后再试');

/// 传输层状态码 → 失败类型。只认「能确定原因」的码，其余交给文本分类。
///
/// 这是 HTTP 状态与提示文案之间的**唯一映射口**：404 不等于网络故障，
/// 401/403 不等于文件丢失，两者与「连不上」必须分开。
PlaybackFailure? failureForHttpStatus(int? status) {
  if (status == null) return null;
  if (status == 404 || status == 410) return mediaMissingFailure;
  if (status == 401 || status == 403) return mediaDeniedFailure;
  return null;
}

/// 用传输层证据校正已经分好的失败类型。
///
/// 播放器的 `stream.error` 只说「打不开」，分类只能靠措辞猜；而 mpv 内部日志
/// 带着真实的 HTTP 状态。所有失败路径都汇到 `_showFailure`，在那里统一做一次
/// 校正——不在各条错误回调里各猜一遍。
PlaybackFailure withTransportStatus(PlaybackFailure f, int? status) {
  final exact = failureForHttpStatus(status);
  if (exact == null) return f;
  // 已确定的解码/数据缺失结论不被覆盖：状态码只用来纠正「网络」这种模糊归类。
  if (f.kind == PlaybackFailureKind.decode ||
      f.kind == PlaybackFailureKind.data) {
    return f;
  }
  return exact;
}

/// 媒体扩展名：判断「这一段词是不是文件名的末尾」。
///
/// 不用「第一个空格」当终点，就是因为媒体文件名里带空格是常态；也不用
/// 「整行都是路径」——那会把冒号后面的错误措辞（`Protocol not supported`）
/// 一起吃掉，导致失败原因丢失。
///
/// 0.9.281：原先本文件自己列了第三张扩展名表（视频多 `ts`、图片多 `avif`），
/// 与 `media_path` / `cover_ext` / `author_avatar` 都不同宽。脱敏边界判错
/// 一位，整段路径连同文件名就会留在日志里（AGENTS.md 红线）。现在转发
/// 唯一分类表 `media_path.isMediaFilePath`。
bool _looksLikeMediaFile(String token) => isMediaFilePath(token);

bool _redactBoundaryOk(String s, int at) {
  if (at == 0) return true;
  final p = s[at - 1];
  return p == ' ' ||
      p == '\t' ||
      p == '"' ||
      p == "'" ||
      p == '(' ||
      p == '[' ||
      p == '=';
}

/// 把一处地址/路径整段换成 `<path>`，返回消耗到的下标。
///
/// 起始标记已经在标记串之后（`http(s)://` 或 `/media/`、`/api/`）。终点候选按
/// 优先级：带媒体扩展名的词 → 闭合引号 / 换行 / `: ` 详情分隔符 → 串尾。
///
/// 这样 `open /media/我的 作品库/文件名 带空格.jpg failed` 会吃到 `.jpg` 为止
/// （`failed` 是错误措辞，保留），而 `cannot open "/media/lib/我的 作品.mp4"`
/// 会在闭合引号处停下并保留引号。
int _redactOneSpan(String s, int start) {
  var end = s.length;
  var closing = '';
  for (var k = start; k < s.length; k++) {
    final c = s[k];
    if (c == '"' || c == "'") {
      end = k;
      closing = c;
      break;
    }
    if (c == '\n' || c == '\r') {
      end = k;
      break;
    }
    if (c == ':' && k + 1 < s.length && s[k + 1] == ' ') {
      end = k;
      break;
    }
  }
  // 在区间里找「带媒体扩展名」的词作为真实终点。
  var stop = -1;
  var k = start;
  while (k < end) {
    while (k < end && s[k] == ' ') {
      k++;
    }
    if (k >= end) break;
    final t = RegExp(r'[^ \t]+').matchAsPrefix(s.substring(0, end), k);
    if (t == null) break;
    if (_looksLikeMediaFile(t.group(0)!)) {
      stop = t.end;
      break;
    }
    k = t.end;
  }
  // 找不到扩展名：非 ASCII/百分号编码说明这一段就是文件名，整段吃掉；
  // 否则只吃到第一个空白，留出后面的错误措辞。
  if (stop < 0) {
    final region = s.substring(start, end);
    final looksPathy =
        region.contains('%') || region.codeUnits.any((u) => u > 0x7f);
    if (looksPathy) {
      stop = end;
    } else {
      final t = RegExp(r'\S+').matchAsPrefix(s, start);
      stop = t == null ? start : t.end;
    }
  }
  if (closing.isNotEmpty) stop = end;
  return stop;
}

/// 把所有 `http(s)://…` 与 `/media/…`、`/api/…` 换成 `<path>`。
///
/// **不能写成「`/media/` 后面的非空白字符」这种朴素正则**：那会匹配到
/// **第一个空格**就停，而媒体路径里带空格是常态（`/media/库/我的 作品.mp4`、
/// `stream error at /media/lib-1/a b c.webm`）。旧实现只吃掉第一个空格之前
/// 那一段，剩下的 `作品.mp4` / `b c.webm` 原样留在日志里——文件名属于内容，
/// 正是 AGENTS.md 明令禁止进日志的东西，而截断后的日志看起来「已经脱敏」。
///
/// 起始位置必须是边界（行首、空白、引号、括号、`=`）：`x/media/not-a-path`
/// 里的 `/media/` 只是某个词的一部分，不是路径起点，不动它。
String _redactMediaPaths(String s) {
  final marker = RegExp(r'https?://|/(?:media|api)/');
  final out = StringBuffer();
  var i = 0;
  while (i < s.length) {
    final m = marker.firstMatch(s.substring(i));
    if (m == null) {
      out.write(s.substring(i));
      break;
    }
    final at = i + m.start;
    final after = i + m.end;
    if (!_redactBoundaryOk(s, at)) {
      // 不是路径起点（粘在前一个词里）：原样跳过这段标记，不误删内容。
      out.write(s.substring(i, after));
      i = after;
      continue;
    }
    out.write(s.substring(i, at));
    var closing = '';
    final stop = _redactOneSpan(s, after);
    if (stop < s.length && (s[stop] == '"' || s[stop] == "'")) {
      closing = s[stop];
    }
    out.write('<path>');
    i = stop;
    if (closing.isNotEmpty) {
      out.write(closing);
      i = stop + 1;
    }
  }
  return out.toString();
}

/// G20：单条作品数据异常，重试无意义，直接提示上/下滑切换。
const PlaybackFailure workDataFailure = PlaybackFailure(
    PlaybackFailureKind.data,
    '作品不可用',
    '作品数据不完整或媒体文件缺失，上滑/下滑查看其他作品');

/// 去掉消息里的 URL 与媒体路径，只留「错误文本」本身。
///
/// 播放器的错误消息几乎总带着媒体地址（`...decoder failed for
/// http://nas:8090/media/lib-001/a.mp4`）。若直接对整条消息做关键词匹配，
/// 地址里的 `http` 会让**每一条**媒体错误都命中网络关键词——解码失败、
/// 格式不支持全被显示成「网络连接失败」，用户按提示查网络是白费功夫。
/// 所以先把地址剥掉，剩下的才是真正要分类的错误文本。
String _stripUrls(String msg) {
  var s = msg.replaceAll(RegExp(r'https?://\S+'), ' ');
  // 没有协议头的裸路径（`/media/lib-001/...`）同样会把 `media`/库 id 混进
  // 关键词匹配，一并剥掉。
  s = s.replaceAll(RegExp(r'(?<=[\s("])/(?:media|api)/\S+'), ' ');
  return s;
}

/// 把播放器/网络异常转成用户能看懂的失败提示。
PlaybackFailure classifyPlaybackError(Object? error) {
  final raw = '${error ?? ''}'.toLowerCase();
  if (raw.isEmpty || raw == 'null') return unknownFailure;
  final msg = _stripUrls(raw);

  const networkKeys = [
    'connection',
    'connect',
    'socket',
    'network',
    'unreachable',
    'timed out',
    'timeout',
    'dns',
    'host',
    'http',
    '404',
    '403',
    '401',
    '500',
    '502',
    '503',
    '504',
    'no route',
    'reset by peer',
    'broken pipe',
  ];
  const decodeKeys = [
    'decode',
    'decoder',
    'codec',
    'demux',
    'invalid data',
    'unsupported',
    'no video',
    'no audio',
    'format',
    'parse',
    'corrupt',
    'truncated',
    'hevc',
    'h264',
    'aac',
  ];

  // 解码类优先：`MediaCodecRenderer: Failed to initialize decoder` 一类消息
  // 剥掉地址后已不含网络词，必须落到「解码失败」而不是「网络失败」。
  final isDecode = decodeKeys.any(msg.contains);
  final isNetwork = networkKeys.any(msg.contains);
  if (isDecode && !isNetwork) return decodeFailure;
  if (isNetwork && !isDecode) return networkFailure;
  // 两类词同时出现：先看有没有明确的解码失败措辞（解码器初始化/格式不支持），
  // 这类消息常同时含 `failed to connect` 之类的通用词。
  if (isDecode) {
    const strongDecode = [
      'decoder',
      'codec',
      'decode',
      'demux',
      'unsupported',
      'invalid data',
      'no video',
      'no audio',
      'corrupt',
      'truncated',
    ];
    if (strongDecode.any(msg.contains)) return decodeFailure;
    return networkFailure;
  }
  if (msg.contains('failed to open') || msg.contains('could not open')) {
    // 没有 HTTP 状态时，多为流打不开：弱网或解码初始化失败，统一提示重试。
    return networkFailure;
  }
  return unknownFailure;
}

/// 把原始播放器错误整理成**可写日志**的脱敏摘要。
///
/// 媒体地址与文件名属于隐私（AGENTS.md 红线），不能进日志；但
/// `decoder` / `unsupported` / `timeout` 这类非内容措辞必须留下，
/// 否则失败只能记成 `failure:network` 三个字，无法定位。
///
/// 规则：把 `http(s)://…` 与 `/media/…`、`/api/…` 整段换成 `<path>` →
/// 空白折叠 → 截断 160 字符。空输入返回 `no-detail`。
String sanitizePlaybackErrorForLog(Object? raw) {
  final s0 = '${raw ?? ''}'.trim();
  if (s0.isEmpty) return 'no-detail';
  var s = _redactMediaPaths(s0);
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return 'no-detail';
  // 截断走 text_clip：播放器错误原文可能含 emoji / 增补平面字符，
  // 硬切会把代理对切开，日志里出现半个字符。
  return clipToUnits(s, 160);
}
