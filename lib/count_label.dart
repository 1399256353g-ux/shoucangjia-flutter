/// 计数文案（**唯一出口**）：`1234 → 1.2k`、`12345 → 1.2万`、`1.2e8 → 1.2亿`。
///
/// 第十八批把这条规则收回 `unit_library.dart`，但它的调用点早已不止单元库：
/// 基础库卡片（`unit_library_view`）、设置→单元库（`main`）、文件结构页
/// （`folder_structure_page`）、作者挂载面板（`author_mount_sheet`）都要显示
/// 计数。放在 `unit_library` 里，别的页面要么 import 整个单元库模块（分层
/// 反了），要么**自己再拼一遍**——后者的实际后果是本轮修的那个缺口：
///
/// | 位置 | 写法 |
/// |---|---|
/// | `unit_library_view` 单元库卡 | `formatCount(works)` |
/// | `unit_library_view` 基础库卡 | `${basic.works} 作品` ← 原始数字 |
/// | `main` 设置→单元库 | `${b.works} 作品` ← 原始数字 |
/// | `folder_structure_page` | `${r.authors} 位作者` ← 原始数字 |
///
/// 同一个基础库，网格卡片写 `1.2万 作品`、设置页写 `12345 作品`。数字都对，
/// 但「同一个读数两种写法」本身就是缺陷：用户会以为两处不是同一份数据。
///
/// 所以规则搬到这里（与 `byte_size.dart` 平级：都是「纯文本读数」），
/// `unit_library.dart` 保留 re-export，既有 import 不必改。
library;

/// 计数显示：1234 → 1.2k，12345 → 1.2万，1.2e8 → 1.2亿，1.2e12 → 1.2万亿。
///
/// 四处缺口：
///  - 没有「亿」以上的档，int 上限（坏数据常见形态）算出
///    `92233720368.5亿`（实测）——十一位数字把卡片撑破；
///  - 负计数直接输出 `-5`（服务端出错时会把 `-1` 当计数发下来，
///    在卡片上读成「负数个作品」）；
///  - **四舍五入会把计数说大**：`999949` 先切万再 `toStringAsFixed(1)`
///    得到 `100.0` → `100万`，实际还不满 100 万。
///
/// 计数一律**向下截断**到一位小数（宁可少报也不能虚假跨档），单位用尽就
/// 换更大的单位（k → 万 → 亿 → 万亿 → 亿亿），不输出荒唐长数字——与
/// `formatBytes` 的 EB、`formatClockSeconds` 的 `--:--` 同一条规则。
String formatCount(int n) {
  if (n <= 0) return '0';
  if (n < 1000) return '$n';
  if (n < 10000) return _scaledCount(n, 1000, 'k');
  if (n < 100000000) return _scaledCount(n, 10000, '万');
  if (n < 1000000000000) return _scaledCount(n, 100000000, '亿');
  if (n < 10000000000000000) {
    return _scaledCount(n, 1000000000000, '万亿');
  }
  // int64 上限 9.22e18 → `922.3亿亿`（仍是可读的七位数字以内）。
  return _scaledCount(n, 10000000000000000, '亿亿');
}

/// `n / unit` 保留一位小数（**截断**，不进位），去掉末尾 `.0`。
///
/// 截断而不是四舍五入：`999949` 向上会变成 `100万`（凭空跨档），
/// 而计数类文案一旦多说就不能再用；末尾一整位小数也省下来（`3万` 而非 `3.0万`）。
///
/// **不能用 `n * 10 ~/ unit`**：int64 上 `n * 10` 在 `n > 9.2e17` 时会静默
/// 回绕成负数，服务端把计数写成 `9223372036854775807`（int 上限，坏数据常见
/// 形态）时显示成 `0亿`——看起来像「这个库没有作品」。先取整、再用余数求
/// 小数位，中间值都不会超 `unit * 10`，任何计数都不会溢出。
String _scaledCount(int n, int unit, String suffix) {
  final whole = n ~/ unit;
  final frac = (n % unit) * 10 ~/ unit; // 0–9，余数 < unit 所以不会溢出
  return frac == 0 ? '$whole$suffix' : '$whole.$frac$suffix';
}

/// 作品计数行（**唯一出口**）：底部那一行「共 N 件」。
///
/// 这里原先直接插 `shown.length`——那是**已经拉到内存里的条数**，而作品列表
/// 是 60 条一页的增量加载。于是同一次进入基础库，顶部 tab 写「作品 300」、
/// 底部写「共 60 件」；往下滚两屏变成「共 180 件」。同一屏两个总数，而且
/// 越大越错（`共` 是总数，却在滚动中一直变大）。
///
/// 规则：
///  - 全部加载完（`loaded >= total`）或服务端没给 total → 「共 N 件」；
///  - 还有未加载的页 → 「已载入 X / 共 Y 件」（两个数都写清，任何时刻都自洽）；
///  - 叠加类型筛选时前缀换成「符合 N 件」——那是筛选后的条数，不是总数。
/// 计数一律走 [formatCount]，与卡片/设置页同一套单位。
String worksCountLabel({
  required int shown,
  required int loaded,
  int total = 0,
  bool filtered = false,
}) {
  final s = shown > 0 ? shown : 0;
  final l = loaded > 0 ? loaded : 0;
  final t = total > 0 ? total : 0;
  final head = filtered ? '符合 ${formatCount(s)} 件' : '';
  // total 不可信（服务端没给/给了负数/比已载入还小）时以已载入为准：
  // 「共 60 件」下面却摆着 120 张卡片，是比缺总数更难解释的读数。
  final full = t > 0 ? (t > l ? t : l) : l;
  if (l >= full) {
    if (filtered) return head;
    return '共 ${formatCount(full)} 件';
  }
  final loadedPart = '已载入 ${formatCount(l)} / 共 ${formatCount(full)} 件';
  return filtered ? '$head · $loadedPart' : loadedPart;
}
