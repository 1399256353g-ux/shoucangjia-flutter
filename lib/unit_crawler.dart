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
  final String schedule;
  final int intervalMin;
  final String note;
  final String script;

  const UnitCrawlerConfig({
    this.enabled = false,
    this.schedule = '04:10',
    this.intervalMin = 0,
    this.note = '',
    this.script = 'sync.sh',
  });

  factory UnitCrawlerConfig.fromJson(Map? raw) {
    final m = raw ?? const {};
    return UnitCrawlerConfig(
      enabled: m['enabled'] == true,
      schedule: normalizeSchedule('${m['schedule'] ?? ''}'),
      intervalMin: normalizeInterval(m['intervalMin']),
      note: clipNote('${m['note'] ?? ''}'),
      script: normalizeScriptName('${m['script'] ?? ''}'),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'schedule': schedule,
        'intervalMin': intervalMin,
        'note': note,
        'script': script,
      };

  UnitCrawlerConfig copyWith({
    bool? enabled,
    String? schedule,
    int? intervalMin,
    String? note,
    String? script,
  }) =>
      UnitCrawlerConfig(
        enabled: enabled ?? this.enabled,
        schedule: schedule ?? this.schedule,
        intervalMin: intervalMin ?? this.intervalMin,
        note: note ?? this.note,
        script: script ?? this.script,
      );

  /// 同步相关设置是否可用（J17：必须选中一个真实存在的脚本）。
  bool get syncReady => enabled && script.isNotEmpty;

  String get intervalLabel =>
      intervalMin <= 0 ? '仅按每日时间' : '每 $intervalMin 分钟 + 每日时间';
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

/// 每日执行时间：只接受 HH:MM（00:00–23:59），否则回落 04:10。
String normalizeSchedule(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
  if (m == null) return '04:10';
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return '04:10';
  return '${h.toString().padLeft(2, '0')}:${m.group(2)}';
}

/// 间隔分钟：0–1440，非法值按 0。
int normalizeInterval(dynamic raw) {
  final n = raw is num ? raw.round() : int.tryParse('${raw ?? ''}') ?? 0;
  return n.clamp(0, 1440);
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

/// 顶级单元库（rel 为空）不允许单独配置爬虫。
bool unitCrawlerConfigurable(String rel) => rel.trim().isNotEmpty;

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
