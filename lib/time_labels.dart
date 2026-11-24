/// 本地时间文案（**单一真源**）。
///
/// 第十二批收口：同一件事「毫秒/字符串时间戳 → `MM-dd HH:mm`」原先在
/// 5 个文件里各写一份，其中出现两种不同结果：
///  - `deleted_monitor.atLabel` / `syncLabelOf` / `syncTimeLabel` /
///    `unit_crawler_page._t` / `crash_guard` 内联：都用本地时区；
///  - `deleted_monitor.syncKeyOf`：**故意用 UTC**（批次键不能随时区漂移），
///    这是唯一例外，保留在 `deleted_monitor` 本文件并明确注释。
///
/// 这里只放「给人看」的那几档，全部走本地时区；`—` 表示无有效时间。
library;

/// 两位补零。
String _two(int n) => n.toString().padLeft(2, '0');

/// `11-23 17:05`（本地时区）；无效时间返回 `—`。
String monthDayTime(DateTime at) {
  final l = at.toLocal();
  return '${_two(l.month)}-${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}';
}

/// 毫秒时间戳版；`<= 0` 视为无有效时间返回 `—`。
String monthDayTimeOfMs(int ms) =>
    ms <= 0 ? '—' : monthDayTime(DateTime.fromMillisecondsSinceEpoch(ms));

/// ISO 字符串版；解析失败返回 [fallback]（默认空串，由调用方决定显示什么）。
String monthDayTimeOfIso(String at, {String fallback = ''}) {
  final t = DateTime.tryParse(at);
  return t == null ? fallback : monthDayTime(t);
}

/// `2026-11-23 17:05`（本地时区）；用于“某次更新时间”这类需要年份的位置。
String yearMonthDayTime(DateTime at) {
  final l = at.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)} '
      '${_two(l.hour)}:${_two(l.minute)}';
}

/// `2026-11-23T17:05` 的 **UTC** 版本——只用于「批次键」这类需要跨时区稳定的
/// 标识，不用于展示。展示一律走本地时区的那几个函数。
///
/// 第十二批收口时特意保留成独立命名：`deleted_monitor.syncKeyOf` 以前自己
/// 内联了一遍补零，看起来像漏收的副本；改成本地时区会把同一批拆成两组。
String yearMonthDayTimeUtc(DateTime at) {
  final u = at.toUtc();
  return '${u.year}-${_two(u.month)}-${_two(u.day)}T${_two(u.hour)}:${_two(u.minute)}';
}

/// 秒级时间戳版；`<= 0` 视为无有效时间返回 `—`。
String yearMonthDayTimeOfSec(int sec) =>
    sec <= 0 ? '—' : yearMonthDayTime(DateTime.fromMillisecondsSinceEpoch(sec * 1000));

/// `2026-11-23T17:05:09.123`（本地时区，带毫秒）——诊断日志对齐卡顿时间点用。
String isoLikeLocalMs(DateTime at) {
  String three(int n) => n.toString().padLeft(3, '0');
  return '${at.year.toString().padLeft(4, '0')}-${_two(at.month)}-${_two(at.day)}'
      'T${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}'
      '.${three(at.millisecond)}';
}

/// `HH:mm:ss`（本地时区）——日志行前缀用。
String clockHms(DateTime at) =>
    '${_two(at.hour)}:${_two(at.minute)}:${_two(at.second)}';

/// `HH:mm:ss.SSS`（本地时区）——卡顿/暂停追踪用，毫秒用于对齐同一帧。
String clockHmsMs(DateTime at) =>
    '${clockHms(at)}.${at.millisecond.toString().padLeft(3, '0')}';

/// `11-23 17:05:09`（本地时区）——闪退记录每行的前缀。
String monthDayHms(DateTime at) =>
    '${_two(at.month)}-${_two(at.day)} ${clockHms(at)}';

/// 播放位置/时长：`mm:ss`，满 1 小时后为 `h:mm:ss`。
///
/// 第十二批收口：播放页进度行与进度条原先用一份**只到分钟、不进位**的
/// 写法（65 分钟显示成 `65:03`），而同一 App 的封面角标、长按菜单用的是
/// 进位写法（`1:05:03`）。同一部片子两个时间说法不同，属于同规则两份实现。
String formatClockMs(int ms) => formatClockSeconds(ms < 0 ? 0 : ms ~/ 1000);

/// 秒版：`mm:ss` / `h:mm:ss`（见 [formatClockMs]）。
String formatClockSeconds(int totalSeconds) {
  final t = totalSeconds < 0 ? 0 : totalSeconds;
  final h = t ~/ 3600;
  final m = (t % 3600) ~/ 60;
  final s = t % 60;
  final mm = _two(m);
  return h > 0 ? '$h:$mm:${_two(s)}' : '$mm:${_two(s)}';
}

/// [Duration] 版，供不接受毫秒的调用点使用。
String formatClock(Duration d) => formatClockMs(d.inMilliseconds);
