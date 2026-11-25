// 抓取间隔文案的唯一实现。
//
// 「每 N 分钟 / 每 N 小时」这条规则此前在四个地方各写了一份三元表达式：
//   - main.dart `_freqText`（基础库爬虫页频率回显）
//   - main.dart 爬虫设置页「当前：…抓取一次」
//   - unit_crawler_page.dart 快检间隔 chip 与全量间隔 chip
//   - unit_crawler_page.dart 底部「当前：…」汇总行
// 它们的阈值判断（>= 60 进小时）与取整方式一旦分叉，同一个数字会显示成
// 「每 1 小时」和「每 60 分钟」两种样子。这里只留一条规则。

/// 分钟数 → 「每 N 小时」/「每 N 分钟」。
///
/// 逐字沿用历史行为：>= 60 分钟按小时显示并**向下取整**（90 → 每 1 小时）；
/// 非正数表示不自动抓取，由调用方自己决定兜底文案，这里给「不自动」。
///
/// 上限 [kMaxIntervalMinutes] 不是防防御冗余：服务端旧字段 `intervalMin`
/// 被写成 int 上限时，旧实现会输出「每 153722867280912930 小时」
/// （实测）——数值没算错，但这不可能是真的抓取间隔，它只是把一个坏配置
/// 写进了界面。与「无穷大不是间隔」一样，超限值当「不自动」。
const int kMaxIntervalMinutes = 100 * 365 * 24 * 60; // 100 年，单位：分钟

String everyMinutesLabel(int minutes) {
  if (minutes <= 0 || minutes > kMaxIntervalMinutes) return '不自动';
  if (minutes >= 60) return '每 ${minutes ~/ 60} 小时';
  return '每 $minutes 分钟';
}
