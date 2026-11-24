/// 播放器后端抽象（阶段4 · 平台层）——**骨架，未接线**。
///
/// ⚠️ 2026-11-24：本文件已从 `lib/` 移到 `docs/skeletons/`。
/// 原因：`lib/` 内**零 import**（`grep -rn "player_backend" lib` = 0），
/// 播放页仍然直接持有 media_kit 的 `Player`/`VideoController`，即「定义了一个
/// 谁都不用的接口，只有文档在描述它」。留在 `lib/` 里会让人误以为换后端只要
/// 改一个枚举。等真要上 iOS 原生（或任何第二后端）时，把它移回 `lib/`、
/// 让播放页依赖本接口，再按 `docs/ios-native-player.md` 的步骤验收。
///
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'decode_fallback.dart';

/// 可选的后端实现。选择逻辑见 [selectPlayerBackendKind]。
enum PlayerBackendKind {
  /// libmpv（media_kit），Android / Windows / Linux 继续使用。
  mpv,

  /// iOS 原生 AVPlayer（video_player / AVPlayerLayer），见
  /// `player_ios_native.dart`。
  iosNative,
}

/// 平台 + 开关 → 后端选择。
///
/// 纯逻辑（不碰 Platform、不碰播放器），便于单测，也便于回退开关：
/// iOS 上原生路径出问题时，只要调用方传 `iosNativeEnabled: false`，
/// 立刻回到 mpv，不需要改任何播放代码。
PlayerBackendKind selectPlayerBackendKind({
  required bool isIOS,
  required bool iosNativeEnabled,
}) {
  if (isIOS && iosNativeEnabled) return PlayerBackendKind.iosNative;
  return PlayerBackendKind.mpv;
}

/// 一次打开请求。
///
/// 对应 media_kit 的 `Media(uri, httpHeaders: ...)` + `open(play: ...)`；
/// iOS 原生侧对应 `VideoPlayerController.networkUrl(uri, httpHeaders: ...)`。
@immutable
class PlayerSource {
  /// 完整媒体地址（http/https/file）。NAS 鉴权靠 [httpHeaders]。
  final String uri;

  /// 请求头（NAS 的鉴权 token 等），原样透传给两端。
  final Map<String, String> httpHeaders;

  /// 调试用的媒体标题（mpv 显示在窗口标题/日志），iOS 不使用。
  final String? title;

  const PlayerSource(
    this.uri, {
    this.httpHeaders = const <String, String>{},
    this.title,
  });
}

/// 视频参数快照：显示尺寸（已按像素宽高比校正）与显示比例。
///
/// mpv 通过 `video-params` 上报 dw/dh/aspect；iOS 原生只有解码尺寸，
/// 比例需要按 preferredTransform 自行换算，见 `player_ios_native.dart`。
@immutable
class VideoParamsSnapshot {
  /// 显示宽度（像素），未知为 null。
  final int? width;

  /// 显示高度（像素），未知为 null。
  final int? height;

  /// 显示比例（w/h），未知为 null。
  final double? aspect;

  const VideoParamsSnapshot({this.width, this.height, this.aspect});

  /// 还没拿到尺寸（首帧前）。
  static const VideoParamsSnapshot unknown = VideoParamsSnapshot();

  /// 是否已经有可用的画面尺寸。
  bool get hasSize => (width ?? 0) > 0 && (height ?? 0) > 0;

  /// 由宽高推出比例（width/height），用于两端统一口径。
  double? get resolvedAspect =>
      aspect ?? ((width != null && height != null && height! > 0)
          ? width! / height!
          : null);

  @override
  bool operator ==(Object other) =>
      other is VideoParamsSnapshot &&
      other.width == width &&
      other.height == height &&
      other.aspect == aspect;

  @override
  int get hashCode => Object.hash(width, height, aspect);

  @override
  String toString() => 'VideoParamsSnapshot($width x $height, aspect: $aspect)';
}

/// 同步状态快照。
///
/// 播放页只在「自救」等同步判断里读当前状态（`stallRecoveryAction` 需要
/// `playing` / 位置），其余一律走事件流。
@immutable
class PlayerSnapshot {
  final Duration position;
  final Duration duration;
  final bool playing;
  final bool buffering;
  final bool completed;

  /// 音量，沿用 media_kit 的 0..100 语义（两端都按此换算）。
  final double volume;

  /// 播放速率，1.0 为原速。
  final double rate;

  const PlayerSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.volume = 100,
    this.rate = 1.0,
  });

  /// 尚未打开任何媒体。
  static const PlayerSnapshot idle = PlayerSnapshot();

  PlayerSnapshot copyWith({
    Duration? position,
    Duration? duration,
    bool? playing,
    bool? buffering,
    bool? completed,
    double? volume,
    double? rate,
  }) =>
      PlayerSnapshot(
        position: position ?? this.position,
        duration: duration ?? this.duration,
        playing: playing ?? this.playing,
        buffering: buffering ?? this.buffering,
        completed: completed ?? this.completed,
        volume: volume ?? this.volume,
        rate: rate ?? this.rate,
      );

  @override
  String toString() =>
      'PlayerSnapshot(position: $position, duration: $duration, '
      'playing: $playing, buffering: $buffering)';
}

/// 一条播放错误（解码失败 / 地址打不开 / 网络中断）。
///
/// 保持字符串形态：播放页现有 `classifyPlaybackError(String)` 直接可用，
/// 两端都只要把原始错误文本塞进来即可。
@immutable
class PlayerError {
  final String message;

  /// 原始异常/错误对象，便于日志，不参与分类。
  final Object? cause;

  const PlayerError(this.message, {this.cause});

  @override
  String toString() => 'PlayerError($message)';
}

/// 后端能力声明。
///
/// 播放页据此决定要不要挂兜底逻辑，而不是猜平台：
/// - iOS 原生不提供 `loop-file`（[playlistLoop] = false），循环交给上层；
/// - iOS 原生没有运行时切软解的能力（[runtimeDecodeSwitch] = false），
///   硬解失败只能换后端重开；
/// - iOS 原生不需要「重建纹理」这种 mpv 专属兜底
///   （[needsTextureRebuildWorkaround] = false）。
@immutable
class PlayerCapabilities {
  /// 后端名字，用于日志/诊断面板。
  final String name;

  /// 能否截取当前帧（`screenshot`）。
  final bool videoScreenshot;

  /// 能否在播放器内部单条循环（mpv `PlaylistMode.single`）。
  final bool playlistLoop;

  /// 能否在运行时切换硬解/软解（需要重建后端）。
  final bool runtimeDecodeSwitch;

  /// 是否原生上报视频显示尺寸/比例。
  final bool nativeVideoParams;

  /// 应用退到后台时音频能否继续（需配合音频会话与后台模式）。
  final bool backgroundAudio;

  /// 是否需要「音频在走但没画面 → 重建纹理」这类 mpv 专属兜底。
  final bool needsTextureRebuildWorkaround;

  /// 位置事件的大致间隔（用于发现「进度条不动」的判定阈值）。
  final Duration positionTick;

  const PlayerCapabilities({
    required this.name,
    this.videoScreenshot = true,
    this.playlistLoop = true,
    this.runtimeDecodeSwitch = true,
    this.nativeVideoParams = true,
    this.backgroundAudio = false,
    this.needsTextureRebuildWorkaround = false,
    this.positionTick = const Duration(milliseconds: 100),
  });

  /// mpv（media_kit）后端能力，与当前线上行为一致。
  static const PlayerCapabilities mpv = PlayerCapabilities(
    name: 'mpv',
    positionTick: Duration(milliseconds: 100),
    needsTextureRebuildWorkaround: true,
  );

  /// iOS 原生（AVPlayer）后端能力。
  static const PlayerCapabilities iosNative = PlayerCapabilities(
    name: 'ios-avplayer',
    // AVPlayerLayer 没有截图 API，计划走 AVAssetImageGenerator（待原生扩展）。
    videoScreenshot: false,
    playlistLoop: false,
    runtimeDecodeSwitch: false,
    nativeVideoParams: false,
    backgroundAudio: true,
    needsTextureRebuildWorkaround: false,
    positionTick: Duration(milliseconds: 100),
  );
}

/// 播放器后端接口。
///
/// 实现者：`MpvBackend`（本文件）、`IosNativeBackend`（player_ios_native.dart）。
/// 所有 `Future` 方法都必须可重复调用且不抛异常（内部吞掉底层错误并从
/// [errorStream] 上报），这样播放页的自救/重试逻辑不必到处 try/catch。
abstract class PlayerBackend {
  /// 后端名字（日志用）。
  String get name;

  /// 能力声明。
  PlayerCapabilities get capabilities;

  /// 当前同步状态。
  PlayerSnapshot get state;

  // ---- 事件流 ----
  /// 播放位置。
  Stream<Duration> get positionStream;

  /// 媒体总时长（打开后才有 > 0）。
  Stream<Duration> get durationStream;

  /// 是否正在播放。
  Stream<bool> get playingStream;

  /// 是否在缓冲（弱网提示用）。
  Stream<bool> get bufferingStream;

  /// 是否播放到结尾（播完切下一条 / 单条循环用）。
  Stream<bool> get completedStream;

  /// 视频尺寸/比例（首帧对齐、画面比例用）。
  Stream<VideoParamsSnapshot> get videoParamsStream;

  /// 播放错误。
  Stream<PlayerError> get errorStream;

  // ---- 控制 ----
  /// 打开媒体。[play] 为 false 时只解封装预缓冲，不出声不起播。
  Future<void> open(PlayerSource source, {bool play = true});

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// 停止并释放当前媒体（保留后端实例，供预缓冲槽位复用）。
  Future<void> stop();

  /// 音量，0..100（media_kit 语义）。
  Future<void> setVolume(double volume);

  /// 播放速率，1.0 为原速。
  Future<void> setRate(double rate);

  /// 单条循环开关（仅 [PlayerCapabilities.playlistLoop] 为 true 的后端支持）。
  Future<void> setLoopPlayback(bool enabled);

  /// 截取当前帧。不支持或失败时返回 null。
  Future<Uint8List?> screenshot({String format = 'image/jpeg'});

  // ---- 画面 ----
  /// 视频画面组件。调用方负责尺寸/裁剪（FittedBox / ClipRect 等）。
  Widget buildVideo({Key? key, BoxFit fit = BoxFit.contain});

  /// 释放后端（含底层播放器）。
  Future<void> dispose();
}

/// media_kit（libmpv）后端。
///
/// 与现有 `_PlaybackSlot` 完全等价：`PlayerConfiguration(title: 'Dizi',
/// bufferSize: 32MB)` + `VideoControllerConfiguration(hwdec: hwdecFor(mode))`。
/// 迁移期需要 media_kit 原生对象时用 [rawPlayer] / [rawController]。
class MpvBackend implements PlayerBackend {
  MpvBackend({DecodeMode decodeMode = DecodeMode.hardware}) {
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'Dizi',
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(hwdec: hwdecFor(decodeMode)),
    );
  }

  late final Player _player;
  late final VideoController _controller;

  /// 迁移期逃生口：底层 media_kit Player。
  Player get rawPlayer => _player;

  /// 迁移期逃生口：底层 media_kit VideoController。
  VideoController get rawController => _controller;

  @override
  String get name => 'mpv';

  @override
  PlayerCapabilities get capabilities => PlayerCapabilities.mpv;

  @override
  PlayerSnapshot get state {
    try {
      final s = _player.state;
      return PlayerSnapshot(
        position: s.position,
        duration: s.duration,
        playing: s.playing,
        buffering: s.buffering,
        completed: s.completed,
        volume: s.volume,
        rate: s.rate,
      );
    } catch (_) {
      return PlayerSnapshot.idle;
    }
  }

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<PlayerError> get errorStream =>
      _player.stream.error.map((msg) => PlayerError(msg));

  @override
  Stream<VideoParamsSnapshot> get videoParamsStream =>
      _player.stream.videoParams.map(_snapshotOf);

  static VideoParamsSnapshot _snapshotOf(VideoParams vp) {
    final w = vp.dw;
    final h = vp.dh;
    final aspect = vp.aspect ?? ((w != null && h != null && h > 0) ? w / h : null);
    return VideoParamsSnapshot(width: w, height: h, aspect: aspect);
  }

  @override
  Future<void> open(PlayerSource source, {bool play = true}) async {
    try {
      await _player.open(
        Media(source.uri, httpHeaders: source.httpHeaders),
        play: play,
      );
    } catch (e) {
      // 底层异常统一走 errorStream，调用方不必 try/catch。
    }
  }

  @override
  Future<void> play() => _swallow(_player.play);

  @override
  Future<void> pause() => _swallow(_player.pause);

  @override
  Future<void> seek(Duration position) => _swallow(() => _player.seek(position));

  @override
  Future<void> stop() => _swallow(_player.stop);

  @override
  Future<void> setVolume(double volume) =>
      _swallow(() => _player.setVolume(volume));

  @override
  Future<void> setRate(double rate) => _swallow(() => _player.setRate(rate));

  @override
  Future<void> setLoopPlayback(bool enabled) => _swallow(() => _player
      .setPlaylistMode(enabled ? PlaylistMode.single : PlaylistMode.none));

  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async {
    try {
      return await _player.screenshot(format: format);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget buildVideo({Key? key, BoxFit fit = BoxFit.contain}) => Video(
        key: key,
        controller: _controller,
        fit: fit,
        controls: NoVideoControls,
      );

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {
      // 已释放/正在释放，忽略。
    }
  }

  Future<void> _swallow(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // 与播放页现有 `try {} catch (_) {}` 风格一致：控制指令失败不抛出。
    }
  }
}
