/// iOS 原生播放器后端（阶段4 · 平台层）骨架。
///
/// 背景：iOS 目前和 Android/Windows 一样走 media_kit(libmpv) + 外部纹理，
/// 黑屏有声、纹理重建、起播卡顿都集中在这条路径上。owner 已同意 iOS 长期
/// 单独走原生 AVPlayer，本文件是基于 `video_player`（内部即
/// video_player_avfoundation → AVPlayer / AVPlayerLayer）的实现骨架。
///
/// 已实现（`video_player` 2.10.x 可用能力内）：
/// - open / play / pause / seek / stop / setVolume / setRate
/// - position / duration / playing / buffering / completed / videoParams / error
///   七路事件流（统一成 [PlayerBackend] 的流式接口）
/// - 画面组件：AVPlayerLayer 平台视图（默认）或 Flutter 纹理视图
///
/// 明确未实现（见 TODO，均需要原生扩展，不在本轮范围）：
/// - 截当前帧（`screenshot`）：AVPlayerLayer 没有截图 API，需要
///   AVAssetImageGenerator 或平台通道自绘；当前返回 null。
/// - 单条循环（loop-file）：video_player 的 setLooping 在结尾会 seek(0)
///   重新出帧，等于「再走一遍起播」，不符合本项目「停在末帧」的节奏，
///   因此接口层禁用，循环交给上层处理。
/// - 运行时硬解/软解切换：AVPlayer 没有对应开关，只能换后端重开。
/// - `videoGravity`：插件固定 AVLayerVideoGravityResizeAspect（letterbox），
///   要 fill/cover 需要自己算容器尺寸或写原生插件。
///
/// 本轮不接线：`lib/main.dart` 未引用本文件。接入步骤与回退开关设计见
/// `docs/ios-native-player.md`。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';

import 'player_backend.dart';

/// 视频画面的承载方式。
enum IosVideoSurface {
  /// AVPlayerLayer 平台视图（`VideoViewType.platformView`）：画面由 iOS 合成，
  /// Flutter 侧不复制像素，缩放/旋转不触发纹理重建。iOS 推荐默认值。
  platformView,

  /// Flutter 纹理视图（`VideoViewType.textureView`）：每帧把 CVPixelBuffer
  /// 三角化拷进纹理，行为更接近现在的 mpv 外部纹理，便于对照排查。
  textureView,
}

/// 基于 AVPlayer 的 iOS 播放器后端。
///
/// 使用约定：
/// - 只在 iOS 上实例化（其他平台 `video_player` 没有实现，`initialize()` 会
///   以 MissingPluginException 的形式进入 [errorStream]）。
/// - 所有控制方法都不抛异常：内部失败统一从 [errorStream] 上报，与
///   [MpvBackend] 的约定一致。
class IosNativeBackend implements PlayerBackend {
  IosNativeBackend({
    this.surface = IosVideoSurface.platformView,
    double volume = 100,
  }) : _volume = volume.clamp(0, 100).toDouble();

  /// 画面承载方式。
  final IosVideoSurface surface;

  VideoPlayerController? _controller;

  /// 每次 open 递增，迟到的初始化结果据此放弃。
  int _epoch = 0;
  bool _disposed = false;

  double _volume;
  double _rate = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = false;
  bool _completed = false;
  VideoParamsSnapshot _params = VideoParamsSnapshot.unknown;
  String? _lastError;

  final StreamController<Duration> _positions =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> _durations =
      StreamController<Duration>.broadcast();
  final StreamController<bool> _playings = StreamController<bool>.broadcast();
  final StreamController<bool> _bufferings = StreamController<bool>.broadcast();
  final StreamController<bool> _completeds = StreamController<bool>.broadcast();
  final StreamController<VideoParamsSnapshot> _paramsStream =
      StreamController<VideoParamsSnapshot>.broadcast();
  final StreamController<PlayerError> _errors =
      StreamController<PlayerError>.broadcast();

  @override
  String get name => 'ios-avplayer';

  /// 能力声明：见文件头的「明确未实现」。
  @override
  PlayerCapabilities get capabilities => PlayerCapabilities.iosNative;

  @override
  PlayerSnapshot get state => PlayerSnapshot(
        position: _position,
        duration: _duration,
        playing: _playing,
        buffering: _buffering,
        completed: _completed,
        volume: _volume,
        rate: _rate,
      );

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Stream<Duration> get durationStream => _durations.stream;

  @override
  Stream<bool> get playingStream => _playings.stream;

  @override
  Stream<bool> get bufferingStream => _bufferings.stream;

  @override
  Stream<bool> get completedStream => _completeds.stream;

  @override
  Stream<VideoParamsSnapshot> get videoParamsStream => _paramsStream.stream;

  @override
  Stream<PlayerError> get errorStream => _errors.stream;

  // ---- 控制 ----

  @override
  Future<void> open(PlayerSource source, {bool play = true}) async {
    if (_disposed) return;
    final epoch = ++_epoch;
    await _releaseController();
    if (_disposed || epoch != _epoch) return;
    _resetState();

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(source.uri),
      httpHeaders: source.httpHeaders,
      viewType: surface == IosVideoSurface.platformView
          ? VideoViewType.platformView
          : VideoViewType.textureView,
    );
    _controller = controller;
    controller.addListener(_onValueChanged);
    try {
      await controller.initialize();
    } catch (e) {
      if (epoch == _epoch) {
        _reportError('AVPlayer 初始化失败：$e', cause: e);
      }
      return;
    }
    if (_disposed || epoch != _epoch) return;

    // 初始化完成后先补齐时长/尺寸/首帧位置，再恢复音量与速率。
    _syncFromValue(controller.value);
    try {
      await controller.setVolume(_volume / 100);
      await controller.setPlaybackSpeed(_rate);
    } catch (_) {
      // 参数下发失败不影响播放，下一次 setVolume/setRate 会重试。
    }
    if (play) await this.play();
  }

  @override
  Future<void> play() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.play();
    } catch (e) {
      _reportError('播放失败：$e', cause: e);
    }
  }

  @override
  Future<void> pause() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.pause();
    } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.seekTo(position);
    } catch (e) {
      _reportError('跳转失败：$e', cause: e);
    }
  }

  /// 语义差异：mpv 的 stop 会卸载媒体；AVPlayer 侧只暂停并归零，保留控制器
  /// 以便槽位复用（预缓冲池需要）。真正释放请调用 [dispose]。
  @override
  Future<void> stop() async {
    final c = _controller;
    if (c == null) return;
    try {
      await c.pause();
      await c.seekTo(Duration.zero);
    } catch (_) {}
    _emitPosition(Duration.zero);
    _emitCompleted(false);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 100).toDouble();
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setVolume(_volume / 100);
    } catch (_) {}
  }

  @override
  Future<void> setRate(double rate) async {
    if (rate <= 0) return;
    _rate = rate;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.setPlaybackSpeed(rate);
    } catch (_) {}
  }

  /// TODO(ios-native)：AVPlayer 没有 loop-file。这里不启用插件自带的
  /// `setLooping`（结尾 seek(0) 会重新起播、闪一下首帧），保持与项目
  /// 「播完停在末帧」的节奏一致，循环由上层按 completed 事件处理。
  @override
  Future<void> setLoopPlayback(bool enabled) async {
    // 故意空实现：见上方 TODO 与 PlayerCapabilities.iosNative.playlistLoop。
  }

  /// TODO(ios-native)：AVPlayerLayer 无截图 API。
  /// 计划方案：AVAssetImageGenerator(时间=当前 position) 取帧，或原生
  /// 平台通道对 AVPlayerLayer 做 render(in:)；两者都需要写 iOS 原生代码。
  @override
  Future<Uint8List?> screenshot({String format = 'image/jpeg'}) async => null;

  // ---- 画面 ----

  @override
  Widget buildVideo({Key? key, BoxFit fit = BoxFit.contain}) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return SizedBox.shrink(key: key);
    }
    final aspect = _params.resolvedAspect;
    if (aspect == null || aspect <= 0) {
      return SizedBox.shrink(key: key);
    }
    final player = VideoPlayer(c);
    if (surface == IosVideoSurface.platformView) {
      // 平台视图不放进 FittedBox：平台视图被打上缩放变换会走额外的合成
      // 路径甚至显示异常。用 AspectRatio 交出正确比例，AVPlayerLayer 自己
      // 做 letterbox（插件固定 ResizeAspect）；要 cover 需自算容器尺寸。
      return AspectRatio(key: key, aspectRatio: aspect, child: player);
    }
    // 纹理视图：按视频自身比例给固定基准尺寸 + FittedBox 缩放，
    // 与现有 mpv 播放页的做法一致（缩放窗口不重建纹理）。
    const double baseH = 720.0;
    final baseW = (baseH * aspect).clamp(64.0, 8192.0);
    return ClipRect(
      key: key,
      child: FittedBox(
        fit: fit,
        alignment: Alignment.center,
        child: SizedBox(width: baseW, height: baseH, child: player),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    await _releaseController();
    await _positions.close();
    await _durations.close();
    await _playings.close();
    await _bufferings.close();
    await _completeds.close();
    await _paramsStream.close();
    await _errors.close();
  }

  // ---- 内部 ----

  Future<void> _releaseController() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    c.removeListener(_onValueChanged);
    try {
      await c.dispose();
    } catch (_) {}
  }

  void _resetState() {
    _lastError = null;
    _completed = false;
    _emitPosition(Duration.zero);
    if (_duration != Duration.zero) {
      _duration = Duration.zero;
      _durations.add(Duration.zero);
    }
    if (_playing) {
      _playing = false;
      _playings.add(false);
    }
    if (_buffering) {
      _buffering = false;
      _bufferings.add(false);
    }
    if (_params != VideoParamsSnapshot.unknown) {
      _params = VideoParamsSnapshot.unknown;
      _paramsStream.add(VideoParamsSnapshot.unknown);
    }
  }

  /// `VideoPlayerController` 是 ValueNotifier：位置由插件每 100ms 轮询推进
  /// （`_applyPlayPause` 里的 Timer.periodic），其他字段由平台事件驱动。
  /// 这里把「值变化」翻译成 [PlayerBackend] 的事件流，只推变化过的字段。
  void _onValueChanged() {
    final c = _controller;
    if (c == null || _disposed) return;
    if (c.value.hasError) {
      final desc = c.value.errorDescription ?? 'AVPlayer 播放失败';
      if (desc != _lastError) {
        _lastError = desc;
        _reportError(desc);
      }
      return;
    }
    _syncFromValue(c.value);
  }

  void _syncFromValue(VideoPlayerValue v) {
    if (!v.isInitialized) return;

    if (v.duration > Duration.zero && v.duration != _duration) {
      _duration = v.duration;
      _durations.add(v.duration);
    }
    if (v.position != _position) {
      _emitPosition(v.position);
    }
    if (v.isPlaying != _playing) {
      _playing = v.isPlaying;
      _playings.add(v.isPlaying);
    }
    if (v.isBuffering != _buffering) {
      _buffering = v.isBuffering;
      _bufferings.add(v.isBuffering);
    }
    final params = _paramsOf(v);
    if (params != _params) {
      _params = params;
      _paramsStream.add(params);
    }

    final duration = _duration;
    if (duration > Duration.zero) {
      final atEnd = v.isCompleted || v.position >= duration;
      if (atEnd && !_completed) {
        _completed = true;
        _completeds.add(true);
      } else if (!atEnd &&
          _completed &&
          v.position < duration - const Duration(seconds: 1)) {
        // 回退 / 重播后重新武装，保证下一轮播完还能再报一次。
        _completed = false;
        _completeds.add(false);
      }
    }
  }

  void _emitPosition(Duration position) {
    _position = position;
    if (!_positions.isClosed) _positions.add(position);
  }

  void _emitCompleted(bool value) {
    if (_completed == value) return;
    _completed = value;
    if (!_completeds.isClosed) _completeds.add(value);
  }

  void _reportError(String message, {Object? cause}) {
    if (_disposed) return;
    _errors.add(PlayerError(message, cause: cause));
  }

  /// 显示尺寸/比例。`VideoPlayerValue.size` 已是解码尺寸（未按
  /// preferredTransform 旋转），`aspectRatio` 由插件按 rotationCorrection
  /// 换算出「显示」比例，两者口径与 mpv 的 dw/dh/aspect 对齐。
  static VideoParamsSnapshot _paramsOf(VideoPlayerValue v) {
    final size = v.size;
    final aspect = v.aspectRatio;
    if (size.width <= 0 || size.height <= 0) {
      return aspect > 0
          ? VideoParamsSnapshot(aspect: aspect)
          : VideoParamsSnapshot.unknown;
    }
    final w = size.width.round();
    final h = size.height.round();
    return VideoParamsSnapshot(
      width: w,
      height: h,
      aspect: aspect > 0 ? aspect : w / h,
    );
  }
}
