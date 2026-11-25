import 'package:flutter/foundation.dart';
import 'unit_fraction.dart';

/// 播放进度 = pos / dur（0..1）。时长未知（0/负数）时视为 0。
///
/// 纯函数：进度不再从整页 build 里现算，而是由位置/时长两个
/// ValueNotifier 派生，只有订阅它的进度条会重建。
double playbackFraction(Duration position, Duration duration) {
  final d = duration.inMilliseconds;
  if (d <= 0) return 0;
  final p = position.inMilliseconds;
  return unitFraction(p / d);
}

/// 由 [position] / [duration] 派生出的进度 [ValueListenable]。
///
/// 播放中位置每 ~100ms 变一次，这里只把变化的进度值通知给进度条自身
/// （ScrubBar 的 ValueListenableBuilder），播放页其它层不参与重建。
/// 值不变时不发通知，避免无谓重绘。
class PlaybackFraction extends ChangeNotifier implements ValueListenable<double> {
  PlaybackFraction({
    required ValueListenable<Duration> position,
    required ValueListenable<Duration> duration,
  })  : _position = position,
        _duration = duration {
    _value = playbackFraction(_position.value, _duration.value);
    _position.addListener(_recompute);
    _duration.addListener(_recompute);
  }

  final ValueListenable<Duration> _position;
  final ValueListenable<Duration> _duration;
  double _value = 0;

  @override
  double get value => _value;

  void _recompute() {
    final next = playbackFraction(_position.value, _duration.value);
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _position.removeListener(_recompute);
    _duration.removeListener(_recompute);
    super.dispose();
  }
}
