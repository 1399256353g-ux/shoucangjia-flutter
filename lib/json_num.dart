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

/// 数值/数字字符串 → int；无法解析时返回 **null**（**唯一实现**）。
///
/// 与 [intOf] 的区别只在失败时给不给默认值。**必须用这个版本**的场合是
/// 「失败要能与 0 区分」的解析（键码、配置项、越界判定）：这些地方把失败
/// 写成 0 会变成「合法的 0」——0 号键、0 权重，语义完全不同。
///
/// 关键点：`v is num` 之后**不能直接 `toInt()`**。JSON 里的 `1e999` 会被
/// `jsonDecode` 解析成 `double.infinity`，而 `infinity.toInt()` 抛
/// `Unsupported operation: Infinity or NaN toInt`——这发生在**启动读配置**的
/// 路径上（角标配色、等级权重、按键键码），一次坏值就让整份设置退回默认。
int? intOrNull(dynamic v) {
  if (v is num) {
    if (v is double && !v.isFinite) return null;
    return v.toInt();
  }
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// 数值/数字字符串 → double；无法解析或非有限值时返回 **null**。
///
/// 字符串分支同样要过 [isFinite]：`double.tryParse('NaN')` / `'Infinity'` /
/// `'1e999'` 都是**合法解析但非有限**的值，而 JSON 里写成字符串形式时
/// （`{"w": "NaN"}`、手工改过的配置文件）根本走不到 `is num` 那条守卫。
/// 放进 UI 的后果比“显示错”重：`NaN.clamp(0,3)` 返回 `NaN`，
/// `Border.all(width: NaN)` 在绘制阶段断言失败——医疗词条/角标一挂就灰屏。
double? doubleOrNull(dynamic v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  if (v is String) {
    final d = double.tryParse(v.trim());
    return (d != null && d.isFinite) ? d : null;
  }
  return null;
}

/// 整数的饱和加法：溢出时停在 ±int 上限，不回绕。
///
/// `9223372036854775807 + 9223372036854775807` 在 int64 上得到 **-2**（实测），
/// 而这类值真的会出现在服务端 JSON 里（坏数据/占位值常见写成 int 上限）。
/// 用普通 `+` 累加计数时，两个坏条目就能把「总播放量」变成负数，
/// 排行榜里显示成负值、排序也翻过来。
int addSat(int a, int b) {
  final r = a + b;
  // 同号且结果反号 = 回绕。
  if ((a >= 0) == (b >= 0) && (r >= 0) != (a >= 0)) {
    return a >= 0 ? 9223372036854775807 : -9223372036854775808;
  }
  return r;
}

/// 一组整数的饱和求和（非负计数用；负值按 0 计）。
int sumSat(Iterable<int> values) {
  var total = 0;
  for (final v in values) {
    if (v <= 0) continue;
    total = addSat(total, v);
  }
  return total;
}

/// 非负 × 非负 的饱和乘法：越界回绕时停在 int 上限。
///
/// `9223372036854775807 * 10` 实测得 **-10**。等级/排行里的加权分就是
/// 「计数 × 权重」，一个写成 int 上限的计数乘上权重 10 就变成负分，
/// 排序里等级直接从 S 掉到 D。
int mulSat(int a, int b) {
  if (a <= 0 || b <= 0) return 0;
  const max = 9223372036854775807;
  if (a > max ~/ b) return max;
  return a * b;
}

/// 数值/数字字符串 → int；无法解析时返回 [fallback]（默认 0）。
int intOf(dynamic v, [int fallback = 0]) => intOrNull(v) ?? fallback;

/// 数值/数字字符串 → double；无法解析时返回 [fallback]（默认 0）。
double doubleOf(dynamic v, [double fallback = 0]) => doubleOrNull(v) ?? fallback;

/// 数值/数字字符串 → num；无法解析或非有限值时返回 **null**。
///
/// 需要保留「整数就还是整数」的调用方用它（时长累加、封面角标）：
/// `intOf` 会把 `2.5` 截成 `2`，而时长角标应当显示 `0:02` 还是 `0:03`
/// 是另一件事，不该在解析层就丢掉小数。
num? numOrNull(dynamic v) {
  if (v is num) {
    if (v is double && !v.isFinite) return null;
    return v;
  }
  if (v is String) {
    // 与 [doubleOrNull] 同一条守卫：字符串形式的 `NaN`/`Infinity`/`1e999`
    // 会被 tryParse 如实解析成非有限值，不加判断就会往下游传 NaN。
    final n = num.tryParse(v.trim());
    if (n == null) return null;
    if (n is double && !n.isFinite) return null;
    return n;
  }
  return null;
}

/// 数值/字符串/布尔 → bool；无法判断时返回 **null**（**唯一实现**）。
///
/// 同一个服务端字段可能发 `true`、`1`、`"true"`、`"yes"`、`"0"`。
/// 此前每个调用方自己写一遍 `== true`，于是 `"true"`（字符串）在某些
/// 地方算 true、在另一些地方算 false——取决于是不是恰好写了 `== 1 ||`。
/// 本文件只认三种答案：明确真、明确假、无法判断；无法判断的**不要**
/// 默默当成 false，交给调用方决定。
bool? boolOrNull(dynamic v) {
  if (v is bool) return v;
  if (v is num) {
    if (v is double && !v.isFinite) return null;
    return v != 0;
  }
  if (v is String) {
    switch (v.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'on':
        return true;
      case 'false':
      case '0':
      case 'no':
      case 'off':
        return false;
    }
  }
  return null;
}

/// 同 [boolOrNull]，无法判断时用 [fallback]。
bool boolOf(dynamic v, [bool fallback = false]) => boolOrNull(v) ?? fallback;
