// L5-D：单元库级爬虫配置（纯函数，便于单测）。
//
// 每个单元库（节点文件夹）在自己的 `crawler/` 下放脚本，并独立保存
// 启用开关 / 时间 / 间隔 / 备注 / 选中的脚本名。顶级单元库（SECRET）
// 不在此列，仍使用库根爬虫。
//
// 没有脚本的单元库只读展示「该单元库没有爬虫脚本」，不启用同步设置。

import 'api_url.dart';
import 'json_num.dart';
import 'media_path.dart' show stripMediaSuffix;
import 'rel_path.dart' show lastRelName;
import 'text_clip.dart';

import 'interval_label.dart';
import 'stable_order.dart';

/// 单元库爬虫配置。
class UnitCrawlerConfig {
  final bool enabled;

  /// 快检：只扫新增/删除，开销小；全量才完整抓取。
  final bool quickCheck;
  final int quickMin;
  final int fullMin;
  final int cooldownMin;
  final String note;
  final String script;

  const UnitCrawlerConfig({
    this.enabled = false,
    this.quickCheck = true,
    this.quickMin = 5,
    this.fullMin = 60,
    this.cooldownMin = 15,
    this.note = '',
    this.script = 'sync.sh',
  });

  factory UnitCrawlerConfig.fromJson(Map? raw) {
    final m = raw ?? const {};
    return UnitCrawlerConfig(
      enabled: boolOf(m['enabled']),
      quickCheck: boolOf(m['quickCheck'], true),
      quickMin: normalizeQuickMin(m['quickMin']),
      // 旧版服务端/旧版配置只有 `intervalMin`（本类的 toJson 仍在写它，
      // 供旧服务端读）。此前这里是 `m['intervalMin'] != null ? 60 : 60`
      // ——三元两支相同，等于把旧值整个丢掉：老配置里的 30 分钟全量
      // 会被读成默认 60 分钟，界面上「当前：…」显示的数字与实际调度不符。
      // 回退链写在 [fullMinFrom] 一处：新字段优先，旧字段次之，最后默认值。
      fullMin: fullMinFrom(m),
      cooldownMin: normalizeCooldown(m['cooldownMin']),
      note: clipNote('${m['note'] ?? ''}'),
      script: normalizeScriptName('${m['script'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'quickCheck': quickCheck,
        'quickMin': quickMin,
        'fullMin': fullMin,
        'cooldownMin': cooldownMin,
        // 兼容旧服务端字段
        'intervalMin': fullMin,
        'note': note,
        'script': script,
      };

  UnitCrawlerConfig copyWith({
    bool? enabled,
    bool? quickCheck,
    int? quickMin,
    int? fullMin,
    int? cooldownMin,
    String? note,
    String? script,
  }) =>
      UnitCrawlerConfig(
        enabled: enabled ?? this.enabled,
        quickCheck: quickCheck ?? this.quickCheck,
        quickMin: quickMin ?? this.quickMin,
        fullMin: fullMin ?? this.fullMin,
        cooldownMin: cooldownMin ?? this.cooldownMin,
        note: note ?? this.note,
        script: script ?? this.script,
      );

  /// 选中的脚本是否**真实存在且可运行**。
  ///
  /// 这条规则原先有两个实现：这里的 `syncReady` 只判 `script.isNotEmpty`，
  /// 页面的真实路径判「名字在脚本列表里且可运行」。于是「配置里写着 sync.sh、
  /// 但目录里没有这个文件」在配置对象上算就绪、在界面上算不可用——同一个问题
  /// 两个答案，而只有后者是产品行为。现在只留这一处。
  ///
  /// **不含 `enabled`**：开关本身要靠它决定能不能打开，把 enabled 掺进来会让
  /// 关掉同步之后再也打不开。
  bool scriptReadyIn(Iterable<UnitCrawlerScript> scripts) {
    final name = script.trim();
    if (name.isEmpty) return false;
    return scripts.any((s) => s.name == name && s.looksRunnable);
  }

  /// 同步频率汇总文案（页面底部「当前：…」那一行）。
  ///
  /// 页面此前自己拼了一遍同样的三元表达式；「每 N 小时 / 每 N 分钟」
  /// 现在统一由 [everyMinutesLabel] 给出，这里是唯一汇总点。
  String get intervalLabel =>
      '快检${quickCheck ? everyMinutesLabel(quickMin) : '关闭'}'
      ' · 全量${everyMinutesLabel(fullMin)}'
      ' · 冷却 $cooldownMin 分钟';
}

/// 单元库 `crawler/` 下的脚本文件。
class UnitCrawlerScript {
  final String name;
  final int size;
  final int mtimeMs;

  const UnitCrawlerScript({
    required this.name,
    this.size = 0,
    this.mtimeMs = 0,
  });

  static List<UnitCrawlerScript> listFrom(dynamic raw) {
    final out = <UnitCrawlerScript>[];
    if (raw is! List) return out;
    for (final e in raw) {
      if (e is! Map) continue;
      final name = '${e['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      out.add(UnitCrawlerScript(
        name: name,
        size: intOf(e['size']),
        mtimeMs: intOf(e['mtime']),
      ));
    }
    // 同名脚本（同一个 `crawler/` 目录被重复挂载、或服务端把同一个文件
    // 用两种相对路径各报一次）之间没有次序依据；`List.sort` 不稳定，同一次
    // 拉取刷新两遍就可能换位置，下拉选中的脚本也跟着跳。这里保持服务端
    // 下发顺序（稳定排序），与 `unit_library` / `category_tree` 同一条规则。
    stableSort(out, (a, b) => a.name.compareTo(b.name));
    return out;
  }

  bool get looksRunnable => _kRunnableScriptExts
      .any((e) => lastRelName(stripMediaSuffix(name)).toLowerCase().endsWith(e));
}

/// 可运行的脚本扩展名（`unit_crawler_page` 的下拉列表与卡片按钮都靠它）。
const List<String> _kRunnableScriptExts = <String>['.sh', '.py', '.js'];

/// 备注：去首尾空白，最多 200 字。
///
/// 用 [clipToUnits] 而不是 `substring(0, 200)`：备注里可能有 emoji，
/// 硬切会切在代理对中间，存到服务端后回到界面上是一个替换方块。
String clipNote(String raw) {
  final s = raw.trim();
  return clipToUnits(s, 200);
}

const List<int> kQuickMinOptions = <int>[1, 5, 10, 15, 30];
const List<int> kFullMinOptions = <int>[30, 60, 180, 720];
const List<int> kCooldownOptions = <int>[5, 15, 30, 60];

int normalizeQuickMin(dynamic raw) {
  final v = intOf(raw, 5);
  return kQuickMinOptions.contains(v) ? v : 5;
}

int normalizeFullMin(dynamic raw) {
  final v = intOf(raw, 60);
  return kFullMinOptions.contains(v) ? v : 60;
}

/// 全量间隔的取值来源：`fullMin` 优先，缺失时读旧字段 `intervalMin`。
///
/// 单独留存这个判定是为了让「旧字段到底还算不算数」只有一个答案；
/// 读取与测试都引用它，不在别处再写一遍 `??` 链。
int fullMinFrom(Map m) => normalizeFullMin(m['fullMin'] ?? m['intervalMin']);

int normalizeCooldown(dynamic raw) {
  final v = intOf(raw, 15);
  return kCooldownOptions.contains(v) ? v : 15;
}

/// 脚本名：只允许文件名，禁止目录穿越与隐藏文件。
///
/// 先剥 `?query` / `#fragment` 再取末段：服务端可能把脚本名字段写成地址
/// 形式（`crawler/run.py?t=2`）。旧写法先取最后一段得到 `run.py?t=2`，
/// 白名单不认 `?` → 回落到 `sync.sh`（一个**不存在**的默认名），于是
/// 「运行」按钮打到一个不存在的脚本上。实测
/// `normalizeScriptName('run.py?x=1')` 返回 `'sync.sh'`。
String normalizeScriptName(String raw) {
  var s = stripMediaSuffix(raw);
  // 以分隔符结尾的是**目录**，不是脚本文件。必须先拦：`lastRelName` 会
  // 把空段吃掉（`relSegments('crawler/') == ['crawler']`），`crawler/` 于是
  // 被当成一个叫 `crawler` 的脚本——现在只是不可运行，但名字已不对。
  if (s.endsWith('/') || s.endsWith('\\')) return 'sync.sh';
  // 取末段走 `rel_path.lastRelName`（`\` 与 `/` 等价，唯一实现）。
  // 旧写法先 `replaceAll('\\', '/')` 再 `lastIndexOf('/')`，是同一规则的
  // 第二份，且与 `looksRunnable` 的可运行判定脱节（后者根本没剥后缀）。
  s = lastRelName(s);
  if (s.isEmpty || s == '.' || s == '..' || s.startsWith('.')) {
    return 'sync.sh';
  }
  if (!RegExp(r'^[A-Za-z0-9._-]{1,64}$').hasMatch(s)) return 'sync.sh';
  return s;
}

/// 单元库接口路径（GET/POST 配置、POST 运行）。
String unitCrawlerUrl(String base, String path,
        {required String unitId, required String rel}) =>
    joinApiUrl(base, path, query: {'unit': unitId, 'rel': rel});

/// 单元库爬虫脚本目录（**绝对路径**）；没有绝对路径时返回空串。
///
/// 0.9.322：此前页面的 `_scriptDir()` 在服务端没给绝对路径时回落到
/// `unit.rel`（相对路径），于是同一页上「库根：/vol1/.../A」与
/// 「脚本目录：A/crawler」两行是两种坐标——用户拿相对路径在磁盘上找不到
/// 那个目录，还以为是脚本放错了位置。相对路径不猜、不显示：调用方拿到空串
/// 就什么都不画，并说明「服务端未返回绝对路径」。
String crawlerScriptDir(String absPath) {
  final p = absPath.trim();
  if (p.isEmpty) return '';
  return p.endsWith('/') || p.endsWith('\\') ? '${p}crawler' : '$p/crawler';
}

/// 运行按钮文案。
String unitCrawlerRunLabel(bool running) => running ? '运行中…' : '运行单元库同步';

/// H：从 `/api/nodes` 响应里取「单元库 rel → 是否有可运行爬虫脚本」。
/// 缺字段时返回空表（调用方按「无脚本」置灰，避免误开同步）。
Map<String, bool> unitCrawlerFlags(dynamic json) {
  final out = <String, bool>{};
  if (json is! Map) return out;
  final raw = json['crawler'];
  if (raw is! Map) return out;
  for (final e in raw.entries) {
    final rel = '${e.key}'.trim();
    if (rel.isEmpty) continue;
    // 走 json_num：服务端同一字段可能发 `true` / `1` / `"true"`。
    // 此前写的是 `e.value == true`，`1` 与 `"true"` 都算未启用——
    // 设置页说已启用、单元库页置灰不能点，同一条配置两种说法。
    out[rel] = boolOf(e.value);
  }
  return out;
}
