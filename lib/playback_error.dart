/// G12：播放失败分类与提示文案。
///
/// 弱网、超时、解码失败在界面上给出不同标题/说明，并统一提供重试入口。
/// 纯逻辑，方便单元测试；不依赖 Flutter 与播放器实现。
enum PlaybackFailureKind { network, decode, timeout, unknown }

class PlaybackFailure {
  final PlaybackFailureKind kind;
  final String title;
  final String detail;

  const PlaybackFailure(this.kind, this.title, this.detail);

  bool get retryable => true;

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

/// 把播放器/网络异常转成用户能看懂的失败提示。
PlaybackFailure classifyPlaybackError(Object? error) {
  final msg = '${error ?? ''}'.toLowerCase();
  if (msg.isEmpty || msg == 'null') return unknownFailure;

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

  // HTTP/连接类错误优先按网络处理（下载失败常带 "failed to open"）。
  if (networkKeys.any(msg.contains)) return networkFailure;
  if (decodeKeys.any(msg.contains)) return decodeFailure;
  if (msg.contains('failed to open') || msg.contains('could not open')) {
    // 没有 HTTP 状态时，多为流打不开：弱网或解码初始化失败，统一提示重试。
    return networkFailure;
  }
  return unknownFailure;
}

/// 加载超时判定：进入页面 elapsedMs 后仍没有时长，就认为失败。
bool playbackLoadTimedOut(int elapsedMs, {required bool hasDuration}) =>
    !hasDuration && elapsedMs >= playbackLoadTimeout.inMilliseconds;
