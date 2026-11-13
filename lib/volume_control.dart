/// H14：音量常驻任务栏的换算逻辑（纯函数，便于测试）。
///
/// 喇叭按钮：点击 = 静音切换；长按/横向拖动 = 调音量。
/// 拖动时按横向位移线性换算，200px 对应 100%，并夹紧到 0–100。
library;

const double kVolumeDragWidth = 200.0;

/// 以 [start] 为按下时的音量，手指横向移动 [dx] 像素后的新音量。
double volumeFromDrag(double start, double dx,
    {double width = kVolumeDragWidth}) {
  if (width <= 0) return start.clamp(0.0, 100.0);
  final v = start + dx / width * 100.0;
  return v.clamp(0.0, 100.0);
}

/// 静音切换后应使用的音量：静音时 0，取消静音时回到上次音量（无效则满音量）。
double volumeAfterMuteToggle({
  required bool nowMuted,
  required double current,
  required double last,
}) {
  if (nowMuted) return 0;
  if (last > 0) return last.clamp(0.0, 100.0);
  return current > 0 ? current.clamp(0.0, 100.0) : 100.0;
}

/// 音量对应的图标语义档位：0 静音、<50 低、其余高。
String volumeIconLevel(double volume, {bool muted = false}) {
  if (muted || volume <= 0) return 'mute';
  if (volume < 50) return 'down';
  return 'up';
}
