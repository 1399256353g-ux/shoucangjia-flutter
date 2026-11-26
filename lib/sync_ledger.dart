/// 同步日志（服务端 `LIBDIR/sync_ledger.json`，保留 7 天）。
///
/// 每轮同步一条记录：时间 / 库 / 单元库 / 模式 / 成功数 / 失败数 / 删除数 /
/// 耗时 / 退出码 + 逐条结果（成功=已落地、失败=抓取失败可重试、删除=曾落地后被删）。
///
/// 解析与展示都放在纯函数里，便于单测；网络请求由页面传入 client。
library;

import 'api_url.dart';
import 'json_num.dart';
import 'rel_path.dart';
import 'time_labels.dart';
import 'http_json.dart';

/// 单条同步结果。
class SyncRunItem {
  final String id;
  final String title;
  final String author;

  /// `landed` 已落地 / `failed` 抓取失败 / `deleted` 已删除。
  final String state;
  final String why;
  final String local;
  final int at;

  const SyncRunItem({
    required this.id,
    this.title = '',
    this.author = '',
    this.state = 'failed',
    this.why = '',
    this.local = '',
    this.at = 0,
  });

  bool get failed => state == 'failed';
  String get stateLabel => switch (state) {
        'landed' => '已落地',
        'deleted' => '已删除',
        _ => '抓取失败',
      };
  String get label {
    final t = title.trim();
    if (t.isNotEmpty) return t;
    final a = author.trim();
    if (a.isNotEmpty) return '@$a · $id';
    return id.isEmpty ? '（无 id）' : id;
  }
}

/// 退出码 → 给人看的说法（**唯一出口**）。
///
/// owner 2026-11-27：「不要出现不明所以的文字」。`exit 0` / `exit 1` 是脚本
/// 视角的字段：用户既不知道 0 是好是坏，也不知道非 0 时该去查什么。同步日志
/// 与爬虫配置页的「上次运行」原先各写了一遍 `' · exit $exit'`（两份），
/// 现在两处都读这里。
///
/// - 没有退出码（本轮还在跑 / 服务端没下发）→ 空串，不占位；
/// - `0` → 「已完成」（脚本正常结束）；
/// - 非 0 → 「退出码 N（有失败）」：把结论写在前面，号码留在括号里供排查。
String syncExitLabel(int? exit) {
  if (exit == null) return '';
  return exit == 0 ? '已完成' : '退出码 $exit（有失败）';
}

/// 一轮同步。
class SyncRun {
  final String id;
  final int at;
  final int ended;
  final String lib;
  final String unit;
  final String mode; // quick / full / manual / retry
  final String script;
  final int ok;
  final int fail;
  final int deleted;
  final int total;
  final int ms;
  final int? exit;
  final bool running;
  final String error;
  final String retryOf;
  final List<SyncRunItem> items;
  final int itemsTotal;

  const SyncRun({
    required this.id,
    this.at = 0,
    this.ended = 0,
    this.lib = '',
    this.unit = '',
    this.mode = '',
    this.script = '',
    this.ok = 0,
    this.fail = 0,
    this.deleted = 0,
    this.total = 0,
    this.ms = 0,
    this.exit,
    this.running = false,
    this.error = '',
    this.retryOf = '',
    this.items = const <SyncRunItem>[],
    this.itemsTotal = 0,
  });

  /// 有失败项（或失败计数>0）才展示「重试」。
  bool get hasFail => fail > 0 || items.any((e) => e.failed);

  /// 失败项的 id（去重，按出现顺序）。
  List<String> get failedIds {
    final seen = <String>{};
    final out = <String>[];
    for (final e in items) {
      if (!e.failed) continue;
      final id = e.id.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(id);
    }
    return out;
  }

  String get modeLabel => switch (mode) {
        'quick' => '快检',
        'full' => '全量',
        'retry' => '重试',
        'manual' => '手动',
        _ => mode.isEmpty ? '同步' : mode,
      };

  String get unitLabel {
    final u = unit.trim();
    if (u.isEmpty) return lib.trim().isEmpty ? '默认库' : lib.trim();
    // 只显示单元库最后一段，避免长路径撑爆一行。
    //
    // 拆分走 [lastRelName]（`rel_path.dart` 唯一实现）：旧写法
    // `u.split('/')` 只认半角 `/`，服务端下发 Windows 风格的 `A\B` 时
    // 整条路径原样显示（实测 `SyncRun(unit: r'A\B').unitLabel == 'A\B'`），
    // 而同一件事在作者挂载面板里也是 `split('/').last`——两处都不会报错，
    // 只是那一行看起来像库名」。
    final seg = lastRelName(u);
    return seg.isEmpty ? u : seg;
  }

  /// `11-23 17:05 · 快检 · 成功 3 · 失败 1 · 2.4s`
  String get summary {
    final parts = <String>[
      syncTimeLabel(at),
      modeLabel,
      '成功 $ok',
      if (fail > 0) '失败 $fail',
      if (deleted > 0) '删除 $deleted',
      if (ms > 0) syncDurationLabel(ms),
      if (running) '运行中…',
    ];
    return parts.join(' · ');
  }
}

/// 整份同步日志。
class SyncLog {
  final List<SyncRun> runs;
  final int total;
  final int keptDays;

  const SyncLog(
      {this.runs = const <SyncRun>[], this.total = 0, this.keptDays = 7});

  static const empty = SyncLog();

  bool get isEmpty => runs.isEmpty;
}

SyncRunItem _itemOf(Map m) => SyncRunItem(
      id: '${m['id'] ?? ''}',
      title: '${m['t'] ?? ''}',
      author: '${m['a'] ?? ''}',
      state: '${m['st'] ?? 'failed'}',
      why: '${m['why'] ?? ''}',
      local: '${m['local'] ?? ''}',
      at: intOf(m['at']),
    );

SyncRun _runOf(Map m) {
  final rawItems = m['items'];
  final items = <SyncRunItem>[
    if (rawItems is List)
      for (final e in rawItems)
        if (e is Map) _itemOf(e),
  ];
  return SyncRun(
    id: '${m['id'] ?? ''}',
    at: intOf(m['at']),
    ended: intOf(m['ended']),
    lib: '${m['lib'] ?? ''}',
    unit: '${m['unit'] ?? ''}',
    mode: '${m['mode'] ?? ''}',
    script: '${m['script'] ?? ''}',
    ok: intOf(m['ok']),
    fail: intOf(m['fail']),
    deleted: intOf(m['deleted']),
    total: intOf(m['total']),
    ms: intOf(m['ms']),
    exit: m['exit'] == null ? null : intOf(m['exit']),
    running: boolOf(m['running']),
    error: '${m['error'] ?? ''}',
    retryOf: '${m['retryOf'] ?? ''}',
    items: items,
    itemsTotal: intOf(m['itemsTotal'], items.length),
  );
}

/// 解析服务端 `/api/sync/logs` 响应，坏数据不崩。
SyncLog parseSyncLog(dynamic raw) {
  if (raw is! Map) return SyncLog.empty;
  final list = raw['runs'] ?? raw['items'] ?? raw['logs'];
  final runs = <SyncRun>[
    if (list is List)
      for (final e in list)
        if (e is Map) _runOf(e),
  ];
  return SyncLog(
    runs: runs,
    total: intOf(raw['total'], runs.length),
    keptDays: intOf(raw['keptDays'], 7),
  );
}

/// `11-23 17:05`（本地时区）；无效时间返回 `—`。
String syncTimeLabel(int ms) => monthDayTimeOfMs(ms);

/// 同步耗时上限（48 小时）：超过它的 `ms` 只可能是坏数据。
const int kSyncMaxDurationMs = 48 * 60 * 60 * 1000;

/// `820ms` / `2.4s` / `1m 05s` / `1h 02m`。
///
/// **先归一到秒再拆分**：此前先 `~/60` 取整分、再对余数 `round()`，
/// 119600ms（119.6s）得出 `1m 60s`。和第十二批修掉的「65:03」是同一个缺口
/// （先截断再拆分），只是单位不同。秒级分支（<60s）保留原行为：<10s 一位
/// 小数，10s 以上向下取整——59.9s 显示 `59s`，不写成一个假的 `60s`。
String syncDurationLabel(int ms) {
  if (ms <= 0) return '—';
  // 48 小时以上的耗时只有一个来源：坏数据。int 上限会被算成
  // `153722867280912m 56s`（实测），同步日志那一行直接把页面撑出横向滚动。
  // 与「耗时未知」同一条出口，不编造一个看起来合理的数字。
  if (ms > kSyncMaxDurationMs) return '—';
  if (ms < 1000) return '${ms}ms';
  // 秒级展示按**原始毫秒**判断（59.9s 就是 59.9s，不因为四舍五入成 60
  // 就跳进分钟分支）；进入分钟分支后才四舍五入到秒，余数不会再出现 60。
  if (ms < 60000) {
    // 档位必须按**截断后的显示值**判，不能按原始秒数 `< 10` 判。
    //
    // 旧写法 `sec < 10 ? toStringAsFixed(1) : '${ms ~/ 1000}s'` 有一个跨档窗口：
    // 9999ms 的 `sec` 是 9.999 < 10，走一位小数分支，而 `toStringAsFixed(1)`
    // **四舍五入**给出 **`10.0s`**（实测）；10000ms 走整数分支给出 **`10s`**。
    // 同一个「10 秒」在同步日志里有两个写法，且 `10.0s` 那个本来是 9.999s，
    // 是被说大成了整 10 秒——与第十二批修的 `1024.0 KB` 同一条口径。
    //
    // 截断到 0.1s 后再看档位：`9999 → 99`（9.9s）、`10000 → 100`（10s），
    // 读数不跨档，也不会出现 `60s`（59999 → 59s）。
    final tenths = ms ~/ 100;
    if (tenths < 100) return '${tenths ~/ 10}.${tenths % 10}s';
    return '${ms ~/ 1000}s';
  }
  final totalSec = (ms / 1000).round();
  // 分钟档**不是末档**：48 小时上限内的同步可能跨小时，而旧实现到分钟就结束，
  // `3599999`（59:59.999）四舍五入成 3600 秒后算出 **`60m 00s`**（实测），
  // `3600000` 也是 `60m 00s`——一个在分钟档里不可能存在的读数，
  // 与第十二批修的 `65:03`、第四十八批的 `1024.0 KB` 同一条口径（单位用尽
  // 就换更大的单位）。超过 1 小时改用 `h:mm` 档，`119600` 仍是 `2m 00s`。
  if (totalSec >= 3600) {
    final h = totalSec ~/ 3600;
    final m = (totalSec % 3600) ~/ 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

Uri syncLogsUri(String base, {String lib = '', int limit = 20}) {
  final l = lib.trim();
  return Uri.parse(joinApiUrl(base, '/api/sync/logs', query: {
    'limit': '$limit',
    if (l.isNotEmpty) 'lib': l,
  }));
}

/// 同步日志保留天数设置地址（`GET` 读 / `POST {keepDays}` 写）。
///
/// owner 2026-11-25：天数可自己设置。服务端只改 `sync_log_settings.json`，
/// 清理时也只裁 `sync_ledger.json`——**不碰 `_deleted.log`**（删除检测记录
/// 是另一个文件，由 dy_prune.js 维护）。
Uri syncLogSettingsUri(String base) =>
    Uri.parse(joinApiUrl(base, '/api/sync/logs/settings'));

/// 解析保留天数响应；坏数据回落 [fallback]。
int parseKeepDays(dynamic raw, {int fallback = 7}) {
  if (raw is! Map) return fallback;
  final n = raw['keepDays'];
  final v = intOf(n, fallback);
  return v.clamp(1, 90);
}

/// 重试地址。base 为空时得到相对地址（不抛异常，由请求层报连接失败）。
Uri syncRetryUri(String base) => Uri.parse(joinApiUrl(base, '/api/sync/retry'));

/// `POST /api/sync/retry` 的请求体：{runId, ids}。
Map<String, dynamic> syncRetryBody(
    {String runId = '', required List<String> ids}) {
  final clean = <String>[];
  final seen = <String>{};
  for (final id in ids) {
    final t = id.trim();
    if (t.isEmpty || !seen.add(t)) continue;
    clean.add(t);
  }
  return {
    if (runId.trim().isNotEmpty) 'runId': runId.trim(),
    'ids': clean,
  };
}

/// 重试响应 → 展示文案；失败原因走 [apiFailureText]（读接口口径）。
///
/// 此前这里自己拼了一遍失败原因，与本文件/其它页面的唯一出口有两处分叉：
///  - `'${body['error']}'`：`error` 是非字符串（`{code: 500}` / `500`）时把对象
///    贴到界面上（0.9.227 已在 13 处修掉同一写法，这里是漏网的第 14 处）；
///  - `'HTTP $status'`：同一个 400 在别的页面显示「请求格式不对」，这里显示
///    「HTTP 400」——状态码文案必须只有一个说法。
/// 成功判定仍要求 `ok == true`（重试是写接口，缺字段不能当成功）。
String syncRetryResultLabel(int status, dynamic body) {
  if (serviceSaidOk(body)) {
    final n = intOf(body['retried']);
    return '已开始重试 $n 条（任务 ${body['retryRunId'] ?? ''}）';
  }
  final err = apiFailureText(status, body, requireOk: false) ?? '';
  return '重试失败：$err';
}

/// 把响应体按 UTF-8 解码成 JSON。
///
/// 保留这个名字只因为它是面板的既有入口；字符集规则已统一到
/// `http_json.dart`（始终 UTF-8，不看 Content-Type），这里只做转发。
dynamic decodeSyncJson(List<int> bytes) => jsonOfBytes(bytes);
