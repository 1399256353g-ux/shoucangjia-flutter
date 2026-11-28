import 'basic_lib.dart';
import 'json_num.dart';
import 'server_origin.dart';

// 首页库树模型（纯函数，便于单测）。
//
// 数据来源：/api/libraries.json（v2，由 NAS `lib_scan.py` 生成）
//  - basicLibraries: 基础库（全量，**【必需】**）
//  - bigLibraries:   旧版分组（**可缺**，新服务端已不再下发）
//
// 0.9.321（第八十五批）：`parse` 曾经把 `bigLibraries` 当作必需字段——
// 它不是 List 就整棵返回 null。新服务端只下发 `basicLibraries`，于是首页
// `_loadTree` 拿到的模型是 null，`buildUnitTree(basics: t?.allBasics ?? [])`
// 退化成「零基础库」：所有词条落 SECRET、单元库卡片的作者/作品数全是 0。
// 现在只有「一条基础库都读不出来」才算 v1（返回 null，页面走旧列表），
// 分组缺失只是没有旧分组，不再连带丢掉全部基础库。
//
// 规则：
//  - 主页默认只展示上层分组（全部折叠），点开才看到基础库，减少首屏长度（J3）
//  - 星标标记「基础库」：被标记的基础库收集到顶部「星标」区，按标记时间倒序
//  - 已星标的基础库不再重复出现在旧分组里，避免同一项出现两次
//  - 找不到 big_id 的基础库归入「未归属」分组，不丢数据
//  - 旧版（v1，只有 libraries 注册表、没有任何基础库）解析返回 null
//
// `BasicLib` 模型本身在 `basic_lib.dart`（0.9.284 与 `source_lib.BasicLibRef`
// 合并为一份）：两处各定义一个「基础库」时，单元库页走的那个少 `cover`/`cv`
// 两个字段，同一张卡在两个页面就取到不同的封面。

export 'basic_lib.dart' show BasicLib;

class BigLib {
  final String id;
  final String name;
  final String path;

  /// 服务端 v2 索引里的统计字段。仅保留结构，不再生成旧的「N 个基础库」描述。
  final int authors;
  final int works;
  final List<BasicLib> basics;
  final String serverId;
  final String serverBase;
  final String serverLabel;

  const BigLib({
    required this.id,
    required this.name,
    required this.path,
    required this.authors,
    required this.works,
    required this.basics,
    this.serverId = '',
    this.serverBase = '',
    this.serverLabel = '',
  });
}

class LibraryTree {
  final List<BigLib> bigs;
  final List<BasicLib> unassigned;

  /// 注意：这里**不再**持有星标副本。
  ///
  /// 星标的唯一真相是 `StarStore`（可监听、跨页同步）。此前 `LibraryTree`
  /// 还按 `stars` 参数算一份 `starred`，但 `lib/` 里没有任何地方读它——
  /// 真实渲染全部走 `StarStore.ids`。同一件事两份状态，改一处忘一处时
  /// 就会出现「星标页有、首页没有」这种没法查的现象，所以直接删掉。
  const LibraryTree({
    required this.bigs,
    required this.unassigned,
  });

  /// 解析 v2；**只要读不出基础库**就返回 null（页面走旧列表兜底）。
  ///
  /// `bigLibraries` 缺失不是错误：新服务端只下发 `basicLibraries`，此处按
  /// 「没有旧分组」处理（`bigs` 为空、全部基础库进 [unassigned]）。
  static LibraryTree? parse(Map<String, dynamic> json) {
    final rawBigs = json['bigLibraries'];
    final rawBasics = json['basicLibraries'];
    if (rawBasics is! List) return null;

    final basics = <BasicLib>[];
    for (final raw in rawBasics) {
      if (raw is! Map) continue;
      final id = '${raw['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      // 解析本体只有 `basic_lib.basicLibFromJson` 一处（与 `source_lib.
      // basicsUnderBase` 同一个入口）：这里再手抄一遍字段，漏掉 `cover`
      // 指针或 `cv` 其中之一，首页与单元库页就会取到不同的封面。
      basics.add(basicLibFromJson(
        raw,
        id: id,
        rel: '${raw['rel'] ?? ''}'.trim(),
        fallbackName: '${raw['name'] ?? id}'.trim(),
      ));
    }

    final bigs = <BigLib>[];
    if (rawBigs is List) {
      for (final raw in rawBigs) {
        if (raw is! Map) continue;
        final id = '${raw['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        final origin = serverOriginOf(raw);
        bigs.add(BigLib(
          id: id,
          name: '${raw['name'] ?? id}'.trim(),
          path: '${raw['path'] ?? ''}'.trim(),
          authors: intOf(raw['authors']),
          works: intOf(raw['works']),
          basics: basics.where((b) => b.bigId == id).toList(growable: false),
          serverId: origin.id,
          serverBase: origin.base,
          serverLabel: origin.label,
        ));
      }
    }
    // 一条基础库都没有 → 不是可用的 v2 载荷，交给页面兜底。
    if (basics.isEmpty) return null;

    final known = {for (final b in bigs) b.id};
    final unassigned =
        basics.where((b) => !known.contains(b.bigId)).toList(growable: false);

    return LibraryTree(bigs: bigs, unassigned: unassigned);
  }

  /// 全部基础库（含未归属），用于重新排序星标。
  List<BasicLib> get allBasics => [
        for (final b in bigs) ...b.basics,
        ...unassigned,
      ];

  BasicLib? basicById(String id) {
    for (final b in bigs) {
      for (final x in b.basics) {
        if (x.id == id) return x;
      }
    }
    for (final x in unassigned) {
      if (x.id == id) return x;
    }
    return null;
  }
}

/// 切换星标：已标记则移除，未标记则插到最前（最近标记优先）。
List<String> toggleStar(List<String> stars, String id, {int max = 20}) {
  final next = List<String>.from(stars);
  if (next.remove(id)) return next;
  next.insert(0, id);
  while (next.length > max) {
    next.removeLast();
  }
  return next;
}

