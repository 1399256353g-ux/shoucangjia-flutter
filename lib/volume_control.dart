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
  // `NaN.clamp(0, 100)` **返回 NaN**（clamp 不消 NaN），NaN 音量进
  // `player.setVolume` 之后听感是「随机」——app 内音量条也会显示 NaN%。
  // 用力上限：任何非有限输入都视为「这次拖动不改变音量」，取当前值。
  final s0 = start.isFinite ? start.clamp(0.0, 100.0) : 100.0;
  if (!width.isFinite || width <= 0 || !dx.isFinite) return s0;
  final v = s0 + dx / width * 100.0;
  return v.isFinite ? v.clamp(0.0, 100.0) : s0;
}

/// 静音切换后应使用的音量：静音时 0，取消静音时回到上次音量（无效则满音量）。
double volumeAfterMuteToggle({
  required bool nowMuted,
  required double current,
  required double last,
}) {
  if (nowMuted) return 0;
  // 同上的 NaN 通道：`NaN > 0` 为 false，两个分支都会掉到「满音量」，
  // 静音再取消静音会突然变成 100%。非有限值按 0 处理（随后用满音量兜底）。
  final l = last.isFinite && last > 0 ? last.clamp(0.0, 100.0) : 0.0;
  if (l > 0) return l;
  final c = current.isFinite && current > 0 ? current.clamp(0.0, 100.0) : 0.0;
  return c > 0 ? c : 100.0;
}

/// 音量图标档位。三处读数（任务栏按钮 / 拖动浮层 / 桌面音量模块）共用
/// 这一条判定，不再各自写一份 `muted || volume == 0 ? off : volume < 50 …`。
enum VolumeIcon { mute, down, up }

/// 静音或 0 → [VolumeIcon.mute]；<50 → [VolumeIcon.down]；其余 [VolumeIcon.up]。
///
/// 非有限值按**静音**显示：`NaN <= 0` 与 `NaN < 50` 都是 false，旧写法
/// 直接把「音量未知」归到「大音量」档（实测），与同文件的 `volumeFromDrag`
/// / `volumeAfterMuteToggle`（非有限一律当 0）恰恰相反——同一个 NaN 在图标
/// 上是满音量、在数字上是 0，弹层里两个显示对不上。
VolumeIcon volumeIconFor(double volume, {bool muted = false}) {
  if (muted || !volume.isFinite || volume <= 0) return VolumeIcon.mute;
  if (volume < 50) return VolumeIcon.down;
  return VolumeIcon.up;
}

