import 'emoji_text.dart';
import 'index_prefix.dart';

/// H11：同步源选择的纯逻辑。
///
/// 名称一律使用账号返回的名称（服务端已按账号名下发），不在客户端追加序号；
/// 未勾选（sync=false）的同步源不参与同步，也不应在主页/库选择页出现。
class CollectionSyncInfo {
  final int idx;
  final String name;
  final int count;
  final bool sync;
  final bool inIndex;
  final bool account;
  final bool customName;

  const CollectionSyncInfo({
    required this.idx,
    required this.name,
    required this.count,
    required this.sync,
    required this.inIndex,
    required this.account,
    required this.customName,
  });

  factory CollectionSyncInfo.fromJson(Map<String, dynamic> j) {
    // 去掉控制字符，并修复不完整的 UTF-16（否则 emoji 名会显示成方框）。
    final rawName = fixEmojiText(
        '${j['name'] ?? ''}'.replaceAll(RegExp(r'[\x00-\x1f]'), ''));
    return CollectionSyncInfo(
      idx: (j['idx'] as num?)?.toInt() ?? 0,
      name: rawName.isEmpty ? '同步源' : rawName,
      count: (j['count'] as num?)?.toInt() ?? 0,
      sync: j['sync'] != false,
      inIndex: j['inIndex'] == true,
      account: j['account'] == true,
      customName: j['customName'] == true,
    );
  }

  /// 是否显示在主页/库选择页
  ///
  /// 0.9.228 删除 `bool get visible => sync;`：它只在 `test/` 里被断言，
  /// 产品路径（设置页、单元库面板、主页）全部自己读 `sync` 或走
  /// `syncCollectionsForUnit`。一个「测试专用的同义 getter」会让人以为
  /// 界面按它过滤，改过滤规则时还以为改的是产品行为。

  /// 列表副标题：不含序号，未勾选时明确提示不参与同步。
  ///
  /// [isDefault] 为真时追加「默认同步源」。此前这是两份实现：
  /// 本 getter 说「账号中 · 未下载」，单元库面板却手拼「暂无索引」——
  /// 同一个同步源在设置页与单元库页有两种说法，且面板那版根本没有
  /// `account` 分支。现在两处都走这里。
  String subtitleWith({bool isDefault = false}) {
    final parts = <String>['$count 个作品'];
    if (!inIndex) parts.add(account ? '账号中 · 未下载' : '暂无索引');
    parts.add(sync ? '参与同步' : '不参与同步 · 主页不显示');
    if (isDefault) parts.add('默认同步源');
    return parts.join(' · ');
  }

  String get subtitle => subtitleWith();
}

/// 解析 /api/settings 返回的 collections：过滤墓碑、按服务端顺序、去重。
List<CollectionSyncInfo> parseCollectionSettings(Map<String, dynamic> j) {
  final raw = (j['collections'] as List?) ?? const [];
  final out = <CollectionSyncInfo>[];
  final seen = <int>{};
  for (final e in raw) {
    if (e is! Map) continue;
    final info = CollectionSyncInfo.fromJson(Map<String, dynamic>.from(e));
    if (info.idx <= 0 || info.name.isEmpty || seen.contains(info.idx)) continue;
    if (Map<String, dynamic>.from(e)['deleted'] == true) continue;
    seen.add(info.idx);
    out.add(info);
  }
  return out;
}

/// 全选/全不选：返回新的勾选状态，不修改原名与顺序
List<CollectionSyncInfo> setAllSync(List<CollectionSyncInfo> rows, bool value) {
  return [
    for (final r in rows)
      CollectionSyncInfo(
        idx: r.idx,
        name: r.name,
        count: r.count,
        sync: value,
        inIndex: r.inIndex,
        account: r.account,
        customName: r.customName,
      )
  ];
}

/// 同步源/单元库匹配用的归一化名：去掉序号、`@`、首尾空白与大小写差异。
String syncUnitKey(String raw) {
  var s = raw.trim();
  while (s.startsWith('@')) {
    s = s.substring(1).trim();
  }
  return stripIndexPrefix(s).toLowerCase();
}

List<String> _unitKeys(String unitName, String unitRel) {
  final keys = <String>[];
  void add(String s) {
    final k = syncUnitKey(s);
    if (k.isNotEmpty && !keys.contains(k)) keys.add(k);
  }

  add(unitName);
  final segs = unitRel
      .replaceAll('\\', '/')
      .split('/')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (segs.isNotEmpty) add(segs.last);
  // 有些单元库是多级目录（分类/子分类），用全部段做包含匹配。
  for (final s in segs) {
    add(s);
  }
  return keys;
}

/// 单个单元库应该展示/管理的同步源。
///
/// - 目录名与同步源同名（去掉序号后）→ 只显示该同步源；
/// - 顶级单元库（`(2) douyin` 这类只有一段的库）→ 显示全部同步源；
/// - 找不到同名项时退回「包含」匹配；
/// - 仍无线索则返回空列表，页面明确提示「未找到同名同步源」，
///   不把账号全部同步源错误地塞进无关单元库。
List<CollectionSyncInfo> syncCollectionsForUnit(
  List<CollectionSyncInfo> rows, {
  required String unitName,
  required String unitRel,
}) {
  if (rows.isEmpty) return const <CollectionSyncInfo>[];
  final keys = _unitKeys(unitName, unitRel);
  final exact = <CollectionSyncInfo>[
    for (final r in rows)
      if (keys.contains(syncUnitKey(r.name))) r,
  ];
  if (exact.isNotEmpty) return exact;
  final segs = unitRel
      .replaceAll('\\', '/')
      .split('/')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  // 只有抖音库根这种「本身就是同步源容器」的顶级单元库才展示全部；
  // 其它无关库根不应把账号全部同步源塞进来。
  final unitKey = syncUnitKey(unitName);
  final isSyncRoot = unitKey == 'douyin' || unitKey.contains('抖音');
  if (segs.length <= 1 && isSyncRoot) return rows;
  final fuzzy = <CollectionSyncInfo>[
    for (final r in rows)
      if (keys.any((k) {
        final n = syncUnitKey(r.name);
        return n.isNotEmpty && (n.contains(k) || k.contains(n));
      }))
        r,
  ];
  return fuzzy;
}
