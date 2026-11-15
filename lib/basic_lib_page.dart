import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'library_tree.dart';

/// M10：基础库页面「作者视图 / 作品视图」双视图。
///
/// 数据来源（服务端）：
///  - `GET /api/lib/<id>/index.json`  → 作者列表（id/name/works/kinds）
///  - `GET /api/lib/<id>/works.json?offset&limit` → 库内全部作品（分页）
///
/// 本页不直接依赖全局 cfg：URL/鉴权/媒体地址由调用方注入，
/// 避免 lib 包与 main.dart 之间形成循环导入。
class BasicLibPage extends StatefulWidget {
  final BasicLib basic;
  final Uri Function(String path, {String? lib}) urlOf;
  final Map<String, String> Function([String? lib]) headersOf;
  final String Function(String path, {String? lib}) mediaUrlOf;
  final void Function(String authorName) onOpenAuthor;
  final void Function(List<dynamic> works, int index)? onPlay;

  const BasicLibPage({
    super.key,
    required this.basic,
    required this.urlOf,
    required this.headersOf,
    required this.mediaUrlOf,
    required this.onOpenAuthor,
    this.onPlay,
  });

  @override
  State<BasicLibPage> createState() => _BasicLibPageState();
}

class _BasicLibPageState extends State<BasicLibPage>
    with SingleTickerProviderStateMixin {
  static const int _pageSize = 120;

  late final TabController _tabs = TabController(length: 2, vsync: this);
  final ScrollController _worksScroll = ScrollController();

  List<Map<String, dynamic>> authors = [];
  List<dynamic> works = [];
  int total = 0;
  bool loadingAuthors = true;
  bool loadingWorks = true;
  bool loadingMore = false;
  String? err;

  @override
  void initState() {
    super.initState();
    _worksScroll.addListener(_onScroll);
    _loadAuthors();
    _loadWorks(reset: true);
  }

  @override
  void dispose() {
    _worksScroll.removeListener(_onScroll);
    _worksScroll.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_worksScroll.hasClients) return;
    final pos = _worksScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) _loadWorks();
  }

  Future<void> _loadAuthors() async {
    try {
      final r = await http
          .get(widget.urlOf('/api/lib/${widget.basic.id}/index.json',
              lib: widget.basic.id),
              headers: widget.headersOf(widget.basic.id))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final list = <Map<String, dynamic>>[];
      for (final a in (j['authors'] as List? ?? const [])) {
        if (a is Map) list.add(Map<String, dynamic>.from(a));
      }
      list.sort((x, y) => _int(y['works']).compareTo(_int(x['works'])));
      if (!mounted) return;
      setState(() {
        authors = list;
        loadingAuthors = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingAuthors = false;
        err = '$e';
      });
    }
  }

  Future<void> _loadWorks({bool reset = false}) async {
    if (reset) {
      works = [];
      total = 0;
      loadingWorks = true;
    } else {
      if (loadingMore || works.length >= total) return;
      loadingMore = true;
    }
    if (mounted) setState(() {});
    try {
      final r = await http
          .get(
              widget.urlOf(
                  '/api/lib/${widget.basic.id}/works.json'
                  '?offset=${reset ? 0 : works.length}&limit=$_pageSize',
                  lib: widget.basic.id),
              headers: widget.headersOf(widget.basic.id))
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw 'HTTP ${r.statusCode}';
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final batch = (j['works'] as List? ?? const []);
      if (!mounted) return;
      setState(() {
        if (reset) works = [];
        works.addAll(batch);
        total = _int(j['total']);
        loadingWorks = false;
        loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingWorks = false;
        loadingMore = false;
        if (err == null) err = '$e';
      });
    }
  }

  static int _int(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);

  static String _kindsLabel(Map<String, dynamic> a) {
    final k = a['kinds'];
    if (k is! Map || k.isEmpty) return '';
    int v = 0, p = 0, c = 0;
    for (final e in k.entries) {
      final key = '${e.key}';
      final n = _int(e.value);
      if (key.startsWith('v:')) {
        if (key.endsWith('chapters')) {
          c += n;
        } else {
          v += n;
        }
      } else if (key.startsWith('p:')) {
        p += n;
      }
    }
    final parts = <String>[
      if (v > 0) '视频 $v',
      if (p > 0) '图文 $p',
      if (c > 0) '合集 $c',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.basic;
    return Scaffold(
      appBar: AppBar(
        title: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: '作者 ${loadingAuthors ? '' : authors.length}'),
            Tab(text: '作品 ${total > 0 ? total : b.works}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _authorsView(),
          _worksView(),
        ],
      ),
    );
  }

  Widget _authorsView() {
    if (loadingAuthors) {
      return const Center(child: CircularProgressIndicator());
    }
    if (authors.isEmpty) {
      return Center(
          child: Text(err ?? '该基础库下没有作者',
              style: const TextStyle(fontSize: 12, color: Colors.grey)));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.86,
      ),
      itemCount: authors.length,
      itemBuilder: (c, i) {
        final a = authors[i];
        final name = '${a['name'] ?? a['name_raw'] ?? ''}'.trim();
        final sub = _kindsLabel(a);
        final scheme = Theme.of(c).colorScheme;
        return Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            key: ValueKey('basic-author-${a['id'] ?? i}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => widget.onOpenAuthor(name),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: scheme.primary.withValues(alpha: 0.15),
                    child: Text(
                      name.isEmpty ? '?' : name.characters.first,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(name,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  Text('${_int(a['works'])} 作品',
                      style:
                          const TextStyle(fontSize: 10, color: Colors.grey)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 9.5, color: Colors.grey)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _worksView() {
    if (loadingWorks && works.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (works.isEmpty) {
      return Center(
          child: Text(err ?? '该基础库下没有作品',
              style: const TextStyle(fontSize: 12, color: Colors.grey)));
    }
    return GridView.builder(
      controller: _worksScroll,
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: works.length + (loadingMore ? 1 : 0),
      itemBuilder: (c, i) {
        if (i >= works.length) {
          return const Center(
              child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final w = works[i];
        final thumb = _thumbOf(w);
        return InkWell(
          key: ValueKey('basic-work-${w is Map ? w['id'] : i}'),
          onTap: widget.onPlay == null ? null : () => widget.onPlay!(works, i),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: thumb.isEmpty
                      ? Container(
                          color: Colors.black12,
                          child: const Icon(Icons.movie_outlined,
                              size: 22, color: Colors.grey))
                      : Image.network(
                          widget.mediaUrlOf(thumb, lib: widget.basic.id),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.black12,
                            child: const Icon(Icons.broken_image_outlined,
                                size: 20, color: Colors.grey),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Text('${w is Map ? (w['ti'] ?? '') : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
        );
      },
    );
  }

  /// 作品缩略图：优先 `th`，其次图文首图 `m[0]`；视频无图时为空。
  static String _thumbOf(dynamic w) {
    if (w is! Map) return '';
    final th = '${w['th'] ?? ''}'.trim();
    if (th.isNotEmpty) return th;
    final m = w['m'];
    if (m is List && m.isNotEmpty) {
      final first = '${m.first}'.trim();
      if (first.isNotEmpty && !first.toLowerCase().endsWith('.mp4')) {
        return first;
      }
    }
    return '';
  }
}
