// L5-D：单元库级爬虫配置（纯函数，便于单测）。
//
// 每个单元库（节点文件夹）在自己的 `crawler/` 下放脚本，并独立保存
// 启用开关 / 时间 / 间隔 / 备注 / 选中的脚本名。顶级单元库（SECRET）
// 不在此列，仍使用库根爬虫。
//
// J17：没有脚本的单元库只读展示「无爬虫脚本」，不启用同步设置。

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
      enabled: m['enabled'] == true,
      quickCheck: m['quickCheck'] != false,
      quickMin: normalizeQuickMin(m['quickMin'] ??
          (m['intervalMin'] != null ? 5 : 5)),
      fullMin: normalizeFullMin(
          m['fullMin'] ?? (m['intervalMin'] != null ? 60 : 60)),
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

  /// 同步相关设置是否可用（J17：必须选中一个真实存在的脚本）。
  bool get syncReady => enabled && script.isNotEmpty;

  String get intervalLabel =>
      '快检${quickCheck ? '每 $quickMin 分钟' : '关闭'} · 全量每 $fullMin 分钟';
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
        size: (e['size'] as num?)?.toInt() ?? 0,
        mtimeMs: (e['mtime'] as num?)?.toInt() ?? 0,
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
  final v = (raw is num) ? raw.toInt() : (int.tryParse('${raw ?? ''}') ?? 5);
  return kQuickMinOptions.contains(v) ? v : 5;
}

int normalizeFullMin(dynamic raw) {
  final v = (raw is num) ? raw.toInt() : (int.tryParse('${raw ?? ''}') ?? 60);
  return kFullMinOptions.contains(v) ? v : 60;
}

int normalizeCooldown(dynamic raw) {
  final v = (raw is num) ? raw.toInt() : (int.tryParse('${raw ?? ''}') ?? 15);
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
    {required String unitId, required String rel}) {
  final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  final q = 'unit=${Uri.encodeQueryComponent(unitId)}'
      '&rel=${Uri.encodeQueryComponent(rel)}';
  final sep = path.contains('?') ? '&' : '?';
  return '$b$path$sep$q';
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
    out[rel] = e.value == true;
  }
  return out;
}
