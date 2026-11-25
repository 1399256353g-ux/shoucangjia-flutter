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

/// 人类可读字节：`0 B` / `512 B` / `2.0 KB` / `5.0 MB` / `3.00 GB` / `1.50 TB`。
///
/// 加上 TB 档不是为了好看：服务端把 `bytes` 写成 int 上限（坏数据占位值）
/// 时，旧实现算出 **`8589934592.00 GB`**（实测）——数值没算错，但把一个
/// 不可能存在的占用以最长的形式写进界面，那一行在窄屏上直接撑破。
/// 与时长文案同一个口径：单位用尽就用更大的单位，不输出荒唐数字。
String formatBytes(int n) {
  if (n <= 0) return '0 B';
  if (n < 1024) return '$n B';
  final kb = n / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  final gb = mb / 1024;
  if (gb < 1024) return '${gb.toStringAsFixed(2)} GB';
  return '${(gb / 1024).toStringAsFixed(2)} TB';
}
