/// 0–1 比例（进度、透明度、面板高度）的唯一归一实现。
///
/// 为什么要有这个文件：同一件事「把值夹到 0–1」在 `lib/` 里被写了 20 遍，
/// 而**非有限值的处理各不相同、且有一处注释把行为写反了**。
///
/// `dart` 实测（不是推测，直接跑过）：
///
/// ```
/// double.nan.clamp(0.0, 1.0)              -> 1.0     ← 不是 NaN！
/// double.infinity.clamp(0.0, 1.0)         -> 1.0
/// double.negativeInfinity.clamp(0.0, 1.0) -> 0.0
/// double.nan.clamp(0.0, 1.0).isFinite     -> true
/// ```
///
/// `clamp` 用 `compareTo` 判界，而 `NaN.compareTo(1.0) == 1`（NaN 视为最大），
/// 于是 NaN 一路走到上界。`playback_flow.dart` 曾注释「NaN.clamp 返回 NaN，
/// 随后 NaN.floor() 抛异常」——**这句是错的**，真实后果不是抛异常，而是
/// 「比例未知」被静默当成「进度 100%」：拖到片尾、面板吸到全屏、底纹拉满。
///
/// 所以默认把非有限值归到 **0**（「还没开始 / 不可用」），需要别的语义时
/// 显式传 [fallback]。调用方若必须区分「值不可用」与「值就是 0」，不要用
/// 本函数——那类场合应该返回 `null`（见 `player_controls.scrubFractionOf`）。
library;

/// 把 [v] 夹到 0–1；非有限值（NaN / ±Infinity）返回 [fallback]。
///
/// [fallback] 自己也会被夹到 0–1；它本身非有限时回落 0，绝不把 NaN 传出去。
double unitFraction(double v, {double fallback = 0}) {
  if (!v.isFinite) {
    return fallback.isFinite ? fallback.clamp(0.0, 1.0).toDouble() : 0.0;
  }
  return v.clamp(0.0, 1.0).toDouble();
}
