import 'dart:convert';

import 'package:http/http.dart' as http;

import 'top_node.dart';

/// 一条基础库目录（媒体库里的真实分类目录）。
class CatalogBasic {
  final String id;
  final String name;
  final String rel;
  final String bigId;
  /// 所属单元库 id（节点文件夹）；顶级 SECRET 为 'secret'。
  final String unitId;
  final String unitName;
  final int authors;
  final int works;

  const CatalogBasic({
    required this.id,
    required this.name,
    required this.rel,
    required this.bigId,
    required this.unitId,
    required this.unitName,
    required this.authors,
    required this.works,
  });
}

/// 媒体库目录（基础库 + 单元库归属）。
///
/// 作者总览/排行榜/筛选都从这里取「全部基础库」，不再只读旧注册表里的
/// 单一抖音收藏库。
class MediaCatalog {
  static List<CatalogBasic> _items = const [];
  static Map<String, String> _unitNames = const {};
  static bool _loaded = false;

  static List<CatalogBasic> get basics => _items;
  static Map<String, String> get unitNames => _unitNames;

  static String unitIdOf(String basicId) {
    for (final b in _items) {
      if (b.id == basicId) return b.unitId;
    }
    return '';
  }

  static String unitNameOf(String unitId) {
    if (unitId.isEmpty) return '';
    return _unitNames[unitId] ??
        (unitId == 'secret' ? TopNodeName.current : unitId);
  }

  /// 单元库列表（去重，SECRET 最后）。
  static List<MapEntry<String, String>> get units {
    final seen = <String>{};
    final out = <MapEntry<String, String>>[];
    for (final b in _items) {
      if (!seen.add(b.unitId)) continue;
      out.add(MapEntry(b.unitId, b.unitName));
    }
    out.sort((a, b) {
      if (a.key == 'secret') return 1;
      if (b.key == 'secret') return -1;
      return a.value.compareTo(b.value);
    });
    return out;
  }

  static Future<void> ensure({
    required String base,
    required Map<String, String> headers,
  }) async {
    if (_loaded) return;
    try {
      final rs = await Future.wait([
        http.get(Uri.parse('$base/api/libraries.json'), headers: headers)
            .timeout(const Duration(seconds: 12)),
        http.get(Uri.parse('$base/api/nodes'), headers: headers)
            .timeout(const Duration(seconds: 12)),
      ]);
      if (rs[0].statusCode != 200) return;
      final j = jsonDecode(utf8.decode(rs[0].bodyBytes));
      if (j is! Map) return;
      // owner 2026-11-22：顶级节点名＝媒体库根目录名。
      TopNodeName.setFromRoot('${j['root'] ?? ''}');
      final basicsRaw = j['basicLibraries'];
      if (basicsRaw is! List) return;

      final nodeRels = <String>[];
      if (rs[1].statusCode == 200) {
        final nj = jsonDecode(utf8.decode(rs[1].bodyBytes));
        final list = nj is Map ? nj['nodes'] : null;
        if (list is List) {
          for (final e in list) {
            final rel = (e is Map
                    ? '${e['rel'] ?? e['path'] ?? e['name'] ?? ''}'
                    : '$e')
                .trim();
            if (rel.isNotEmpty) nodeRels.add(rel);
          }
        }
      }

      final items = <CatalogBasic>[];
      for (final e in basicsRaw) {
        if (e is! Map) continue;
        final id = '${e['id'] ?? ''}'.trim();
        final name = '${e['name'] ?? ''}'.trim();
        var rel = '${e['rel'] ?? ''}'.trim();
        if (rel.isEmpty) {
          final path = '${e['path'] ?? ''}'.trim();
          final base = '${j['root'] ?? ''}'.trim();
          if (base.isNotEmpty && path.startsWith('$base/')) {
            rel = path.substring(base.length + 1);
          }
        }
        if (id.isEmpty || name.isEmpty || rel.isEmpty) continue;
        var unitId = 'secret';
        var unitName = TopNodeName.current;
        var bestLen = -1;
        for (final n in nodeRels) {
          if ((rel == n || rel.startsWith('$n/')) && n.length > bestLen) {
            bestLen = n.length;
            unitId = 'unit:$n';
            final segs = n.split('/');
            unitName = segs.isEmpty ? n : segs.last;
          }
        }
        items.add(CatalogBasic(
          id: id,
          name: name,
          rel: rel,
          bigId: '${e['big_id'] ?? ''}',
          unitId: unitId,
          unitName: unitName,
          authors: int.tryParse('${e['authors'] ?? 0}') ?? 0,
          works: int.tryParse('${e['works'] ?? 0}') ?? 0,
        ));
      }
      items.sort((a, b) => b.works.compareTo(a.works));
      _items = items;
      _unitNames = {
        for (final b in items) b.unitId: b.unitName,
      };
      _loaded = true;
    } catch (_) {}
  }

  /// 仅供测试重置。
  static void resetForTest(
      {List<CatalogBasic> basics = const [],
      Map<String, String>? unitNames}) {
    _items = basics;
    _unitNames = unitNames ??
        {for (final b in basics) b.unitId: b.unitName};
    _loaded = true;
  }
}
