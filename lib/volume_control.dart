/// H14：音量常驻任务栏的换算逻辑（纯函数，便于测试）。
///
/// 喇叭按钮：点击 = 静音切换；长按/横向拖动 = 调音量。
/// 拖动时按横向位移线性换算，200px 对应 100%，并夹紧到 0–100。
library;

const double kVolumeDragWidth = 200.0;

/// I1：iOS/Android 改用系统音量键，不再提供应用内音量调节 UI；仅桌面端保留。
bool volumeUiEnabled({required bool isDesktop, bool isWeb = false}) =>
    !isWeb && isDesktop;

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

/// 音量图标档位。三处读数（任务栏按钮 / 拖动浮层 / 桌面音量模块）共用
/// 这一条判定，不再各自写一份 `muted || volume == 0 ? off : volume < 50 …`。
enum VolumeIcon { mute, down, up }

/// 静音或 0 → [VolumeIcon.mute]；<50 → [VolumeIcon.down]；其余 [VolumeIcon.up]。
VolumeIcon volumeIconFor(double volume, {bool muted = false}) {
  if (muted || volume <= 0) return VolumeIcon.mute;
  if (volume < 50) return VolumeIcon.down;
  return VolumeIcon.up;
}

