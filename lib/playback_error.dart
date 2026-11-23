/// G12：播放失败分类与提示文案。
///
/// 弱网、超时、解码失败在界面上给出不同标题/说明，并统一提供重试入口。
/// 纯逻辑，方便单元测试；不依赖 Flutter 与播放器实现。
enum PlaybackFailureKind { network, decode, timeout, data, unknown }

class PlaybackFailure {
  final PlaybackFailureKind kind;
  final String title;
  final String detail;

  const PlaybackFailure(this.kind, this.title, this.detail);

  bool get retryable => kind != PlaybackFailureKind.data;

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

/// 加载超时判定：进入页面 elapsedMs 后仍没有时长，就认为失败。
bool playbackLoadTimedOut(int elapsedMs, {required bool hasDuration}) =>
    !hasDuration && elapsedMs >= playbackLoadTimeout.inMilliseconds;
