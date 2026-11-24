/// 服务端 JSON 数值 → int / double（**唯一实现**）。
///
/// 服务端同一个计数字段有时发数字、有时发字符串（`"3"`），有时缺省。
/// 「先看是不是 num、不是就 tryParse 字符串、都失败用默认值」这套判断
/// 此前在 12 个文件里各抄了一遍，并且**已经分叉**：
///
/// | 位置 | 数字分支 |
/// |---|---|
/// | `resize_cache_api._int` | `v.round()` |
/// | 其余 11 处 | `v.toInt()` |
///
/// 同一个 `files: 1.6` 在缓存页显示 2、在其它页显示 1；`hit + miss`
/// 因为分子先四舍五入，命中率还与逐条计数对不上。规则只能有一份。
///
/// 语义固定为 **截断**（`toInt()`，与 Dart 对 num 的默认转换一致）：
/// 计数字段永远不该被向上取整——`1.6 个文件` 四舍五入成 2 是凭空多一个文件。
library;

/// 数值/数字字符串 → int；无法解析时返回 [fallback]（默认 0）。
int intOf(dynamic v, [int fallback = 0]) {
  if (v is num) {
    if (v is double && !v.isFinite) return fallback;
    return v.toInt();
  }
  if (v is String) return int.tryParse(v.trim()) ?? fallback;
  return fallback;
}

/// 数值/数字字符串 → double；无法解析时返回 [fallback]（默认 0）。
double doubleOf(dynamic v, [double fallback = 0]) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : fallback;
  }
  if (v is String) return double.tryParse(v.trim()) ?? fallback;
  return fallback;
}
