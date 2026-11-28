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

/// 库根爬虫频率的可选档位（分钟），`0` 表示不自动。
///
/// 0.9.361：设置页的 chip 列表此前是 `{0:'不自动', 30:'每 30 分钟', …}`
/// ——档位与**文案**一起写死。同一页下面那行「当前：…抓取一次」走
/// [everyMinutesLabel]，于是同一份数据在同一页有两个说法出口：改了
/// [everyMinutesLabel] 的措辞（比如「每 30 分」）chip 不会跟，用户看到的
/// 档位名和回显名不一样，还都是「看起来正常」。档位归这里，文案归
/// [everyMinutesLabel]，不再各存一份。

/// 库根爬虫频率档位：`0`（不自动）+ 30 分钟 … 24 小时。
///
/// 只放分钟数；文字一律由 [everyMinutesLabel] 生成（含 `0` → 「不自动」）。
const List<int> kCrawlIntervalOptions = <int>[0, 30, 60, 360, 720, 1440];

String everyMinutesLabel(int minutes) {
  if (minutes <= 0 || minutes > kMaxIntervalMinutes) return '不自动';
  if (minutes >= 60) return '每 ${minutes ~/ 60} 小时';
  return '每 $minutes 分钟';
}

/// 纯时长：「N 分钟」。**不是**频率（频率是「每 N 分钟」，见 [everyMinutesLabel]）。
///
/// 0.9.362：快检冷却的档位 chip 写 `'$m 分钟'`，而同一页底部汇总行写
/// `'冷却 $cooldownMin 分钟'` —— 同一个时长、同一个单位后缀，两处各拼一遍。
/// 单位改成「分」或加上秒数时只能改到一处，另一处会留着旧说法。
/// 这里只管「数字 + 单位」，前缀（`冷却`）由调用方加。
String minutesLabel(int minutes) => '$minutes 分钟';
