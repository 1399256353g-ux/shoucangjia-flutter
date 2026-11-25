/// 布局尺寸的**唯一**取值口径（有限性 + 取整）。
///
/// 背景（0.9.246 第三十六批）：`MediaQuery.sizeOf` / `constraints.maxWidth`
/// 在嵌套滚动、对话框、以及「窗口正被拖成 0 高」的中间态里可以是
/// `double.infinity` 或 `NaN`。而 Dart 的 `num.ceil()` / `num.floor()` /
/// `num.round()` 对这两种值**直接抛** `Unsupported operation:
/// Infinity or NaN toInt`——发生在 `build()` 里就是整页灰屏。
///
/// 实测（flutter test 里同样的表达式）：
/// ```
/// double.infinity.ceil()                -> 抛 Unsupported operation
/// double.nan.ceil()                     -> 抛 Unsupported operation
/// recommendVisibleCount(Size(360, inf)) -> 抛 Unsupported operation
/// firstScreenThumbCount(viewportHeight: nan) -> 抛 Unsupported operation
/// ```
///
/// 这些函数此前各自写 `if (x <= 0) return …` 当作守卫。**`NaN <= 0` 为
/// false**、`infinity <= 0` 也为 false，于是守卫一个都拦不住——这不是
/// 「参数不合法」而是「守卫用错了判据」，所以统一收在这里，只留一份。
library;

/// 非有限值（NaN / ±Infinity）→ [fallback]；有限值原样返回。
///
/// 不做任何夹紧：置 0 还是置别的由调用方决定（尺寸置 0 表示「没有可用
/// 空间」，比例置 1 表示「不缩放」，语义不同，不能在这里猜）。
double finiteOr(double v, double fallback) => v.isFinite ? v : fallback;

/// 尺寸 → 向上取整的整数；非有限或 ≤0 时返回 [fallback]。
///
/// 用于「按尺寸算格子数/行数」这类调用：非有限值代表**没有可用空间**，
/// 返回兜底值而不是抛异常。不要用它做四舍五入（[roundDim] 是另一档语义）。
int ceilDim(double v, {int fallback = 1}) =>
    (v.isFinite && v > 0) ? v.ceil() : fallback;

/// 尺寸 → 向下取整的整数；非有限或 ≤0 时返回 [fallback]。
int floorDim(double v, {int fallback = 0}) =>
    (v.isFinite && v > 0) ? v.floor() : fallback;

/// 尺寸 → 四舍五入的整数；非有限时返回 [fallback]（**负数保留**）。
///
/// 与 [ceilDim]/[floorDim] 的区别只在「≤0 要不要兜底」：这个版本负值原样
/// 取整，供后面还要自己夹紧的调用方使用（如 `… .round().clamp(360, 2160)`，
/// 那里负数会被 clamp 收掉，兜底成 0 反而多一条分支）。
int roundDim(double v, {int fallback = 0}) => v.isFinite ? v.round() : fallback;
