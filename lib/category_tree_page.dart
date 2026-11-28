import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'http_json.dart';
import 'http_error_text.dart';

import 'home_action.dart';
import 'category_tree.dart';
import 'lib_names.dart';
import 'library_tree.dart';
import 'error_text.dart';
import 'toast.dart';
import 'loading_view.dart';
import 'api_timeout.dart';
import 'text_styles.dart';
import 'ui_copy.dart';

/// J14：通用分类树页面。
///
/// - 库根下任意层级文件夹都是分类，可无限嵌套（服务端按磁盘真实目录返回）
/// - 显示名称＝磁盘真实目录名；「重命名」直接改磁盘目录，服务端随后重扫索引
/// - 叶子是 `@作者`，点开走作者主页
/// - 顶部输入框按名称筛选分类/作者，命中自动展开
class CategoryTreePage extends StatefulWidget {
  final BasicLib basic;
  final Uri Function(String path, {String? lib}) urlOf;
  final Map<String, String> Function([String? lib]) headersOf;
  final void Function(String authorName) onOpenAuthor;

  const CategoryTreePage({
    super.key,
    required this.basic,
    required this.urlOf,
    required this.headersOf,
    required this.onOpenAuthor,
  });

  @override
  State<CategoryTreePage> createState() => _CategoryTreePageState();
}

class _CategoryTreePageState extends State<CategoryTreePage> {
  final TextEditingController _filter = TextEditingController();
  final Set<String> _expanded = <String>{};

  CategoryNode? tree;
  bool loading = true;
  bool renaming = false;
  String? err;

  @override
  void initState() {
    super.initState();
    _filter.addListener(_onFilterChanged);
    _load();
  }

  @override
  void dispose() {
    _filter.removeListener(_onFilterChanged);
    _filter.dispose();
    super.dispose();
  }

  void _onFilterChanged() {
    final q = _filter.text.trim();
    final t = tree;
    if (q.isEmpty || t == null) {
      setState(() {});
      return;
    }
    final want = expandedForQuery(t, q);
    setState(() => _expanded.addAll(want));
  }

  Future<void> _load() async {
    try {
      final r = await http
          .get(
              widget
                  .urlOf('/api/cat/tree', lib: widget.basic.id)
                  .replace(queryParameters: {'lib': widget.basic.id}),
              headers: widget.headersOf(widget.basic.id))
          .timeout(kTimeoutReadHeavy);
      if (r.statusCode != 200) throw httpErrorText(r.statusCode);
      final j = jsonOf(r);
      final t = j is Map<String, dynamic> ? parseCategoryTree(j) : null;
      if (t == null) throw '返回结构异常';
      if (!mounted) return;
      setState(() {
        tree = t;
        loading = false;
        err = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        err = errorText(e);
      });
    }
  }

  Future<void> _rename(CategoryNode node) async {
    final ctl = TextEditingController(text: node.name);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重命名分类'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将同时重命名磁盘目录：${node.rel}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            TextField(
              controller: ctl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '新名称',
                helperText: '显示名称即磁盘目录名',
              ),
              onSubmitted: (v) => Navigator.of(c).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(c).pop(), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(c).pop(ctl.text),
              child: const Text('确定')),
        ],
      ),
    );
    ctl.dispose();
    if (name == null) return;
    final clean = name.trim();
    if (clean == node.name) return;
    final bad = validateCategoryName(clean);
    if (bad != null) {
      _toast(bad);
      return;
    }
    setState(() => renaming = true);
    try {
      final r = await http
          .post(
            widget
                .urlOf('/api/cat/rename', lib: widget.basic.id)
                .replace(queryParameters: {'lib': widget.basic.id}),
            headers: {
              ...widget.headersOf(widget.basic.id),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'rel': node.rel, 'name': clean}),
          )
          .timeout(kTimeoutHeavyWrite);
      final j = r.statusCode == 200 ? jsonOf(r) : null;
      final bad = apiFailureText(r.statusCode, j);
      if (bad != null) throw bad;
      if (!mounted) return;
      // 本地先映射，随后重新拉取以对齐磁盘（索引重扫是异步的）。
      final next = renameNodeInTree(tree!, node.rel, clean);
      setState(() {
        if (next != null) tree = next;
        renaming = false;
      });
      _toast('已重命名，索引重建中');
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => renaming = false);
      _toast(failureLine('重命名', errorText(e)));
    }
  }

  void _toast(String msg) => showToast(this, msg);

  @override
  Widget build(BuildContext context) {
    final filtered =
        tree == null ? null : filterCategoryTree(tree!, _filter.text);
    return Scaffold(
      appBar: AppBar(
        // 0.9.355：这一页标题原来自拼 `widget.basic.name`——只做原样输出，
        // 既不按「省略编号」开关去序号，名字为空/纯空格时也不回落 id。
        // 同一个基础库在单元库页标题、基础库卡标题、设置页行里都是
        // `libEntryTitle` 的结果，只有这一页会显示成「分类 · 」或「分类 · (1) 名称」。
        title: Text('分类 · ${libEntryTitle(widget.basic.id, widget.basic.name)}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          const HomeAction(),
          if (renaming)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: InlineSpinner())),
            ),
          IconButton(
            tooltip: kRefreshTooltip,
            onPressed: loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _filter,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
                hintText: '筛选分类或作者',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                suffixIcon: _filter.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _filter.clear(),
                      ),
              ),
            ),
          ),
          Expanded(child: _body(filtered)),
        ],
      ),
    );
  }

  Widget _body(CategoryNode? node) {
    if (loading) return const LoadingView();
    if (node == null) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(err ?? '加载失败',
            textAlign: TextAlign.center,
            style: kHintTextStyle),
      ));
    }
    if (node.children.isEmpty && node.authors.isEmpty) {
      return const Center(
          child: Text('库根下没有分类或作者',
              style: kHintTextStyle));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      children: [
        for (final c in node.children) _nodeTile(c, 0),
        if (node.authors.isNotEmpty) ..._authorTiles(node.authors, 0),
      ],
    );
  }

  Widget _nodeTile(CategoryNode node, int depth) {
    final q = _filter.text.trim();
    final open =
        q.isNotEmpty && expandedForQuery(tree!, q).contains(node.rel) ||
            _expanded.contains(node.rel);
    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            key: ValueKey('cat-${node.rel}'),
            dense: true,
            leading: Icon(open ? Icons.folder_open : Icons.folder_outlined,
                size: 20),
            title: Text(node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13)),
            subtitle: Text(node.subtitle,
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!node.isLeaf)
                  Icon(open ? Icons.expand_less : Icons.expand_more, size: 18),
                PopupMenuButton<String>(
                  tooltip: '分类操作',
                  onSelected: (v) {
                    if (v == 'rename') _rename(node);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                  ],
                ),
              ],
            ),
            onTap: () {
              if (node.isLeaf) {
                // 叶子目录下都是作者，展开即可直达。
                setState(() {
                  if (!_expanded.remove(node.rel)) _expanded.add(node.rel);
                });
                return;
              }
              setState(() {
                if (!_expanded.remove(node.rel)) _expanded.add(node.rel);
              });
            },
          ),
          if (open) ...[
            for (final c in node.children) _nodeTile(c, depth + 1),
            ..._authorTiles(node.authors, depth + 1),
          ],
        ],
      ),
    );
  }

  List<Widget> _authorTiles(List<String> authors, int depth) => [
        for (final a in authors)
          Padding(
            padding: EdgeInsets.only(left: depth * 12.0),
            child: ListTile(
              key: ValueKey('cat-author-$a'),
              dense: true,
              leading: const Icon(Icons.person_outline, size: 18),
              title: Text('@$a',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5)),
              onTap: () => widget.onOpenAuthor(a),
            ),
          ),
      ];
}
