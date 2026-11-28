
import 'count_label.dart';
import 'dart:convert';
import 'json_num.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'http_json.dart';
import 'http_error_text.dart';

import 'card_metrics.dart';
import 'grid_spec.dart';
import 'work_card_prefetch.dart';
import 'author_avatar.dart';
import 'author_avatar_store.dart';
import 'author_avatar_view.dart';
import 'author_uid_index.dart';
import 'avatar_prefetch.dart';
import 'author_index.dart';
import 'author_letter_bar.dart';
import 'home_action.dart';
import 'category_tree_page.dart';
import 'library_revision.dart';
import 'library_tree.dart';
import 'stable_order.dart';
import 'media_priority.dart';
import 'scroll_decode.dart';
import 'work_card.dart';
import 'work_forms.dart';
import 'work_cover.dart';
import 'author_grade.dart';
import 'unit_author_groups.dart'
    show
        authorCreateSummary,
        authorDirForName,
        authorDirError,
        unitAuthorCreateUrl;
import 'author_badge_row.dart';
import 'library_badge.dart';
import 'lib_names.dart';
import 'error_text.dart';

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
/// 在 isolate 里解析 works.json：把 UTF-8 解码 + JSON 解析都移出 UI 线程。
/// 大库单页几十到上百条，主线程解析会直接卡住首帧。
Map<String, dynamic> _parseWorksPayload(List<int> bytes) =>
    jsonOfBytes(bytes) as Map<String, dynamic>;

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

  /// 所属单元库 id（仅用于词条的 emoji 后缀与层级外观）。
  ///
  /// 0.9.291：此前本页手写词条容器，既不显示 emoji、也不用
  /// `LibraryBadge.decorationFor` 的层级边框/底纹，圆角更是 `circular(4)`
  /// ——同一位作者在作者总览卡与基础库页作者卡上**词条长得不一样**
  /// （同一张卡的两处渲染，属于本批要收的那一类）。
  final String sourceUnitId;

  /// 所属媒体库（顶级单元库）名称与 id。
  ///
  /// owner 2026-11-27：「词条还是没下发…媒体库词条啊」——作者卡上只有
  /// 单元库一级，属于哪个媒体库看不出来。页面自己拿不到单元库树的父级
  /// （本页只收一个基础库），所以由调用方（有 `unitTree` 的那一层）算好传入；
  /// 空串＝不贴（单连接旧形态没有媒体库这一层，不编造）。
  final String sourceMediaLabel;
  final String sourceMediaId;

  /// 同一**直接上级单元库**下的全部基础库（新建作者时可多选）。
  ///
  /// owner 2026-11-28：「新建时可以选择在哪些基础库有作品，列出所属单元库下
  /// 所有基础库以供选择，选择后本地自动创建好文件夹」。
  ///
  /// 由调用方（持有单元库树的那一层）传入；空列表＝页面建不了作者目录，
  /// 右上角入口直接不显示（不拿本页单个基础库去猜）。
  final List<BasicLib> siblingBasics;

  /// 媒体库词条配色（由调用方按同一份顺序算出）。
  ///
  /// 必须由调用方传，不能在本页自己 `colorForUnit(sourceMediaId)`：不带
  /// `order` 时会退到 id 散列，而作者卡/首页/media 卡片走的是注册表顺序——
  /// 同一个媒体库在两处是两个颜色，两边各自都「算得出一个色」。
  final int sourceMediaColor;

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
    this.sourceUnitId = '',
    this.sourceMediaLabel = '',
    this.sourceMediaId = '',
    this.sourceMediaColor = LibraryBadge.gray,
    this.siblingBasics = const <BasicLib>[],
  });

  @override
  State<BasicLibPage> createState() => _BasicLibPageState();
}

class _BasicLibPageState extends State<BasicLibPage>
    with SingleTickerProviderStateMixin {
  // owner 2026-11-19：单页从 120 降到 60，降低一次性解码/建卡的数量，
  // 避免大库（几百到上千件）翻页时内存与解码压力叠加导致崩溃。
  static const int _pageSize = 60;

  // owner 2026-11-19：「作品」在前，「作者」在后；进入基础库默认停在作品页。
  late final TabController _tabs =
      TabController(length: 2, vsync: this, initialIndex: 0);
  final ScrollController _worksScroll = ScrollController();
  final ScrollController _authorScroll = ScrollController();
  final TextEditingController _authorSearch = TextEditingController();

  List<Map<String, dynamic>> authors = [];
  List<dynamic> works = [];
  /// 作者搜索词：仅本地过滤当前基础库的作者，不发请求（owner 2026-11-22）。
  String _authorQuery = '';
  List<Map<String, dynamic>>? _authorShownCache;
  List<String> _authorShownKeys = const <String>[];
  /// 作者 → `av` 头像路径（`/api/authors.json` 下发；空表示无头像）。
  final Map<String, String> _authorAv = <String, String>{};
  /// 作者 → 兜底头像（该作者第一件作品的缩略图）。
  final Map<String, String> _authorFallback = <String, String>{};
  /// 作者 → `/api/author_stats.json` 统计（用于等级词条）。
  final Map<String, dynamic> _authorStats = <String, dynamic>{};
  /// 作品类型多选筛选（空集合 = 全部）；只在本地过滤，不影响接口分页。
  final Set<String> _typeFilter = <String>{};
  /// 各类型数量：作品分页更新时算一次，避免每次 build 全量重扫。
  Map<String, int> _typeCounts = const <String, int>{};
  int total = 0;
  bool loadingAuthors = true;
  bool loadingWorks = true;
  bool loadingMore = false;
  String? err;

  /// 「卡片快速刷新」第 4 步：本库索引被重建后，作品/作者都回到第一页重拉。
  late final ValueNotifier<int> _libRev = ValueNotifier<int>(0);

  /// 作品网格 / 作者网格自己的可用尺寸（0.9.300）。
  ///
  /// 此前两个预热入口都拿 `MediaQuery.size`（整个窗口）：本页网格上方压着
  /// TabBar + 搜索框/筛选行，实际可用高度常只有窗口的七成——按窗口算两屏
  /// 就会多拉一整行看不见的封面/头像。预热的几何必须是网格自己的约束。
  /// 布局阶段只写字段、不 `setState`（与作者页头部测量同一做法）。
  Size? _worksViewport;
  Size? _authorsViewport;

  void _onLibDataChanged() {
    final v = LibDataRevision.revisionOf(widget.basic.id);
    if (v == _libRev.value) return;
    _libRev.value = v;
    if (!mounted) return;
    _worksScroll.jumpTo(0);
    _loadAuthors();
    _loadAvatars();
    _loadAuthorStats();
    _loadWorks(reset: true);
  }

  @override
  void initState() {
    super.initState();
    _worksScroll.addListener(_onScroll);
    _tabs.addListener(_onTabChanged);
    LibDataRevision.listenable(widget.basic.id).addListener(_onLibDataChanged);
    _libRev.value = LibDataRevision.revisionOf(widget.basic.id);
    _loadAuthors();
    _loadAvatars();
    _loadAuthorStats();
    _loadWorks(reset: true);
  }

  @override
  void dispose() {
    LibDataRevision.listenable(widget.basic.id)
        .removeListener(_onLibDataChanged);
    _tabs.removeListener(_onTabChanged);
    _libRev.dispose();
    _worksScroll.removeListener(_onScroll);
    _worksScroll.dispose();
    _authorScroll.dispose();
    _authorSearch.dispose();
    _tabs.dispose();
    super.dispose();
  }

  /// 作者 tab 切进来时才预热：停在作品页时不必先占解码额度。
  void _onTabChanged() {
    if (_tabs.index == 1) _scheduleAuthorPrefetch();
  }

  /// 三份数据（作者列表 / `av` / 兜底图）任一到手都可能补齐首屏头像，
  /// 都已就绪时发一次预热；不在 build 里做，放帧后。
  void _scheduleAuthorPrefetch() {
    if (!mounted || authors.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchAuthors();
    });
  }

  void _onScroll() {
    if (!_worksScroll.hasClients) return;
    final pos = _worksScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) _loadWorks();
  }

  /// 新建作者：选基础库（可多选）+ 名字，在选中的每个基础库下建 `@作者` 目录。
  ///
  /// owner 2026-11-28：「新建时可以选择在哪些基础库有作品，列出所属单元库下
  /// 所有基础库以供选择，选择后本地自动创建好文件夹」。
  ///
  /// 只调服务端已有的 `POST /api/unit/authors/create`（它幂等：目录已存在返回
  /// 409，不改任何已有文件）。不失败已创建的那几个。
  Future<void> _openNewAuthor() async {
    final basics = widget.siblingBasics;
    if (basics.isEmpty) return;
    final picked = <String>{widget.basic.id}; // 默认带上本页这个库
    final nameCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('新建作者'),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                key: const ValueKey('new-author-name'),
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '作者名（会建成 @作者名 目录）',
                  isDense: true,
                ),
                onChanged: (_) => setD(() {}),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('哪些基础库有他的作品（可多选）',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final b in basics)
                      CheckboxListTile(
                        key: ValueKey('new-author-lib-${b.id}'),
                        dense: true,
                        value: picked.contains(b.id),
                        title: Text(b.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        onChanged: (v) => setD(() {
                          if (v == true) {
                            picked.add(b.id);
                          } else {
                            picked.remove(b.id);
                          }
                        }),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
              key: const ValueKey('new-author-ok'),
              onPressed: (nameCtl.text.trim().isEmpty || picked.isEmpty)
                  ? null
                  : () => Navigator.pop(c, true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final dir = authorDirForName(nameCtl.text);
    final bad = authorDirError(dir);
    if (bad != null) {
      _snack(bad);
      return;
    }
    var made = 0;
    var existed = 0;
    final failed = <String>[];
    for (final lib in picked) {
      try {
        final r = await http
            .post(
              Uri.parse(unitAuthorCreateUrl(widget.urlOf('').toString())),
              headers: {
                ...widget.headersOf(lib),
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'lib': lib, 'name': nameCtl.text.trim()}),
            )
            .timeout(const Duration(seconds: 15));
        if (r.statusCode == 409) {
          existed++;
        } else if (r.statusCode == 200) {
          made++;
        } else {
          failed.add(lib);
        }
      } catch (_) {
        failed.add(lib);
      }
    }
    if (!mounted) return;
    _snack(authorCreateSummary(
        made: made, existed: existed, failed: failed.length));
    if (made > 0) await _loadAuthors();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadAuthors() async {    try {
      final r = await http
          .get(widget.urlOf('/api/lib/${widget.basic.id}/index.json',
              lib: widget.basic.id),
              headers: widget.headersOf(widget.basic.id))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) throw httpErrorText(r.statusCode);
      // 解析放到 isolate：避免大 payload 在 UI 线程卡顿/掉帧。
      final j = await compute(_parseWorksPayload, r.bodyBytes);
      final list = <Map<String, dynamic>>[];
      for (final a in listOf(j['authors'])) {
        if (a is Map) list.add(Map<String, dynamic>.from(a));
      }
      // 有首字母索引条后，列表必须按名称分组排列，否则「跳到某字母」
      // 会落在列表中间、上下都还有该字母的作者。作品数只作为同组内的次序。
      // 首字母分组只按名称分；同组内按作品数降序。两者都相等时（跨库同名
      // 作者合并后很常见，比如两个库各有一位「@小林」且作品数相同）没有
      // 任何次序依据——`List.sort` 不稳定，于是「刷新一下两位作者换位置」。
      // 用稳定排序保持服务端下发顺序：结果可复现，且不会因为多一条无关
      // 作者而把整段顺序重排。
      stableSort(list, (x, y) {
        final c = compareAuthorNames(
            '${x['name'] ?? x['name_raw'] ?? ''}', '${y['name'] ?? y['name_raw'] ?? ''}');
        if (c != 0) return c;
        return intOf(y['works']).compareTo(intOf(x['works']));
      });
      if (!mounted) return;
      setState(() {
        authors = list;
        _authorShownCache = null;
        loadingAuthors = false;
      });
      // 作者 tab 已在前台就直接预热首屏头像（从其它页返回/搜索后也一样）。
      if (_tabs.index == 1) _scheduleAuthorPrefetch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingAuthors = false;
        err = errorText(e);
      });
    }
  }

  /// 作者搜索结果（本地即时过滤，缓存到搜索词/源列表变化为止）。
  List<Map<String, dynamic>> get _shownAuthors {
    final cached = _authorShownCache;
    if (cached != null) return cached;
    final q = _authorQuery;
    final list = q.trim().isEmpty
        ? List<Map<String, dynamic>>.from(authors)
        : authors
            .where((a) => authorMatchesQuery(
                '${a['name'] ?? a['name_raw'] ?? ''}', q))
            .toList(growable: false);
    _authorShownCache = list;
    _authorShownKeys = [
      for (final a in list) '${a['name'] ?? a['name_raw'] ?? ''}',
    ];
    return list;
  }

  void _setAuthorQuery(String v) {
    if (v == _authorQuery) return;
    setState(() {
      _authorQuery = v;
      _authorShownCache = null;
    });
    if (_authorScroll.hasClients) _authorScroll.jumpTo(0);
    _scheduleAuthorPrefetch();
  }

  void _clearAuthorQuery() {
    if (_authorQuery.isEmpty) return;
    _authorSearch.clear();
    _setAuthorQuery('');
  }

  /// 作者头像索引：`/api/authors.json` 的 `av`（索引文件里没有头像）。
  Future<void> _loadAvatars() async {
    try {
      final r = await http
          .get(widget.urlOf('/api/authors.json', lib: widget.basic.id),
              headers: widget.headersOf(widget.basic.id))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final j = jsonOf(r);
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
      // `av` 通常晚于作者列表到达：到了再补一次首屏预热（去重表会挡重复）。
      if (_tabs.index == 1) _scheduleAuthorPrefetch();
    } catch (_) {}
  }

  /// 兜底头像：每个作者第一件作品的缩略图（作品分页更新时重建）。
  void _rebuildAuthorFallback() {
    _authorFallback.clear();
    addFirstThumbPerAuthor(_authorFallback, works, thumbOf: _thumbOf);
  }

  Future<void> _loadAuthorStats() async {
    try {
      final r = await http
          .get(widget.urlOf('/api/author_stats.json', lib: widget.basic.id),
              headers: widget.headersOf(widget.basic.id))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final j = jsonOf(r);
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
      if (r.statusCode != 200) throw httpErrorText(r.statusCode);
      final j = jsonOf(r);
      final batch = listOf(j['works']);
      if (!mounted) return;
      setState(() {
        if (reset) works = [];
        works.addAll(batch);
        total = intOf(j['total']);
        _filteredCache = null;
        loadingWorks = false;
        loadingMore = false;
        // 类型数量只在作品变化时算一次（原来是每次 build 扫 4 遍全列表）。
        _typeCounts = workTypeCounts(works);
        // 头像兜底跟着作品更新；分页追加时只处理新批次，避免 O(n²) 全量重扫。
        if (reset) {
          _rebuildAuthorFallback();
        } else {
          addFirstThumbPerAuthor(_authorFallback, batch, thumbOf: _thumbOf);
        }
      });
      if (reset) _prefetchFirstScreen();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingWorks = false;
        loadingMore = false;
        if (err == null) err = errorText(e);
      });
    }
  }


  static String _kindsLabel(Map<String, dynamic> a) {
    final k = a['kinds'];
    if (k is! Map || k.isEmpty) return '';
    int v = 0, p = 0, c = 0;
    for (final e in k.entries) {
      final key = '${e.key}';
      final n = intOf(e.value);
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
        // 0.9.352：这里原来自拼 `stripIndex(b.name)`，绕过了库名唯一出口。
        // 名字是纯空格时标题整条空白；名字里带旧的「抖音收藏」时这一页仍
        // 原样露出，而设置页/网络设置那页已经按 `displayLibraryName` 回落 id
        // ——同一个库两页两个名字。现在与其它页同一个出口。
        title: Text(libraryDisplayName(b.id, b.name),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          const HomeAction(),
          // owner 2026-11-28：「新建作者怎么还没添加，加到基础库首页右上角，
          // 新建时可以选择在哪些基础库有作品，列出所属单元库下所有基础库以供
          // 选择，选择后本地自动创建好文件夹」。
          //
          // 没有同级基础库列表时不显示（不拿本页单个库去猜）。
          if (widget.siblingBasics.isNotEmpty)
            IconButton(
              key: const ValueKey('basic-new-author'),
              tooltip: '新建作者',
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: _openNewAuthor,
            ),
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
            Tab(
                key: const ValueKey('basic-tab-works'),
                text: '作品 ${formatCount(total > 0 ? total : b.works)}'),
            Tab(
                key: const ValueKey('basic-tab-authors'),
                text:
                    '作者 ${loadingAuthors ? '' : formatCount(authors.length)}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _worksView(),
          _authorsView(),
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
    final shown = _shownAuthors;
    final letters = authorIndexLetters(_authorShownKeys);
    final starts = authorGroupStarts(_authorShownKeys);
    // 索引条是否可见只有 `authorIndexBarVisible` 一处判定：网格内边距、
    // 条带本身、点字母跳转三处都读它，不会出现「条带画了但网格没让位」。
    final hasIndexBar = authorIndexBarVisible(letters);
    return Column(children: [
      _authorSearchBar(),
      Expanded(
        child: LayoutBuilder(builder: (c, cons) {
          // 作者网格自己的约束即预热几何（`_authorsViewport`）：此前预热拿窗口
          // 尺寸，而本页上方还有 TabBar 与搜索框，多算一整行。
          if (cons.biggest != _authorsViewport) {
            _authorsViewport = cons.biggest;
            _scheduleAuthorPrefetch();
          }
          if (shown.isEmpty) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('无匹配作者',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 8),
                TextButton(
                    key: const ValueKey('basic-author-empty-clear'),
                    onPressed: _clearAuthorQuery,
                    child: const Text('清除搜索')),
              ]),
            );
          }
          return Stack(children: [
        GridView.builder(
          controller: _authorScroll,
          // 右侧让出索引条宽度（≥28dp）：字母条只占右边缘条带，
          // 但卡片不能被它压住，否则最后一列点击会被抢。
          padding: basicAuthorGridPadding(hasIndexBar: hasIndexBar),
          gridDelegate: kBasicAuthorGrid.delegate,
          itemCount: shown.length,
          itemBuilder: (c, i) {
        final a = shown[i];
        final name = '${a['name'] ?? a['name_raw'] ?? ''}'.trim();
        final sub = _kindsLabel(a);
        final scheme = Theme.of(c).colorScheme;
        return Material(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          // 与作者总览卡同一个圆角（`card_metrics.kCardRadius`），
          // 此前这里是第三份字面量 12。
          borderRadius: BorderRadius.circular(kCardRadius),
          child: InkWell(
            key: ValueKey('basic-author-${a['id'] ?? i}'),
            borderRadius: BorderRadius.circular(kCardRadius),
            onTap: () => widget.onOpenAuthor(name),
            child: Padding(
              padding: kBasicAuthorCardPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _authorAvatar(
                    key: ValueKey('basic-author-avatar-${a['id'] ?? i}'),
                    context: c,
                    name: name,
                  ),
                  const SizedBox(height: 6),
                  // 词条：媒体库（若有）→ 单元库（去序号）→ 作者等级，与作者总览卡
                  // **同一套渲染**（0.9.291：此前这里是两个手写 Container—圆角 4、
                  // 无 emoji、无层级边框、等级字重不同，于是同一作者在两页词条长得不一样）。
                  // 数据来源仍是本页自己的 `sourceLabel` 与 `_authorStats`；
                  // 可以统一的是渲染，不是每个作者属于哪个库。
                  //
                  // owner 2026-11-27：媒体库这一级由调用方按单元库树注入
                  // （本页只有基础库，拿不到父级）。
                  AuthorBadgeRow(
                    unitLabel: widget.sourceLabel,
                    unitColor: widget.sourceColor,
                    unitId: widget.sourceUnitId,
                    extraChips: <BadgeChipSpec>[
                      if (widget.sourceMediaId.isNotEmpty &&
                          widget.sourceMediaLabel.isNotEmpty)
                        BadgeChipSpec(
                          label: widget.sourceMediaLabel,
                          color: widget.sourceMediaColor,
                          unitId: widget.sourceMediaId,
                          kind: LibEntryKind.top,
                        ),
                    ],
                    grade: AuthorGrade.fromStats(
                        _authorStats[name],
                        works: intOf(a['works'])),
                  ),
                  const SizedBox(height: 4),
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
                  Text('${formatCount(intOf(a['works']))} 作品',
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
        ),
            if (hasIndexBar)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: kAuthorIndexBarWidth,
                child: _authorIndexBar(letters, starts, cons.maxWidth),
              ),
          ]);
        }),
      ),
    ]);
  }

  /// 作者搜索框（本地过滤，不发请求）。
  Widget _authorSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SizedBox(
        height: kBasicAuthorSearchHeight,
        child: TextField(
          key: const ValueKey('basic-author-search'),
          controller: _authorSearch,
          onChanged: _setAuthorQuery,
          textInputAction: TextInputAction.search,
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: '搜索本库作者',
            hintStyle: const TextStyle(fontSize: 12.5, color: Colors.grey),
            prefixIcon: const Icon(Icons.search, size: 18),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 34, minHeight: 34),
            suffixIcon: _authorQuery.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('basic-author-search-clear'),
                    tooltip: '清除',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: _clearAuthorQuery,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 30, minHeight: 30),
                  ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  /// 右侧竖排首字母索引条；点字母或按住上下滑动滚到该字母首位作者。
  Widget _authorIndexBar(
      List<String> letters, Map<String, int> starts, double viewportWidth) {
    return AuthorLetterBar(
      keyPrefix: 'basic-author-index-',
      letters: letters,
      width: kAuthorIndexBarWidth,
      // 条带已经只在可见时挂载（`authorIndexBarVisible`），这里不再重复判定。
      onLetter: (l) => _jumpToAuthorLetter(l, starts, viewportWidth, true),
    );
  }

  void _jumpToAuthorLetter(String letter, Map<String, int> starts,
      double viewportWidth, bool hasIndexBar) {
    final idx = starts[letter];
    if (idx == null) return;
    final max = _authorScroll.hasClients
        ? _authorScroll.position.maxScrollExtent
        : 0.0;
    final target = authorGridOffsetForIndex(
      index: idx,
      viewportWidth: viewportWidth,
      maxScrollExtent: max,
      // 与网格实际内边距同源：索引条可见时右侧多让一条条带。
      paddingRight: authorGridPadRight(hasIndexBar: hasIndexBar),
    );
    _authorScroll.animateTo(target,
        duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  /// 作者卡片头像：手动设置 > 爬虫 `av` > 兜底图（该作者第一件作品的缩略图），
  /// 都没有时回退首字占位。
  ///
  /// 0.9.290：绘制与优先级合成只有一处（`author_avatar_view`）。此前本页自己
  /// 画了一遍，**不监听** `AuthorAvatarStore`——在作者主页手动设的头像，回到
  /// 这里仍然是旧图（真缺陷）；占位样式与解码宽度也都是第二套。
  Widget _authorAvatar({
    Key? key,
    required BuildContext context,
    required String name,
    double size = kAvatarBasicAuthorSize,
  }) {
    // 本页不是 `main.AuthorAvatar`，手动头像的变更信号要自己接。
    return AnimatedBuilder(
      animation: AuthorAvatarStore.instance,
      builder: (c, _) {
        final picked = resolveAvatarSource(
          // `manualAvatarFor`：手动头像有 uid 时按 `uid:` 键存（改名后仍
          // 找得到），本页原先只按名字查，改名后这里退回爬虫图。
          manual: manualAvatarFor(name),
          fallback: pickAuthorAvatar(
              av: _authorAv[name] ?? '', fallback: _authorFallback[name] ?? ''),
          fallbackLib: widget.basic.id,
        );
        return AuthorAvatarView(
          key: key,
          name: name,
          mediaPath: picked.path,
          lib: picked.lib,
          size: size,
          urlOf: widget.mediaUrlOf,
          headersOf: widget.headersOf,
        );
      },
    );
  }

  /// 作者 tab 首屏头像预热（0.9.290）。
  ///
  /// 此前本页是**唯一没有预热入口**的头像列表：首屏逐张请求，先露占位再跳图。
  /// 整条链复用 `avatar_prefetch.prefetchAvatarItems`（与排行榜、作者总览同一
  /// 份），本页只决定「预热哪些作者」与「几何用哪个网格」。
  void _prefetchAuthors() {
    if (!mounted || authors.isEmpty) return;
    final shown = _shownAuthors;
    if (shown.isEmpty) return;
    // 网格还没排过（首帧）/窗口尺寸未知时不预热：拿窗口尺寸顶替一次就会
    // 多拉一整行，而且再也不会被纠正。尺寸一到手 LayoutBuilder 会重排预热。
    final viewport = _authorsViewport;
    if (viewport == null) return;
    final mq = MediaQuery.of(context);
    final hasIndexBar = authorIndexBarVisible(authorIndexLetters(_authorShownKeys));
    // 几何与 `_authorsView` 的 delegate / padding 同源：只读
    // `kBasicAuthorGrid` 与 `basicAuthorGridPadding`，不自己挑数字。
    final n = kBasicAuthorGrid.prefetchCount(
      viewport,
      padding: basicAuthorGridPadding(hasIndexBar: hasIndexBar),
    );
    if (n <= 0) return;
    String avOf(Map<String, dynamic> a) =>
        _authorAv['${a['name'] ?? a['name_raw'] ?? ''}'] ?? '';
    String fbOf(Map<String, dynamic> a) =>
        _authorFallback['${a['name'] ?? a['name_raw'] ?? ''}'] ?? '';
    prefetchAvatarItems(
      [
        for (final a in shown.take(n))
          (path: pickAuthorAvatar(av: avOf(a), fallback: fbOf(a)),
              lib: widget.basic.id),
      ],
      limit: n,
      displaySize: kAvatarBasicAuthorSize,
      devicePixelRatio: mq.devicePixelRatio,
      urlOf: (path, lib) => widget.mediaUrlOf(path, lib: lib),
      headersOf: (lib) => widget.headersOf(lib),
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
      _worksTopBar(shown),
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
    // 滚动时收紧缩略图预取并发（默认 4 → 2），停下立刻恢复。
    return ScrollDecodeScope(
      // 网格自己的约束既是排布依据，也是预热的几何来源（`_worksViewport`）。
      child: LayoutBuilder(builder: (context, cons) {
        if (cons.biggest != _worksViewport) {
          _worksViewport = cons.biggest;
          // 帧后发：不在 build 里启动图片请求。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _prefetchFirstScreen();
          });
        }
        return GridView.builder(
          controller: _worksScroll,
          padding: kBasicWorkGridPadding,
          gridDelegate: kBasicWorkGrid.delegate,
          itemCount: filtered.length + (loadingMore ? 1 : 0),
          itemBuilder: (c, i) {
            if (i >= filtered.length) {
              return const Center(
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)));
            }
            final w = filtered[i];
            final cover = _coverOf(w);
            return WorkCard(
              key: ValueKey('basic-work-${w is Map ? w['id'] : i}'),
              title: w is Map ? '${w['ti'] ?? ''}' : '',
              typeLabel: _typeLabel(_workType(w)),
              coverUrl: cover,
              headers: widget.headersOf(widget.basic.id),
              onTap: widget.onPlay == null
                  ? null
                  : () => widget.onPlay!(filtered, i),
            );
          },
        );
      }),
    );
  }

  /// 封面统一走 work_cover：th → 图文首图 → 视频抽帧（带版本参数避开旧缓存）。
  String _coverOf(dynamic w) => workCoverUrl(
        w,
        lib: widget.basic.id,
        urls: standardCoverUrls(
          lib: widget.basic.id,
          mediaUrlOf: widget.mediaUrlOf,
          urlOf: widget.urlOf,
        ),
      );

  /// 首屏缩略图预热（0.9.26）：作品一到手就先按显示宽度拉首屏可见封面，
  /// provider 与 `WorkCard` 完全一致（同 URL + 同 `ResizeImage` 宽度），
  /// 因此卡片渲染时直接命中缓存，不再先空白再逐张请求。
  void _prefetchFirstScreen() {
    if (!mounted || works.isEmpty) return;
    // 同上：尺寸未知（首帧前）不预热，等 `_worksGrid` 的 LayoutBuilder 报尺寸。
    final viewport = _worksViewport;
    if (viewport == null) return;
    final mq = MediaQuery.of(context);
    final shown = filtered;
    final headers = widget.headersOf(widget.basic.id);
    // 0.9.288：整条链（张数 → 封面 → w= → 解码宽度 → 入队）只有
    // `work_card_prefetch.prefetchWorkCovers` 一处。本页只负责「取哪些作品」
    // 与「带哪个库的鉴权头」。几何与 `_worksGrid` 的 delegate / padding 同源
    // （`kBasicWorkGrid` + `kBasicWorkGridPadding`）。
    prefetchWorkCovers(
      // 网格自己的尺寸（`_worksViewport`），不是窗口：上方还有 TabBar 与
      // 筛选行，按窗口算会把屏幕外的一整行也预热进来。
      viewport: viewport,
      grid: kBasicWorkGrid,
      padding: kBasicWorkGridPadding,
      devicePixelRatio: mq.devicePixelRatio,
      maxItems: shown.length,
      // 惰性 `map`：只有真正入队的那几张才去跑封面链（`_coverOf` 要按
      // th → 图文首图 → 视频抽帧 逐级判断）。写成列表字面量会把已渲染的
      // 60 张全部算一遍，再只用前 24 张的结果。
      items: shown.map((w) => (cover: _coverOf(w), headers: headers)),
    );
  }

  // ---- 作品类型筛选（全部/视频/图文/合集，多选，本地过滤） ----

  // 全站统一的类型顺序与文案：视频、图片、合集、图文。
  static const List<String> _typeOrder = workFilterOrder;

  static String _workType(dynamic w) => workFilterType(w);

  static String _typeLabel(String type) => workFilterLabel(type);

  /// 本地过滤后的作品列表；筛选为空时即全部作品。
  /// 排序：入库时间（默认，新的在前）、播放量、标题。
  WorkSort _sortMode = WorkSort.ingest;

  /// 排序/筛选结果缓存：作品分页追加、类型筛选、排序方式变化时置空，
  /// build 与首屏预热只读缓存，避免每次重排整张列表（大库上千件）。
  List<dynamic>? _filteredCache;

  List<dynamic> get filtered => _filteredCache ??=
      sortWorks(filterWorksByType(works, _typeFilter), _sortMode);

  int _countOf(String type) => _typeCounts[type] ?? 0;

  void _toggleType(String type) {
    setState(() {
      if (!_typeFilter.add(type)) _typeFilter.remove(type);
      _filteredCache = null;
    });
    _prefetchFirstScreen();
  }

  void _clearTypeFilter() {
    if (_typeFilter.isEmpty) return;
    setState(() {
      _typeFilter.clear();
      _filteredCache = null;
    });
    _prefetchFirstScreen();
  }

  /// owner 2026-11-22：类型筛选、排序、总数压成一行（约 40dp），
  /// 把竖向空间让给作品网格。类型仍是多选，排序仍保留三项。
  Widget _worksTopBar(List<dynamic> shown) {
    final typeLabel = _typeFilter.isEmpty
        ? '类型筛选'
        : '类型 ${_typeFilter.length}';
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(children: [
          MenuAnchor(
            key: const ValueKey('basic-type-menu-anchor'),
            alignmentOffset: const Offset(0, 4),
            menuChildren: [
              MenuItemButton(
                key: const ValueKey('basic-type-all'),
                onPressed: _clearTypeFilter,
                leadingIcon: Icon(
                  _typeFilter.isEmpty
                      ? Icons.check
                      : Icons.check_box_outline_blank,
                  size: 16,
                ),
                // 「全部」是**该基础库的作品总数**，不是当前内存里的条数：
                // 旧写法插 `works.length`，分页只拉到 60 条时这里写「全部 60」，
                // 与上面 tab 的「作品 300」自相矛盾。total 不可用时退回已载入数。
                child: Text('全部 ${formatCount(total > 0 ? total : works.length)}',
                    style: const TextStyle(fontSize: 12)),
              ),
              for (final type in _typeOrder)
                CheckboxMenuButton(
                  key: ValueKey('basic-type-$type'),
                  value: _typeFilter.contains(type),
                  onChanged: _countOf(type) == 0 && !_typeFilter.contains(type)
                      ? null
                      : (_) => _toggleType(type),
                  child: Text('${_typeLabel(type)} ${_countOf(type)}',
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
            builder: (ctx, controller, _) => TextButton.icon(
              key: const ValueKey('basic-type-menu'),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.tune, size: 16),
              label: Text(typeLabel, style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(width: 2),
          MenuAnchor(
            key: const ValueKey('basic-sort-menu-anchor'),
            alignmentOffset: const Offset(0, 4),
            menuChildren: [
              for (final s in workSortOrder)
                MenuItemButton(
                  key: ValueKey('basic-sort-${s.name}'),
                  onPressed: () {
                    if (s == _sortMode) return;
                    setState(() {
                      _sortMode = s;
                      _filteredCache = null;
                    });
                    _prefetchFirstScreen();
                  },
                  leadingIcon: Icon(
                    s == _sortMode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 16,
                  ),
                  child: Text(workSortLabel(s),
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
            builder: (ctx, controller, _) => TextButton.icon(
              key: const ValueKey('basic-works-sort'),
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              icon: const Icon(Icons.sort, size: 16),
              label: Text(workSortLabel(_sortMode),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const Spacer(),
          Text(
              worksCountLabel(
                shown: shown.length,
                loaded: works.length,
                total: total,
                filtered: _typeFilter.isNotEmpty,
              ),
              key: const ValueKey('basic-works-count'),
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ),
    );
  }

  /// 作品缩略图：优先 `th`，其次图文首图 `m[0]`；视频无图时为空。
  /// 作者头像兜底图：现成缩略图优先，其次图文首图（与作品封面同一口径）。
  static String _thumbOf(dynamic w) => workCoverPath(w);
}
