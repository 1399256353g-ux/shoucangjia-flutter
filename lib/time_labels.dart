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

/// 毫秒时间戳能否构造出 `DateTime`：`DateTime` 只接受
/// ±8640000000000000 毫秒（约 ±273790 年），越界构造**抛 RangeError**。
///
/// 服务端时间字段是普通 JSON 数字，一个写坏的值（`1e30`）经 `intOf` 会
/// 落到 int 上限 9223372036854775807，`DateTime.fromMillisecondsSinceEpoch`
/// 当场抛异常——同步日志页/删除监测页会在 build 阶段崩成灰屏。
const int kMaxEpochMs = 8640000000000000;

bool isValidEpochMs(int ms) =>
    ms >= -kMaxEpochMs && ms <= kMaxEpochMs;

/// 安全的毫秒→DateTime；越界返回 null（不抛）。
DateTime? dateTimeOfMs(int ms) =>
    isValidEpochMs(ms) ? DateTime.fromMillisecondsSinceEpoch(ms) : null;

/// 年月日 → 当天 0 点毫秒；**月/日越界或年份不可表示时返回 null**。
///
/// `DateTime(2026, 13, 45)` 不报错，它会**静默滚动**成 2027-02-14；而
/// `DateTime(275761, 1, 1)` 直接抛 `ArgumentError`。这两种行为都不能留在
/// 排序/展示路径上：滚动的结果是一个看起来合法、其实错了一个多月的日期；
/// 抛异常则发生在 `List.sort` 的比较函数里——整张作品列表在 build 阶段崩掉。
///
/// 所以先按「人类可表示范围」挡一道，再用回读校验拦住 2 月 31 日这类
/// 会被 DateTime 滚到下个月的日期。非法一律返回 null，由调用方当作
/// 「没有时间」处理（排序保持原序、显示 `—`）。
int? msFromDateParts(int year, int month, int day) {
  if (year < 1900 || year > 3000) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  final dt = DateTime(year, month, day);
  if (dt.year != year || dt.month != month || dt.day != day) return null;
  return dt.millisecondsSinceEpoch;
}

/// 安全的秒→DateTime；先判范围再乘 1000——`sec * 1000` 在 int64 上会
/// **静默回绕**，1e19 秒会变成 1969 年而不是报错。
DateTime? dateTimeOfSec(int sec) {
  if (sec > kMaxEpochMs ~/ 1000 || sec < -(kMaxEpochMs ~/ 1000)) return null;
  return dateTimeOfMs(sec * 1000);
}

/// 秒级时间戳乘 1000 的**安全**版本：越界返回 0 而不是回绕成负数。
///
/// 爬虫索引里的 `srcAt` 偶尔是秒，个别条目会被写成离谱的大数；
/// `sec * 1000` 在 int64 上静默回绕，得到一个**负**的毫秒值。负值在
/// 排序里会沉到最后（看起来像「最新」），显示时又变成 1969 年。
int msFromEpochSeconds(int sec) {
  if (sec <= 0) return 0;
  const maxSec = kMaxEpochMs ~/ 1000;
  if (sec > maxSec) return 0;
  return sec * 1000;
}

/// `11-23 17:05`（本地时区）；无效时间返回 `—`。
String monthDayTime(DateTime at) {
  final l = at.toLocal();
  return '${_two(l.month)}-${_two(l.day)} ${_two(l.hour)}:${_two(l.minute)}';
}

/// 毫秒时间戳版；`<= 0` 或超出可表示范围视为无有效时间返回 `—`。
String monthDayTimeOfMs(int ms) {
  if (ms <= 0) return '—';
  final t = dateTimeOfMs(ms);
  return t == null ? '—' : monthDayTime(t);
}

/// ISO 字符串 → DateTime；**超出人类可表示年份范围的返回 null**。
///
/// `DateTime.tryParse` 只在「年份位数超过 6 位」时返回 null，6 位年份会被
/// 如实解析并**静默回绕**：实测 `999999-01-01T00:00:00Z` 得到
/// `-169110-11-25`（毫秒值 -5.4e15，仍在 `kMaxEpochMs` 之内，所以
/// 只查毫秒范围拦不住）。服务端一个写坏的时间字段就会让日志行显示成
/// 「公元前十一万年」，排序也跟着乱。
///
/// 与 [msFromDateParts] 用同一个年份口径（1900–3000）：媒体/日志时间
/// 都落在这个区间，区间外一律当作「没有时间」。
DateTime? dateTimeOfIso(String at) {
  final t = DateTime.tryParse(at);
  if (t == null) return null;
  if (t.year < 1900 || t.year > 3000) return null;
  return t;
}

/// ISO 字符串 → 毫秒时间戳；解析失败或年份越界返回 0。
int msFromIso(String at) =>
    dateTimeOfIso(at)?.millisecondsSinceEpoch ?? 0;

/// ISO 字符串版；解析失败返回 [fallback]（默认空串，由调用方决定显示什么）。
String monthDayTimeOfIso(String at, {String fallback = ''}) {
  final t = dateTimeOfIso(at);
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

/// 秒级时间戳版；`<= 0` 或超出可表示范围视为无有效时间返回 `—`。
String yearMonthDayTimeOfSec(int sec) {
  if (sec <= 0) return '—';
  final t = dateTimeOfSec(sec);
  return t == null ? '—' : yearMonthDayTime(t);
}

/// `2026-11-23`（本地时区，只要日期）；无效返回空串。
String yearMonthDayOfSec(int sec) {
  if (sec <= 0) return '';
  final t = dateTimeOfSec(sec);
  if (t == null) return '';
  final l = t.toLocal();
  return '${l.year}-${_two(l.month)}-${_two(l.day)}';
}

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
