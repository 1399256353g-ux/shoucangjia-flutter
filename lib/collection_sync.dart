/// H11：收藏夹同步选择的纯逻辑。
///
/// 名称一律使用账号返回的名称（服务端已按账号名下发），不在客户端追加序号；
/// 未勾选（sync=false）的收藏夹不参与同步，也不应在主页/库选择页出现。
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
    final rawName =
        '${j['name'] ?? ''}'.replaceAll(RegExp(r'[\x00-\x1f]'), '').trim();
    return CollectionSyncInfo(
      idx: (j['idx'] as num?)?.toInt() ?? 0,
      name: rawName.isEmpty ? '收藏夹' : rawName,
      count: (j['count'] as num?)?.toInt() ?? 0,
      sync: j['sync'] != false,
      inIndex: j['inIndex'] == true,
      account: j['account'] == true,
      customName: j['customName'] == true,
    );
  }

  /// 是否显示在主页/库选择页
  bool get visible => sync;

  /// 列表副标题：不含序号，未勾选时明确提示不参与同步
  String get subtitle {
    final parts = <String>['$count 个作品'];
    if (!inIndex) parts.add(account ? '账号中 · 未下载' : '暂无索引');
    parts.add(sync ? '参与同步' : '不参与同步 · 主页不显示');
    return parts.join(' · ');
  }
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
