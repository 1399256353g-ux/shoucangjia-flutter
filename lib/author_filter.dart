/// J10：作者筛选工具的纯逻辑。
///
/// 维度：
///   - 基础库多选 / 大库多选（同一维度内取并集，任一命中即可）
///   - 等级多选（D/C/B/A/S）
///   - 作品类型多选（视频/图片/合集/图文）
/// 不同维度之间叠加（AND）；某个维度空集合表示不限制。
/// 另提供 `/api/lib/<id>/index.json` 的 `kinds` 解析与结果计数。
library;

import 'package:flutter/foundation.dart';
import 'http_json.dart';
import 'json_num.dart';

import 'work_forms.dart';
import 'stable_order.dart';

class AuthorBigNode {
  final String id;
  final String name;
  const AuthorBigNode({required this.id, required this.name});
}

class AuthorLibNode {
  final String id;
  final String name;
  final String bigId;
  const AuthorLibNode({
    required this.id,
    required this.name,
    this.bigId = '',
  });
}

/// 作者筛选状态；全部为空即“未筛选”。
class AuthorFilterState {
  /// J10 旧维度：基础库/大库（保留以兼容历史数据与测试）。
  final Set<String> basics;
  final Set<String> bigs;
  /// L5 新维度：单元库（作者总览/推荐/排行统一按此筛选）。
  final Set<String> units;

  /// P3：顶级节点（＝每个连接的媒体库根）维度。
  ///
  /// 与 [units] 是包含关系：选中某个顶级节点即收敛到它的整棵子树，
  /// 两条维度同时存在时按「单元库维度内取并集」的既有语义合并——
  /// 顶级节点命中同样算库维度命中，不会与单元库筛选互相覆盖。
  final Set<String> tops;
  final Set<String> grades;
  final Set<String> types;

  AuthorFilterState({
    Set<String>? basics,
    Set<String>? bigs,
    Set<String>? units,
    Set<String>? tops,
    Set<String>? grades,
    Set<String>? types,
  })  : basics = {...?basics},
        bigs = {...?bigs},
        units = {...?units},
        tops = {...?tops},
        grades = {...?grades},
        types = {...?types};

  bool get isActive =>
      basics.isNotEmpty ||
      bigs.isNotEmpty ||
      units.isNotEmpty ||
      tops.isNotEmpty ||
      grades.isNotEmpty ||
      types.isNotEmpty;

  int get activeCount =>
      basics.length +
      bigs.length +
      units.length +
      tops.length +
      grades.length +
      types.length;

  AuthorFilterState copy() => AuthorFilterState(
        basics: basics,
        bigs: bigs,
        units: units,
        tops: tops,
        grades: grades,
        types: types,
      );

  void clear() {
    basics.clear();
    bigs.clear();
    units.clear();
    tops.clear();
    grades.clear();
    types.clear();
  }

  void toggleBasic(String id) {
    if (id.isEmpty) return;
    if (!basics.remove(id)) basics.add(id);
  }

  void toggleBig(String id) {
    if (id.isEmpty) return;
    if (!bigs.remove(id)) bigs.add(id);
  }

  void toggleUnit(String id) {
    if (id.isEmpty) return;
    if (!units.remove(id)) units.add(id);
  }

  void toggleTop(String id) {
    if (id.isEmpty) return;
    if (!tops.remove(id)) tops.add(id);
  }

  void toggleGrade(String g) {
    if (g.isEmpty) return;
    if (!grades.remove(g)) grades.add(g);
  }

  void toggleType(String t) {
    if (t.isEmpty) return;
    if (!types.remove(t)) types.add(t);
  }

  /// 单条作者是否命中当前筛选。
  /// [basicId]/[bigId] 为空表示无法归类：只在未选库维度时通过。
  bool matches({
    required String basicId,
    required String bigId,
    String unitId = '',
    String topId = '',
    required String grade,
    required Set<String> workTypes,
  }) {
    if (basics.isNotEmpty ||
        bigs.isNotEmpty ||
        units.isNotEmpty ||
        tops.isNotEmpty) {
      final byBasic = basicId.isNotEmpty && basics.contains(basicId);
      final byBig = bigId.isNotEmpty && bigs.contains(bigId);
      final byUnit = unitId.isNotEmpty && units.contains(unitId);
      // P3：顶级节点是单元库的祖先，选中它即收敛整棵子树。
      final byTop = topId.isNotEmpty && tops.contains(topId);
      // 库维度内取并集：基础库/大库/单元库/顶级节点任一命中即可。
      if (!byBasic && !byBig && !byUnit && !byTop) return false;
    }
    if (grades.isNotEmpty) {
      if (grade.isEmpty || !grades.contains(grade)) return false;
    }
    if (types.isNotEmpty) {
      if (workTypes.isEmpty) return false;
      if (!workTypes.any(types.contains)) return false;
    }
    return true;
  }

  /// 生成一行简短摘要，例如「基础库 2 · 大库 1 · 等级 A/S · 视频/图文」。
  ///
  /// 四个库维度（top/unit/basic/big）此前各自写了一遍「取名字 → 排序 → 拼接」
  /// ——同一段 5 行代码四份拷贝，改一处就分叉。这里只留一条：[_namesPart]。
  String summary({
    Map<String, String> basicNames = const {},
    Map<String, String> bigNames = const {},
    Map<String, String> unitNames = const {},
    Map<String, String> topNames = const {},
  }) {
    final parts = <String>[
      if (tops.isNotEmpty) _namesPart('顶级节点', tops, topNames),
      if (units.isNotEmpty) _namesPart('单元库', units, unitNames),
      if (basics.isNotEmpty) _namesPart('基础库', basics, basicNames),
      if (bigs.isNotEmpty) _namesPart('媒体库', bigs, bigNames),
      if (grades.isNotEmpty)
        '等级 ${['S', 'A', 'B', 'C', 'D'].where(grades.contains).join('/')}',
      if (types.isNotEmpty)
        workFilterOrder.where(types.contains).map(workFilterLabel).join('/'),
    ];
    return parts.isEmpty ? '未筛选' : parts.join(' · ');
  }
}

/// 单个库维度的摘要片段：`<标题> 名字/名字`。
///
/// 名字排序用 [stableSort]：同一个 id 在 `names` 里缺省时回落 id，两个 id
/// 指向同一个显示名（服务端两台主机同名库）时裸 `sort` 会换位——摘要文字
/// 每次刷新不一样，看起来像「筛选条件变了」。
String _namesPart(String label, Set<String> ids, Map<String, String> names) {
  final list = [for (final id in ids) names[id] ?? id];
  stableSort(list, (a, b) => a.compareTo(b));
  return '$label ${list.join('/')}';
}

/// 把基础库 id/名称/大库 id 组装成节点列表，按 rel/名称稳定排序。
List<AuthorLibNode> authorLibNodes(
    Iterable<AuthorLibNode> nodes) {
  final seen = <String>{};
  final out = <AuthorLibNode>[];
  for (final n in nodes) {
    if (n.id.isEmpty || !seen.add(n.id)) continue;
    out.add(n);
  }
  out.sort((a, b) {
    final c = a.name.compareTo(b.name);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return out;
}

/// `/api/lib/<id>/index.json` 的 `kinds` 键（如 `v:single`）转换为
/// 作者主页使用的作品筛选分类（video/post/collection/picture）。
String authorTypeFromKind(String kind) {
  switch (kind.trim()) {
    case 'v:chapters':
    case 'p:album':
      return workFilterCollection;
    case 'p:post':
      return workFilterPost;
    case 'v:single':
      return workFilterVideo;
    case 'p:single':
      return workFilterPicture;
    default:
      return '';
  }
}

/// 解析单个基础库索引里的作者作品类型：作者名 → 类型集合。
/// 坏数据（非 Map、非数字计数、计数为 0）全部忽略，不抛异常。
Map<String, Set<String>> authorTypesFromIndex(dynamic indexJson) {
  final out = <String, Set<String>>{};
  if (indexJson is! Map) return out;
  final authors = listOf(indexJson['authors']);
  for (final e in authors) {
    if (e is! Map) continue;
    final name = '${e['name'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final kinds = e['kinds'];
    if (kinds is! Map) continue;
    final set = out[name] ??= <String>{};
    for (final k in kinds.entries) {
      // 计数值可能是 `3` 也可能是 `"3"`：intOf 两种都认。
      // 此前这里写成 `k.value is num ? intOf(...) : intOf(...)`——两个分支逐字相同，
      // 读起来像「数字和字符串分开处理」，实际是同一个调用的死分支。
      final n = intOf(k.value);
      if (n <= 0) continue;
      final t = authorTypeFromKind('${k.key}');
      if (t.isNotEmpty) set.add(t);
    }
    if (set.isEmpty) out.remove(name);
  }
  return out;
}

/// 合并多个基础库的作者类型（同一作者可能出现在多个库）。
Map<String, Set<String>> mergeAuthorTypes(
    Iterable<Map<String, Set<String>>> parts) {
  final out = <String, Set<String>>{};
  for (final p in parts) {
    for (final e in p.entries) {
      (out[e.key] ??= <String>{}).addAll(e.value);
    }
  }
  return out;
}

/// J11：全 App 共享的作者筛选状态。
///
/// 作者总览、排行榜、搜索、推荐共用同一份筛选；在任一页面调整后，
/// 其余页面下次可见时自动沿用，并立即刷新自身列表。
class AuthorFilterShared extends ValueNotifier<AuthorFilterState> {
  AuthorFilterShared() : super(AuthorFilterState());

  /// 应用一次筛选结果（由筛选面板返回）。
  void apply(AuthorFilterState next) {
    value = next;
  }

  /// 清空所有维度。
  void clearAll() {
    value = AuthorFilterState();
  }
}

/// 全局单例；页面只读 [value]，通过 [apply]/[clearAll] 修改。
final AuthorFilterShared authorFilter = AuthorFilterShared();

/// J11：把共享筛选应用到任意列表。
///
/// 各页面只需要提供「单条是否命中」的 [match]，过滤/未过滤两种分支
/// 与列表复制策略集中在这里，避免每个页面各写一套导致行为漂移。
List<T> applyAuthorFilter<T>(
  Iterable<T> items,
  AuthorFilterState filter,
  bool Function(T item, AuthorFilterState filter) match,
) {
  if (!filter.isActive) return List<T>.from(items);
  return items.where((e) => match(e, filter)).toList(growable: false);
}
