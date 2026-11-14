/// F34：解码失败的兜底策略。
///
/// 应用宝/安卓模拟器里，个别 H.264/HEVC 作品在硬件解码路径上会失败
/// （libmpv 报 decode/codec 错误），但同一文件软件解码可以正常播放。
/// 这里提供一层纯逻辑：判定是否值得自动切到软件解码重试，以及对应的
/// mpv `hwdec` 取值；播放器重建留在 UI 层，方便单测覆盖。
library;

import 'playback_error.dart';

/// 解码路径。hardware 为默认的 `auto-safe`，software 强制 `no`。
enum DecodeMode { hardware, software }

/// Windows 上用安全硬件解码；其他平台 media_kit 默认即可。
const String hwdecAutoSafe = 'auto-safe';

/// 关闭硬件解码，改用 CPU 解码（兼容性最好，功耗更高）。
const String hwdecSoftware = 'no';

String hwdecFor(DecodeMode mode) =>
    mode == DecodeMode.software ? hwdecSoftware : hwdecAutoSafe;

DecodeMode otherDecodeMode(DecodeMode mode) =>
    mode == DecodeMode.software ? DecodeMode.hardware : DecodeMode.software;

/// 是否应自动切软件解码重试。
///
/// 只在「视频 + 当前为硬件解码 + 本次进入页面还没重试过 + 失败类型像解码问题」
/// 时返回 true；网络/超时/数据缺失不重试，避免弱网下白白重开一次媒体。
bool shouldRetryWithSoftwareDecode({
  required PlaybackFailureKind? kind,
  required DecodeMode mode,
  required bool alreadyRetried,
  required bool isVideo,
  bool tokenAlive = true,
}) {
  if (!tokenAlive || !isVideo || alreadyRetried) return false;
  if (mode == DecodeMode.software) return false;
  return kind == PlaybackFailureKind.decode ||
      kind == PlaybackFailureKind.unknown;
}

/// 自动重试时给用户的一行提示（不打断播放，浮层淡出）。
const String softwareDecodeNotice = '已切换软件解码重试…';
