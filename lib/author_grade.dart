import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 作者等级（D–S）：按播放量、小水滴、作品数加权算分，再按逐级门槛定级。
/// 纯逻辑版本，便于单元测试；配置持久化到 SharedPreferences。
class AuthorGrade {
  static const String prefsKey = 'author_grades_v1';

  /// 从低到高；[grades].length - 1 个门槛。
  static const List<String> grades = <String>['D', 'C', 'B', 'A', 'S'];

  /// 等级底色（D 灰 → S 金）。
  static const List<int> colors = <int>[
    0xFF6B7280,
    0xFF16A34A,
    0xFF2563EB,
    0xFF7C3AED,
    0xFFF59E0B,
  ];

  /// 默认权重与门槛（分数 = 播放×1 + 水滴×10 + 作品×2）。
  static const int defaultPlayWeight = 1;
  static const int defaultDropWeight = 10;
  static const int defaultWorkWeight = 2;
  static const List<int> defaultThresholds = <int>[100, 500, 2000, 8000];

  static int playWeight = defaultPlayWeight;
  static int dropWeight = defaultDropWeight;
  static int workWeight = defaultWorkWeight;
  static List<int> thresholds = List<int>.from(defaultThresholds);

  static void reset() {
    playWeight = defaultPlayWeight;
    dropWeight = defaultDropWeight;
    workWeight = defaultWorkWeight;
    thresholds = List<int>.from(defaultThresholds);
  }

  /// 加权分数；负值按 0 处理。
  static int score({int plays = 0, int drops = 0, int works = 0}) {
    int nz(int v) => v < 0 ? 0 : v;
    final s = nz(plays) * playWeight +
        nz(drops) * dropWeight +
        nz(works) * workWeight;
    return s < 0 ? 0 : s;
  }

  /// 分数对应等级下标（0=D … 4=S）。
  static int indexForScore(int score, {List<int>? thresholdsOverride}) {
    final t = thresholdsOverride ?? thresholds;
    var idx = 0;
    for (var i = 0; i < t.length && i < grades.length - 1; i++) {
      if (score >= t[i]) {
        idx = i + 1;
      } else {
        break;
      }
    }
    return idx;
  }

  static String gradeFor({int plays = 0, int drops = 0, int works = 0}) =>
      grades[indexForScore(score(plays: plays, drops: drops, works: works))];

  /// 作者统计 → 等级：全 App 唯一入口（作者总览、排行榜、推荐、搜索、作者主页）。
  /// [stats] 为 `/api/author_stats.json` 里的单作者条目（含 `p`/`dr`），
  /// 缺失或不是 Map 时按 0 统计，只保留作品数权重。
  static String fromStats(dynamic stats, {int works = 0}) {
    final m = stats is Map ? stats : const {};
    int n(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);
    return gradeFor(plays: n(m['p']), drops: n(m['dr']), works: works);
  }

  static int colorForGrade(String grade) {
    final i = grades.indexOf(grade.toUpperCase());
    return colors[i < 0 ? 0 : i];
  }

  static int colorFor({int plays = 0, int drops = 0, int works = 0}) =>
      colorForGrade(gradeFor(plays: plays, drops: drops, works: works));

  /// 解析配置；非法字段逐项回落默认值，门槛自动去负并补齐/截断。
  static void applyJson(Map<String, dynamic> j) {
    reset();
    int? readInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    playWeight = (readInt(j['play']) ?? defaultPlayWeight).clamp(0, 1000);
    dropWeight = (readInt(j['drop']) ?? defaultDropWeight).clamp(0, 10000);
    workWeight = (readInt(j['work']) ?? defaultWorkWeight).clamp(0, 1000);

    final raw = j['t'];
    if (raw is List && raw.length >= grades.length - 1) {
      final list = <int>[];
      var ok = true;
      for (var i = 0; i < grades.length - 1; i++) {
        final v = readInt(raw[i]);
        if (v == null || v < 0) {
          ok = false;
          break;
        }
        list.add(v);
      }
      // 必须严格递增，否则视为坏数据回落默认，避免等级错乱。
      if (ok) {
        for (var i = 1; i < list.length; i++) {
          if (list[i] <= list[i - 1]) ok = false;
        }
      }
      if (ok) thresholds = list;
    }
  }

  static Map<String, dynamic> toJson() => <String, dynamic>{
        'play': playWeight,
        'drop': dropWeight,
        'work': workWeight,
        't': List<int>.from(thresholds),
      };

  /// P6：服务端下发是否已生效。true 时本机不再读写 SharedPreferences，
  /// 也不再显示任何修改入口（配置唯一来源＝服务端）。
  static bool remoteManaged = false;

  /// P6：服务端下发的时间戳（秒），仅用于显示「已同步」。
  static int remoteAt = 0;

  /// P6：把服务端 `GET /api/author-grade.json` 的响应套用到本地。
  ///
  /// 接受两种形状：`{ok,grade:{...}}` 与裸 `{play,drop,work,t}`。
  /// 服务端数据非法时不改动现有配置，返回 false。
  static bool applyRemote(Map<String, dynamic>? resp) {
    if (resp == null) return false;
    final raw = resp['grade'];
    final src = (raw is Map) ? Map<String, dynamic>.from(raw) : resp;
    final play = _intOf(src['play']);
    final drop = _intOf(src['drop']);
    final work = _intOf(src['work']);
    final t = _strictThresholds(src['t']);
    if (play == null || drop == null || work == null || t == null) {
      return false;
    }
    playWeight = play;
    dropWeight = drop;
    workWeight = work;
    thresholds = t;
    remoteManaged = true;
    remoteAt = (src['at'] is num ? (src['at'] as num).toInt() : 0);
    return true;
  }

  static int? _intOf(Object? v) {
    if (v is num) {
      final n = v.toInt();
      return n < 0 ? null : n;
    }
    if (v is String) {
      final n = int.tryParse(v.trim());
      return (n == null || n < 0) ? null : n;
    }
    return null;
  }

  /// 门槛必须恰好 [grades].length-1 个且严格递增，否则整组作废。
  static List<int>? _strictThresholds(Object? raw) {
    if (raw is! List || raw.length != grades.length - 1) return null;
    final out = <int>[];
    for (final v in raw) {
      final n = _intOf(v);
      if (n == null) return null;
      out.add(n);
    }
    for (var i = 1; i < out.length; i++) {
      if (out[i] <= out[i - 1]) return null;
    }
    return out;
  }

  static Map<String, dynamic> parse(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final j = jsonDecode(raw);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static String encode() => jsonEncode(toJson());

  /// P6：配置来源已改为服务端（`/api/author-grade.json`）。
  ///
  /// 本机只保留一份**只读缓存**，用于首屏立即拿到上次同步值；
  /// 真正生效的配置由 [applyRemote] 套用，本地不再写回服务端。
  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      final j = parse(raw);
      if (j.isEmpty) {
        reset();
      } else {
        reset();
        // 只读缓存：解析成功也只当作「上次已知值」，不改 remoteManaged。
        final play = _intOf(j['play']);
        final drop = _intOf(j['drop']);
        final work = _intOf(j['work']);
        final t = _strictThresholds(j['t']);
        if (play != null) playWeight = play;
        if (drop != null) dropWeight = drop;
        if (work != null) workWeight = work;
        if (t != null) thresholds = t;
      }
    } catch (_) {
      reset();
    }
  }

  /// P6：只写本机只读缓存，供下次启动首帧使用；服务端配置由 PUT 接口写。
  static Future<void> cacheLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(prefsKey, encode());
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(prefsKey, encode());
    } catch (_) {}
  }
}
