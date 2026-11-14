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

  static Map<String, dynamic> parse(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final j = jsonDecode(raw);
      if (j is Map) return Map<String, dynamic>.from(j);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static String encode() => jsonEncode(toJson());

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      final j = parse(raw);
      if (j.isEmpty) {
        reset();
      } else {
        applyJson(j);
      }
    } catch (_) {
      reset();
    }
  }

  static Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(prefsKey, encode());
    } catch (_) {}
  }
}
