// J14 通用分类树模型（纯函数，便于单测）。
//
// 规则（owner 设计）：
//  - 基础库（库根）以下任意层级文件夹都是「分类」，可无限嵌套
//  - App 里显示的名称＝磁盘真实目录名；改名即重命名磁盘目录
//  - 叶子固定是 `@作者` 目录（一个作者就是一个叶子）
//  - 分类可折叠、可按名称筛选
//
// 数据来源：`GET /api/cat/tree?lib=<基础库 id>`，返回
//   { root, name, dirs:[{name, rel, authors:[...], dirs:[...]}] }
// 本文件只做解析、校验、改名后的本地映射与筛选，不做 IO。

/// 一个分类节点（对应磁盘上的一个真实目录）。
class CategoryNode {
  /// 磁盘真实目录名（显示名，不做任何美化）。
  final String name;

  /// 相对基础库根的路径，如 `A/B`。
  final String rel;

  /// 下级分类（按名称排序）。
  final List<CategoryNode> children;

  /// 直属作者名（不含 `@`）。
  final List<String> authors;

  const CategoryNode({
    required this.name,
    required this.rel,
    this.children = const [],
    this.authors = const [],
  });

  /// 分类段（rel 拆分结果）。
  List<String> get segments => splitCatRel(rel);

  /// 最深一层：没有下级分类时就是叶子（叶子上的目录都是作者）。
  bool get isLeaf => children.isEmpty;

  /// 整棵子树的分类数（不含自身）。
  int get childCategoryCount =>
      children.length + children.fold(0, (n, c) => n + c.childCategoryCount);

  /// 整棵子树的作者数（含下级分类）。
  int get authorCount =>
      authors.length + children.fold(0, (n, c) => n + c.authorCount);

  /// 按 id（rel）查找子树里的分类节点。
  CategoryNode? findByRel(String target) {
    if (rel == target) return this;
    for (final c in children) {
      final hit = c.findByRel(target);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 深度优先列出全部作者（`@名字`），保持层级顺序。
  List<String> get allAuthors => [
        for (final a in authors) '@$a',
        for (final c in children) ...c.allAuthors,
      ];

  /// 摘要：`3 个分类 · 12 位作者`。
  String get subtitle {
    final c = childCategoryCount;
    final a = authorCount;
    if (c == 0) return '$a 位作者';
    return '$c 个分类 · $a 位作者';
  }
}

/// 路径拆分（统一分隔符，去掉空段与 `.`）；`..` 保留以便校验时被拒。
List<String> splitCatRel(String rel) {
  final out = <String>[];
  for (final raw in rel.split(RegExp(r'[\\/]+'))) {
    final s = raw.trim();
    if (s.isEmpty || s == '.') continue;
    out.add(s);
  }
  return out;
}

String joinCatRel(Iterable<String> segs) => segs.join('/');

/// 从服务端 JSON 解析分类树；结构不合法返回 null。
CategoryNode? parseCategoryTree(Map<String, dynamic> json) {
  final dirs = json['dirs'];
  if (dirs is! List) return null;
  final rootName = '${json['name'] ?? ''}'.trim();
  return CategoryNode(
    name: rootName.isEmpty ? '库根' : rootName,
    rel: '',
    children: _parseNodes(dirs, ''),
    authors: _stringList(json['authors']),
  );
}

List<CategoryNode> _parseNodes(List raw, String parentRel) {
  final out = <CategoryNode>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final name = '${item['name'] ?? ''}'.trim();
    final relRaw = '${item['rel'] ?? ''}'.trim();
    if (name.isEmpty) continue;
    final rel = relRaw.isEmpty
        ? (parentRel.isEmpty ? name : '$parentRel/$name')
        : relRaw;
    out.add(CategoryNode(
      name: name,
      rel: rel,
      children: _parseNodes(item['dirs'] as List? ?? const [], rel),
      authors: _stringList(item['authors']),
    ));
  }
  out.sort((a, b) => a.name.compareTo(b.name));
  return out;
}

List<String> _stringList(dynamic v) {
  if (v is! List) return const [];
  final out = <String>[];
  for (final x in v) {
    final s = '${x ?? ''}'.trim();
    if (s.isEmpty) continue;
    out.add(s.startsWith('@') ? s.substring(1) : s);
  }
  return out;
}

/// 校验分类新名称；合法返回 null，否则返回原因（中文，可直接展示）。
String? validateCategoryName(String name) {
  final s = name.trim();
  if (s.isEmpty) return '名称不能为空';
  if (s == '.' || s == '..') return '名称不能是 . 或 ..';
  if (RegExp(r'[\\/:*?"<>|]').hasMatch(s)) return '名称不能包含 \\ / : * ? " < > |';
  if (RegExp(r'[\x00-\x1f]').hasMatch(s)) return '名称不能包含控制字符';
  if (s.startsWith('.')) return '名称不能以 . 开头';
  if (s.startsWith('_')) return '名称不能以 _ 开头（保留目录）';
  if (s.startsWith('@')) return '@ 开头是作者目录，不能用作分类名';
  if (s.length > 80) return '名称过长（最多 80 字）';
  if (s.endsWith(' ')) return '名称不能以空格结尾';
  return null;
}

/// 子树路径前缀替换：`A/B/C` 用 `A/B → A/X` 得到 `A/X/C`；
/// 不在前缀内原样返回。
String rewriteRel(String rel, String from, String to) {
  final r = splitCatRel(from).join('/');
  final segs = splitCatRel(rel);
  if (r.isEmpty) return to.isEmpty ? rel : to;
  final fromSegs = splitCatRel(from);
  if (segs.length < fromSegs.length) return rel;
  for (var i = 0; i < fromSegs.length; i++) {
    if (segs[i] != fromSegs[i]) return rel;
  }
  final tail = segs.skip(fromSegs.length).toList();
  final toSegs = splitCatRel(to);
  return joinCatRel([...toSegs, ...tail]);
}

/// 改名后的本地映射：把 rel 命中节点改成新名字，并递归改写子树路径。
/// [rel] 是被改名节点自身的相对路径；库根不可改名，找不到返回 null。
CategoryNode? renameNodeInTree(CategoryNode root, String rel, String newName) {
  final name = newName.trim();
  if (name.isEmpty) return null;
  final segs = splitCatRel(rel);
  if (segs.isEmpty) return null;
  final targetRel = segs.join('/');
  if (root.findByRel(targetRel) == null) return null;
  final newRel = joinCatRel([...segs.sublist(0, segs.length - 1), name]);

  CategoryNode walk(CategoryNode n) {
    if (n.rel == targetRel) {
      return _mapSubtree(n, n.rel, newRel, newName: name);
    }
    return CategoryNode(
      name: n.name,
      rel: n.rel,
      children: n.children.map(walk).toList(growable: false),
      authors: n.authors,
    );
  }

  return CategoryNode(
    name: root.name,
    rel: root.rel,
    children: root.children.map(walk).toList(growable: false),
    authors: root.authors,
  );
}

/// 子树整体换路径前缀（可选换根名字）。
CategoryNode _mapSubtree(CategoryNode n, String from, String to,
    {String? newName}) {
  return CategoryNode(
    name: newName ?? n.name,
    rel: rewriteRel(n.rel, from, to),
    authors: n.authors,
    children:
        n.children.map((c) => _mapSubtree(c, from, to)).toList(growable: false),
  );
}

/// 按名称筛选：保留命中节点及其祖先；命中节点的整棵子树保留。
/// 查询为空时原样返回。
CategoryNode filterCategoryTree(CategoryNode node, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return node;
  final hit = node.name.toLowerCase().contains(q);
  final kids = <CategoryNode>[];
  for (final c in node.children) {
    final kept = filterCategoryTree(c, q);
    if (kept.children.isNotEmpty ||
        kept.name.toLowerCase().contains(q) ||
        kept.authors.isNotEmpty) {
      kids.add(kept);
    }
  }
  final authors = node.authors
      .where((a) => a.toLowerCase().contains(q))
      .toList(growable: false);
  return CategoryNode(
    name: node.name,
    rel: node.rel,
    children: hit ? node.children : kids,
    authors: hit ? node.authors : authors,
  );
}

/// 筛选后需要展开的节点路径集合（命中节点的祖先）。
Set<String> expandedForQuery(CategoryNode node, String query) {
  final q = query.trim().toLowerCase();
  final out = <String>{};
  if (q.isEmpty) return out;
  bool walk(CategoryNode n) {
    var any = n.name.toLowerCase().contains(q);
    for (final c in n.children) {
      if (walk(c)) any = true;
    }
    if (n.authors.any((a) => a.toLowerCase().contains(q))) any = true;
    if (any && n.rel.isNotEmpty) out.add(n.rel);
    return any;
  }

  walk(node);
  return out;
}
