import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'cover_cache.dart';
import 'home_action.dart';
import 'author_grid.dart';
import 'category_tree_page.dart';
import 'library_tree.dart';
import 'media_priority.dart';
import 'work_card.dart';
import 'author_grade.dart';
import 'library_badge.dart';

/// 作者卡片头像：手动设置 > 爬虫脚本（服务端下发 `av`）> 自动生成（作品图兜底）。
/// 同级按时间新→旧；都为空时由调用方回退到「首字」占位。
String pickAuthorAvatar({
  String manual = '',
  String av = '',
  String fallback = '',
  int manualAt = 0,
  int crawlerAt = 0,
  int autoAt = 0,
}) =>
    pickAvatarPath(
      manual: manual,
      crawler: av,
      auto: fallback,
      manualAt: manualAt,
      crawlerAt: crawlerAt,
      autoAt: autoAt,
    );

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

  /// 作者来源词条：本基础库所属单元库的名称与配色（由调用方按单元库树算出）。
  final String sourceLabel;
  final int sourceColor;

  const BasicLibPage({
    super.key,
    required this.basic,
    required this.urlOf,
    required this.headersOf,
    required this.mediaUrlOf,
    required this.onOpenAuthor,
    this.onPlay,
    this.sourceLabel = '',
    this.sourceColor = LibraryBadge.gray,
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
  /// 作者 → `av` 头像路径（`/api/authors.json` 下发；空表示无头像）。
  final Map<String, String> _authorAv = <String, String>{};
  /// 作者 → 兜底头像（该作者第一件作品的缩略图）。
  final Map<String, String> _authorFallback = <String, String>{};
  /// 作者 → `/api/author_stats.json` 统计（用于等级词条）。
  final Map<String, dynamic> _authorStats = <String, dynamic>{};
  /// 作品类型多选筛选（空集合 = 全部）；只在本地过滤，不影响接口分页。
  final Set<String> _typeFilter = <String>{};
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
    _loadAvatars();
    _loadAuthorStats();
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

  /// 作者头像索引：`/api/authors.json` 的 `av`（索引文件里没有头像）。
  Future<void> _loadAvatars() async {
    try {
      final r = await http
          .get(widget.urlOf('/api/authors.json', lib: widget.basic.id),
              headers: widget.headersOf(widget.basic.id))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map) return;
      final map = <String, String>{};
      j.forEach((k, v) {
        if (v is! Map) return;
        final av = '${v['av'] ?? ''}'.trim();
        if (av.isNotEmpty) map['$k'] = av;
      });
      if (!mounted) return;
      setState(() {
        _authorAv
          ..clear()
          ..addAll(map);
      });
    } catch (_) {}
  }

  /// 兜底头像：每个作者第一件作品的缩略图（作品分页更新时重建）。
  void _rebuildAuthorFallback() {
    _authorFallback.clear();
    for (final w in works) {
      if (w is! Map) continue;
      final a = '${w['a'] ?? ''}'.trim();
      if (a.isEmpty || _authorFallback.containsKey(a)) continue;
      final th = _thumbOf(w);
      if (th.isNotEmpty) _authorFallback[a] = th;
    }
  }

  Future<void> _loadAuthorStats() async {
    try {
      final r = await http
          .get(widget.urlOf('/api/author_stats.json', lib: widget.basic.id),
              headers: widget.headersOf(widget.basic.id))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final authors = j is Map ? j['authors'] : null;
      if (authors is! Map) return;
      if (!mounted) return;
      setState(() {
        _authorStats
          ..clear()
          ..addAll(Map<String, dynamic>.from(authors));
      });
    } catch (_) {}
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
        // 头像兜底跟着作品更新（作者第一件作品的缩略图）
        _rebuildAuthorFallback();
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
        actions: [
          const HomeAction(),
          IconButton(
            key: const ValueKey('basic-categories'),
            tooltip: '分类树',
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => CategoryTreePage(
                basic: b,
                urlOf: widget.urlOf,
                headersOf: widget.headersOf,
                onOpenAuthor: widget.onOpenAuthor,
              ),
            )),
          ),
        ],
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
                  _authorAvatar(
                    key: ValueKey('basic-author-avatar-${a['id'] ?? i}'),
                    context: c,
                    name: name,
                  ),
                  const SizedBox(height: 6),
                  // 词条：单元库（去序号）+ 作者等级，与作者总览卡同一套
                  Wrap(
                    spacing: 3,
                    runSpacing: 3,
                    alignment: WrapAlignment.center,
                    children: [
                      if (widget.sourceLabel.isNotEmpty)
                        Container(
                          key: const ValueKey('basic-author-source'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Color(widget.sourceColor),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            LibraryBadge.stripIndex(widget.sourceLabel),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.3,
                              color: Color(LibraryBadge.textColorOn(
                                  widget.sourceColor)),
                            ),
                          ),
                        ),
                      Builder(builder: (_) {
                        final g = AuthorGrade.fromStats(
                            _authorStats[name],
                            works: _int(a['works']));
                        return Container(
                          key: const ValueKey('basic-author-grade'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Color(AuthorGrade.colorForGrade(g)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            g,
                            style: TextStyle(
                              fontSize: 9,
                              height: 1.3,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  Expanded(
                    child: Center(
                      child: Text(name,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  Text('${_int(a['works'])} 作品',
                      style: const TextStyle(fontSize: 9.5, color: Colors.grey)),
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

  /// 作者卡片头像：有 `av` 用 `av`（带鉴权、按显示尺寸解码），
  /// 否则用兜底图（该作者第一件作品的缩略图），都没有时回退首字占位。
  Widget _authorAvatar({
    Key? key,
    required BuildContext context,
    required String name,
    double size = 58,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.isEmpty ? '?' : name.characters.first;
    final placeholder = Center(
      child: Text(initial,
          style: TextStyle(
              fontSize: size * 0.38,
              fontWeight: FontWeight.w600,
              color: scheme.primary)),
    );
    final path = pickAuthorAvatar(
        av: _authorAv[name] ?? '', fallback: _authorFallback[name] ?? '');
    final url =
        path.isEmpty ? '' : widget.mediaUrlOf(path, lib: widget.basic.id);
    // 缩略按显示尺寸 × 像素比解码，避免整张头像原图进内存。
    final px = avatarDecodeWidth(
        displaySize: size,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context));
    return ClipOval(
      child: Container(
        key: key,
        width: size,
        height: size,
        color: scheme.primary.withValues(alpha: 0.15),
        child: url.isEmpty
            ? placeholder
            : CachedNetworkImage(
              cacheManager: DiziCache.manager,
                imageUrl: url,
                httpHeaders: widget.headersOf(widget.basic.id),
                width: size,
                height: size,
                fit: BoxFit.cover,
                memCacheWidth: px,
                fadeInDuration: Duration.zero,
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
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
    final shown = filtered;
    return Column(children: [
      _typeFilterBar(),
      if (shown.isEmpty)
        Expanded(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('该类型下暂无作品',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              TextButton(
                  onPressed: _typeFilter.isEmpty ? null : _clearTypeFilter,
                  child: const Text('清除筛选')),
            ]),
          ),
        )
      else
        Expanded(child: _worksGrid(shown)),
    ]);
  }

  Widget _worksGrid(List<dynamic> filtered) {
    return GridView.builder(
      controller: _worksScroll,
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: filtered.length + (loadingMore ? 1 : 0),
      itemBuilder: (c, i) {
        if (i >= filtered.length) {
          return const Center(
              child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final w = filtered[i];
        final thumb = _thumbOf(w);
        final wid = w is Map ? '${w['id'] ?? ''}' : '';
        // 视频没有 thumb.jpg 时走后端按需抽帧（抽过一次即落盘缓存）
        final cover = thumb.isNotEmpty
            ? widget.mediaUrlOf(thumb, lib: widget.basic.id)
            : (w is Map && w['t'] == 'v' && wid.isNotEmpty
                ? widget
                    .urlOf('/api/thumb/${widget.basic.id}/$wid',
                        lib: widget.basic.id)
                    .toString()
                : '');
        return WorkCard(
          key: ValueKey('basic-work-${w is Map ? w['id'] : i}'),
          title: w is Map ? '${w['ti'] ?? ''}' : '',
          typeLabel: _typeLabel(_workType(w)),
          coverUrl: cover,
          headers: widget.headersOf(widget.basic.id),
          onTap:
              widget.onPlay == null ? null : () => widget.onPlay!(filtered, i),
        );
      },
    );
  }

  // ---- 作品类型筛选（全部/视频/图文/合集，多选，本地过滤） ----

  static const List<String> _typeOrder = <String>['video', 'post', 'collection'];

  /// 作品类型：视频 / 图文 / 合集（与卡片右上角标签保持一致）。
  static String _workType(dynamic w) {
    if (w is! Map) return 'video';
    final kind = '${w['kind'] ?? ''}';
    if (kind == 'chapters' || kind == 'album') return 'collection';
    if (kind == 'post') return 'post';
    if ('${w['t']}' == 'p') return 'post';
    return 'video';
  }

  static String _typeLabel(String type) {
    switch (type) {
      case 'post':
        return '图文';
      case 'collection':
        return '合集';
      default:
        return '视频';
    }
  }

  /// 本地过滤后的作品列表；筛选为空时即全部作品。
  List<dynamic> get filtered {
    if (_typeFilter.isEmpty) return works;
    return works.where((w) => _typeFilter.contains(_workType(w))).toList();
  }

  int _countOf(String type) => works.where((w) => _workType(w) == type).length;

  void _toggleType(String type) {
    setState(() {
      if (!_typeFilter.add(type)) _typeFilter.remove(type);
    });
  }

  void _clearTypeFilter() {
    if (_typeFilter.isEmpty) return;
    setState(_typeFilter.clear);
  }

  Widget _typeFilterBar() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          Center(
            child: FilterChip(
              key: const ValueKey('basic-type-all'),
              label: Text('全部 ${works.length}',
                  style: const TextStyle(fontSize: 12)),
              selected: _typeFilter.isEmpty,
              showCheckmark: false,
              onSelected: (_) => _clearTypeFilter(),
            ),
          ),
          for (final type in _typeOrder)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Center(
                child: FilterChip(
                  key: ValueKey('basic-type-$type'),
                  label: Text('${_typeLabel(type)} ${_countOf(type)}',
                      style: const TextStyle(fontSize: 12)),
                  selected: _typeFilter.contains(type),
                  showCheckmark: false,
                  onSelected: _countOf(type) == 0 && !_typeFilter.contains(type)
                      ? null
                      : (_) => _toggleType(type),
                ),
              ),
            ),
          if (_typeFilter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Center(
                child: TextButton(
                    onPressed: _clearTypeFilter,
                    child: const Text('清除', style: TextStyle(fontSize: 12))),
              ),
            ),
        ],
      ),
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
