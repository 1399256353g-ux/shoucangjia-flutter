/// 字节数 → 人类可读文案（**全 App 唯一出口**）。
///
/// 第十二批收口：同一条规则原先有 3 份实现，且结果不同——
///  - `cover_cache.formatBytes`：B/KB/MB/GB 四级，负数原样输出 `-5 B`；
///  - `resize_cache_api.bytesText`：同样四级，但先夹到 0（负数显示 `0 B`）；
///  - `crash_guard.crashLogFileInfo` 内联：只有三级，**没有 GB**，
///    2 GB 的日志会显示成 `2048.0 MB`。
///
/// 前两份只差「负数怎么办」，第三份是格式真的不一样。现在统一到这里：
/// 负数与 0 一律 `0 B`，四级固定 B / KB(1 位) / MB(1 位) / GB(2 位)。
library;

import 'dart:math' as math;

/// 人类可读字节：`0 B` / `512 B` / `2.0 KB` / `5.0 MB` / `3.00 GB` / `1.50 TB`。
///
/// 加上 TB 档不是为了好看：服务端把 `bytes` 写成 int 上限（坏数据占位值）
/// 时，旧实现算出 **`8589934592.00 GB`**（实测）——数值没算错，但把一个
/// 不可能存在的占用以最长的形式写进界面，那一行在窄屏上直接撑破。
/// 与时长文案同一个口径：单位用尽就用更大的单位，不输出荒唐数字。
String formatBytes(int n) {
  if (n <= 0) return '0 B';
  if (n < 1024) return '$n B';
  // 每一档先看「**按下限精度截断**后是否还小于 1024」，不是看原始比值。
  //
  // 旧写法 `final kb = n / 1024; if (kb < 1024) …` 的边界是错的：
  // 1048575 字节（1 MB − 1）算出 `kb = 1023.999…`，确实 < 1024，于是走 KB
  // 档，而 `toStringAsFixed(1)` 会**四舍五入**成 **`1024.0 KB`**（实测）。
  // 1024 KB 就是 1 MB，这行字读起来是一个不可能存在的读数。MB→GB、
  // GB→TB 同理（`1073741823` → `1024.0 MB`、`1099511627775` → `1024.00 GB`），
  // 所以每一档的末尾都有一个窗口会跨档显示。
  //
  // 修法用**截断**而不是四舍五入：与 `unit_library.formatCount` 同一条口径
  // （「宁可少报也不能虚假跨档」）。1048575 → `1023.9 KB`，是一个诚实的
  // 读数；显示精度本身只有 0.1 KB，说成 `1024.0 KB` 就是多报了。
  final kb = n / 1024;
  if (_cutValue(kb, 1) < 1024) return '${_truncated(kb, 1)} KB';
  final mb = kb / 1024;
  if (_cutValue(mb, 1) < 1024) return '${_truncated(mb, 1)} MB';
  final gb = mb / 1024;
  if (_cutValue(gb, 2) < 1024) return '${_truncated(gb, 2)} GB';
  return '${_truncated(gb / 1024, 2)} TB';
}

/// 保留 [digits] 位小数的**截断值**（不进位，转定点文本）。
String _truncated(double v, int digits) =>
    _cutValue(v, digits).toStringAsFixed(digits);

/// 截断到 [digits] 位小数的数值（比较跨档用）。
double _cutValue(double v, int digits) {
  final scale = math.pow(10, digits).toDouble();
  return (v * scale).floorToDouble() / scale;
}
