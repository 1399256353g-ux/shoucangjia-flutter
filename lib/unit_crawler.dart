// L5-D：单元库级爬虫配置（纯函数，便于单测）。
//
// 每个单元库（节点文件夹）在自己的 `crawler/` 下放脚本，并独立保存
// 启用开关 / 时间 / 间隔 / 备注 / 选中的脚本名。顶级单元库（SECRET）
// 不在此列，仍使用库根爬虫。
//
// J17：没有脚本的单元库只读展示「无爬虫脚本」，不启用同步设置。

import 'api_url.dart';
import 'json_num.dart';

import 'interval_label.dart';

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

  /// 选中的脚本是否**真实存在且可运行**（J17）。
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
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  bool get looksRunnable =>
      name.endsWith('.sh') || name.endsWith('.py') || name.endsWith('.js');
}

/// 备注：去首尾空白，最多 200 字。
String clipNote(String raw) {
  final s = raw.trim();
  return s.length <= 200 ? s : s.substring(0, 200);
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
String normalizeScriptName(String raw) {
  var s = raw.trim().replaceAll('\\', '/');
  final slash = s.lastIndexOf('/');
  if (slash >= 0) s = s.substring(slash + 1);
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
    out[rel] = e.value == true;
  }
  return out;
}
