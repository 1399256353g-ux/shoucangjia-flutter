import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'app_settings.dart';
import 'app_theme.dart';
import 'author_filter.dart';
import 'author_drag.dart';
import 'author_avatar.dart';
import 'author_filter_bar.dart';
import 'author_filter_ui.dart';
import 'author_grid.dart';
import 'author_grade.dart';
import 'basic_lib_page.dart';
import 'folder_structure_page.dart';
import 'background_pause.dart';
import 'collection_sync.dart';
import 'continue_watching.dart';
import 'cover_badges.dart';
import 'decode_fallback.dart';
import 'home_action.dart';
import 'lib_names.dart';
import 'infinite.dart';
import 'library_badge.dart';
import 'library_rank.dart';
import 'lib_cover.dart';
import 'loop_link.dart';
import 'library_tree.dart';
import 'unit_crawler_page.dart';
import 'unit_library.dart';
import 'unit_library_view.dart';
import 'work_card.dart';
import 'likes.dart';
import 'multi_server.dart';
import 'playback_flow.dart';
import 'pic_zoom.dart';
import 'playback_error.dart';
import 'text_fit.dart';
import 'ui_auto_hide.dart';
import 'ui_fade.dart';
import 'volume_control.dart';
import 'playback_menu.dart';
import 'player_controls.dart';
import 'preload_policy.dart';
import 'preload_plan.dart';
import 'swipe_control.dart';
import 'swipe_physics.dart';
import 'stage_tap.dart';
import 'star_store.dart';
import 'start_fade.dart';
import 'source_lib.dart';
import 'watch_progress.dart';
import 'work_forms.dart';
import 'work_plays.dart';
import 'work_safety.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  // G10：先载入观看记录，列表首帧就能显示「已看完」角标
  await WatchProgressStore.ensureLoaded();
  // G17：载入「继续观看」，主页首帧直接显示
  await ContinueWatchingStore.ensureLoaded();
  // L5-C：载入本机播放量，基础库自动封面首帧即可用
  await WorkPlaysStore.ensureLoaded();
  runApp(const App());
}

// 轻触震动：iOS/Android 生效，桌面端静默忽略
void hapticTap() {
  try {
    HapticFeedback.lightImpact();
  } catch (_) {}
}

// 选择震动（拖动进度条跨段时用，比 lightImpact 更轻）
void hapticSelect() {
  try {
    HapticFeedback.selectionClick();
  } catch (_) {}
}

// 动图判断：GIF 必须交给 Image.network 才能播放动画，
// CachedNetworkImage 只取首帧。
bool isGifPath(String path) {
  final low = path.toLowerCase();
  return low.endsWith('.gif') || low.contains('.gif?');
}

class Cfg {
  String base = '';
  String user = 'zzx';
  String pass = '';
  String lib = '';
  String libName = '';

  /// J7：库 → 连接映射。同一库 id 在聚合时已去重，这里保存最终来源的 IP。
  final Map<String, Map<String, String>> _bindings = {};

  void setBindings(Map<String, Map<String, String>> bindings) {
    _bindings
      ..clear()
      ..addAll(bindings);
  }

  void bindLibrary(String libId, String base,
      {String? user, String? pass, String? server}) {
    final b = normalizeBase(base);
    if (libId.isEmpty || b.isEmpty) return;
    _bindings[libId] = {
      'base': b,
      'user': user ?? this.user,
      'pass': pass ?? this.pass,
      'server': server ?? '',
    };
  }

  String baseFor([String? libId]) {
    final l = libId ?? lib;
    return _bindings[l]?['base'] ?? base;
  }

  Map<String, String> headersFor([String? libId]) {
    final b = _bindings[libId ?? lib];
    final u = b?['user'] ?? user;
    final p = b?['pass'] ?? pass;
    return {
      'Authorization': 'Basic ${base64Encode(utf8.encode('$u:$p'))}',
    };
  }

  /// 当前库所在连接的认证；没有绑定则回落到当前连接。
  Map<String, String> get headers => headersFor(lib);
  // lib 省略时用当前库；显式传入可查询其他库
  Uri u(String path, {String? lib}) {
    final l = lib ?? this.lib;
    final b = baseFor(l);
    if (b.isEmpty || l.isEmpty) return Uri.parse('$b$path');
    final sep = path.contains('?') ? '&' : '?';
    return Uri.parse('$b$path${sep}lib=${Uri.encodeQueryComponent(l)}');
  }

  // 媒体路径统一带库前缀：/media/<lib>/<相对路径>
  String media(String p, {String? lib}) {
    final l = lib ?? this.lib;
    if (l.isEmpty || !p.startsWith('/media/')) return p;
    final rest = p.substring(7);
    if (rest.startsWith('$l/')) return p;
    return '/media/${Uri.encodeComponent(l)}/$rest';
  }

  /// 媒体绝对地址：按作品所属库路由到对应 IP。
  String mediaUrl(String p, {String? lib}) =>
      '${baseFor(lib)}${media(p, lib: lib)}';
}

final cfg = Cfg();
final navKey = GlobalKey<NavigatorState>();

/// J9：作者来源词条所需的基础库映射与统计。
/// 一次加载后按库缓存，词条显示「基础库」名称（如「🦶」），不是大库名。
class LibMeta {
  final List<BasicLibRef> basics;
  final Map<String, dynamic> stats;

  /// J10：大库 id → 名称，用于作者筛选里的「大库」多选。
  final Map<String, String> bigNames;

  /// L5：单元库树（作者筛选与词条来源）。为空表示服务端未提供节点信息。
  final UnitLibrary? unitTree;

  /// 含基础库的单元库（深度优先，SECRET 最后）。
  final List<UnitLibrary> units;

  /// 基础库 id → 所属单元库 id。
  final Map<String, String> basicToUnit;

  const LibMeta({
    required this.basics,
    required this.stats,
    this.bigNames = const {},
    this.unitTree,
    this.units = const [],
    this.basicToUnit = const {},
  });

  static final Map<String, LibMeta> cache = <String, LibMeta>{};
  static final Map<String, Future<LibMeta>> _loading =
      <String, Future<LibMeta>>{};

  static Future<LibMeta> load(String lib) {
    final hit = cache[lib];
    if (hit != null) return Future.value(hit);
    return _loading.putIfAbsent(lib, () async {
      var basics = const <BasicLibRef>[];
      var stats = <String, dynamic>{};
      var bigNames = <String, String>{};
      UnitLibrary? unitTree;
      var units = const <UnitLibrary>[];
      var basicToUnit = const <String, String>{};
      try {
        final rs = await Future.wait([
          http.get(cfg.u('/api/libraries.json', lib: lib),
              headers: cfg.headers),
          http.get(cfg.u('/api/libraries', lib: lib), headers: cfg.headers),
          http.get(cfg.u('/api/author_stats.json', lib: lib),
              headers: cfg.headers),
          http.get(cfg.u('/api/nodes', lib: lib), headers: cfg.headers),
        ]).timeout(const Duration(seconds: 10));
        if (rs[0].statusCode == 200 && rs[1].statusCode == 200) {
          final lj = jsonDecode(rs[0].body);
          final reg = jsonDecode(rs[1].body);
          var base = '';
          if (reg is Map && reg['libraries'] is List) {
            for (final e in reg['libraries'] as List) {
              if (e is Map && '${e['id']}' == lib) {
                base = '${e['base'] ?? e['dir'] ?? ''}';
                break;
              }
            }
          }
          // `lib` 本身是基础库 id（基础库页/基础库作者页）时注册表里没有它，
          // 用库根作坐标系即可建出完整单元库树（只需基础库→单元库映射）。
          if (base.isEmpty && lj is Map) {
            final rootPath = '${lj['root'] ?? ''}'.trim();
            final raw = lj['basicLibraries'];
            if (rootPath.isNotEmpty && raw is List) {
              for (final e in raw) {
                if (e is Map && '${e['id']}' == lib) {
                  base = rootPath;
                  break;
                }
              }
            }
          }
          if (lj is Map && base.isNotEmpty) {
            final ljm = Map<String, dynamic>.from(lj);
            basics = basicsUnderBase(ljm, base);
            final bigs = ljm['bigLibraries'];
            if (bigs is List) {
              for (final e in bigs) {
                if (e is! Map) continue;
                final id = '${e['id'] ?? ''}';
                if (id.isEmpty) continue;
                bigNames[id] = '${e['name'] ?? id}';
              }
            }
            if (basics.isNotEmpty) {
              // 单元库节点的 rel 以库根（libraries.json `root`）为坐标系，
              // 而基础库默认按注册库 base 换算；两者不同源时按前缀永远匹配
              // 不上，词条会全部落到 SECRET。这里额外用库根坐标建一份
              // 「单元库归属」用的基础库列表。
              final root = '${ljm['root'] ?? ''}'.trim();
              final basicList = <BasicLib>[
                for (final b in basics)
                  BasicLib(
                      id: b.id,
                      name: b.name,
                      rel: b.rel,
                      bigId: b.bigId,
                      authors: 0,
                      works: 0),
              ];
              var unitBasics = basicList;
              if (root.isNotEmpty) {
                final full = <BasicLib>[];
                for (final b in basics) {
                  final rel = relUnderBase(root, b.path);
                  if (rel.isEmpty) continue;
                  full.add(BasicLib(
                      id: b.id,
                      name: b.name,
                      rel: rel,
                      bigId: b.bigId,
                      authors: 0,
                      works: 0));
                }
                if (full.isNotEmpty) unitBasics = full;
              }
              // 单元库＝owner 在「文件结构」里勾选的节点文件夹（/api/nodes），
              // 与主页使用同一份来源；只有节点为空时才退回 v2 分组。
              final marks = <String>[];
              if (rs[3].statusCode == 200) {
                try {
                  final nj = jsonDecode(utf8.decode(rs[3].bodyBytes));
                  final list = nj is Map ? nj['nodes'] : null;
                  if (list is List) {
                    for (final e in list) {
                      // /api/nodes 既可能是字符串，也可能是 {id,rel,name} 对象。
                      final s = (e is Map
                              ? '${e['rel'] ?? e['path'] ?? e['name'] ?? ''}'
                              : '$e')
                          .trim();
                      if (s.isNotEmpty) marks.add(s);
                    }
                  }
                } catch (_) {}
              }
              final nodes = marks.isEmpty
                  ? nodesFromV2(ljm, root: base)
                  : nodesFromMarks(marks);
              final tree = buildUnitTree(nodes: nodes, basics: unitBasics);
              if (tree != null) {
                unitTree = tree;
                units = flattenUnits(tree);
                basicToUnit = unitOfBasics(tree);
              }
            }
          }
        }
        if (rs[2].statusCode == 200) {
          final sj = jsonDecode(rs[2].body);
          if (sj is Map && sj['authors'] is Map) {
            stats = Map<String, dynamic>.from(sj['authors'] as Map);
          }
        }
      } catch (_) {}
      final meta = LibMeta(
          basics: basics,
          stats: stats,
          bigNames: bigNames,
          unitTree: unitTree,
          units: units,
          basicToUnit: basicToUnit);
      cache[lib] = meta;
      _loading.remove(lib);
      return meta;
    });
  }

  static void invalidate(String lib) {
    cache.remove(lib);
  }

  /// 基础库词条显示名：路径命中基础库时用其名称，否则回落到传入的库名。
  String labelFor(String mediaPath, String fallback) {
    final b = basicLibForMedia(basics, mediaPath);
    if (b == null) return '';
    return basicLibLabel(b, fallback);
  }

  /// 作者所属基础库 id（用于配色）；未命中返回空。
  String idFor(String mediaPath) =>
      basicLibForMedia(basics, mediaPath)?.id ?? '';

  /// 作者所属基础库 id：兼容库作用域路径（`/media/lib-015/...`）。
  String basicIdForPath(String mediaPath) => basicIdForMedia(basics, mediaPath);

  /// 按基础库 id 取词条（搜索结果直接带 `_bid`，无需按路径反查）。
  BasicLibRef? basicById(String id) {
    for (final b in basics) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// L5：作者所属单元库 id；无法匹配基础库时为空。
  /// 有基础库但没有节点归属时回落到顶级 `secret`。
  String unitIdFor(String mediaPath) {
    // 作者来源词条＝作者所属基础库的单元库：先由基础库反查单元库，
    // 这样 lib-001…lib-039 与 douyin 的基础库都走同一套口径。
    final basic = basicIdForPath(mediaPath);
    if (basic.isNotEmpty) {
      final unit = basicToUnit[basic];
      if (unit != null && unit.isNotEmpty) return unit;
    }
    // 兜底：按节点文件夹（单元库）路径匹配（旧数据、非基础库媒体）。
    final rel = decodeMediaRel(mediaPath);
    if (rel.isNotEmpty) {
      String bestRel = '';
      String bestId = '';
      for (final u in units) {
        final r = u.rel.trim();
        if (r.isEmpty) continue;
        if ((rel == r || rel.startsWith('$r/')) && r.length > bestRel.length) {
          bestRel = r;
          bestId = u.id;
        }
      }
      if (bestId.isNotEmpty) return bestId;
    }
    if (basic.isNotEmpty) return basicToUnit[basic] ?? 'secret';
    return rel.isEmpty ? '' : 'secret';
  }

  String unitNameOf(String id) {
    if (id.isEmpty) return '';
    if (id == 'secret') return 'SECRET';
    for (final u in units) {
      if (u.id == id) return u.name;
    }
    return id;
  }

  /// 单元库配色顺序（不含顶级 SECRET）。
  List<String> get unitOrder => [
        for (final u in units)
          if (u.id != 'secret') u.id
      ];

  Map<String, String> get unitNames =>
      {for (final u in units) u.id: unitNameOf(u.id)};

  /// J10：作者所属大库 id；无法匹配基础库时为空。
  String bigIdFor(String mediaPath) {
    final b = basicLibForMedia(basics, mediaPath);
    if (b == null) return '';
    if (b.bigId.isNotEmpty) return b.bigId;
    // 旧数据缺少 big_id 时按路径前缀回退到名称中含该前缀的大库。
    return '';
  }

  /// 作者作品类型集合（由外部类型索引提供作者名后取用）。
  Set<String> typesFor(Map<String, Set<String>> types, String author) =>
      types[author] ?? const <String>{};

  List<String> get order => basics.map((e) => e.id).toList();

  Map<String, String> get names => {
        for (final b in basics) b.id: basicLibLabel(b, b.name),
      };

  String gradeFor(String author, int works) =>
      AuthorGrade.fromStats(stats[author], works: works);
}

/// J10：作者作品类型索引。T3 起只走基础库索引
/// `/api/lib/<id>/index.json` 的 kinds（覆盖库内全部作品，无需逐作者请求）；
/// 旧「收藏夹」`/api/c/<idx>.json` 通道已移除。按注册库缓存，失败不阻断筛选。
final Map<String, Future<Map<String, Set<String>>>> _authorTypeCache = {};

Future<Map<String, Set<String>>> _authorTypesForLib(String lib) {
  return _authorTypeCache.putIfAbsent(lib, () async {
    try {
      final reg = await http
          .get(cfg.u('/api/libraries', lib: lib), headers: cfg.headers)
          .timeout(const Duration(seconds: 12));
      if (reg.statusCode != 200) return <String, Set<String>>{};
      final lj = await http
          .get(cfg.u('/api/libraries.json', lib: lib), headers: cfg.headers)
          .timeout(const Duration(seconds: 12));
      if (lj.statusCode != 200) return <String, Set<String>>{};
      final regJson = jsonDecode(utf8.decode(reg.bodyBytes));
      var base = '';
      if (regJson is Map && regJson['libraries'] is List) {
        for (final e in regJson['libraries'] as List) {
          if (e is Map && '${e['id']}' == lib) {
            base = '${e['base'] ?? ''}';
            break;
          }
        }
      }
      final libJson = jsonDecode(utf8.decode(lj.bodyBytes));
      if (base.isEmpty || libJson is! Map) return <String, Set<String>>{};
      final basics = basicsUnderBase(Map<String, dynamic>.from(libJson), base);
      final parts = await Future.wait(
          [for (final b in basics) _typesFromLibIndex(lib, b.id)]);
      return mergeAuthorTypes(parts);
    } catch (_) {
      return <String, Set<String>>{};
    }
  });
}

Future<Map<String, Set<String>>> _typesFromLibIndex(
    String lib, String basicId) async {
  try {
    final r = await http
        .get(cfg.u('/api/lib/$basicId/index.json', lib: lib),
            headers: cfg.headers)
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return <String, Set<String>>{};
    return authorTypesFromIndex(jsonDecode(utf8.decode(r.bodyBytes)));
  } catch (_) {
    return <String, Set<String>>{};
  }
}

/// 汇总多个注册库的作者类型。
Future<Map<String, Set<String>>> loadAuthorTypes(Iterable<String> libs) async {
  final parts =
      await Future.wait([for (final l in libs.toSet()) _authorTypesForLib(l)]);
  return mergeAuthorTypes(parts);
}

// 作者统计上报（播放/访问），失败静默，不影响播放
void postStat(String type, String author, {String? lib}) {
  if (cfg.base.isEmpty || author.isEmpty) return;
  try {
    http
        .post(cfg.u('/api/stats', lib: lib),
            headers: {...cfg.headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'type': type, 'author': author}))
        .ignore();
  } catch (_) {}
}

// 小水滴：每个作品每日 1 颗、每周 3 颗，服务端按作者累计
Future<Map<String, dynamic>?> fetchDropStatus(String id, {String? lib}) async {
  if (cfg.base.isEmpty || id.isEmpty) return null;
  try {
    final r = await http
        .get(cfg.u('/api/drops?id=${Uri.encodeQueryComponent(id)}', lib: lib),
            headers: cfg.headers)
        .timeout(const Duration(seconds: 8));
    final j = jsonDecode(r.body);
    if (j is Map) {
      return {'status': r.statusCode, ...Map<String, dynamic>.from(j)};
    }
  } catch (_) {}
  return null;
}

// 立即同步：collection（单个收藏夹）/ authors（作者信息）/ all（全部）
Future<Map<String, dynamic>?> startServerSync(
    {required String target,
    int? idx,
    String? author,
    String? lib,
    bool full = false}) async {
  if (cfg.base.isEmpty) return null;
  try {
    final r = await http
        .post(cfg.u('/api/sync', lib: lib),
            headers: {...cfg.headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'target': target,
              if (idx != null) 'idx': idx,
              if (author != null) 'author': author,
              'full': full,
            }))
        .timeout(const Duration(seconds: 15));
    final j = jsonDecode(r.body);
    if (j is Map)
      return {'status': r.statusCode, ...Map<String, dynamic>.from(j)};
  } catch (_) {}
  return null;
}

Future<Map<String, dynamic>?> serverSyncStatus() async {
  if (cfg.base.isEmpty) return null;
  try {
    final r = await http
        .get(cfg.u('/api/sync'), headers: cfg.headers)
        .timeout(const Duration(seconds: 8));
    final j = jsonDecode(r.body);
    if (j is Map) return Map<String, dynamic>.from(j);
  } catch (_) {}
  return null;
}

// 所有同步源页面共用：确认后同步全部同步源（NAS 后台），完成后回调刷新
Future<void> syncAllCollectionsFlow(BuildContext context,
    {Future<void> Function()? onFinished}) async {
  if (cfg.base.isEmpty) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('立即同步全部同步源'),
      content: const Text('将同步全部同步源的最新作品，并刷新封面、索引与作者信息。\n\n'
          '同步在 NAS 后台运行，可能需要较长时间；期间可继续浏览。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('开始同步')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final j = await startServerSync(target: 'all');
  if (!context.mounted) return;
  if (j == null || j['ok'] != true) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步启动失败：${j?['error'] ?? '网络错误'}')));
    return;
  }
  final exit = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _SyncAllProgressDialog(),
  );
  if (!context.mounted) return;
  if (exit != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(exit == 0 ? '全部同步源同步完成' : '同步结束（退出码 $exit），请查看日志')));
  }
  if (onFinished != null) await onFinished();
}

// 同步全部同步源进度：后台任务在 NAS 上运行，这里只轮询状态
class _SyncAllProgressDialog extends StatefulWidget {
  const _SyncAllProgressDialog();
  @override
  State<_SyncAllProgressDialog> createState() => _SyncAllProgressDialogState();
}

class _SyncAllProgressDialogState extends State<_SyncAllProgressDialog> {
  Timer? timer;
  bool done = false;
  int tries = 0;

  @override
  void initState() {
    super.initState();
    _poll();
    timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  Future<void> _poll() async {
    if (done) return;
    final s = await serverSyncStatus();
    if (!mounted || done) return;
    if (s == null) {
      tries++;
      if (tries > 5) _finish(-1);
      return;
    }
    tries = 0;
    if (s['running'] == true) return;
    _finish((s['exit'] as num?)?.toInt() ?? -1);
  }

  void _finish(int exit) {
    if (done || !mounted) return;
    done = true;
    timer?.cancel();
    Navigator.of(context).pop(exit);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('正在同步全部同步源'),
      content: const Row(children: [
        SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 14),
        Expanded(
            child: Text('同步任务已在 NAS 后台启动，完成后会自动刷新。',
                style: TextStyle(fontSize: 13))),
      ]),
      actions: [
        TextButton(
            onPressed: () {
              done = true;
              timer?.cancel();
              Navigator.of(context).pop();
            },
            child: const Text('转到后台')),
      ],
    );
  }
}

Future<Map<String, dynamic>?> sendDrop(String id, String author,
    {String? lib}) async {
  if (cfg.base.isEmpty || id.isEmpty || author.isEmpty) return null;
  try {
    final r = await http
        .post(cfg.u('/api/drops', lib: lib),
            headers: {...cfg.headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'id': id, 'author': author}))
        .timeout(const Duration(seconds: 8));
    final j = jsonDecode(r.body);
    if (j is Map) {
      return {'status': r.statusCode, ...Map<String, dynamic>.from(j)};
    }
  } catch (_) {}
  return null;
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final sp = await SharedPreferences.getInstance();
    final legacyBase = sp.getString('base') ?? '';
    cfg.user = sp.getString('user') ?? 'zzx';
    cfg.pass = sp.getString('pass') ?? '';
    final servers = migrateLegacy(
      servers: decodeServers(sp.getString('servers_v1')),
      base: legacyBase,
      user: cfg.user,
      pass: cfg.pass,
    );
    if (servers.isNotEmpty) {
      await sp.setString('servers_v1', encodeServers(servers));
    }
    final activeId = sp.getString('active_server_v1') ?? '';
    ServerConn? active;
    for (final s in servers) {
      if (s.id == activeId) {
        active = s;
        break;
      }
    }
    active ??= servers.isEmpty ? null : servers.first;
    if (active != null) {
      cfg.base = active.base;
      cfg.user = active.user;
      cfg.pass = active.pass;
    }
    cfg.setBindings(decodeBindings(sp.getString('lib_bindings_v1')));
    cfg.lib = sp.getString('lib') ?? '';
    await AppSettings.load();
    await AppTheme.load();
    if (mounted) setState(() => ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    // 主题选取即时生效：AppTheme.current 变化会重建 MaterialApp（设置页预览用）。
    return ValueListenableBuilder<String>(
      valueListenable: AppTheme.current,
      builder: (context, _, __) => MaterialApp(
        title: 'Dizi',
        navigatorKey: navKey,
        // 主题里带显式 emoji 字体回退链：Windows/Android/iOS 各自命中本机彩色
        // emoji 字体，避免收藏夹名（如「🦶」）或作者名里的 emoji 显示成方框。
        theme: AppTheme.themeData,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
            navKey.currentState?.maybePop();
            return null;
          }),
        },
        home: cfg.base.isEmpty ? const SettingsPage() : const HomePage(),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<ServerConn> servers = [];
  String activeId = '';
  final Map<String, String> testMsg = {};
  final Map<String, bool> testOk = {};
  final Set<String> testing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sp = await SharedPreferences.getInstance();
    final list = migrateLegacy(
      servers: decodeServers(sp.getString('servers_v1')),
      base: sp.getString('base') ?? '',
      user: sp.getString('user') ?? 'zzx',
      pass: sp.getString('pass') ?? '',
    );
    final active = sp.getString('active_server_v1') ?? '';
    if (!mounted) return;
    setState(() {
      servers = list;
      activeId = list.any((s) => s.id == active)
          ? active
          : (list.isEmpty ? '' : list.first.id);
    });
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('servers_v1', encodeServers(servers));
    await sp.setString('active_server_v1', activeId);
    ServerConn? active;
    for (final s in servers) {
      if (s.id == activeId) active = s;
    }
    active ??= servers.isEmpty ? null : servers.first;
    if (active != null) {
      cfg.base = active.base;
      cfg.user = active.user;
      cfg.pass = active.pass;
      await sp.setString('base', active.base);
      await sp.setString('user', active.user);
      await sp.setString('pass', active.pass);
    } else {
      cfg.base = '';
      await sp.setString('base', '');
    }
  }

  Future<void> _test(ServerConn s) async {
    setState(() => testing.add(s.id));
    final sw = Stopwatch()..start();
    try {
      final headers = {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${s.user}:${s.pass}'))}',
      };
      final rs = await Future.wait([
        http
            .get(Uri.parse('${s.base}/api/index.json'), headers: headers)
            .timeout(const Duration(seconds: 8)),
        http
            .get(Uri.parse('${s.base}/api/libraries.json'), headers: headers)
            .timeout(const Duration(seconds: 8)),
      ]);
      if (rs[0].statusCode != 200) throw Exception('HTTP ${rs[0].statusCode}');
      final cols =
          (jsonDecode(rs[0].body)['collections'] as List?)?.length ?? 0;
      var basics = 0;
      if (rs[1].statusCode == 200) {
        final j = jsonDecode(rs[1].body);
        if (j is Map) basics = (j['basicLibraries'] as List?)?.length ?? 0;
      }
      sw.stop();
      if (mounted) {
        setState(() {
          testOk[s.id] = true;
          testMsg[s.id] =
              '连接成功 · $cols 同步源 · $basics 基础库 · ${sw.elapsedMilliseconds}ms';
        });
      }
    } catch (e) {
      sw.stop();
      if (mounted) {
        setState(() {
          testOk[s.id] = false;
          testMsg[s.id] = '连接失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => testing.remove(s.id));
    }
  }

  Future<void> _edit([ServerConn? old]) async {
    final label = TextEditingController(text: old?.label ?? '');
    final base =
        TextEditingController(text: old?.base ?? 'http://192.168.2.4:8090');
    final user = TextEditingController(text: old?.user ?? cfg.user);
    final pass = TextEditingController(text: old?.pass ?? cfg.pass);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(old == null ? '添加网络连接' : '编辑网络连接'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: label,
                decoration: const InputDecoration(
                    labelText: '名称（可选）', hintText: '家里 / 公司 / 备用 NAS')),
            const SizedBox(height: 8),
            TextField(
                controller: base,
                decoration: const InputDecoration(
                    labelText: '地址', hintText: 'http://192.168.2.4:8090')),
            const SizedBox(height: 8),
            TextField(
                controller: user,
                decoration: const InputDecoration(labelText: '用户名')),
            const SizedBox(height: 8),
            TextField(
                controller: pass,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(old == null ? '添加' : '保存')),
        ],
      ),
    );
    if (ok != true) return;
    final b = normalizeBase(base.text);
    if (b.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('地址不能为空')));
      }
      return;
    }
    final dup = servers.any((s) => s.base == b && s.id != old?.id);
    if (dup) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('该地址已添加')));
      }
      return;
    }
    final s = old == null
        ? ServerConn(
            id: nextServerId(servers),
            label: label.text.trim(),
            base: b,
            user: user.text.trim(),
            pass: pass.text,
          )
        : old.copyWith(
            label: label.text.trim(),
            base: b,
            user: user.text.trim(),
            pass: pass.text,
          );
    setState(() {
      if (old == null) {
        servers = [...servers, s];
        activeId = activeId.isEmpty ? s.id : activeId;
      } else {
        servers = [
          for (final x in servers) x.id == old.id ? s : x,
        ];
      }
      testMsg.remove(s.id);
      testOk.remove(s.id);
    });
    await _persist();
  }

  Future<void> _delete(ServerConn s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('删除连接「${s.title}」？'),
        content: const Text('只删除本机保存的地址与账号，不删除 NAS 上的媒体和库。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      servers = servers.where((x) => x.id != s.id).toList();
      if (activeId == s.id) activeId = servers.isEmpty ? '' : servers.first.id;
    });
    await _persist();
  }

  Future<void> _toggle(ServerConn s, bool v) async {
    setState(() {
      servers = [
        for (final x in servers) x.id == s.id ? x.copyWith(visible: v) : x,
      ];
    });
    await _persist();
  }

  Future<void> _activate(ServerConn s) async {
    setState(() => activeId = s.id);
    await _persist();
  }

  Future<void> _saveAndEnter() async {
    await _persist();
    if (!mounted) return;
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(true);
    } else if (cfg.base.isNotEmpty) {
      nav.pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('多网络连接'), actions: [
        IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加连接',
            onPressed: () => _edit()),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            '可添加多个 NAS 地址（IP）。主页与媒体库会聚合所有可见连接的库；'
            '同名/同 id 的库只显示一份。隐藏某条连接只会隐藏它的库，配置仍保留。',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        if (servers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
                child: Text('还没有连接，点右上角 + 添加一个 NAS 地址',
                    style: TextStyle(color: Colors.grey))),
          ),
        for (final s in servers) _card(s),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: servers.isEmpty ? null : _saveAndEnter,
            child: const Text('保存并进入')),
        const SizedBox(height: 8),
        const Text('支持 http/https，自动补全 http://；地址与密码只保存在本机。',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }

  Widget _card(ServerConn s) {
    final isActive = s.id == activeId;
    final msg = testMsg[s.id];
    final ok = testOk[s.id];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(isActive ? Icons.check_circle : Icons.dns_outlined,
                size: 20, color: isActive ? Colors.green : null),
            const SizedBox(width: 8),
            Expanded(
                child: Text(s.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            if (isActive)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text('当前',
                    style: TextStyle(fontSize: 11, color: Colors.green)),
              ),
            Switch(
                value: s.visible,
                onChanged: (v) => _toggle(s, v),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ]),
          Text(s.base,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text('账号：${s.user} · ${s.visible ? '库参与聚合' : '库已隐藏'}',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(msg,
                  style: TextStyle(
                      fontSize: 11,
                      color: ok == true ? Colors.green : Colors.redAccent)),
            ),
          const SizedBox(height: 4),
          Wrap(spacing: 4, children: [
            TextButton(
                onPressed: () => _activate(s),
                child: Text(isActive ? '当前连接' : '设为当前')),
            TextButton(
                onPressed: testing.contains(s.id) ? null : () => _test(s),
                child: Text(testing.contains(s.id) ? '测试中…' : '测试')),
            TextButton(onPressed: () => _edit(s), child: const Text('编辑')),
            TextButton(
                onPressed: () => _delete(s),
                child: const Text('删除',
                    style: TextStyle(color: Colors.redAccent))),
          ]),
        ]),
      ),
    );
  }
}

class LibraryBadgeColorsPage extends StatefulWidget {
  const LibraryBadgeColorsPage({super.key});
  @override
  State<LibraryBadgeColorsPage> createState() => _LibraryBadgeColorsPageState();
}

class _LibraryBadgeColorsPageState extends State<LibraryBadgeColorsPage> {
  List<Map<String, dynamic>> libs = [];
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await LibraryBadge.load();
    await _loadLibs();
  }

  Future<void> _loadLibs() async {
    if (mounted) setState(() => err = null);
    try {
      final r = await http
          .get(cfg.u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final list = librariesWithDisplayNames(
          ((j['libraries'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());
      if (!mounted) return;
      setState(() {
        libs = list;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          err = '$e';
          loading = false;
        });
      }
    }
  }

  List<String> get _order => libs.map((e) => '${e['id']}').toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('库词条配色'), actions: [
        IconButton(
            tooltip: '刷新',
            onPressed: _loadLibs,
            icon: const Icon(Icons.refresh)),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text('加载失败：$err',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12))),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _loadLibs, child: const Text('重试')),
                ]))
              : ListView(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text('作者卡片左上角的库词条颜色。默认按库注册顺序自动配色，也可逐库指定。',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  for (final l in libs) _libTile(l),
                ]),
    );
  }

  Widget _libTile(Map<String, dynamic> l) {
    final id = '${l['id']}';
    final name = displayLibraryName(id, '${l['name'] ?? ''}');
    final color = LibraryBadge.colorFor(id, order: _order);
    return ListTile(
      leading: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
            color: Color(color), borderRadius: BorderRadius.circular(7)),
      ),
      title: Row(children: [
        Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        LibBadgeChip(label: name, color: color),
      ]),
      subtitle: Text(id, style: const TextStyle(fontSize: 11)),
      trailing: Text(
        LibraryBadge.custom[id] == null ? '自动' : '自定义',
        style: TextStyle(
            fontSize: 12,
            color: LibraryBadge.custom[id] == null
                ? Colors.grey
                : Colors.lightBlueAccent),
      ),
      onTap: () async {
        final chosen = await _showColorDialog(name, id, color);
        if (chosen == null) return;
        await LibraryBadge.setColor(id, chosen == -1 ? null : chosen);
        if (mounted) setState(() {});
      },
    );
  }

  /// 返回 -1 表示恢复自动配色，null 表示取消。
  Future<int?> _showColorDialog(String name, String id, int autoColor) async {
    int? current = LibraryBadge.custom[id];
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('「$name」词条颜色'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LibBadgeChip(label: name, color: current ?? autoColor),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (var i = 0; i < LibraryBadge.palette.length; i++)
                GestureDetector(
                  onTap: () => setLocal(() {
                    current = LibraryBadge.palette[i];
                  }),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(LibraryBadge.palette[i]),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: current == LibraryBadge.palette[i]
                            ? Colors.white
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: current == LibraryBadge.palette[i]
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setLocal(() => current = null),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('自动配色'),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(current ?? -1),
                child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}

// 库词条：作者卡片左上角的小标签，颜色按库自动分配（设置里可改）
class LibBadgeChip extends StatelessWidget {
  final String label;
  final int color;
  const LibBadgeChip({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: Color(color).withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
        border:
            Border.all(color: Colors.black.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 9,
          height: 1.25,
          fontWeight: FontWeight.w600,
          color: Color(LibraryBadge.textColorOn(color)),
        ),
      ),
    );
  }
}

class LibBadges extends StatelessWidget {
  final List<String> libIds;
  final List<String> order;
  final Map<String, String> names;

  /// 固定使用灰色的词条 id（顶级 SECRET / 无归属库名）。
  final Set<String> grayIds;
  // 等级词条（D–S），空串表示不显示
  final String grade;
  const LibBadges({
    super.key,
    required this.libIds,
    this.order = const [],
    this.names = const {},
    this.grayIds = const {},
    this.grade = '',
  });

  @override
  Widget build(BuildContext context) {
    final labels = LibraryBadge.labels(libIds, names: names);
    if (labels.isEmpty && grade.isEmpty) return const SizedBox.shrink();
    final shown = libIds.where((e) => e.isNotEmpty).toList();
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (var i = 0; i < labels.length; i++)
          LibBadgeChip(
            label: labels[i],
            color: (labels[i].startsWith('+') ||
                    (i < shown.length && grayIds.contains(shown[i])))
                ? LibraryBadge.gray
                : LibraryBadge.colorFor(i < shown.length ? shown[i] : '',
                    order: order),
          ),
        if (grade.isNotEmpty)
          LibBadgeChip(
            label: grade,
            color: AuthorGrade.colorForGrade(grade),
          ),
      ],
    );
  }
}

/// T2：单元库词条。
///
/// 作者/作品能归到单元库 → 显示单元库名并按库配色；
/// 顶级 SECRET 或无归属 → 固定灰色（无归属时显示库名兜底）。
class UnitBadges extends StatelessWidget {
  final LibMeta? meta;
  final String mediaPath;

  /// 已知基础库 id 时直接用它归属单元库（如搜索结果来自基础库 works.json，
  /// 作品条目里没有作者头像路径 `av`，无法按路径匹配）。
  final String basicId;

  /// 没有单元库归属时显示的库 id / 库名。
  final String fallbackId;
  final String fallbackName;
  final String grade;
  const UnitBadges({
    super.key,
    required this.meta,
    required this.mediaPath,
    required this.fallbackId,
    required this.fallbackName,
    this.basicId = '',
    this.grade = '',
  });

  @override
  Widget build(BuildContext context) {
    final unitId = basicId.isNotEmpty
        ? (meta?.basicToUnit[basicId] ?? '')
        : (meta?.unitIdFor(mediaPath) ?? '');
    // 不再回退到「库名」词条（抖音收藏已废弃）；没有单元库归属就显示 SECRET。
    final id = unitId.isEmpty ? 'secret' : unitId;
    final names = <String, String>{...?meta?.unitNames};
    names['secret'] = 'SECRET';
    final gray = unitId.isEmpty || unitId == 'secret';
    return LibBadges(
      libIds: id.isEmpty ? const [] : <String>[id],
      order: meta?.unitOrder ?? const [],
      names: names,
      grayIds: gray ? <String>{id} : const {},
      grade: grade,
    );
  }
}

/// 作者头像：作者总览、排行榜、作者主页共用一套尺寸/解码/占位规则。
class AuthorAvatar extends StatelessWidget {
  static const double gridSize = 58;
  static const double rankSize = 42;
  static const double headerSize = 64;

  final String name;
  final String mediaPath;

  /// 头像所在库（决定媒体地址与鉴权头）；为空时用当前库。
  final String? lib;
  final double size;

  const AuthorAvatar({
    super.key,
    required this.name,
    required this.mediaPath,
    this.lib,
    this.size = headerSize,
  });

  @override
  Widget build(BuildContext context) {
    final letter = name.isEmpty ? '?' : name[0];
    final placeholder = Container(
      width: size,
      height: size,
      color: Colors.blueGrey,
      alignment: Alignment.center,
      child: Text(letter, style: TextStyle(fontSize: size * 0.4)),
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: mediaPath.isEmpty
            ? placeholder
            : CachedNetworkImage(
                imageUrl: cfg.mediaUrl(mediaPath, lib: lib),
                httpHeaders: cfg.headersFor(lib),
                fit: BoxFit.cover,
                // 按实际显示尺寸 × 像素比解码，避免整张大图进内存
                memCacheWidth: avatarDecodeWidth(
                    displaySize: size,
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context)),
                fadeInDuration: Duration.zero,
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}

/// 作者词条（单元库 + 等级）：全 App 唯一入口。
///
/// 等级统一由 [AuthorGrade] 计算：统计优先用调用方传入的 [stats]
/// （作者总览会把多库统计合并），否则回落到 [meta] 内该作者的统计。
class AuthorBadges extends StatelessWidget {
  final LibMeta? meta;
  final String name;
  final String mediaPath;
  final String basicId;
  final String fallbackId;
  final String fallbackName;
  final int works;

  /// 显式指定的作者统计（含 `p`/`dr`）；null 表示从 [meta] 取。
  final Map<String, dynamic>? stats;

  const AuthorBadges({
    super.key,
    required this.meta,
    required this.name,
    required this.mediaPath,
    required this.fallbackId,
    required this.fallbackName,
    this.basicId = '',
    this.works = 0,
    this.stats,
  });

  /// 统计来源：显式 stats > 当前库 meta 中该作者的统计。
  Map<String, dynamic>? get _stats {
    if (stats != null) return stats;
    final s = meta?.stats[name];
    return s is Map ? Map<String, dynamic>.from(s) : null;
  }

  /// 作者所属基础库 id，决定来源词条（单元库名/配色）。
  /// 顺序：显式基础库 → 头像/媒体路径 → 当前库本身是基础库（基础库页）。
  String get _basicId {
    if (basicId.isNotEmpty) return basicId;
    final m = meta;
    if (m == null) return '';
    final byPath = m.basicIdForPath(mediaPath);
    if (byPath.isNotEmpty) return byPath;
    if (fallbackId.isNotEmpty && m.basicById(fallbackId) != null) {
      return fallbackId;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return UnitBadges(
      meta: meta,
      mediaPath: mediaPath,
      basicId: _basicId,
      fallbackId: fallbackId,
      fallbackName: fallbackName,
      grade: AuthorGrade.fromStats(_stats, works: works),
    );
  }
}

class AuthorGradeSettingsPage extends StatefulWidget {
  const AuthorGradeSettingsPage({super.key});
  @override
  State<AuthorGradeSettingsPage> createState() =>
      _AuthorGradeSettingsPageState();
}

class _AuthorGradeSettingsPageState extends State<AuthorGradeSettingsPage> {
  final _play = TextEditingController();
  final _drop = TextEditingController();
  final _work = TextEditingController();
  final _thresholds = List<TextEditingController>.generate(
      AuthorGrade.grades.length - 1, (_) => TextEditingController());
  String? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    AuthorGrade.load().then((_) {
      if (!mounted) return;
      setState(() {
        _fillFromConfig();
        _ready = true;
      });
    });
  }

  void _fillFromConfig() {
    _play.text = '${AuthorGrade.playWeight}';
    _drop.text = '${AuthorGrade.dropWeight}';
    _work.text = '${AuthorGrade.workWeight}';
    for (var i = 0; i < _thresholds.length; i++) {
      _thresholds[i].text = '${AuthorGrade.thresholds[i]}';
    }
  }

  @override
  void dispose() {
    _play.dispose();
    _drop.dispose();
    _work.dispose();
    for (final c in _thresholds) {
      c.dispose();
    }
    super.dispose();
  }

  int? _read(TextEditingController c) {
    final v = int.tryParse(c.text.trim());
    if (v == null || v < 0) return null;
    return v;
  }

  Future<void> _save() async {
    final play = _read(_play);
    final drop = _read(_drop);
    final work = _read(_work);
    final ts = _thresholds.map(_read).toList();
    if (play == null || drop == null || work == null) {
      setState(() => _error = '权重必须是不小于 0 的整数');
      return;
    }
    if (ts.any((e) => e == null)) {
      setState(() => _error = '门槛必须是不小于 0 的整数');
      return;
    }
    final list = ts.cast<int>();
    for (var i = 1; i < list.length; i++) {
      if (list[i] <= list[i - 1]) {
        setState(() => _error = '等级门槛需逐级递增（C < B < A < S）');
        return;
      }
    }
    setState(() => _error = null);
    AuthorGrade.playWeight = play;
    AuthorGrade.dropWeight = drop;
    AuthorGrade.workWeight = work;
    AuthorGrade.thresholds = list;
    await AuthorGrade.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('等级配置已保存')));
  }

  Future<void> _reset() async {
    AuthorGrade.reset();
    await AuthorGrade.save();
    if (!mounted) return;
    setState(() {
      _fillFromConfig();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作者等级'), actions: [
        TextButton(
            onPressed: _ready ? _reset : null, child: const Text('恢复默认')),
      ]),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              const Text('等级词条', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  '作者卡片库词条后显示 D–S 等级。分数 = 播放×权重 + 水滴×权重 + 作品×权重；'
                  '达到门槛即升一级，等级越高门槛递增。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (var i = 0; i < AuthorGrade.grades.length; i++)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    LibBadgeChip(
                        label: AuthorGrade.grades[i],
                        color: AuthorGrade.colors[i]),
                    const SizedBox(width: 4),
                    Text(i == 0 ? '0 起' : '≥${AuthorGrade.thresholds[i - 1]}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
              ]),
              const Divider(height: 28),
              Row(children: [
                Expanded(child: _numField('播放权重', _play)),
                const SizedBox(width: 10),
                Expanded(child: _numField('水滴权重', _drop)),
                const SizedBox(width: 10),
                Expanded(child: _numField('作品权重', _work)),
              ]),
              const SizedBox(height: 16),
              const Text('等级门槛（分数）',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(children: [
                for (var i = 1; i < AuthorGrade.grades.length; i++) ...[
                  if (i > 1) const SizedBox(width: 8),
                  Expanded(
                    child: _numField(
                        '${AuthorGrade.grades[i - 1]}→${AuthorGrade.grades[i]}',
                        _thresholds[i - 1]),
                  ),
                ],
              ]),
              const SizedBox(height: 12),
              Text(
                  '示例：播放 100、水滴 5、作品 10 → '
                  '${AuthorGrade.score(plays: 100, drops: 5, works: 10)} 分 → '
                  '${AuthorGrade.gradeFor(plays: 100, drops: 5, works: 10)} 级',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
              const SizedBox(height: 20),
              FilledButton(onPressed: _save, child: const Text('保存')),
            ]),
    );
  }

  Widget _numField(String label, TextEditingController c) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );
}

class SettingsHubPage extends StatelessWidget {
  const SettingsHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.dns),
          title: const Text('多网络连接'),
          subtitle: Text(cfg.base.isEmpty
              ? '未设置 · 可添加多个 NAS 地址并聚合库'
              : '${cfg.base} · 可添加多个地址并聚合库'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const SettingsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.library_books_outlined),
          title: const Text('媒体库与爬虫'),
          subtitle: const Text('选择 / 添加 / 删除库 · 库根爬虫 · 维护检查'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const LibraryPage())),
        ),
        ListTile(
          leading: const Icon(Icons.folder_special),
          title: const Text('同步源选择'),
          subtitle: const Text('账号全部同步源 · 勾选参与同步，未勾选不在主页显示'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CollectionAdminPage())),
        ),
        ListTile(
          leading: const Icon(Icons.sell_outlined),
          title: const Text('库词条配色'),
          subtitle: const Text('作者卡片上的库标签 · 每库自动配色，可自定义'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LibraryBadgeColorsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('作者等级'),
          subtitle: const Text('D–S 等级词条 · 播放/水滴加权、门槛可调'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AuthorGradeSettingsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('主题外观'),
          subtitle: const Text('多套配色 · 点击即时预览，不用重启'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ThemeSettingsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('播放参数'),
          subtitle: const Text('默认倍速 · 图文间隔 · 全屏隐藏时间'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlaybackSettingsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('按键绑定'),
          subtitle: const Text('Windows / 桌面端快捷键 · 播放、翻页、全屏'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const KeyBindingsPage())),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('关于 Dizi'),
          subtitle: const Text('本地媒体库客户端 0.9.0'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Dizi',
            applicationVersion: '0.9.0',
            children: const [Text('本地媒体库客户端')],
          ),
        ),
      ]),
    );
  }
}

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppTheme.current,
      builder: (context, currentId, __) {
        final active = normalizeThemeId(currentId);
        return Scaffold(
          appBar: AppBar(title: const Text('主题外观')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                child: Text(
                  '点任意一套主题立即切换并预览，选择会自动保存；'
                  '播放页始终保持全屏黑底，主题影响浏览与设置界面。',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: kAppThemes.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.22,
                ),
                itemBuilder: (context, i) {
                  final spec = kAppThemes[i];
                  return _ThemePreviewCard(
                    spec: spec,
                    selected: spec.id == active,
                    onTap: () => AppTheme.select(spec.id),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text('用当前主题预览',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: Column(children: [
                  const ListTile(
                    leading: Icon(Icons.play_circle_outline),
                    title: Text('示例条目'),
                    subtitle: Text('标题与副标题会跟随主题变色'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                    child: Row(children: [
                      FilledButton(onPressed: () {}, child: const Text('主按钮')),
                      const SizedBox(width: 10),
                      OutlinedButton(
                          onPressed: () {}, child: const Text('次按钮')),
                      const Spacer(),
                      Switch(value: true, onChanged: (_) {}),
                    ]),
                  ),
                ]),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 主题卡片：用该主题自己的配色画一个迷你界面，选中项加描边与勾。
class _ThemePreviewCard extends StatelessWidget {
  final AppThemeSpec spec;
  final bool selected;
  final VoidCallback onTap;

  const _ThemePreviewCard({
    required this.spec,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = buildThemeData(spec).colorScheme;
    final borderColor = selected
        ? scheme.primary
        : scheme.outlineVariant.withValues(alpha: 0.5);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: spec.background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _dot(scheme.primary),
                const SizedBox(width: 6),
                _dot(scheme.secondary),
                const SizedBox(width: 6),
                _dot(scheme.tertiary),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle, size: 18, color: scheme.primary),
              ]),
              const Spacer(),
              Container(
                height: 4,
                width: 64,
                decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 8),
              Text(spec.name,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
              const SizedBox(height: 2),
              Text(spec.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

class PlaybackSettingsPage extends StatefulWidget {
  const PlaybackSettingsPage({super.key});
  @override
  State<PlaybackSettingsPage> createState() => _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends State<PlaybackSettingsPage> {
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  Future<void> _persist() => AppSettings.save();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放参数'), actions: [
        TextButton(
          onPressed: () {
            setState(() => AppSettings.resetDefaults());
            _persist();
          },
          child: const Text('恢复默认'),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('默认播放倍速', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('进入播放器时自动应用，播放中仍可用倍速按钮临时切换。',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final s in _speeds)
            ChoiceChip(
              label: Text('${s}x'),
              selected: (AppSettings.defaultSpeed - s).abs() < 0.001,
              onSelected: (_) {
                setState(() => AppSettings.defaultSpeed = s);
                _persist();
              },
            ),
        ]),
        const Divider(height: 32),
        Row(children: [
          const Expanded(
              child: Text('图文自动切换间隔',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Text('${AppSettings.imageIntervalSec}s',
              style: const TextStyle(color: Colors.amber)),
        ]),
        Slider(
          value: AppSettings.imageIntervalSec.toDouble().clamp(1, 20),
          min: 1,
          max: 20,
          divisions: 19,
          label: '${AppSettings.imageIntervalSec}s',
          onChanged: (v) =>
              setState(() => AppSettings.imageIntervalSec = v.round()),
          onChangeEnd: (_) => _persist(),
        ),
        const Text('图文作品停留多久后自动展示下一张（到末尾自动切下一条）。',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const Divider(height: 32),
        Row(children: [
          const Expanded(
              child: Text('全屏隐藏控制栏时间',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Text('${AppSettings.hideUiSec}s',
              style: const TextStyle(color: Colors.amber)),
        ]),
        Slider(
          value: AppSettings.hideUiSec.toDouble().clamp(1, 30),
          min: 1,
          max: 30,
          divisions: 29,
          label: '${AppSettings.hideUiSec}s',
          onChanged: (v) => setState(() => AppSettings.hideUiSec = v.round()),
          onChangeEnd: (_) => _persist(),
        ),
        const Text('全屏播放时无操作多久后自动隐藏进度条与控制栏；点击屏幕可再次呼出。',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const Divider(height: 32),
        Row(children: [
          const Expanded(
              child: Text('滑动预加载条数',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          Text(
              AppSettings.preloadPerSide == 0
                  ? '关闭'
                  : '前后各 ${AppSettings.preloadPerSide} 条',
              style: const TextStyle(color: Colors.amber)),
        ]),
        Slider(
          value: AppSettings.preloadPerSide.toDouble(),
          min: 0,
          max: preloadMaxPerSide.toDouble(),
          divisions: preloadMaxPerSide,
          label: '${AppSettings.preloadPerSide}',
          onChanged: (v) => setState(() =>
              AppSettings.preloadPerSide = clampPreloadPerSide(v.round())),
          onChangeEnd: (_) => _persist(),
        ),
        const Text('按滑动方向提前打开前后各 N 条媒体，切条时首帧已就绪；0 为关闭。',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 12),
        const Text('预加载内存上限', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final mb in preloadMemoryOptions)
            ChoiceChip(
              label: Text('$mb MB'),
              selected: AppSettings.preloadMemoryMb == mb,
              onSelected: (_) {
                setState(() =>
                    AppSettings.preloadMemoryMb = clampPreloadMemoryMb(mb));
                _persist();
              },
            ),
        ]),
        const Text('超出上限时优先淘汰离当前条目最远的缓存，正在播放的条目不受影响。',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }
}

class KeyBindingsPage extends StatefulWidget {
  const KeyBindingsPage({super.key});
  @override
  State<KeyBindingsPage> createState() => _KeyBindingsPageState();
}

class _KeyBindingsPageState extends State<KeyBindingsPage> {
  Future<void> _rebind(PlayerAction action) async {
    final id = await showDialog<int>(
      context: context,
      builder: (_) => _KeyCaptureDialog(action: action),
    );
    if (id == null || !mounted) return;
    setState(() => AppSettings.bind(action, id));
    await AppSettings.save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('按键绑定'), actions: [
        TextButton(
          onPressed: () {
            setState(() => AppSettings.resetDefaults());
            AppSettings.save();
          },
          child: const Text('恢复默认'),
        ),
      ]),
      body: ListView(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
              '点击任意一行，然后按下新的按键即可绑定（Windows 桌面端生效，移动端可忽略）。'
              '方向键与 Esc 始终保留。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        const Divider(height: 1),
        for (final a in PlayerAction.values)
          ListTile(
            leading: const Icon(Icons.keyboard_alt_outlined),
            title: Text(actionLabels[a]!),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6)),
              child: Text(AppSettings.keyLabel(a),
                  style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ),
            onTap: () => _rebind(a),
          ),
      ]),
    );
  }
}

class _KeyCaptureDialog extends StatefulWidget {
  final PlayerAction action;
  const _KeyCaptureDialog({required this.action});
  @override
  State<_KeyCaptureDialog> createState() => _KeyCaptureDialogState();
}

class _KeyCaptureDialogState extends State<_KeyCaptureDialog> {
  static final _modifiers = <int>{
    LogicalKeyboardKey.shift.keyId,
    LogicalKeyboardKey.control.keyId,
    LogicalKeyboardKey.alt.keyId,
    LogicalKeyboardKey.meta.keyId,
    LogicalKeyboardKey.capsLock.keyId,
    LogicalKeyboardKey.fn.keyId,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.handled;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    if (_modifiers.contains(k.keyId)) return KeyEventResult.handled;
    Navigator.of(context).pop(k.keyId);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('绑定「${actionLabels[widget.action]}」'),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Container(
          height: 88,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.keyboard,
                size: 26,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text('请按下要绑定的按键…',
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消（Esc）')),
      ],
    );
  }
}

class CollectionAdminPage extends StatefulWidget {
  const CollectionAdminPage({super.key});
  @override
  State<CollectionAdminPage> createState() => _CollectionAdminPageState();
}

class _CollectionAdminPageState extends State<CollectionAdminPage> {
  List<CollectionSyncInfo> cols = [];
  int? defaultIdx;
  int accountCount = 0;
  bool loading = true;
  bool saving = false;
  String? err;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final r = await http.get(cfg.u('/api/settings'), headers: cfg.headers);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      _apply(jsonDecode(r.body) as Map<String, dynamic>, setLoading: true);
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    if (mounted) setState(() => loading = false);
  }

  void _apply(Map<String, dynamic> j, {bool setLoading = false}) {
    if (!mounted) return;
    final list = parseCollectionSettings(j);
    setState(() {
      cols = list;
      defaultIdx = (j['default'] as num?)?.toInt();
      accountCount = (j['accountCount'] as num?)?.toInt() ??
          list.where((c) => c.account).length;
      err = null;
      if (setLoading) loading = false;
    });
  }

  Future<Map<String, dynamic>> _send(
      String path, Map<String, dynamic> body) async {
    final r = await http.post(cfg.u(path),
        headers: {...cfg.headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body));
    if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Future<void> _save() async {
    final seq = ++_seq;
    setState(() => saving = true);
    try {
      final j = await _send('/api/settings', {
        'default': defaultIdx,
        'collections': [
          for (final c in cols)
            {
              'idx': c.idx,
              'name': c.name,
              'sync': c.sync,
            }
        ],
      });
      if (!mounted || seq != _seq) return;
      _apply(j);
    } catch (e) {
      if (mounted && seq == _seq) _toast('保存失败：$e');
    } finally {
      if (mounted && seq == _seq) setState(() => saving = false);
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex--;
      final item = cols.removeAt(oldIndex);
      cols.insert(newIndex, item);
    });
    _save();
  }

  void _toggle(CollectionSyncInfo c, bool value) {
    setState(() {
      final i = cols.indexWhere((e) => e.idx == c.idx);
      if (i < 0) return;
      cols[i] = CollectionSyncInfo(
        idx: c.idx,
        name: c.name,
        count: c.count,
        sync: value,
        inIndex: c.inIndex,
        account: c.account,
        customName: c.customName,
      );
      // 默认同步源必须保持勾选：关闭时自动改选第一个仍参与同步的同步源
      if (!value && defaultIdx == c.idx) {
        int? next;
        for (final e in cols) {
          if (e.sync) {
            next = e.idx;
            break;
          }
        }
        defaultIdx = next;
      }
    });
    _save();
  }

  Future<void> _toggleAll(bool value) async {
    setState(() {
      cols = setAllSync(cols, value);
      if (!value) {
        defaultIdx = null;
      } else if (defaultIdx == null && cols.isNotEmpty) {
        defaultIdx = cols.first.idx;
      }
    });
    await _save();
  }

  Future<void> _rename(CollectionSyncInfo c) async {
    final ctrl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名同步源'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          decoration: const InputDecoration(labelText: '显示名称'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    ctrl.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final j = await _send('/api/collections/rename', {
        'idx': c.idx,
        'name': name,
      });
      _apply(j);
    } catch (e) {
      _toast('重命名失败：$e');
    }
  }

  Future<void> _delete(CollectionSyncInfo c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除同步源'),
        content: Text('将从 App 中移除「${c.name}」，清除该同步源的索引数据并关闭同步。\n\n'
            'NAS 上的原始视频、图片和文案不会被删除。\n此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final j = await _send('/api/collections/delete', {'idx': c.idx});
      _apply(j);
      _toast('已移除「${c.name}」并关闭同步');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = cols.where((c) => c.sync).length;
    return Scaffold(
      appBar: AppBar(title: const Text('同步源选择'), actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.checklist),
          tooltip: '批量勾选',
          onSelected: (v) => _toggleAll(v == 'all'),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'all', child: Text('全选（全部参与同步）')),
            PopupMenuItem(value: 'none', child: Text('全不选（全部暂不同步）')),
          ],
        ),
        if (cfg.lib == 'douyin')
          IconButton(
              icon: const Icon(Icons.cloud_sync),
              tooltip: '立即同步全部同步源',
              onPressed: () async {
                await syncAllCollectionsFlow(context, onFinished: load);
              }),
        if (saving)
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('加载失败：$err'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: load, child: const Text('重试')),
                ]))
              : cols.isEmpty
                  ? const Center(child: Text('没有同步源'))
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(children: [
                          const Icon(Icons.info_outline,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                '账号共 $accountCount 个同步源 · $enabled 个参与同步。'
                                '关闭后不参与同步，也不出现在主页/库选择页；名称与账号一致。',
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                          ),
                        ]),
                      ),
                      Expanded(
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: cols.length,
                          onReorder: _reorder,
                          itemBuilder: (_, i) {
                            final c = cols[i];
                            final isDefault = defaultIdx == c.idx;
                            return ListTile(
                              key: ValueKey('col-${c.idx}'),
                              leading: ReorderableDragStartListener(
                                index: i,
                                child: const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Icon(Icons.drag_indicator),
                                ),
                              ),
                              title: Row(children: [
                                if (isDefault) ...const [
                                  Icon(Icons.star,
                                      size: 16, color: Colors.amber),
                                  SizedBox(width: 4),
                                ],
                                Expanded(
                                    child: Text(c.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                              ]),
                              subtitle: Text(c.subtitle),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: c.sync,
                                      onChanged: (v) => _toggle(c, v),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert),
                                      onSelected: (v) async {
                                        if (v == 'default') {
                                          setState(() => defaultIdx = c.idx);
                                          await _save();
                                        } else if (v == 'rename') {
                                          await _rename(c);
                                        } else if (v == 'delete') {
                                          await _delete(c);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        if (c.sync)
                                          const PopupMenuItem(
                                              value: 'default',
                                              child: Text('设为默认同步源')),
                                        const PopupMenuItem(
                                            value: 'rename',
                                            child: Text('重命名')),
                                        const PopupMenuItem(
                                            value: 'delete',
                                            child: Text('删除（关闭同步）')),
                                      ],
                                    ),
                                  ]),
                            );
                          },
                        ),
                      ),
                    ]),
    );
  }
}

class LibraryPage extends StatefulWidget {
  /// L5：内嵌到主页时只渲染内容（无 Scaffold/AppBar）——主页＝单元库卡片。
  final bool embedded;

  const LibraryPage({super.key, this.embedded = false});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<Map<String, dynamic>> libs = [];
  List<ServerConn> servers = [];
  String? defaultId;
  bool loading = true;
  String? err;
  String? warn;
  bool changed = false;

  /// J2：大库/基础库两级选择。v1 服务端没有 bigLibraries 时为 null，走原列表。
  LibraryTree? tree;

  /// L5：单元库树（节点文件夹＝单元库，SECRET 顶级）。
  UnitLibrary? unitTree;
  Set<String> expanded = <String>{};
  List<String> stars = <String>[];

  /// J3：旧注册表默认收起，只在需要管理时展开。
  bool legacyOpen = false;

  @override
  void initState() {
    super.initState();
    WorkPlaysStore.revision.addListener(_onPlaysChanged);
    // 0.9.6：星标是全局状态，任何页面切换后本页都要跟着刷新。
    StarStore.instance.addListener(_onStarsChanged);
    load();
  }

  @override
  void dispose() {
    WorkPlaysStore.revision.removeListener(_onPlaysChanged);
    StarStore.instance.removeListener(_onStarsChanged);
    super.dispose();
  }

  // 0.9.6：星标被任何页面改动后，同步本页快照（返回主页不再显示旧图标）。
  void _onStarsChanged() {
    if (!mounted) return;
    final next = StarStore.instance.ordered;
    if (next.length == stars.length && next.every((e) => stars.contains(e))) {
      return;
    }
    setState(() => stars = next);
  }

  // L5-C：有新的本机播放记录时刷新封面
  void _onPlaysChanged() {
    if (mounted) setState(() {});
  }

  /// L5-C：基础库封面 URL。自定义 `_cover/` 优先，其次本机播放量最高的作品缩略图。
  String _basicCoverUrl(BasicLib b) {
    final top = topPlayed(WorkPlaysStore.countsFor(b.id));
    final pick = pickBasicCover(
      rel: b.rel,
      version: b.coverVersion,
      ext: b.coverExt,
      bestThumb: top?.thumb ?? '',
    );
    if (pick.isEmpty) return '';
    return cfg.mediaUrl(pick.path, lib: b.id);
  }

  Uri _u(String path, [String? lib, String? atBase]) {
    final sep = path.contains('?') ? '&' : '?';
    return Uri.parse(
        '${atBase ?? cfg.baseFor(lib)}$path${sep}lib=${Uri.encodeQueryComponent(lib ?? cfg.lib)}');
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
      warn = null;
    });
    try {
      final sp = await SharedPreferences.getInstance();
      final all = migrateLegacy(
        servers: decodeServers(sp.getString('servers_v1')),
        base: sp.getString('base') ?? cfg.base,
        user: sp.getString('user') ?? cfg.user,
        pass: sp.getString('pass') ?? cfg.pass,
      );
      final visible = all.where((s) => s.visible).toList(growable: false);
      final use = visible.isEmpty
          ? [
              ServerConn(
                  id: 'legacy',
                  label: '默认连接',
                  base: cfg.base,
                  user: cfg.user,
                  pass: cfg.pass)
            ].where((s) => s.base.isNotEmpty).toList()
          : visible;
      final snaps = <ServerLibraries>[];
      for (final s in use) {
        final h = {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('${s.user}:${s.pass}'))}',
        };
        try {
          final rs = await Future.wait([
            http
                .get(Uri.parse('${s.base}/api/libraries'), headers: h)
                .timeout(const Duration(seconds: 10)),
            http
                .get(Uri.parse('${s.base}/api/libraries.json'), headers: h)
                .timeout(const Duration(seconds: 10)),
          ]);
          var list = <Map<String, dynamic>>[];
          var def = '';
          if (rs[0].statusCode == 200) {
            final j = jsonDecode(rs[0].body);
            if (j is Map) {
              list = librariesWithDisplayNames(
                  ((j['libraries'] as List?) ?? const [])
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList());
              def = '${j['default'] ?? ''}';
            }
          }
          Map<String, dynamic>? treeJson;
          if (rs[1].statusCode == 200) {
            final j = jsonDecode(rs[1].body);
            if (j is Map) treeJson = Map<String, dynamic>.from(j);
          }
          if (def.isNotEmpty && defaultId == null) defaultId = def;
          snaps
              .add(ServerLibraries(server: s, libraries: list, tree: treeJson));
        } catch (e) {
          snaps.add(ServerLibraries(server: s, error: '$e'));
        }
      }
      final merged = mergeRegisteredLibraries(snaps);
      final treeJson = mergeLibraryTrees(snaps);
      // 记录库 → 连接，之后播放/统计/媒体都按所属 IP 路由。
      final bindings = buildBindings(servers: use, libraries: merged);
      final byBase = {for (final s in use) s.base: s};
      if (treeJson != null) {
        for (final raw in (treeJson['basicLibraries'] as List?) ?? const []) {
          if (raw is! Map) continue;
          final id = '${raw['id'] ?? ''}'.trim();
          final s = byBase['${raw['_serverBase'] ?? ''}'];
          if (id.isEmpty || s == null) continue;
          bindings[id] = {
            'base': s.base,
            'user': s.user,
            'pass': s.pass,
            'server': s.id,
          };
        }
      }
      cfg.setBindings(bindings);
      await sp.setString('lib_bindings_v1', encodeBindings(bindings));
      final failures =
          snaps.where((s) => s.error != null).map((s) => s.server.title);
      if (!mounted) return;
      setState(() {
        servers = use;
        libs = merged;
        if (failures.isNotEmpty) {
          warn = '部分连接失败：${failures.join('、')}（其余库已照常显示）';
        }
      });
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    await _loadTree();
    if (mounted) setState(() => loading = false);
  }

  /// 读取 v2 索引与本地星标；任何失败都只影响大库区，不影响已注册库。
  Future<void> _loadTree() async {
    try {
      // 0.9.6：星标统一从 StarStore 读，保证各页面看到同一份数据。
      await StarStore.instance.load();
      final saved = StarStore.instance.ordered;
      final snaps = <ServerLibraries>[];
      for (final s in servers) {
        final h = {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('${s.user}:${s.pass}'))}',
        };
        try {
          final r = await http
              .get(Uri.parse('${s.base}/api/libraries.json'), headers: h)
              .timeout(const Duration(seconds: 8));
          if (r.statusCode != 200) continue;
          final j = jsonDecode(r.body);
          if (j is! Map) continue;
          snaps.add(ServerLibraries(
              server: s,
              libraries: const [],
              tree: Map<String, dynamic>.from(j)));
        } catch (_) {}
      }
      final merged = mergeLibraryTrees(snaps);
      if (merged == null) {
        if (mounted) setState(() => tree = null);
        return;
      }
      final t = LibraryTree.parse(merged, stars: saved);
      // 节点文件夹由 owner 在「文件结构」里指定；默认为空 = 只有顶级 SECRET。
      final marked = await _fetchMarkedNodes();
      final nodes = marked
          .map((rel) => LibNode(
                id: 'node:$rel',
                rel: rel,
                name: splitRel(rel).isEmpty ? rel : splitRel(rel).last,
              ))
          .toList(growable: false);
      final units = buildUnitTree(
        nodes: nodes,
        basics: t?.allBasics ?? const <BasicLib>[],
        topName: 'SECRET',
      );
      if (!mounted) return;
      setState(() {
        stars = saved;
        tree = t;
        unitTree = units;
      });
    } catch (_) {}
  }

  /// 星标标记单元库（不是基础库）。
  Future<void> _toggleUnitStar(UnitLibrary u) async {
    // 0.9.6：写入 StarStore（唯一真相），已入栈的父页/子页会一起刷新。
    await StarStore.instance.toggle(u.id);
    if (mounted) setState(() => stars = StarStore.instance.ordered);
  }

  /// L5-C：基础库封面（自定义 `_cover/` 优先，其次本机播放量最高的作品缩略图）。
  String _coverUrlFor(BasicLib b) => _basicCoverUrl(b);

  /// L5-C：单元库封面（仅自定义 `_cover/`，否则默认图）。
  String _unitCoverUrl(UnitLibrary u) {
    final pick = pickUnitCover(
        rel: u.rel, version: u.node.coverVersion, ext: u.node.coverExt);
    if (!pick.isEmpty) return cfg.mediaUrl(pick.path);
    // 没有自定义封面时，用该单元库下第一个基础库的封面兜底，
    // 避免单元库卡片大面积空白。
    if (u.basics.isNotEmpty) {
      final fallback = _basicCoverUrl(u.basics.first);
      if (fallback.isNotEmpty) return fallback;
    }
    return '';
  }

  void _openStars() {
    final root = unitTree;
    final starred = <UnitLibrary>[];
    if (root != null) {
      final ids = StarStore.instance.ready ? StarStore.instance.ordered : stars;
      for (final id in ids) {
        final u = root.findById(id);
        if (u != null) starred.add(u);
      }
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => StarredUnitsPage(
        units: starred,
        onOpenUnit: _openUnit,
        onToggleUnitStar: _toggleUnitStar,
        unitCoverOf: _unitCoverUrl,
      ),
    ));
  }

  /// 鉴权头（拆分拼接，避免与既有写法混用）。
  String _authFor(ServerConn s) =>
      'Basic ' + base64Encode(utf8.encode(s.user + ':' + s.pass));

  /// 读取 owner 指定的节点文件夹（服务端 nodes.json）；失败时按「只有 SECRET」处理。
  Future<List<String>> _fetchMarkedNodes() async {
    if (servers.isEmpty) return const [];
    final s = servers.first;
    try {
      final r = await http.get(Uri.parse('${s.base}/api/nodes'), headers: {
        'Authorization': _authFor(s),
      }).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return const [];
      final j = jsonDecode(r.body);
      final list = (j is Map) ? j['nodes'] : null;
      if (list is! List) return const [];
      return list
          .map((e) =>
              (e is Map ? '${e['rel'] ?? e['path'] ?? e['name'] ?? ''}' : '$e')
                  .trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 已注册媒体库管理（添加/删除/默认/爬虫），从首页移入独立面板。
  void _openRegisteredLibs() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(c).size.height * 0.72,
          child: Column(children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('已注册媒体库（管理）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              // 抖音收藏已废弃：不再出现在文件库管理列表里。
              child: ListView(children: [
                for (final l in libs)
                  if ('${l['id']}' != 'douyin') _libTile(l)
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _openFolders() async {
    if (servers.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FolderStructurePage(
        urlOf: (path) => Uri.parse('${servers.first.base}$path'),
        headersOf: () => {
          'Authorization': _authFor(servers.first),
        },
        onSaved: (_) async => load(),
      ),
    ));
  }

  void _openUnit(UnitLibrary u) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (c) => UnitLibraryPage(
        unit: u,
        stars: stars.toSet(),
        onOpenUnit: (sub) => Navigator.of(c).push(MaterialPageRoute<void>(
          builder: (_) => UnitLibraryPage(
            unit: sub,
            stars: stars.toSet(),
            onOpenUnit: (s2) => _openUnit(s2),
            onToggleUnitStar: _toggleUnitStar,
            onTapBasic: (b) => _showBasicOn(c, b),
            coverOf: _coverUrlFor,
            unitCoverOf: _unitCoverUrl,
            onConfigureUnit: _openUnitCrawler,
          ),
        )),
        onToggleUnitStar: _toggleUnitStar,
        onTapBasic: (b) => _showBasicOn(c, b),
        coverOf: _coverUrlFor,
        unitCoverOf: _unitCoverUrl,
        onConfigureUnit: _openUnitCrawler,
      ),
    ));
  }

  /// L5-D：打开单元库级爬虫配置（顶级 SECRET 不提供）。
  void _openUnitCrawler(UnitLibrary u) {
    if (u.rel.trim().isEmpty) return;
    final base = u.node.serverBase.isNotEmpty
        ? u.node.serverBase
        : cfg.baseFor(u.basics.isNotEmpty ? u.basics.first.id : null);
    var headers =
        cfg.headersFor(u.basics.isNotEmpty ? u.basics.first.id : null);
    for (final s in servers) {
      if (s.base == base) {
        headers = {
          'Authorization':
              'Basic ${base64Encode(utf8.encode('${s.user}:${s.pass}'))}',
        };
        break;
      }
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UnitCrawlerPage(unit: u, base: base, headers: headers),
    ));
  }

  void _showBasicOn(BuildContext c, BasicLib b) {
    // 直接在当前页之上打开基础库，不能再 pop：否则返回会少一级
    // （从「某个单元库的基础库列表」进入后，返回会越过该列表）。
    _showBasic(b, from: c);
  }

  void _showBasic(BasicLib b, {BuildContext? from}) {
    // 作者来源词条：本基础库所属单元库（与作者卡/作者页同一口径）。
    final root = unitTree;
    final unit = root == null ? null : unitForBasic(root, b.id);
    final unitOrder = root == null
        ? const <String>[]
        : [
            for (final u in flattenUnits(root))
              if (u.id != root.id) u.id
          ];
    Navigator.of(from ?? context).push(MaterialPageRoute<void>(
      builder: (_) => BasicLibPage(
        basic: b,
        urlOf: (path, {lib}) => cfg.u(path, lib: lib ?? b.id),
        headersOf: ([lib]) => cfg.headersFor(lib ?? b.id),
        mediaUrlOf: (path, {lib}) => cfg.mediaUrl(path, lib: lib ?? b.id),
        sourceLabel: unit?.name ?? '',
        sourceColor: unit == null
            ? LibraryBadge.gray
            : LibraryBadge.colorFor(unit.id, order: unitOrder),
        onOpenAuthor: (name) => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => AuthorPage(name: name, libs: [b.id]))),
        onPlay: (works, index) => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) =>
                    PlayerPage(works: works, start: index, lib: b.id))),
      ),
    ));
  }

  Future<void> _switchTo(Map<String, dynamic> l) async {
    cfg.lib = '${l['id']}';
    cfg.libName = displayLibraryName('${l['id']}', '${l['name'] ?? ''}');
    final sb = '${l['_serverBase'] ?? ''}';
    if (sb.isNotEmpty) {
      cfg.bindLibrary(cfg.lib, sb,
          user: '${l['_serverUser'] ?? cfg.user}',
          pass: '${l['_serverPass'] ?? cfg.pass}',
          server: '${l['_serverId'] ?? ''}');
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setString('lib', cfg.lib);
    await sp.setString('lib_bindings_v1', encodeBindings(cfg._bindings));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _setDefault(Map<String, dynamic> l) async {
    try {
      final id = '${l['id']}';
      final sb = '${l['_serverBase'] ?? ''}';
      final r = await http.post(_u('/api/libraries/default', id, sb),
          headers: {...cfg.headersFor(id), 'Content-Type': 'application/json'},
          body: jsonEncode({'id': l['id']}));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已将「${l['name']}」设为默认库')));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('设置失败：$e')));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('删除库「${l['name']}」？'),
        content: const Text('仅从注册表移除，不删除数据目录和媒体文件。当前库或唯一库不能删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final id = '${l['id']}';
      final sb = '${l['_serverBase'] ?? ''}';
      final r = await http.post(_u('/api/libraries/delete', id, sb),
          headers: {...cfg.headersFor(id), 'Content-Type': 'application/json'},
          body: jsonEncode({'id': l['id']}));
      final j = jsonDecode(r.body);
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已移除库注册（数据保留）')));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$e')));
      }
    }
  }

  Future<void> _add() async {
    final id = TextEditingController();
    final name = TextEditingController();
    final desc = TextEditingController();
    final base = TextEditingController(text: '/vol1/1000/');
    final dir = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('添加媒体库'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: id,
                decoration:
                    const InputDecoration(labelText: '库 ID（小写字母/数字/-/_）')),
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: '显示名称')),
            TextField(
                controller: desc,
                decoration: const InputDecoration(labelText: '描述（可选）')),
            TextField(
                controller: base,
                decoration: const InputDecoration(
                    labelText: '媒体根目录（绝对路径）', hintText: '/vol1/1000/...')),
            TextField(
                controller: dir,
                decoration: const InputDecoration(
                    labelText: '数据目录（可选，默认服务端 libs/<id>）')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok != true) return;
    final lid = id.text.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,31}$').hasMatch(lid)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('库 ID 格式不正确')));
      return;
    }
    if (name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('名称不能为空')));
      return;
    }
    try {
      final atBase = await () async {
        final sp = await SharedPreferences.getInstance();
        final active = sp.getString('active_server_v1') ?? '';
        for (final s in servers) {
          if (s.id == active) return s.base;
        }
        return servers.isEmpty ? cfg.base : servers.first.base;
      }();
      final r = await http.post(_u('/api/libraries', null, atBase),
          headers: {...cfg.headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'id': lid,
            'name': name.text.trim(),
            'desc': desc.text.trim(),
            'base': base.text.trim(),
            'dir': dir.text.trim(),
          }));
      final j = jsonDecode(r.body);
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('媒体库已添加')));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('添加失败：$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('媒体库'), actions: [
          IconButton(
              icon: const Icon(Icons.refresh), onPressed: load, tooltip: '刷新'),
          IconButton(
              icon: const Icon(Icons.dns_outlined),
              tooltip: '多网络连接',
              onPressed: () async {
                await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()));
                await load();
              }),
          IconButton(
              icon: const Icon(Icons.account_tree_outlined),
              tooltip: '文件结构 / 节点设置',
              onPressed: _openFolders),
          IconButton(
              icon: const Icon(Icons.tune),
              tooltip: '已注册媒体库（管理）',
              onPressed: _openRegisteredLibs),
          IconButton(
              icon: const Icon(Icons.add), onPressed: _add, tooltip: '添加库'),
        ]),
        body: _body(),
      ),
    );
  }

  /// 内容区：主页内嵌与独立「媒体库」页共用。
  Widget _body() {
    if (err != null) return Center(child: Text('加载失败：$err'));
    if (loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      children: [
        if (warn != null)
          Container(
            color: Colors.orange.withValues(alpha: 0.12),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(warn!,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.orange))),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Text(
              '聚合 ${servers.where((s) => s.visible).length} 条连接'
              ' · ${libs.length} 个已注册库（同 id 只显示一次）',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ),
        if (unitTree != null)
          UnitLibraryHomeView(
            tree: unitTree!,
            stars: stars.toSet(),
            onOpenUnit: _openUnit,
            onToggleUnitStar: _toggleUnitStar,
            onTapBasic: _showBasic,
            onOpenStars: _openStars,
            unitCoverOf: (u) => _unitCoverUrl(u),
          )
        else
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 48, 24, 48),
            child: Center(
              child: Text(
                '还没有可显示的单元库\n先在设置 → 媒体库连接，或在「文件结构」里指定节点文件夹',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _libTile(Map<String, dynamic> l) {
    final id = '${l['id']}';
    final isCur = id == cfg.lib;
    final isDef = id == defaultId;
    final cr = (l['crawler'] as Map?) ?? const {};
    final scripts = (l['crawlerScripts'] as List?) ?? const [];
    return ListTile(
      leading: Icon(
          isCur ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: isCur ? Colors.amber : Colors.grey),
      title: Text(
          '${displayLibraryName('$id', '${l['name']}')}  ${isDef ? '★' : ''}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$id · ${l['count'] ?? 0} 条 / ${l['cols'] ?? 0} 个同步源',
              style: const TextStyle(fontSize: 12)),
          Text('${l['base']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if ('${l['_serverLabel'] ?? ''}'.isNotEmpty)
            Text('连接：${l['_serverLabel']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(
              '爬虫：${cr['enabled'] == true ? '已启用' : '未启用'} · ${cr['schedule'] ?? '04:10'} · 脚本 ${scripts.length} 个 · ${(l['indexOk'] == true) ? '索引正常' : '索引缺失'}',
              style: TextStyle(
                  fontSize: 11,
                  color:
                      l['indexOk'] == true ? Colors.grey : Colors.redAccent)),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'default') _setDefault(l);
          if (v == 'crawler') {
            Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) => CrawlerConfigPage(lib: l)))
                .then((_) => load());
          }
          if (v == 'maint') {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MaintenancePage(lib: l)));
          }
          if (v == 'delete') _delete(l);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'default', child: Text('设为默认库')),
          const PopupMenuItem(value: 'crawler', child: Text('爬虫配置')),
          const PopupMenuItem(value: 'maint', child: Text('维护检查')),
          const PopupMenuItem(value: 'delete', child: Text('删除库（保留文件）')),
        ],
      ),
      onTap: () {
        changed = changed || !isCur;
        _switchTo(l);
      },
    );
  }
}

class CrawlerConfigPage extends StatefulWidget {
  final Map<String, dynamic> lib;
  const CrawlerConfigPage({super.key, required this.lib});
  @override
  State<CrawlerConfigPage> createState() => _CrawlerConfigPageState();
}

class _CrawlerConfigPageState extends State<CrawlerConfigPage> {
  bool loading = true;
  bool saving = false;
  String? err;
  bool enabled = false;
  String schedule = '04:10';
  int intervalMin = 0;
  String note = '';
  List scripts = [];

  String get libId => '${widget.lib['id']}';

  Uri _u(String path) => Uri.parse(
      '${cfg.baseFor(libId)}$path?lib=${Uri.encodeQueryComponent(libId)}');

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final r = await http
          .get(_u('/api/crawler'), headers: cfg.headersFor(libId))
          .timeout(const Duration(seconds: 10));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      final c = (j['crawler'] as Map?) ?? const {};
      if (!mounted) return;
      setState(() {
        enabled = c['enabled'] == true;
        schedule = '${c['schedule'] ?? '04:10'}';
        intervalMin = (c['intervalMin'] as num?)?.toInt() ?? 0;
        note = '${c['note'] ?? ''}';
        scripts = (j['scripts'] as List?) ?? const [];
      });
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final r = await http.post(_u('/api/crawler'),
          headers: {
            ...cfg.headersFor(libId),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'enabled': enabled,
            'schedule': schedule.trim(),
            'intervalMin': intervalMin,
            'note': note,
          }));
      final j = jsonDecode(r.body);
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('爬虫配置已保存')));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('爬虫配置 · ${widget.lib['name']}'), actions: [
        TextButton(
            onPressed: saving ? null : save,
            child: Text(saving ? '保存中…' : '保存')),
      ]),
      body: err != null
          ? Center(child: Text('加载失败：$err'))
          : loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text('库根：${widget.lib['base']}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用爬虫调度'),
                    subtitle: const Text('仅保存配置；实际调度由 NAS cron / 维护接口触发'),
                    value: enabled,
                    onChanged: (v) => setState(() => enabled = v),
                  ),
                  const Divider(),
                  // 抓取频率：不再以「每日几点」为主，按固定间隔执行。
                  const Text('抓取频率',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final opt in const <int, String>{
                      0: '不自动',
                      30: '每 30 分钟',
                      60: '每 1 小时',
                      360: '每 6 小时',
                      720: '每 12 小时',
                      1440: '每 24 小时',
                    }.entries)
                      ChoiceChip(
                        label: Text(opt.value),
                        selected: intervalMin == opt.key,
                        onSelected: (_) =>
                            setState(() => intervalMin = opt.key),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  Text(
                      intervalMin == 0
                          ? '当前：不自动抓取（仍可手动同步）'
                          : '当前：每 ${intervalMin >= 60 ? '${intervalMin ~/ 60} 小时' : '$intervalMin 分钟'}抓取一次',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                  TextFormField(
                    initialValue: note,
                    decoration: const InputDecoration(labelText: '备注'),
                    maxLines: 2,
                    onChanged: (v) => note = v,
                  ),
                  const Divider(height: 28),
                  const Text('库根脚本',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  if (scripts.isEmpty)
                    const Text('未发现脚本（保存后服务端会在库根 crawler/ 生成模板）',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  for (final s in scripts)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.terminal, size: 18),
                      title: Text('${(s as Map)['name']}'),
                      subtitle: Text('${((s['size'] as num?)?.toInt() ?? 0)} B',
                          style: const TextStyle(fontSize: 11)),
                    ),
                ]),
    );
  }
}

class MaintenancePage extends StatefulWidget {
  final Map<String, dynamic> lib;
  const MaintenancePage({super.key, required this.lib});
  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  bool loading = true;
  bool running = false;
  String? err;
  Map<String, dynamic> data = {};
  bool deepScan = false;

  String get libId => '${widget.lib['id']}';
  Uri _u(String path) => Uri.parse(
      '${cfg.baseFor(libId)}$path?lib=${Uri.encodeQueryComponent(libId)}');

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool deep = false}) async {
    setState(() {
      loading = true;
      err = null;
      if (deep) deepScan = true;
    });
    try {
      final r = await http
          .get(Uri.parse('${_u('/api/maintenance')}${deep ? '&deep=1' : ''}'),
              headers: cfg.headersFor(libId))
          .timeout(Duration(seconds: deep ? 90 : 15));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (mounted) setState(() => data = j);
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> runCrawler() async {
    setState(() => running = true);
    try {
      final r = await http.post(_u('/api/maintenance'),
          headers: {
            ...cfg.headersFor(libId),
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'action': 'run-crawler', 'lib': libId}));
      final j = jsonDecode(r.body);
      if (r.statusCode != 200 || j['ok'] == false) {
        throw Exception('${j['error'] ?? 'HTTP ${r.statusCode}'}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('爬虫已启动 pid=${j['pid']}，日志：${j['log']}')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('启动失败：$e')));
      }
    }
    if (mounted) setState(() => running = false);
  }

  String _list(Object? v) =>
      ((v as List?) ?? const []).map((e) => '$e').join(', ');

  String _deadLine(dynamic e) {
    if (e is! Map) return '$e';
    final kind = e['kind'] == 'm' ? '媒体' : (e['kind'] == 'th' ? '封面' : '音频');
    return '同步源${e['idx']} · ${e['id']} · $kind · ${e['reason']}';
  }

  @override
  Widget build(BuildContext context) {
    final deep = data['deep'] is Map ? data['deep'] as Map : null;
    final deepOk = deep == null || deep['ok'] == true;
    final ok = data['indexOk'] == true && data['baseOk'] == true && deepOk;
    return Scaffold(
      appBar: AppBar(title: Text('维护 · ${widget.lib['name']}'), actions: [
        IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => load(),
            tooltip: '重新扫描'),
      ]),
      body: err != null
          ? Center(child: Text('加载失败：$err'))
          : loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Row(children: [
                    Icon(ok ? Icons.check_circle : Icons.warning_amber,
                        color: ok ? Colors.green : Colors.orange),
                    const SizedBox(width: 8),
                    Text(ok ? '基础检查通过' : '发现问题',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const Divider(height: 24),
                  _row('库 ID', libId),
                  _row('数据目录', '${data['dir']}'),
                  _row('媒体目录', '${data['base']}'),
                  _row('索引', '${data['indexOk'] == true ? '正常' : '缺失/损坏'}'),
                  _row('作品/同步源',
                      '${data['total'] ?? 0} / ${data['collections'] ?? 0}'),
                  _row('索引文件', '${data['cFiles'] ?? 0} 个'),
                  _row('缺失', _list(data['missing'])),
                  _row('孤儿', _list(data['orphans'])),
                  _row('损坏', _list(data['bad'])),
                  _row('媒体目录存在', '${data['baseOk'] == true ? '是' : '否'}'),
                  _row('爬虫目录', '${data['crawlerDir'] ?? '未创建'}'),
                  if (deep != null) ...[
                    const Divider(height: 24),
                    Row(children: [
                      Icon(deepOk ? Icons.check_circle : Icons.error,
                          color: deepOk ? Colors.green : Colors.red),
                      const SizedBox(width: 8),
                      Text('媒体一致性巡检',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                    _row('媒体文件', '${deep['checked'] ?? 0} 个'),
                    _row('缺失 / 空文件',
                        '${deep['missing'] ?? 0} / ${deep['zero'] ?? 0}'),
                    _row('封面',
                        '${deep['thumbs'] ?? 0} 个，缺失 ${deep['thumbMissing'] ?? 0}'),
                    _row('音频缺失', '${deep['audioMissing'] ?? 0}'),
                    _row('耗时', '${deep['ms'] ?? 0} ms'),
                    if ((deep['dead'] as List?)?.isNotEmpty == true)
                      _row(
                          '失效明细',
                          (deep['dead'] as List)
                              .take(10)
                              .map(_deadLine)
                              .join('\n')),
                  ],
                  const Divider(height: 24),
                  OutlinedButton.icon(
                    onPressed: loading
                        ? null
                        : () async {
                            setState(() => deepScan = true);
                            await load(deep: true);
                          },
                    icon: const Icon(Icons.fact_check_outlined),
                    label: Text(deepScan ? '重新深度巡检' : '深度巡检全部媒体文件'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: running ? null : runCrawler,
                    icon: const Icon(Icons.play_arrow),
                    label: Text(running ? '启动中…' : '运行库根爬虫 sync.sh'),
                  ),
                  const SizedBox(height: 8),
                  const Text('运行前请确认脚本已在库根 crawler/ 中就绪；日志写在 crawler/run.log。',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 110,
              child: Text(k, style: const TextStyle(color: Colors.grey))),
          Expanded(child: SelectableText(v)),
        ]),
      );
}

/// L5：主页＝单元库卡片（不是抖音收藏夹）。
///
/// 抖音收藏没有特殊地位：它只是「文件结构」里被设为节点的普通目录，
/// 和其他单元库平级。按 idx 的旧收藏夹列表从右上角「收藏夹」进入。
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _libEpoch = 0;

  @override
  void initState() {
    super.initState();
    _syncCurrentLib();
  }

  /// 只同步「当前库」指向服务端默认库，用于播放/同步路由；不拉收藏夹列表。
  Future<void> _syncCurrentLib() async {
    try {
      final r = await http
          .get(cfg.u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final lj = jsonDecode(r.body) as Map<String, dynamic>;
      final ls = librariesWithDisplayNames(
          ((lj['libraries'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());
      if (ls.isEmpty) return;
      Map<String, dynamic>? pick;
      for (final e in ls) {
        if (e['id'] == cfg.lib) {
          pick = e;
          break;
        }
      }
      pick ??= ls.firstWhere((e) => e['id'] == lj['default'],
          orElse: () => ls.first);
      final changed = cfg.lib != pick['id'];
      cfg.lib = '${pick['id']}';
      cfg.libName =
          displayLibraryName('${pick['id']}', '${pick['name'] ?? ''}');
      if (changed) {
        final sp = await SharedPreferences.getInstance();
        await sp.setString('lib', cfg.lib);
      }
    } catch (_) {}
  }

  /// 「文件结构」：列出库下全部文件夹，勾选哪些是节点文件夹（单元库）。
  Future<void> _openFolders() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FolderStructurePage(
        urlOf: (path) => Uri.parse('${cfg.base}$path'),
        headersOf: () => cfg.headers,
      ),
    ));
    if (!mounted) return;
    setState(() => _libEpoch++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Text('媒体库'),
        actions: [
          const HomeAction(),
          IconButton(
              key: const ValueKey('open-folder-structure-home'),
              icon: const Icon(Icons.account_tree_outlined),
              tooltip: '文件结构 / 节点文件夹',
              onPressed: _openFolders),
          IconButton(
              icon: const Icon(Icons.auto_awesome),
              tooltip: '推荐',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RecommendPage()))),
          IconButton(
              icon: const Icon(Icons.people_alt_outlined),
              tooltip: '作者',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AuthorGridPage()))),
          IconButton(
              icon: const Icon(Icons.leaderboard_outlined),
              tooltip: '排行榜',
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const RankPage()))),
          IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SearchPage()))),
          IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsHubPage()))),
        ],
      ),
      body: LibraryPage(key: ValueKey('home-libs-$_libEpoch'), embedded: true),
    );
  }
}

class RankPage extends StatefulWidget {
  final String? initialLib;
  const RankPage({super.key, this.initialLib});
  @override
  State<RankPage> createState() => _RankPageState();
}

class _RankPageState extends State<RankPage> {
  static const _periods = <String, String>{
    'week': '周榜',
    'month': '月榜',
    'year': '年榜',
    'all': '总榜',
  };
  String period = 'week';
  String metric = 'play';
  List<Map<String, dynamic>> libs = [];
  String sel = '';
  // 排行榜改为按单元库筛选（与作者总览同一套单元库树）。
  String unitSel = '';
  List rows = [];
  final Map<String, LibMeta> metas = {};
  bool loading = true;
  String? err;
  // J11：筛选状态全 App 共享（总览/排行/搜索/推荐同一份）
  AuthorFilterState get filter => authorFilter.value;
  Map<String, Set<String>> authorTypes = {};
  bool typesLoading = false;
  String _typesForSel = '';

  @override
  void initState() {
    super.initState();
    authorFilter.addListener(_onSharedFilter);
    sel = widget.initialLib ?? 'all';
    loadLibs();
    load();
  }

  void _onSharedFilter() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    authorFilter.removeListener(_onSharedFilter);
    super.dispose();
  }

  Future<void> loadLibs() async {
    try {
      final meta = await LibMeta.load(cfg.lib);
      if (!mounted) return;
      final list = [
        for (final e in meta.bigNames.entries) {'id': e.key, 'name': e.value}
      ]..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      setState(() {
        libs = list;
        metas[cfg.lib] = meta;
      });
    } catch (_) {}
  }

  Future<void> load() async {
    if (mounted) setState(() => err = null);
    try {
      // 0.9.8：排行榜数据源改为全部基础库；大库筛选在本地按作者所属基础库收敛。
      final r = await http.get(
          cfg.u('/api/rank?period=$period&metric=$metric', lib: 'all'),
          headers: cfg.headers);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(r.body);
      final meta = await LibMeta.load(cfg.lib);
      if (!mounted) return;
      metas[cfg.lib] = meta;
      final list =
          (j is Map && j['authors'] is List) ? j['authors'] as List : [];
      setState(() {
        rows = list;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          err = '$e';
          loading = false;
        });
      }
    }
  }

  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

  Map<String, dynamic> _rowMap(dynamic e) =>
      e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};

  LibMeta? _rowMeta(Map<String, dynamic> e) =>
      metas[cfg.lib] ?? (metas.isEmpty ? null : metas.values.first);

  String _rowUnitId(Map<String, dynamic> e) =>
      _rowMeta(e)?.unitIdFor('${e['avatar'] ?? ''}') ?? '';

  bool _rowMatches(Map<String, dynamic> e, AuthorFilterState f) {
    final meta = _rowMeta(e);
    final av = '${e['avatar'] ?? ''}';
    final name = '${e['name'] ?? ''}';
    return f.matches(
      basicId: meta?.idFor(av) ?? '',
      bigId: meta?.bigIdFor(av) ?? '',
      unitId: meta?.unitIdFor(av) ?? '',
      grade: meta?.gradeFor(name, _n(e['works'])) ?? '',
      workTypes: authorTypes[name] ?? const <String>{},
    );
  }

  List<Map<String, dynamic>> get _visibleRows => [
        for (final e in rows)
          if ((sel == 'all' ||
                  _rowMeta(_rowMap(e))
                          ?.bigIdFor('${_rowMap(e)['avatar'] ?? ''}') ==
                      sel) &&
              (unitSel.isEmpty || _rowUnitId(_rowMap(e)) == unitSel) &&
              (!filter.isActive || _rowMatches(_rowMap(e), filter)))
            _rowMap(e)
      ];

  /// 排行榜可选的单元库（来自各库的单元库树）。
  List<AuthorLibNode> get _allUnits {
    final out = <AuthorLibNode>[];
    final seen = <String>{};
    for (final m in metas.values) {
      for (final u in m.units) {
        if (!seen.add(u.id)) continue;
        out.add(AuthorLibNode(id: u.id, name: m.unitNameOf(u.id)));
      }
    }
    return authorLibNodes(out);
  }

  List<AuthorLibNode> get _filterBasics {
    final out = <AuthorLibNode>[];
    final seen = <String>{};
    for (final m in metas.values) {
      for (final b in m.basics) {
        if (!seen.add(b.id)) continue;
        out.add(AuthorLibNode(
            id: b.id, name: basicLibLabel(b, b.name), bigId: b.bigId));
      }
    }
    return authorLibNodes(out);
  }

  List<AuthorBigNode> get _filterBigs {
    final out = <AuthorBigNode>[];
    final seen = <String>{};
    for (final b in _filterBasics) {
      if (b.bigId.isEmpty || !seen.add(b.bigId)) continue;
      var name = b.bigId;
      for (final m in metas.values) {
        final n = m.bigNames[b.bigId];
        if (n != null && n.isNotEmpty) {
          name = n;
          break;
        }
      }
      out.add(AuthorBigNode(id: b.bigId, name: name));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Map<String, String> get _filterLibNames =>
      {for (final b in _filterBasics) b.id: b.name};

  Map<String, String> get _filterBigNames =>
      {for (final b in _filterBigs) b.id: b.name};

  /// T2：单元库筛选选项（含顶级 SECRET）。
  List<AuthorLibNode> get _filterUnits {
    final out = <AuthorLibNode>[];
    final seen = <String>{};
    for (final m in metas.values) {
      for (final u in m.units) {
        if (!seen.add(u.id)) continue;
        out.add(AuthorLibNode(id: u.id, name: m.unitNameOf(u.id)));
      }
    }
    return authorLibNodes(out);
  }

  Map<String, String> get _filterUnitNames =>
      {for (final u in _filterUnits) u.id: u.name};

  int _filterCount(AuthorFilterState f) =>
      rows.where((e) => _rowMatches(_rowMap(e), f)).length;

  Future<void> _ensureTypes() async {
    if (typesLoading) return;
    if (_typesForSel == sel && authorTypes.isNotEmpty) return;
    final targets = metas.keys.toList();
    if (targets.isEmpty) return;
    setState(() => typesLoading = true);
    final map = await loadAuthorTypes(targets);
    if (!mounted) return;
    setState(() {
      authorTypes = map;
      _typesForSel = sel;
      typesLoading = false;
    });
  }

  Future<void> _openFilter() async {
    await _ensureTypes();
    if (!mounted) return;
    final res = await showAuthorFilterSheet(
      context: context,
      initial: filter,
      basics: _filterBasics,
      bigs: _filterBigs,
      units: _filterUnits,
      grades: const ['S', 'A', 'B', 'C', 'D'],
      count: _filterCount,
    );
    if (res == null || !mounted) return;
    authorFilter.apply(res);
  }

  Future<void> _open(String name) async {
    dynamic row;
    for (final e in rows) {
      if (e is Map && '${e['name'] ?? ''}' == name) {
        row = e;
        break;
      }
    }
    final ls = row is Map && row['libs'] is List
        ? (row['libs'] as List).map((e) => '$e').toList()
        : [sel == 'all' ? cfg.lib : sel];
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AuthorPage(name: name, libs: ls.isEmpty ? null : ls)));
    if (mounted) load();
  }

  Color _rankColor(BuildContext context, int i) {
    if (i == 0) return const Color(0xFFFFC107);
    if (i == 1) return const Color(0xFFB0BEC5);
    if (i == 2) return const Color(0xFFBF8970);
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleRows;
    return Scaffold(
      appBar: AppBar(title: const Text('排行榜'), actions: [
        IconButton(
            tooltip: '刷新', onPressed: load, icon: const Icon(Icons.refresh)),
        const HomeAction(),
      ]),
      body: Column(children: [
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('全部单元库'),
                  selected: unitSel.isEmpty,
                  onSelected: (_) {
                    if (unitSel.isEmpty) return;
                    setState(() => unitSel = '');
                  },
                ),
              ),
              for (final u in _allUnits)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(u.name),
                    selected: unitSel == u.id,
                    onSelected: (_) {
                      if (unitSel == u.id) return;
                      setState(() => unitSel = u.id);
                    },
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              for (final p in _periods.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.value),
                    selected: period == p.key,
                    onSelected: (_) {
                      setState(() {
                        period = p.key;
                        loading = true;
                      });
                      load();
                    },
                  ),
                ),
              const SizedBox(width: 8),
              const VerticalDivider(width: 1, indent: 10, endIndent: 10),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('播放量'),
                selected: metric == 'play',
                onSelected: (_) {
                  if (metric == 'play') return;
                  setState(() {
                    metric = 'play';
                    loading = true;
                  });
                  load();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('小水滴'),
                selected: metric == 'drop',
                onSelected: (_) {
                  if (metric == 'drop') return;
                  setState(() {
                    metric = 'drop';
                    loading = true;
                  });
                  load();
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Row(children: [
            const Icon(Icons.leaderboard, size: 13, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    metric == 'drop'
                        ? '按${_periods[period]}统计作者收到的小水滴'
                        : '按${_periods[period]}统计作者播放量',
                    style: const TextStyle(fontSize: 11, color: Colors.grey))),
          ]),
        ),
        // J10/J11：排行榜复用同一套作者筛选（状态与其他页面共享）
        AuthorFilterBar(
          filter: filter,
          loading: typesLoading,
          onOpen: _openFilter,
          onClear: authorFilter.clearAll,
          summary: filter.isActive
              ? '${filter.summary(basicNames: _filterLibNames, bigNames: _filterBigNames, unitNames: _filterUnitNames)} · 命中 ${visible.length}/${rows.length}'
              : null,
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : err != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text('加载失败：$err',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12))),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: load, child: const Text('重试')),
                    ]))
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                              filter.isActive
                                  ? '没有符合筛选条件的作者'
                                  : (metric == 'drop'
                                      ? '本期还没有小水滴，去播放页送一颗吧'
                                      : '本期还没有播放记录'),
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: visible.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final e = visible[i];
                            final name = '${e['name'] ?? ''}';
                            final av = '${e['avatar'] ?? ''}';
                            final score = _n(e['score']);
                            final rowLib = sel == 'all'
                                ? '${e['lib'] ?? cfg.lib}'
                                : (sel.isEmpty ? cfg.lib : sel);
                            final meta = metas[rowLib];
                            String libName(String id) {
                              for (final l in libs) {
                                if ('${l['id']}' == id) {
                                  return '${l['name'] ?? l['id']}';
                                }
                              }
                              return id;
                            }

                            return AuthorRankTile(
                              rank: i + 1,
                              rankColor: _rankColor(context, i),
                              name: name,
                              avatar: av,
                              lib: rowLib,
                              libName: libName(rowLib),
                              meta: meta,
                              works: _n(e['works']),
                              plays: _n(e['plays']),
                              drops: _n(e['drops']),
                              scoreText:
                                  metric == 'drop' ? '💧 $score' : '$score',
                              onTap: name.isEmpty ? null : () => _open(name),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

// 各库总播放量/水滴数排行榜：离线库不参与
class LibraryRankPage extends StatefulWidget {
  const LibraryRankPage({super.key});
  @override
  State<LibraryRankPage> createState() => _LibraryRankPageState();
}

class _LibraryRankPageState extends State<LibraryRankPage> {
  String metric = 'play';
  List<LibraryRankRow> rows = [];
  int skipped = 0;
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (mounted) setState(() => err = null);
    try {
      final r = await http
          .get(cfg.u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final list = librariesWithDisplayNames(
          ((j['libraries'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());

      final loaded = <String, Map<String, dynamic>>{};
      var offline = 0;
      for (final lib in list) {
        final id = '${lib['id'] ?? ''}';
        if (id.isEmpty) continue;
        if (!libraryOnline(lib)) {
          offline++;
          continue;
        }
        try {
          final sr = await http
              .get(cfg.u('/api/author_stats.json', lib: id),
                  headers: cfg.headers)
              .timeout(const Duration(seconds: 8));
          if (sr.statusCode != 200) {
            offline++;
            continue;
          }
          loaded[id] = statsAuthors(jsonDecode(sr.body));
        } catch (_) {
          offline++;
        }
      }

      final ranked = buildLibraryRank(
        libs: list,
        stats: loaded,
        metric: metric,
        currentLib: cfg.lib,
      );
      if (!mounted) return;
      setState(() {
        rows = ranked;
        skipped = offline;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          err = '$e';
          loading = false;
        });
      }
    }
  }

  Color _rankColor(BuildContext context, int i) {
    if (i == 0) return const Color(0xFFFFC107);
    if (i == 1) return const Color(0xFFB0BEC5);
    if (i == 2) return const Color(0xFFBF8970);
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('各库排行'), actions: [
        IconButton(
            tooltip: '刷新', onPressed: load, icon: const Icon(Icons.refresh)),
        const HomeAction(),
      ]),
      body: Column(children: [
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            children: [
              ChoiceChip(
                label: const Text('总播放量'),
                selected: metric == 'play',
                onSelected: (_) {
                  if (metric == 'play') return;
                  setState(() => metric = 'play');
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('总水滴数'),
                selected: metric == 'drop',
                onSelected: (_) {
                  if (metric == 'drop') return;
                  setState(() => metric = 'drop');
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Row(children: [
            const Icon(Icons.stacked_bar_chart, size: 13, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
                child: Text(
                    '${rows.length} 个库参与'
                    '${skipped > 0 ? ' · 已跳过 $skipped 个离线库' : ''}'
                    ' · 统计来自本机',
                    style: const TextStyle(fontSize: 11, color: Colors.grey))),
          ]),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : err != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text('加载失败：$err',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12))),
                      const SizedBox(height: 12),
                      FilledButton(onPressed: load, child: const Text('重试')),
                    ]))
                  : rows.isEmpty
                      ? const Center(
                          child: Text('暂无可参与排行的库',
                              style:
                                  TextStyle(color: Colors.grey, fontSize: 12)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final score = metric == 'drop' ? r.drops : r.plays;
                            final sub = metric == 'drop'
                                ? '播放 ${r.plays} · ${r.drops} 水滴'
                                : '${r.plays} 播放 · ${r.drops} 水滴';
                            return ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              leading: SizedBox(
                                width: 34,
                                child: Text('${r.rank}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _rankColor(context, i))),
                              ),
                              title: Row(children: [
                                Flexible(
                                  child: Text(r.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (r.current)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: Colors.lightBlueAccent
                                            .withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Text('当前',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.lightBlueAccent)),
                                  ),
                              ]),
                              subtitle: Text(sub,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                              trailing: Text(
                                  metric == 'drop' ? '💧 $score' : '$score',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.lightBlueAccent)),
                              onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          RankPage(initialLib: r.id))),
                            );
                          },
                        ),
        ),
      ]),
    );
  }
}

/// 作者卡（网格）：作者总览唯一实现。
///
/// 规格：圆角 12、高 170、头像 58、左上单元库词条 + 等级、
/// 名称/统计/作品数各一行、文字一律单行省略，卡片尺寸不随内容变化。
class AuthorGridCard extends StatelessWidget {
  static const double radius = 12;
  static const double extent = 170;

  final String name;
  final String avatar;
  final String lib;
  final LibMeta? meta;
  final Map<String, dynamic> stats;
  final int works;
  final String subtitle;
  final VoidCallback? onTap;

  const AuthorGridCard({
    super.key,
    required this.name,
    required this.avatar,
    required this.lib,
    required this.meta,
    required this.stats,
    required this.works,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: Stack(fit: StackFit.expand, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
              decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(radius)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: AuthorAvatar(
                      name: name,
                      mediaPath: avatar,
                      lib: lib,
                      size: AuthorAvatar.gridSize,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 16,
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: 13,
                    child: Text(subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10, color: scheme.onSurfaceVariant)),
                  ),
                  SizedBox(
                    height: 12,
                    child: Text('$works 作品',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 9,
                            color: scheme.onSurfaceVariant
                                .withValues(alpha: 0.7))),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 5,
              left: 5,
              right: 4,
              child: AuthorBadges(
                meta: meta,
                name: name,
                mediaPath: avatar,
                fallbackId: lib,
                fallbackName: meta?.names[lib] ?? lib,
                works: works,
                stats: stats,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 作者行（排行榜）：排名 + 头像 + 名称 + 单元库词条/等级 + 指标 + 分数。
class AuthorRankTile extends StatelessWidget {
  final int rank;
  final Color rankColor;
  final String name;
  final String avatar;
  final String lib;
  final String libName;
  final LibMeta? meta;
  final int works;
  final int plays;
  final int drops;
  final String scoreText;
  final VoidCallback? onTap;

  const AuthorRankTile({
    super.key,
    required this.rank,
    required this.rankColor,
    required this.name,
    required this.avatar,
    required this.lib,
    required this.libName,
    required this.meta,
    required this.works,
    required this.plays,
    required this.drops,
    required this.scoreText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: 30,
            child: Text('$rank',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: rankColor))),
        AuthorAvatar(
          name: name,
          mediaPath: avatar,
          lib: lib,
          size: AuthorAvatar.rankSize,
        ),
      ]),
      title: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AuthorBadges(
          meta: meta,
          name: name,
          mediaPath: avatar,
          fallbackId: lib,
          fallbackName: libName,
          works: works,
        ),
        const SizedBox(height: 2),
        Text('播放 $plays · 水滴 $drops · $works 作品',
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
      trailing: Text(scoreText,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.lightBlueAccent)),
      onTap: onTap,
    );
  }
}

// 作者网格页：头像平铺，按播放量/访问次数/访问日期/作品数/小水滴排序
class AuthorGridPage extends StatefulWidget {
  const AuthorGridPage({super.key});
  @override
  State<AuthorGridPage> createState() => _AuthorGridPageState();
}

class _AuthorGridPageState extends State<AuthorGridPage> {
  static const _sorts = <String, String>{
    'plays': '播放量',
    'visits': '访问次数',
    'visited': '访问日期',
    'works': '作品数',
    'drops': '小水滴',
  };

  List<MapEntry<String, Map<String, dynamic>>> authors = [];
  Map<String, dynamic> stats = {};
  // 0.9.8：作者数据源改为全部基础库（`/api/authors.json?lib=all`）。
  // libs 仅保留大库筛选项（全部基础库 / big-01…），basics 用于筛选面板。
  List<Map<String, dynamic>> libs = [];
  List<BasicLibRef> basics = const [];
  String sel = 'all';
  final Map<String, List<String>> authorLibs = {};
  // J9：库 -> 基础库/统计映射，用于显示基础库来源词条
  final Map<String, LibMeta> metas = {};
  String sort = 'plays';
  bool loading = true;
  String? err;
  bool syncing = false;
  // 当前库是否配置了爬虫脚本；没有脚本时禁用联网同步按钮。
  bool hasScripts = false;
  // G19：作者网格渐进渲染，避免一次构建上千个头像卡顿
  int _shown = 0;
  Timer? syncTimer;
  // I7：排序结果只算一次并缓存；返回作者页时静默刷新，数据没变就不重建网格
  List<MapEntry<String, Map<String, dynamic>>> _ordered = const [];
  final ScrollController _scroll = ScrollController();
  String _sig = '';
  // T1：作者卡没有现成头像（av 为空）时，从该作者作品图里挑一张兜底。
  // 只对缺头像的作者发一次请求，结果按「库|作者」缓存在内存里。
  final Map<String, String> _avFallback = {};
  final Set<String> _avLookup = {};
  // J11：作者筛选状态全 App 共享（总览/排行/搜索/推荐同一份）
  AuthorFilterState get filter => authorFilter.value;
  Map<String, Set<String>> authorTypes = {};
  bool typesLoading = false;
  String _typesForSel = '';

  @override
  void initState() {
    super.initState();
    authorFilter.addListener(_onSharedFilter);
    sel = 'all';
    loadLibs();
    LibraryBadge.load().then((_) {
      if (mounted) setState(() {});
    });
    AuthorGrade.load().then((_) {
      if (mounted) setState(() {});
    });
    load();
  }

  @override
  void dispose() {
    authorFilter.removeListener(_onSharedFilter);
    syncTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onSharedFilter() {
    if (!mounted) return;
    setState(() => _applyOrder());
  }

  Future<void> _syncAuthors() async {
    if (syncing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('立即同步作者'),
        content: const Text('只补抓缺少头像/简介的作者，速度较快。\n'
            '需要整位作者全量刷新，请进入该作者主页同步。\n\n同步在 NAS 后台运行。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('开始同步')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final j = await startServerSync(target: 'authors');
    if (j == null || j['ok'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('同步启动失败：${j?['error'] ?? '网络错误'}')));
      }
      return;
    }
    setState(() => syncing = true);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已开始同步作者，完成后自动刷新')));
    }
    syncTimer?.cancel();
    var tries = 0;
    syncTimer = Timer.periodic(const Duration(seconds: 4), (t) async {
      tries++;
      final s = await serverSyncStatus();
      if (!mounted) {
        t.cancel();
        return;
      }
      if (s == null) {
        if (tries > 5) {
          t.cancel();
          setState(() => syncing = false);
        }
        return;
      }
      if (s['running'] == true) return;
      t.cancel();
      setState(() => syncing = false);
      final code = s['exit'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(code == 0 ? '作者同步完成' : '作者同步结束（退出码 $code）')));
      }
      await load();
    });
  }

  Future<void> loadLibs() async {
    try {
      final meta = await LibMeta.load(cfg.lib);
      if (!mounted) return;
      final list = [
        for (final e in meta.bigNames.entries) {'id': e.key, 'name': e.value}
      ]..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
      setState(() {
        basics = meta.basics;
        libs = list;
        metas[cfg.lib] = meta;
      });
      try {
        final cr = await http.get(
            Uri.parse('${cfg.base}/api/crawler?lib=${Uri.encodeQueryComponent(cfg.lib)}'),
            headers: cfg.headers).timeout(const Duration(seconds: 8));
        if (cr.statusCode == 200) {
          final cj = jsonDecode(cr.body);
          final scripts = (cj is Map ? cj['scripts'] : null);
          if (mounted) {
            setState(
                () => hasScripts = scripts is List && scripts.isNotEmpty);
          }
        }
      } catch (_) {}
    } catch (_) {}
  }

  /// [quiet] 为 true 时用于从作者页返回后的静默刷新：
  /// 不显示加载骨架、不重置滚动位置，数据签名没变就完全不 setState，
  /// 避免整页 Grid 重建造成返回卡顿（I7）。
  Future<void> load({bool quiet = false}) async {
    if (mounted) {
      if (!quiet) {
        setState(() {
          err = null;
          loading = true;
        });
      } else if (err != null) {
        setState(() => err = null);
      }
    }
    final auMap = <String, Map<String, dynamic>>{};
    final stMap = <String, Map<String, dynamic>>{};
    final auLibs = <String, List<String>>{};
    try {
      // 全部基础库合并索引（服务端 lib=all：同名作者作品数相加，libs 带出处）。
      final ar = await http
          .get(cfg.u('/api/authors.json', lib: 'all'), headers: cfg.headers)
          .timeout(const Duration(seconds: 20));
      final sr = await http
          .get(cfg.u('/api/author_stats.json', lib: cfg.lib),
              headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (ar.statusCode != 200) throw Exception('HTTP ${ar.statusCode}');
      final m = jsonDecode(utf8.decode(ar.bodyBytes)) as Map<String, dynamic>;
      for (final e in m.entries) {
        if (e.value is! Map) continue;
        final v = Map<String, dynamic>.from(e.value as Map);
        final ls = (v['libs'] as List?)?.whereType<String>().toList() ??
            const <String>[];
        auMap[e.key] = {...v, '_lib': ls.isNotEmpty ? ls.first : cfg.lib};
        if (ls.isNotEmpty) auLibs[e.key] = ls;
      }
      dynamic sj;
      if (sr.statusCode == 200) {
        try {
          sj = jsonDecode(sr.body);
        } catch (_) {}
      }
      if (sj is Map && sj['authors'] is Map) {
        for (final e in (sj['authors'] as Map).entries) {
          if (e.value is! Map) continue;
          stMap['${e.key}'] = Map<String, dynamic>.from(e.value as Map);
        }
      }
      final meta = await LibMeta.load(cfg.lib);
      if (!mounted) return;
      metas[cfg.lib] = meta;
      basics = meta.basics;
      if (!mounted) return;
      final entries =
          auMap.entries.map((e) => MapEntry(e.key, e.value)).toList();
      final sig = _dataSignature(entries, stMap);
      if (quiet && sig == _sig) {
        // 返回作者页但统计/头像都没变化：直接结束，网格与滚动位置保持原样
        if (loading) setState(() => loading = false);
        return;
      }
      final keepScroll = quiet;
      setState(() {
        authors = entries;
        stats = stMap;
        authorLibs
          ..clear()
          ..addAll(auLibs);
        _sig = sig;
        _applyOrder(resetShown: !keepScroll);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        // 静默刷新失败时保留现有列表，不打扰用户
        if (quiet) return;
        setState(() {
          err = '$e';
          loading = false;
        });
      }
    }
  }

  /// 仅用于判断「返回后数据是否真的变了」：作者数、头像、作品数与三项统计。
  String _dataSignature(List<MapEntry<String, Map<String, dynamic>>> entries,
      Map<String, dynamic> stMap) {
    final b = StringBuffer(sel)
      ..write('|')
      ..write(entries.length);
    for (final e in entries) {
      b
        ..write('|')
        ..write(e.key)
        ..write(':')
        ..write(e.value['av'] ?? '')
        ..write(':')
        ..write(e.value['n'] ?? 0)
        ..write(':')
        ..write(e.value['bio'] ?? '');
      final s = stMap[e.key];
      if (s is Map) {
        b
          ..write(':')
          ..write(s['p'] ?? 0)
          ..write(':')
          ..write(s['v'] ?? 0)
          ..write(':')
          ..write(s['dr'] ?? 0)
          ..write(':')
          ..write(s['lv'] ?? 0);
      }
    }
    return b.toString();
  }

  Map<String, dynamic> _s(String name) => stats[name] is Map
      ? Map<String, dynamic>.from(stats[name] as Map)
      : const {};

  LibMeta? _metaOf(MapEntry<String, Map<String, dynamic>> e) =>
      metas[cfg.lib] ?? (basics.isEmpty ? null : metas.values.first);

  String _basicIdOf(MapEntry<String, Map<String, dynamic>> e) {
    final m = _metaOf(e);
    final byAv = m?.basicIdForPath('${e.value['av'] ?? ''}') ?? '';
    if (byAv.isNotEmpty) return byAv;
    // 合并索引已给出作者出处；无头像时也能筛选到所属基础库。
    final l = '${e.value['_lib'] ?? ''}';
    return l.startsWith('lib-') && m?.basicById(l) != null ? l : '';
  }

  String _bigIdOf(MapEntry<String, Map<String, dynamic>> e) {
    final m = _metaOf(e);
    final byAv = m?.bigIdFor('${e.value['av'] ?? ''}') ?? '';
    if (byAv.isNotEmpty) return byAv;
    final b = m?.basicById(_basicIdOf(e));
    return b?.bigId ?? '';
  }

  // T2：作者所属单元库 id（顶级 SECRET / 无归属为空）。
  String _unitIdOf(MapEntry<String, Map<String, dynamic>> e) {
    final m = _metaOf(e);
    final byAv = m?.unitIdFor('${e.value['av'] ?? ''}') ?? '';
    if (byAv.isNotEmpty) return byAv;
    final b = _basicIdOf(e);
    return b.isEmpty ? '' : (m?.basicToUnit[b] ?? '');
  }

  String _gradeOf(MapEntry<String, Map<String, dynamic>> e) =>
      AuthorGrade.gradeFor(
        plays: _num(_s(e.key)['p']),
        drops: _num(_s(e.key)['dr']),
        works: _num(e.value['n']),
      );

  Set<String> _typesOf(String name) => authorTypes[name] ?? const <String>{};

  /// J10：把当前可见的 meta 汇总成筛选面板需要的节点。
  List<AuthorLibNode> get _filterBasics {
    final meta = metas[cfg.lib];
    final nodes = <AuthorLibNode>[
      if (meta != null)
        for (final b in meta.basics)
          AuthorLibNode(
              id: b.id, name: basicLibLabel(b, b.name), bigId: b.bigId)
    ];
    return authorLibNodes(nodes);
  }

  List<AuthorBigNode> get _filterBigs {
    final out = <AuthorBigNode>[];
    final seen = <String>{};
    for (final b in _filterBasics) {
      if (b.bigId.isEmpty || !seen.add(b.bigId)) continue;
      var name = b.bigId;
      for (final m in metas.values) {
        final n = m.bigNames[b.bigId];
        if (n != null && n.isNotEmpty) {
          name = n;
          break;
        }
      }
      out.add(AuthorBigNode(id: b.bigId, name: name));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Map<String, String> get _filterLibNames =>
      {for (final b in _filterBasics) b.id: b.name};

  Map<String, String> get _filterBigNames =>
      {for (final b in _filterBigs) b.id: b.name};

  /// T2：单元库筛选选项（含顶级 SECRET）。
  List<AuthorLibNode> get _filterUnits {
    final out = <AuthorLibNode>[];
    final seen = <String>{};
    for (final m in metas.values) {
      for (final u in m.units) {
        if (!seen.add(u.id)) continue;
        out.add(AuthorLibNode(id: u.id, name: m.unitNameOf(u.id)));
      }
    }
    return authorLibNodes(out);
  }

  Map<String, String> get _filterUnitNames =>
      {for (final u in _filterUnits) u.id: u.name};

  int _filterCount(AuthorFilterState f) => countMatchingAuthors(
        authors,
        f,
        basicIdOf: (e) => _basicIdOf(MapEntry('', e)),
        bigIdOf: (e) => _bigIdOf(MapEntry('', e)),
        unitIdOf: (e) => _unitIdOf(MapEntry('', e)),
        gradeOf: (name, e) => _gradeOf(MapEntry(name, e)),
        typesOf: _typesOf,
      );

  Future<void> _ensureTypes() async {
    if (typesLoading) return;
    if (_typesForSel == sel && authorTypes.isNotEmpty) return;
    setState(() => typesLoading = true);
    // 类型索引一次扫全部基础库（服务端 /api/lib/<id>/index.json）。
    final map = await loadAuthorTypes([cfg.lib]);
    if (!mounted) return;
    setState(() {
      authorTypes = map;
      _typesForSel = sel;
      typesLoading = false;
      _applyOrder();
    });
  }

  Future<void> _openFilter() async {
    await _ensureTypes();
    if (!mounted) return;
    final res = await showAuthorFilterSheet(
      context: context,
      initial: filter,
      basics: _filterBasics,
      bigs: _filterBigs,
      units: _filterUnits,
      grades: const ['S', 'A', 'B', 'C', 'D'],
      count: _filterCount,
    );
    if (res == null || !mounted) return;
    authorFilter.apply(res);
  }

  int _num(dynamic v) =>
      v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

  int _metric(MapEntry<String, Map<String, dynamic>> e) {
    final s = _s(e.key);
    switch (sort) {
      case 'visits':
        return _num(s['v']);
      case 'visited':
        return _num(s['lv']);
      case 'works':
        return _num(e.value['n']);
      case 'drops':
        return _num(s['dr']);
      default:
        return _num(s['p']);
    }
  }

  /// I7：排序只在数据/排序方式变化时执行一次，结果缓存在 [_ordered]，
  /// build 与滚动回调都只读缓存，避免上千作者反复排序。
  void _applyOrder({bool resetShown = true}) {
    final base = authors.where((e) {
      if (sel != 'all' && _bigIdOf(e) != sel) return false;
      if (!filter.isActive) return true;
      return filter.matches(
        basicId: _basicIdOf(e),
        bigId: _bigIdOf(e),
        unitId: _unitIdOf(e),
        grade: _gradeOf(e),
        workTypes: _typesOf(e.key),
      );
    }).toList();
    _ordered = sortAuthorEntries(base,
        metric: _metric, works: (e) => _num(e.value['n']), name: (e) => e.key);
    if (resetShown) {
      _shown = _ordered.length;
    } else if (_shown > _ordered.length) {
      _shown = _ordered.length;
    }
  }

  String _fmtDate(int sec) {
    if (sec <= 0) return '未访问';
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000).toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  String _selLabel() {
    if (sel == 'all') return '全部基础库';
    for (final l in libs) {
      if ('${l['id']}' == sel) return '${l['name'] ?? l['id']}';
    }
    return '全部基础库';
  }

  String _sub(MapEntry<String, Map<String, dynamic>> e) {
    final s = _s(e.key);
    switch (sort) {
      case 'visits':
        return '访问 ${_num(s['v'])} 次';
      case 'visited':
        return '最近 ${_fmtDate(_num(s['lv']))}';
      case 'works':
        return '${_num(e.value['n'])} 个作品';
      case 'drops':
        return '水滴 ${_num(s['dr'])}';
      default:
        return '播放 ${_num(s['p'])}';
    }
  }

  // T1：为缺头像的作者取一张作品图兜底（每条作者+库只发一次请求）。
  Future<void> _fetchFallbackAvatar(String name, String lib, String idx) async {
    if (!mounted) return;
    final key = '$lib|$name';
    if (_avLookup.contains(key)) return;
    _avLookup.add(key);
    try {
      final r = await http.get(cfg.u('/api/a/$idx.json', lib: lib),
          headers: cfg.headers);
      if (r.statusCode != 200) return;
      final m = jsonDecode(r.body);
      final pick = pickFallbackAvatar(avatarCandidatesFromWorks(
          ((m is Map ? m['works'] : null) as List?)?.whereType<Map>() ??
              const <Map>[]));
      if (pick == null || pick.isEmpty || !mounted) return;
      setState(() => _avFallback[key] = pick);
    } catch (_) {}
  }

  Future<void> _open(String name) async {
    final ls =
        (authorLibs[name]?.isNotEmpty ?? false) ? authorLibs[name]! : [cfg.lib];
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AuthorPage(name: name, libs: List<String>.from(ls))));
    // I7：返回时静默刷新统计；数据未变化则完全不 setState，网格不重建
    if (mounted) await load(quiet: true);
  }

  Widget _authorCell(MapEntry<String, Map<String, dynamic>> e) {
    final av = '${e.value['av'] ?? ''}';
    final lib = '${e.value['_lib'] ?? (sel == 'all' ? cfg.lib : sel)}';
    final meta = metas[cfg.lib] ?? (metas.isEmpty ? null : metas.values.first);

    // T1：av 优先；没有 av 用作品图兜底；都拿不到才显示首字母占位
    final fallbackKey = '$lib|${e.key}';
    final shownAv = av.isNotEmpty ? av : (_avFallback[fallbackKey] ?? '');
    if (av.isEmpty && shownAv.isEmpty) {
      final idx = '${e.value['i'] ?? ''}';
      if (idx.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fetchFallbackAvatar(e.key, lib, idx);
        });
      }
    }
    return AuthorGridCard(
      name: e.key,
      avatar: shownAv,
      lib: lib,
      meta: meta,
      stats: _s(e.key),
      works: _num(e.value['n']),
      subtitle: _sub(e),
      onTap: () => _open(e.key),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作者'), actions: [
        const HomeAction(),
        IconButton(
            tooltip: '各库排行',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LibraryRankPage())),
            icon: const Icon(Icons.stacked_bar_chart)),
        IconButton(
            tooltip: syncing
                ? '同步中…'
                : (hasScripts ? '立即同步作者' : '当前库未配置爬虫脚本'),
            onPressed: (syncing || !hasScripts) ? null : _syncAuthors,
            icon: syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_sync_outlined)),
        IconButton(
            tooltip: '刷新', onPressed: load, icon: const Icon(Icons.refresh)),
      ]),
      body: loading
          ? const WorkGridSkeleton(count: 18)
          : err != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text('加载失败：$err',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12))),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: load, child: const Text('重试')),
                ]))
              : Column(children: [
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: const Text('全部基础库'),
                            selected: sel == 'all',
                            onSelected: (_) {
                              if (sel == 'all') return;
                              setState(() {
                                sel = 'all';
                                loading = true;
                                _shown = 0;
                              });
                              load();
                            },
                          ),
                        ),
                        for (final l in libs)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${l['name'] ?? l['id']}'),
                              selected: sel == '${l['id']}',
                              onSelected: (_) {
                                if (sel == '${l['id']}') return;
                                setState(() {
                                  sel = '${l['id']}';
                                  loading = true;
                                  _shown = 0;
                                });
                                load();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      children: [
                        for (final s in _sorts.entries)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(s.value),
                              selected: sort == s.key,
                              onSelected: (_) => setState(() {
                                sort = s.key;
                                _applyOrder();
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // J10/J11：筛选工具入口；状态与其他页面共享
                  AuthorFilterBar(
                    filter: filter,
                    loading: typesLoading,
                    onOpen: _openFilter,
                    onClear: authorFilter.clearAll,
                    summary: filter.isActive
                        ? filter.summary(
                            basicNames: _filterLibNames,
                            bigNames: _filterBigNames,
                            unitNames: _filterUnitNames)
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 8, 6),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              '${_ordered.length}${filter.isActive ? '/${authors.length}' : ''} 位作者 · ${_selLabel()} · 播放/访问/水滴为本机统计',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey))),
                    ]),
                  ),
                  Expanded(
                    child: authors.isEmpty
                        ? const Center(
                            child: Text('暂无作者数据',
                                style: TextStyle(color: Colors.grey)))
                        : Builder(builder: (context) {
                            // 全量作者 + 固定高度网格：GridView 自身虚拟化，
                            // 卡片尺寸统一，不再用「渐进显示」限制条数。
                            return GridView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 150,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                mainAxisExtent: 170,
                              ),
                              itemCount: _ordered.length,
                              itemBuilder: (_, i) => _authorCell(_ordered[i]),
                            );
                          }),
                  ),
                ]),
    );
  }
}

// G12：图片加载失败占位（弱网/文件损坏）+ 重试按钮
class _MediaRetryBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _MediaRetryBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.broken_image_outlined,
              size: 40, color: Colors.white38),
          const SizedBox(height: 8),
          Text(message,
              style: const TextStyle(fontSize: 13, color: Colors.white60)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                minimumSize: const Size(104, 34)),
          ),
        ]),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final List works;
  final int start;
  // 作品可能来自非当前库（按库筛选 / 全部库），lib 为列表默认所属库
  final String? lib;
  // T3：不再携带旧「收藏夹」idx/名称，来源只由单元库体系表达
  const PlayerPage(
      {super.key, required this.works, required this.start, this.lib});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// G18：两个播放器槽位。A 播放当前作品，B 在后台静音预缓冲下一条；
/// 切条时交换槽位，预缓冲好的媒体无需重新打开即可起播。
class _PlaybackSlot {
  final String tag;
  final int sid;

  /// 每次换媒体/取消预加载时递增，迟到的异步任务据此放弃。
  int epoch = 0;
  late final Player player;
  late final VideoController vc;

  _PlaybackSlot(this.tag,
      {this.sid = 0, DecodeMode mode = DecodeMode.hardware}) {
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'Dizi',
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    // Windows：显式使用安全硬件解码，避免窗口缩放/最大化时纹理重建导致崩溃
    vc = VideoController(
      player,
      configuration: VideoControllerConfiguration(hwdec: hwdecFor(mode)),
    );
  }
}

class _PlayerPageState extends State<PlayerPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final PageController pc = PageController(initialPage: widget.start);
  // F34：解码失败时可整体切换到软件解码，槽位因此不是 final
  // M6：播放器槽位池。A 为当前播放器，其余槽位用于按滑动方向预加载，
  // 命中缓存时直接切换为活动槽位，避免切条重新打开媒体。
  late final List<_PlaybackSlot> _slots = <_PlaybackSlot>[_PlaybackSlot('a')];
  int _slotActive = 0;
  int _slotSeq = 1;
  DecodeMode _decodeMode = DecodeMode.hardware;
  bool _softwareDecodeRetried = false;
  // 槽位重建后强制重建 Video，避免沿用旧控制器的纹理
  int _videoGen = 0;
  _PlaybackSlot get _active => _slots[_slotActive];
  // 对播放页其余代码保持原有 player / vc 接口，内部指向当前活动槽位
  Player get player => _active.player;
  VideoController get vc => _active.vc;
  // M6：预加载账本 + 运行状态
  final PreloadCache _preloadCache =
      PreloadCache(maxEntries: preloadMaxPerSide * 2);
  final Map<int, String> _preloadBusy = <int, String>{};
  Timer? _preloadTimer;
  int _preloadGen = 0;
  bool _preloadRunning = false;
  // 最近一次滑动/切条方向：1 向下，-1 向上，0 未知
  int _preloadDir = 0;
  final List<StreamSubscription> _playerSubs = <StreamSubscription>[];
  final FocusNode focus = FocusNode();
  int cur = 0;
  int img = 0;
  // J5：视频合集当前章节（非合集恒为 0）
  int _chapter = 0;
  int _openToken = 0;
  double _wheelAcc = 0;
  bool _wheelLock = false;
  Timer? _wheelUnlock;
  Timer? _wheelIdle;
  bool _fsBusy = false;
  int _lastPosSet = 0;
  int _navAt = 0;
  int _lastKeyNav = 0;
  int? _pendingPage;
  bool paused = false;
  // G16：是否因切后台而暂停（回前台时只恢复这种暂停）
  bool _pausedByBackground = false;
  bool loading = true;
  bool muted = false;
  double volume = 100;
  double lastVol = 100;
  // H14：音量常驻任务栏，点击喇叭=静音切换；长按/拖动调音量，
  // 不再弹独立音量模块。拖动中只显示一个轻量提示（松手后自动消失）。
  bool showVol = false;
  bool _volAdjusting = false;
  double _volStart = 100;
  double _volStartDx = 0;
  Timer? _volHintTimer;
  bool get _volHintVisible => _volAdjusting || showVol;
  // G15：移动端左右两侧上下滑——左侧亮度、右侧音量，中间仍可翻页。
  // 亮度用应用内压暗遮罩实现，不引入原生插件；桌面端不启用。
  double brightness = 100;
  bool _swipeActive = false;
  bool _swipeShow = false;
  SwipeZone? _swipeZone;
  double _swipeStartY = 0;
  double _swipeStartValue = 0;
  double _swipeValue = 0;
  int _swipeStep = 0;
  Timer? _swipeHintTimer;
  bool get _swipeHint => _swipeActive || _swipeShow;
  bool get _mobileSwipe =>
      swipeEnabledFor(isAndroid: Platform.isAndroid, isIOS: Platform.isIOS);
  // I1：音量调节 UI 仅桌面端保留，移动端交给系统音量键。
  bool get _volumeUi => volumeUiEnabled(
      isDesktop: Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  // M1 仅移动端改变全屏单击语义；M3 要求 Windows 交互不变（仍单击暂停）。
  bool get _mobileStageTap => Platform.isAndroid || Platform.isIOS;
  bool ui = true;
  bool fs = false;
  // M5：非全屏上下拖拽切条期间，功能区整体淡化（松手恢复）。
  bool _pageSwiping = false;
  // M2：是否由播放页主动锁定过屏幕方向（退出时需恢复系统默认）。
  bool _orientationForced = false;
  bool dragging = false;
  // H13：简介在任务栏内展开（不再弹独立窗口）
  bool captionOpen = false;
  bool barHover = false;
  int pointers = 0;
  // 清屏双指轻触：改为松手时判定，捏合缩放不会误触
  final Map<int, Offset> _stagePointers = <int, Offset>{};
  DateTime? _twoFingerAt;
  bool _twoFingerMoved = false;
  final Map<int, Offset> _twoFingerStarts = <int, Offset>{};
  // G14：图文双指缩放（放大后单击恢复）
  PicZoom _picZoom = PicZoom.initial;
  final Map<int, Offset> _zoomPointers = <int, Offset>{};
  Size _stageSize = Size.zero;
  double _pinchStartDist = 0;
  PicZoom _pinchStartZoom = PicZoom.initial;
  Offset _pinchStartFocal = Offset.zero;
  bool _pinching = false;
  // 每条作品可带 _lib（跨库列表），否则用本页 lib，最后回退当前库
  String _libFor(dynamic w) =>
      '${(w is Map ? w['_lib'] : null) ?? widget.lib ?? cfg.lib}';

  /// G20：安全取作品。列表里意外出现非 Map 条目时用空 Map 顶部，
  /// 让该条显示「作品不可用」占位，而不是让整页 build 抛异常。
  dynamic _workAt(int i) {
    if (i < 0 || i >= widget.works.length) return const <String, dynamic>{};
    final w = widget.works[i];
    if (w is! Map) return const <String, dynamic>{};
    // J5：当前作品的视频合集按 _chapter 叠加章节媒体；
    // 其他条目（预缓冲下一条）始终返回首章。
    if (i == cur) return workWithChapter(w, _chapter);
    return w;
  }

  String get _curLib => _libFor(_workAt(cur));
  double _hoverDx = -1;
  double _hoverDy = -1;
  // L6：单条循环与自动连播的联动集中到 LoopLink（打开循环自动关连播，
  // 关闭循环恢复打开前的连播状态）。
  LoopLink _link = const LoopLink();
  bool get autoplay => _link.autoplay;
  bool get loopOne => _link.loopOne;
  // 当前页面实际已载入的媒体所属 open token；图文无音频时为 -1。
  // 用于忽略 player.stop()/切条时上一段媒体迟到的 completed 事件，
  // 避免刚打开图文就被上一次播放的完成事件带去下一条。
  int _mediaToken = -1;
  // 切条（stop/open）进行中：此时播放器会发出 playing=false，
  // 不能据此改写 paused，否则下一条会停在首帧（F32）。
  bool _opening = false;
  // 连播兜底：视频已就绪但播放器未在播放时补一次 play。
  Timer? playGuard;
  double? dragFrac;
  // 图文进度条拖动时当前指向的图片序号（null = 未在拖动）
  int? dragPic;
  bool resumeAfterDrag = false;
  bool dropBusy = false;
  int dropDayLeft = 1;
  int dropWeekLeft = 3;
  int dropTotal = 0;
  // H15：本次打开作品后是否已送过水滴（决定图标是否变蓝）与点击弹跳动效
  bool dropGlow = false;
  late final AnimationController _dropAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 380));
  late final Animation<double> _dropScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.32)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40),
    TweenSequenceItem(
        tween: Tween(begin: 1.32, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60),
  ]).animate(_dropAnim);
  // G9：双击点赞（仅本地标记）。红心在点击位置弹一下并淡出。
  final Set<String> likedKeys = <String>{};
  Offset? _heartPos;
  int _lastStageTapAt = 0;
  Offset _lastStageTapPos = Offset.zero;
  bool _tapWasPausedBefore = false;
  late final AnimationController _heartAnim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 650));
  late final Animation<double> _heartScale = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 0.55, end: 1.25)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 45),
    TweenSequenceItem(
        tween: Tween(begin: 1.25, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 55),
  ]).animate(_heartAnim);
  double speed = 1.0;
  Duration pos = Duration.zero;
  Duration dur = Duration.zero;
  Timer? autoTimer;
  Timer? hideTimer;
  Timer? retryTimer;
  // I3：起播静音淡入（定时器 + 代数，用户调音量/切条时立即作废）
  Timer? _fadeTimer;
  int _fadeGen = 0;
  // G12：加载超时 / 播放器报错提示与重试
  PlaybackFailure? _failure;
  Timer? _loadTimeout;
  bool _buffering = false;
  bool _slowBuffer = false;
  Timer? _slowBufferTimer;
  // J9：当前库的基础库/统计，用于信息行的来源词条与等级词条
  LibMeta? _meta;
  String _metaLib = '';
  int _imgReload = 0;
  bool manualPic = false;
  StreamSubscription? subPos;
  StreamSubscription? subDur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cur = widget.start;
    speed = AppSettings.defaultSpeed;
    _loadLikes();
    _ensureMetaFor(_curLib);
    _bindPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus.requestFocus();
      open(widget.start);
    });
  }

  Future<void> _ensureMetaFor(String lib) async {
    if (lib.isEmpty || lib == _metaLib) return;
    _metaLib = lib;
    try {
      final m = await LibMeta.load(lib);
      if (mounted) setState(() => _meta = m);
    } catch (_) {}
  }

  /// G18：监听当前活动槽位。切换预缓冲槽位时先解绑旧槽位，避免
  /// 旧播放器迟到的 completed/position 事件干扰新作品。
  void _bindPlayer() {
    for (final s in _playerSubs) {
      s.cancel();
    }
    _playerSubs.clear();
    final p = player;
    p.setPlaylistMode(PlaylistMode.none);
    _playerSubs.add(p.stream.completed.listen((done) {
      if (!identical(p, player)) return;
      if (!done || !mounted) return;
      if (_mediaToken != _openToken) return;
      final w = _workAt(cur);
      // G10：播放完成即标记「已看完」
      _markWatched(w);
      if (w['t'] != 'v') {
        // 图文：整首歌放完才切下一条；单条循环时重新播放；都不开就停下图片轮播
        if (paused) return;
        if (loopOne) {
          try {
            player.seek(Duration.zero);
            player.play();
            setState(() => _setPicIndex(0));
          } catch (_) {}
        } else if (autoplay) {
          next();
        } else {
          pauseAuto();
        }
        return;
      }
      // 视频播完：单条循环就重播本条，否则按连播设置切下一条
      switch (videoEndAction(loopOne: loopOne, autoplay: autoplay)) {
        case VideoEndAction.replay:
          try {
            player.seek(Duration.zero);
            player.play();
          } catch (_) {}
          break;
        case VideoEndAction.nextWork:
          next();
          break;
        case VideoEndAction.stop:
          break;
      }
    }));
    _playerSubs.add(p.stream.playing.listen((v) {
      if (!identical(p, player)) return;
      if (!mounted || _opening) return;
      if (_workAt(cur)['t'] == 'v' && v != !paused) {
        setState(() => paused = !v);
      }
    }));
    subPos = p.stream.position.listen((position) {
      if (!identical(p, player)) return;
      if (!mounted) return;
      // G10：记录观看位置（内部 3s 节流，不受 UI 刷新节流影响）；
      // _opening 期间播放器会先上报 0 位置，不能用来覆盖已有进度
      if (!_opening && _mediaToken == _openToken && _mediaToken > 0) {
        final cw = _workAt(cur);
        if (cw['t'] == 'v') {
          WatchProgressStore.record(
              lib: _libFor(cw),
              id: _watchIdFor(cw),
              positionMs: position.inMilliseconds,
              durationMs: dur.inMilliseconds);
          _recordContinue(cw, position.inMilliseconds, dur.inMilliseconds);
        }
      }
      // 位置流每 100ms 左右触发一次；全量 setState 会让视频层频繁重建、
      // 在 Windows 上造成卡顿与音画不同步。这里节流到 200ms，
      // 但跳转/拖动后的大幅变化立即刷新。
      final now = DateTime.now().millisecondsSinceEpoch;
      final bigJump =
          (position.inMilliseconds - pos.inMilliseconds).abs() > 1200;
      if (!bigJump && now - _lastPosSet < 200) return;
      _lastPosSet = now;
      setState(() => pos = position);
    });
    subDur = p.stream.duration.listen((d) {
      if (!identical(p, player)) return;
      if (d.inMilliseconds > 0) {
        _loadTimeout?.cancel();
        _loadTimeout = null;
      }
      if (mounted) setState(() => dur = d);
    });
    if (subPos != null) _playerSubs.add(subPos!);
    if (subDur != null) _playerSubs.add(subDur!);
    // G12：播放器报错（解码失败/流打不开）直接给出可重试提示，
    // 不再无限转圈；错误可能来自上一条媒体，切条后自动清除。
    _playerSubs.add(p.stream.error.listen((msg) {
      if (!identical(p, player)) return;
      if (!mounted || _failure != null) return;
      final failure = classifyPlaybackError(msg);
      // F34：模拟器/个别解码器上硬件解码失败时，先用软件解码重试一次
      if (_shouldSoftRetry(failure.kind)) {
        _retryWithSoftwareDecode();
        return;
      }
      _showFailure(failure);
    }));
    // G12：弱网缓冲提示 —— 缓冲超过阈值才显示，避免正常起播闪一下
    _playerSubs.add(p.stream.buffering.listen((b) {
      if (!identical(p, player)) return;
      if (!mounted) return;
      if (!b) {
        _slowBufferTimer?.cancel();
        _slowBufferTimer = null;
        if (_buffering || _slowBuffer) {
          setState(() {
            _buffering = false;
            _slowBuffer = false;
          });
        }
        return;
      }
      if (_buffering) return;
      setState(() => _buffering = true);
      _slowBufferTimer?.cancel();
      _slowBufferTimer = Timer(slowBufferThreshold, () {
        if (mounted && _buffering) setState(() => _slowBuffer = true);
      });
    }));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // G16：切后台/最小化/来电时自动暂停（先落盘位置），回前台再恢复；
    // 移动端 inactive 就暂停，桌面端仅最小化/隐藏暂停（失去焦点不打断）。
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (shouldPauseInBackground(state: state.name, isMobile: isMobile)) {
      _pauseForBackground();
      return;
    }
    if (state == AppLifecycleState.resumed && mounted) {
      // 从后台/模拟器切回时焦点可能丢失，方向键会失效；恢复时重新拿回焦点
      focus.requestFocus();
      if (shouldResumeFromBackground(
          pausedByBackground: _pausedByBackground,
          userPaused: paused && !_pausedByBackground)) {
        _resumeFromBackground();
        return;
      }
      // Windows 切回前台后音视频时钟偶发漂移：按已记录位置重新对齐并恢复速率
      if (_workAt(cur)['t'] == 'v' && !paused) {
        try {
          player.seek(pos);
          player.setRate(speed);
          player.play();
        } catch (_) {}
      }
    }
  }

  /// G16：切后台自动暂停，并强制写入观看位置。
  void _pauseForBackground() {
    // G10：切后台/最小化前落盘，避免异常退出丢进度
    _saveWatchProgress(force: true);
    if (widget.works.isEmpty || _failure != null) return;
    // 用户自己暂停的保持原状，回前台不自动播放
    if (paused) return;
    _pausedByBackground = true;
    pauseAuto();
    try {
      player.pause();
    } catch (_) {}
    if (mounted) setState(() => paused = true);
  }

  /// G16：只恢复「因切后台暂停」的播放，并从记忆位置继续。
  void _resumeFromBackground() {
    _pausedByBackground = false;
    if (!mounted) return;
    final isV = _workAt(cur)['t'] == 'v';
    setState(() => paused = false);
    try {
      if (isV) {
        if (pos > Duration.zero) player.seek(pos);
        player.setRate(speed);
      }
      player.play();
    } catch (_) {}
    if (!isV && !manualPic) startAuto();
  }

  // J5：合集按章节记录观看位置，避免章节之间互相覆盖。
  String _watchIdFor(dynamic w) => workWatchKeyFor(w, _chapter);

  /// G10：把当前视频的播放位置写入本地记录（强制写，用于切条/退出/切后台）。
  void _saveWatchProgress({bool force = false}) {
    if (widget.works.isEmpty || cur < 0 || cur >= widget.works.length) return;
    final w = _workAt(cur);
    if (w['t'] != 'v' || dur.inMilliseconds <= 0) return;
    WatchProgressStore.record(
        lib: _libFor(w),
        id: _watchIdFor(w),
        positionMs: pos.inMilliseconds,
        durationMs: dur.inMilliseconds,
        force: force);
    // G17：退出/切条/切后台时强制刷新「继续观看」的位置
    _recordContinue(w, pos.inMilliseconds, dur.inMilliseconds, force: true);
  }

  /// G17：写入「继续观看」条目（含收藏夹信息，便于一键回到原列表续播）。
  void _recordContinue(dynamic w, int positionMs, int durationMs,
      {bool force = false}) {
    if (w is! Map || w['t'] != 'v') return;
    ContinueWatchingStore.record(
        ContinueItem(
          lib: _libFor(w),
          id: _watchIdFor(w),
          title: '${w['ti'] ?? ''}',
          author: '${w['a'] ?? ''}',
          thumb: '${w['th'] ?? ''}',
          type: 'v',
          positionMs: positionMs,
          durationMs: durationMs,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
        force: force);
  }

  /// G10：播放完成时标记「已看完」。
  void _markWatched(dynamic w) {
    if (w is! Map) return;
    WatchProgressStore.markDone(lib: _libFor(w), id: _watchIdFor(w));
    // G17：看完即从「继续观看」移除
    ContinueWatchingStore.remove(_libFor(w), _watchIdFor(w));
  }

  // G12：展示失败提示并停止转圈；重试时整条媒体重新打开。
  void _showFailure(PlaybackFailure f) {
    if (!mounted) return;
    _loadTimeout?.cancel();
    _loadTimeout = null;
    _slowBufferTimer?.cancel();
    _slowBufferTimer = null;
    try {
      player.pause();
    } catch (_) {}
    setState(() {
      _failure = f;
      loading = false;
      _buffering = false;
      _slowBuffer = false;
      paused = true;
    });
  }

  /// F34：是否值得自动切软件解码重试（每条媒体最多一次）。
  bool _shouldSoftRetry(PlaybackFailureKind? kind) =>
      shouldRetryWithSoftwareDecode(
        kind: kind,
        mode: _decodeMode,
        alreadyRetried: _softwareDecodeRetried,
        isVideo: _workAt(cur)['t'] == 'v',
        tokenAlive: mounted,
      );

  /// F34：重建播放器槽位为软件解码，并重开当前作品。
  /// 只在硬件解码报解码错误时触发一次，坏文件不会反复重建播放器。
  Future<void> _retryWithSoftwareDecode() async {
    if (_softwareDecodeRetried || _decodeMode == DecodeMode.software) return;
    _softwareDecodeRetried = true;
    _decodeMode = DecodeMode.software;
    final old = List<_PlaybackSlot>.from(_slots);
    _cancelPreload();
    for (final s in _playerSubs) {
      s.cancel();
    }
    _playerSubs.clear();
    _slots
      ..clear()
      ..add(_PlaybackSlot('a', mode: _decodeMode));
    _slotSeq = 1;
    _slotActive = 0;
    _videoGen++;
    _bindPlayer();
    for (final s in old) {
      try {
        await s.player.dispose();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _failure = null;
      loading = true;
      paused = false;
      _buffering = false;
      _slowBuffer = false;
    });
    await open(cur);
  }

  void _retryPlayback() {
    if (!mounted) return;
    _loadTimeout?.cancel();
    _slowBufferTimer?.cancel();
    setState(() {
      _failure = null;
      loading = true;
      _buffering = false;
      _slowBuffer = false;
    });
    open(cur);
  }

  /// M6：作废正在进行的预加载计划（保留已就绪缓存）。
  void _invalidatePreload() {
    _preloadTimer?.cancel();
    _preloadTimer = null;
    _preloadGen++;
  }

  /// 清空预加载缓存并停掉所有非活动槽位（关闭连播/单条循环等场景）。
  void _cancelPreload({bool stopIdle = true}) {
    _invalidatePreload();
    if (!stopIdle) return;
    for (final s in _slots) {
      if (s.sid == _active.sid) continue;
      _preloadCache.removeSlot(s.sid);
      try {
        s.player.stop();
      } catch (_) {}
    }
  }

  _PlaybackSlot? _slotBySid(int sid) {
    for (final s in _slots) {
      if (s.sid == sid) return s;
    }
    return null;
  }

  /// 命中缓存的槽位：键与序号都必须一致。
  _PlaybackSlot? _cachedSlotFor(String key, int index) {
    for (final s in _slots) {
      if (s.sid == _active.sid) continue;
      final e = _preloadCache.entryOfSlot(s.sid);
      if (e != null && e.key == key && e.index == index) return s;
    }
    return null;
  }

  /// M6：当前条起播后，按滑动方向预载前后各 N 条。
  void _schedulePreload() {
    _invalidatePreload();
    if (AppSettings.preloadPerSide <= 0) return;
    if (widget.works.length <= 1) return;
    final gen = _preloadGen;
    _preloadTimer = Timer(const Duration(milliseconds: 600), () {
      if (gen == _preloadGen) _runPreloads();
    });
  }

  int get _preloadByteLimit => AppSettings.preloadMemoryMb * 1024 * 1024;

  /// 为预加载挑一个槽位：优先淘汰最远的缓存条目并复用其槽位，
  /// 否则在预算内新建，最后复用空闲槽位。
  _PlaybackSlot? _slotForPreload() {
    final victim = _preloadCache.evictionSlot(
      current: cur,
      direction: _preloadDir,
      protectedSlots: <int>{_active.sid},
      protectedKeys: _preloadBusy.values.toSet(),
    );
    if (victim != null) {
      final slot = _slotBySid(victim);
      _preloadCache.removeSlot(victim);
      if (slot != null) return slot;
    }
    final maxSlots = preloadSlotBudget(AppSettings.preloadMemoryMb);
    if (_slots.length < maxSlots &&
        _preloadCache.canFit(preloadEntryBytes, byteLimit: _preloadByteLimit)) {
      final sid = _slotSeq++;
      final s = _PlaybackSlot('s$sid', sid: sid, mode: _decodeMode);
      _slots.add(s);
      return s;
    }
    // 预算已满但也没有可淘汰条目：复用空闲的非活动槽位。
    for (final s in _slots) {
      if (s.sid == _active.sid) continue;
      if (_preloadBusy.containsKey(s.sid)) continue;
      _preloadCache.removeSlot(s.sid);
      return s;
    }
    return null;
  }

  /// 在槽位中静音打开目标媒体，等到解封装/首帧就绪后登记缓存。
  Future<bool> _preloadInto(
      _PlaybackSlot slot, int idx, String key, int gen, String path) async {
    final lib = _libFor(_workAt(idx));
    _preloadBusy[slot.sid] = key;
    final epoch = ++slot.epoch;
    try {
      await slot.player.stop();
      await slot.player.setVolume(0);
      await slot.player.open(
        Media(cfg.mediaUrl(path, lib: lib), httpHeaders: cfg.headersFor(lib)),
        play: false,
      );
      var ready = false;
      for (var i = 0; i < preloadReadyAttempts; i++) {
        if (!mounted || gen != _preloadGen || slot.epoch != epoch) return false;
        var d = Duration.zero;
        try {
          d = slot.player.state.duration;
        } catch (_) {}
        if (d.inMilliseconds > 0) {
          ready = true;
          break;
        }
        await Future<void>.delayed(preloadReadyInterval);
      }
      if (!ready) return false;
      // 再给解码器一点时间铺好首帧，命中时直接出画面。
      await Future<void>.delayed(preloadFirstFrameDelay);
      if (!mounted || gen != _preloadGen || slot.epoch != epoch) return false;
      _preloadCache.put(PreloadEntry(slot: slot.sid, index: idx, key: key));
      return true;
    } catch (_) {
      try {
        await slot.player.stop();
      } catch (_) {}
      return false;
    } finally {
      _preloadBusy.remove(slot.sid);
    }
  }

  Future<void> _runPreloads() async {
    if (!mounted || _preloadRunning) return;
    if (AppSettings.preloadPerSide <= 0) return;
    _preloadRunning = true;
    final gen = ++_preloadGen;
    try {
      final targets = preloadCandidates(
        index: cur,
        count: widget.works.length,
        perSide: AppSettings.preloadPerSide,
        direction: _preloadDir,
      );
      for (final idx in targets) {
        if (!mounted || gen != _preloadGen) return;
        if (idx == cur || idx < 0 || idx >= widget.works.length) continue;
        final w = _workAt(idx);
        if (!workPlayable(w)) continue;
        final path = preloadMediaPath(w);
        if (path == null) continue;
        final key = preloadKeyFor(w, _libFor(w));
        if (_preloadCache.containsKey(key)) continue;
        if (_preloadBusy.containsValue(key)) continue;
        final slot = _slotForPreload();
        if (slot == null) return;
        await _preloadInto(slot, idx, key, gen, path);
      }
    } finally {
      _preloadRunning = false;
    }
  }

  Future<void> open(int i, {bool saveProgress = true}) async {
    if (widget.works.isEmpty || i < 0 || i >= widget.works.length) return;
    // 切条前先把上一条的进度落盘
    if (saveProgress) _saveWatchProgress(force: true);
    // J5：切到其他作品时回到第一集
    if (i != cur) _chapter = 0;
    final w = _workAt(i);
    final wl = _libFor(w);
    _ensureMetaFor(wl);
    // G20：单条作品数据异常时不再调用播放器（避免未捕获异常卡死整页），
    // 只切到该条并展示占位，PageView 仍可继续上下滑。
    if (!workPlayable(w)) {
      _cancelPreload();
      autoTimer?.cancel();
      retryTimer?.cancel();
      playGuard?.cancel();
      _loadTimeout?.cancel();
      _slowBufferTimer?.cancel();
      _preloadTimer?.cancel();
      _preloadTimer = null;
      ++_openToken;
      _opening = false;
      _pendingPage = null;
      _mediaToken = -1;
      _pausedByBackground = false;
      try {
        await player.stop();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        cur = i;
        _setPicIndex(0);
        captionOpen = false;
        loading = false;
        paused = true;
        _failure = null;
        _buffering = false;
        _slowBuffer = false;
        pos = Duration.zero;
        dur = Duration.zero;
      });
      return;
    }
    final key = preloadKeyFor(w, wl);
    // 记录滑动方向，供后续预加载排序
    if (i != cur) _preloadDir = i > cur ? 1 : -1;
    // M6：命中预加载缓存时直接换槽位，跳过 player.open 与转圈。
    final cachedSlot = _cachedSlotFor(key, i);
    final canUsePreload = cachedSlot != null;
    _invalidatePreload();
    final my = ++_openToken;
    _pausedByBackground = false;
    autoTimer?.cancel();
    retryTimer?.cancel();
    playGuard?.cancel();
    _loadTimeout?.cancel();
    _slowBufferTimer?.cancel();
    _preloadTimer?.cancel();
    _preloadTimer = null;
    manualPic = false;
    _pendingPage = null;
    _mediaToken = -1;
    _opening = true;
    setState(() {
      cur = i;
      _setPicIndex(0);
      captionOpen = false;
      // 缓存命中说明首帧已就绪，直接显示画面，不闪加载圈
      loading = !canUsePreload;
      paused = false;
      _failure = null;
      _buffering = false;
      _slowBuffer = false;
      dropDayLeft = 1;
      dropWeekLeft = 3;
      dropTotal = 0;
      dropGlow = false;
    });
    // G12：15 秒仍拿不到时长就按超时处理，避免弱网无限转圈
    _loadTimeout = Timer(playbackLoadTimeout, () {
      if (!mounted ||
          my != _openToken ||
          _failure != null ||
          dur.inMilliseconds > 0) {
        return;
      }
      _showFailure(timeoutFailure);
    });
    if (canUsePreload) {
      final old = _active;
      final target = cachedSlot;
      _slotActive = _slots.indexOf(target);
      _preloadCache.removeSlot(target.sid);
      _bindPlayer();
      try {
        await old.player.stop();
      } catch (_) {}
      _mediaToken = my;
      setState(() {
        pos = Duration.zero;
        final d0 = player.state.duration;
        dur = d0.inMilliseconds > 0 ? d0 : Duration.zero;
      });
    } else {
      try {
        await player.stop();
      } catch (_) {}
    }
    if (my != _openToken) return;
    _refreshDrop('${w['id'] ?? ''}', my, wl);
    postStat('play', '${w['a'] ?? ''}', lib: wl);
    // L5-C：本机播放量（基础库自动封面取播放量最高的作品），顺手记住缩略图
    WorkPlaysStore.bump(wl, _watchIdFor(w), thumb: '${w['th'] ?? ''}'.trim());
    if (!canUsePreload) {
      try {
        if (w['t'] == 'v') {
          await player.open(Media(
              cfg.mediaUrl(workMediaPaths(w).first, lib: wl),
              httpHeaders: cfg.headersFor(wl)));
        } else if ((w['au'] ?? '').toString().isNotEmpty) {
          await player.open(Media(cfg.mediaUrl(w['au'].toString(), lib: wl),
              httpHeaders: cfg.headersFor(wl)));
        }
        if ((w['t'] == 'v' || (w['au'] ?? '').toString().isNotEmpty) &&
            my == _openToken) {
          _mediaToken = my;
        }
      } catch (e) {
        if (my == _openToken) {
          _opening = false;
          final failure = classifyPlaybackError(e);
          // F34：打开阶段就报解码错误时同样先试软件解码
          if (_shouldSoftRetry(failure.kind)) {
            _retryWithSoftwareDecode();
            return;
          }
          _showFailure(failure);
          return;
        }
      }
    }
    if (my != _openToken) return;
    if (_failure != null) return;
    _loadTimeout?.cancel();
    _loadTimeout = null;
    // I3：等首帧/时长就绪再起播，避免解码器刚启动就推进造成画面抽搐。
    // 预缓冲命中的媒体通常立刻有 duration，这里只是兜底，最多等 ~0.5s。
    for (var attempt = 0; attempt < firstFrameAttempts; attempt++) {
      var known = Duration.zero;
      try {
        known = player.state.duration;
      } catch (_) {}
      if (known.inMilliseconds == 0) known = dur;
      if (!shouldWaitFirstFrame(
        attempt: attempt,
        knownDuration: known,
        tokenAlive: my == _openToken && mounted,
        paused: paused,
      )) {
        break;
      }
      await Future<void>.delayed(
          const Duration(milliseconds: firstFrameIntervalMs));
    }
    if (my != _openToken) return;
    // I3：视频起播先静音，首帧出来后再分步淡入，避免喇叭先爆一声。
    final fadeIn =
        shouldFadeIn(isVideo: w['t'] == 'v', paused: paused, volume: volume);
    _fadeTimer?.cancel();
    _fadeGen++;
    try {
      await player.setVolume(fadeIn ? 0 : volume);
      await player.setRate(speed);
    } catch (_) {}
    // G10：同一作品再次打开时从上次位置续播（已看完则从头）
    if (w['t'] == 'v') {
      final at = resumeMs(WatchProgressStore.of(wl, _watchIdFor(w)));
      if (at > 0) {
        try {
          await player.seek(Duration(milliseconds: at));
          if (mounted && my == _openToken) {
            setState(() => pos = Duration(milliseconds: at));
          }
        } catch (_) {}
      }
    }
    // 媒体已就绪，恢复采信播放器事件；此后一切以用户意图 paused 为准
    _opening = false;
    if (shouldAutoPlay(paused: paused, opening: _opening)) {
      try {
        await player.play();
      } catch (_) {}
      // open 后再确认一次速率，避免个别 Windows 解码器在起播时重置为 1x
      try {
        await player.setRate(speed);
      } catch (_) {}
      // I3：起播后再淡入到目标音量（约 270ms），不再「啪」地直接满音量
      if (fadeIn) _startAudioFade(my);
    }
    if (mounted && my == _openToken && _failure == null) {
      setState(() {
        loading = false;
        // 若打开过程中被切到后台，保持暂停，等回前台再恢复
        if (w['t'] != 'v' && !_pausedByBackground) paused = false;
      });
    }
    // F32 兜底：媒体就绪后 2.5 秒仍未起播且用户没暂停，补一次 play，
    // 避免停在片尾/首帧导致连播链路中断。
    playGuard = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || my != _openToken || _failure != null) return;
      if (_workAt(i)['t'] != 'v') return;
      bool playing = false;
      try {
        playing = player.state.playing;
      } catch (_) {}
      if (shouldForcePlay(
          paused: paused,
          opening: _opening,
          playerPlaying: playing,
          hasMedia: dur.inMilliseconds > 0 || pos.inMilliseconds > 0)) {
        try {
          player.play();
        } catch (_) {}
      }
    });
    retryTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted &&
          my == _openToken &&
          _failure == null &&
          !paused &&
          w['t'] == 'v' &&
          dur.inMilliseconds == 0) {
        player.open(Media(cfg.mediaUrl(workMediaPaths(w).first, lib: wl),
            httpHeaders: cfg.headersFor(wl)));
        player.play();
        _mediaToken = my;
      }
    });
    // 后台打开的作品不启动图文轮播，等回前台再按用户状态恢复
    if (w['t'] != 'v' && !paused) startAuto();
    // G18：起播稳定后再预缓冲下一条，避免和当前条抢带宽
    _schedulePreload();
  }

  Future<void> _refreshDrop(String id, int token, String lib) async {
    if (id.isEmpty) return;
    final r = await fetchDropStatus(id, lib: lib);
    if (!mounted || token != _openToken || r == null) return;
    setState(() {
      dropDayLeft = _intOf(r['dayLeft'], 1);
      dropWeekLeft = _intOf(r['weekLeft'], 3);
      dropTotal = _intOf(r['total'], 0);
    });
  }

  int _intOf(dynamic v, int fallback) =>
      v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? fallback);

  Future<void> _sendDrop() async {
    final w = _workAt(cur);
    final id = '${w['id'] ?? ''}';
    final author = '${w['a'] ?? ''}';
    if (dropBusy || id.isEmpty || author.isEmpty) return;
    if (dropDayLeft <= 0) {
      _toast('今天已经送过小水滴了');
      return;
    }
    if (dropWeekLeft <= 0) {
      _toast('本周小水滴已送完（3/3）');
      return;
    }
    final before = dropTotal;
    // 先本地 +1 并播放动效，失败再回滚
    setState(() {
      dropBusy = true;
      dropGlow = true;
      dropTotal = before + 1;
    });
    _dropAnim.forward(from: 0);
    hapticTap();
    final r = await sendDrop(id, author, lib: _curLib);
    if (!mounted) return;
    setState(() {
      dropBusy = false;
      if (r != null) {
        dropDayLeft = _intOf(r['dayLeft'], dropDayLeft);
        dropWeekLeft = _intOf(r['weekLeft'], dropWeekLeft);
        dropTotal = _intOf(r['total'], dropTotal);
      } else {
        dropTotal = before;
        dropGlow = false;
      }
    });
    if (r != null && r['ok'] == true) {
      _toast('已送 1 颗小水滴 · 今日剩余 $dropDayLeft · 本周剩余 $dropWeekLeft');
    } else {
      _toast('${r?['error'] ?? '发送失败，请检查网络'}');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        backgroundColor: const Color(0xE6222222),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
      ));
  }

  void startAuto() {
    autoTimer?.cancel();
    autoTimer = null;
    if (manualPic || paused) return;
    final t = Timer.periodic(Duration(seconds: AppSettings.imageIntervalSec),
        (timer) {
      if (!identical(timer, autoTimer)) return;
      if (!mounted || paused) return;
      final w = _workAt(cur);
      if (w['t'] == 'v') return;
      final n = (w['m'] as List).length;
      final hasAudio = (w['au'] ?? '').toString().isNotEmpty;
      switch (slideshowAction(
          index: img, count: n, loopOne: loopOne, hasAudio: hasAudio)) {
        case SlideshowAction.nextImage:
          setState(() => _setPicIndex(img + 1));
          break;
        case SlideshowAction.restartImages:
          // 单条循环，或还有背景音乐没放完：图片回到第一张继续
          setState(() => _setPicIndex(0));
          break;
        case SlideshowAction.nextWork:
          next();
          break;
      }
    });
    autoTimer = t;
  }

  void stopAuto() {
    manualPic = true;
    autoTimer?.cancel();
    autoTimer = null;
  }

  void pauseAuto() {
    autoTimer?.cancel();
    autoTimer = null;
  }

  void next() => _step(1);

  void prev() => _step(-1);

  // 连点/连按方向键时直接跳页，避免动画未结束把后续按键吃掉
  void _step(int delta, {bool instant = false}) {
    final base = _pendingPage ?? cur;
    // G20：自动/键盘翻页跳过数据异常的作品，避免卡在坏条目上。
    final target = nextPlayableIndex(
        current: base,
        count: widget.works.length,
        step: delta,
        playable: (i) => workPlayable(_workAt(i)));
    if (target < 0 || target == base) return;
    _pendingPage = target;
    final now = DateTime.now().millisecondsSinceEpoch;
    // I2：110ms 动画结束后再按键仍走动画，只有连击间隔短于动画才直接跳页
    if (instant || now - _navAt < pageTurnDuration.inMilliseconds + 150) {
      pc.jumpToPage(target);
    } else {
      pc.animateToPage(target,
          duration: pageTurnDuration, curve: pageTurnCurve);
    }
    _navAt = now;
  }

  String _likeKeyFor(dynamic w) =>
      workLikeKey(lib: _libFor(w), id: '${(w is Map ? w['id'] : null) ?? ''}');

  bool _isLiked(dynamic w) => likedKeys.contains(_likeKeyFor(w));

  Future<void> _loadLikes() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final keys = parseLikedKeys(sp.getStringList(kLikedWorksPrefsKey));
      if (mounted)
        setState(() => likedKeys
          ..clear()
          ..addAll(keys));
    } catch (_) {}
  }

  Future<void> _setLiked(dynamic w, bool liked, {Offset? at}) async {
    final key = _likeKeyFor(w);
    if (key.isEmpty) return;
    final next = updateLikedKeys(likedKeys, key, liked: liked);
    setState(() {
      likedKeys
        ..clear()
        ..addAll(next);
    });
    if (liked && at != null) {
      hapticTap();
      setState(() => _heartPos = at);
      _heartAnim.forward(from: 0);
    } else if (!liked) {
      hapticSelect();
    }
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(kLikedWorksPrefsKey, next);
    } catch (_) {}
  }

  // 全屏且功能隐藏时，第一次点击只呼出功能区，第二次才暂停；
  // 320ms 内在相近位置再次点击视为双击：点赞并恢复到点击前的播放状态。
  void onStageTap([Offset? pos]) {
    focus.requestFocus();
    final w = _workAt(cur);
    final now = DateTime.now().millisecondsSinceEpoch;
    // M1：全屏单击只切换功能区显隐，不暂停；非全屏保持单击暂停。
    // 双击仍可点赞，即使第一次单击已把全屏功能区收起。
    final isDouble = isStageDoubleTap(
        nowMs: now,
        lastMs: _lastStageTapAt,
        lastPos: _lastStageTapAt > 0 ? _lastStageTapPos : null,
        pos: pos);
    final action = stageTapAction(
      uiVisible: ui,
      fullscreen: fs && _mobileStageTap,
      zoomed: _picZoom.isZoomed,
      doubleTap: isDouble,
    );
    switch (action) {
      case StageTapAction.resetZoom:
        // G14：图片放大时单击只恢复原始大小，不暂停/双击点赞
        _resetPicZoom();
        _lastStageTapAt = 0;
        return;
      case StageTapAction.like:
        _lastStageTapAt = 0;
        // 非「移动端全屏单击语义」时第一次单击已经切换过暂停；
        // 双击按点击前状态恢复（Windows 全屏行为与窗口态一致，见 M3）。
        if (!(fs && _mobileStageTap)) {
          _restorePauseAfterTap(_tapWasPausedBefore);
        }
        if (!_isLiked(w)) _setLiked(w, true, at: pos);
        showUi();
        return;
      case StageTapAction.showUi:
        showUi();
        _lastStageTapAt = 0;
        return;
      case StageTapAction.hideUi:
        // 记录这次点击，使紧接着的第二次点击仍可判定为双击点赞。
        _lastStageTapAt = now;
        _lastStageTapPos = pos ?? Offset.zero;
        hideUiNow();
        return;
      case StageTapAction.togglePause:
        _lastStageTapAt = now;
        _lastStageTapPos = pos ?? Offset.zero;
        _tapWasPausedBefore = paused;
        hapticTap();
        togglePause();
        showUi();
        return;
    }
  }

  /// M1：立即收起功能区（取消自动隐藏计时器，避免残留定时器再触发）。
  void hideUiNow() {
    hideTimer?.cancel();
    hideTimer = null;
    if (!mounted) return;
    setState(() => ui = false);
  }

  // 双击点赞时撤销第一次点击带来的暂停切换（视频流事件可能迟到，
  // 因此这里直接按点击前状态强制对齐，不依赖 paused 是否已刷新）。
  void _restorePauseAfterTap(bool wasPaused) {
    final isV = _workAt(cur)['t'] == 'v';
    setState(() => paused = wasPaused);
    if (wasPaused) {
      pauseAuto();
      try {
        player.pause();
      } catch (_) {}
    } else {
      try {
        player.setRate(speed);
        player.play();
      } catch (_) {}
      if (!isV && !manualPic) startAuto();
    }
  }

  // M9：作者页跟手拖拽。拖动开始时透明路由即入栈（进度 0），位移由手指驱动。
  AuthorDragController? _authorDrag;
  double _authorDragDx = 0;
  bool _authorDragResume = false;
  bool _authorDragClosing = false;

  void _authorDragStart() {
    if (_authorDrag != null) return;
    final name = '${_workAt(cur)['a'] ?? ''}';
    if (name.isEmpty) return;
    _authorDragDx = 0;
    _authorDragClosing = false;
    _authorDragResume = !paused;
    try {
      player.pause();
    } catch (_) {}
    final c = AuthorDragController(vsync: this);
    final route = AuthorDragRoute(
      drag: c,
      builder: (_) => AuthorPage(name: name, libs: [_curLib]),
    );
    _authorDrag = c;
    Navigator.of(context).push(route).whenComplete(() {
      final ac = _authorDrag;
      _authorDrag = null;
      ac?.dispose();
      if (_authorDragResume && mounted && !fs) {
        try {
          player.play();
        } catch (_) {}
      }
    });
  }

  void _authorDragUpdate(double dx, double width) {
    final c = _authorDrag;
    if (c == null || _authorDragClosing) return;
    _authorDragDx += dx;
    c.progress = AuthorDrag.progress(dx: _authorDragDx, width: width);
  }

  void _authorDragEnd(double velocity) {
    final c = _authorDrag;
    if (c == null || _authorDragClosing) return;
    if (AuthorDrag.completes(progress: c.progress, velocity: velocity)) {
      c.settleTo(1, opening: true);
    } else {
      _authorDragCancel();
    }
  }

  void _authorDragCancel() {
    final c = _authorDrag;
    if (c == null || _authorDragClosing) return;
    _authorDragClosing = true;
    c.settleTo(0, opening: false).then((_) {
      if (!mounted) return;
      final nav = Navigator.of(context);
      final route = ModalRoute.of(context);
      if (nav.canPop()) {
        nav.pop();
      } else if (route != null) {
        nav.removeRoute(route);
      }
    });
  }

  // 打开当前作品作者主页：先暂停，返回后按原状态恢复
  Future<void> openAuthor() async {
    final name = '${_workAt(cur)['a'] ?? ''}';
    if (name.isEmpty) return;
    final resume = !paused;
    try {
      player.pause();
    } catch (_) {}
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AuthorPage(name: name, libs: [_curLib])));
    if (resume && mounted && !fs) {
      try {
        player.play();
      } catch (_) {}
    }
  }

  // M2：任务栏横竖屏切换（仅移动端）。以当前实际方向为准反转到另一侧，
  // 旋转后 MediaQuery 会更新，按钮图标随之变化。
  Future<void> toggleOrientation() async {
    final target = toggledMode(screenModeOf(MediaQuery.sizeOf(context)));
    _orientationForced = true;
    try {
      await SystemChrome.setPreferredOrientations(orientationsFor(target));
    } catch (_) {}
    if (mounted) showUi();
  }

  void togglePause() {
    final isV = _workAt(cur)['t'] == 'v';
    // 用户手动操作后不再视为后台暂停，避免回前台被自动恢复
    _pausedByBackground = false;
    if (!isV) {
      final willPause = !paused;
      setState(() => paused = willPause);
      if (willPause) {
        pauseAuto();
        player.pause();
      } else {
        player.play();
        if (!manualPic) startAuto();
      }
      return;
    }
    if (paused) {
      try {
        player.setRate(speed);
      } catch (_) {}
      player.play();
    } else {
      player.pause();
    }
  }

  void toggleMute() {
    _volHintTimer?.cancel();
    setState(() {
      muted = !muted;
      if (muted) {
        lastVol = volume > 0 ? volume : lastVol;
      }
      volume = volumeAfterMuteToggle(
          nowMuted: muted, current: volume, last: lastVol);
      showVol = true; // 轻量反馈，不弹模块
    });
    player.setVolume(volume);
    _volHintTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => showVol = false);
    });
  }

  // H14：统一设置音量（0–100），静音状态跟随音量归零/恢复。
  /// I3：从 0 分步抬到当前音量。token 失效、切条或用户手动调音量时作废。
  void _startAudioFade(int token) {
    final steps = fadeInSteps(volume);
    if (steps.isEmpty) {
      try {
        player.setVolume(volume);
      } catch (_) {}
      return;
    }
    final gen = ++_fadeGen;
    var i = 0;
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 45), (t) {
      if (!mounted || gen != _fadeGen || token != _openToken) {
        t.cancel();
        return;
      }
      if (i >= steps.length) {
        t.cancel();
        try {
          player.setVolume(volume);
        } catch (_) {}
        return;
      }
      try {
        player.setVolume(steps[i]);
      } catch (_) {}
      i++;
    });
  }

  void _setVolume(double v) {
    // 用户主动调音量时取消进行中的淡入，避免定时器把音量又拉回去
    _fadeTimer?.cancel();
    _fadeGen++;
    final nv = v.clamp(0.0, 100.0);
    setState(() {
      volume = nv;
      muted = nv == 0;
      if (nv > 0) lastVol = nv;
    });
    player.setVolume(nv);
  }

  // 长按/横向拖动喇叭调音量：以按下时的音量为基准累加位移。
  void _volDragStart(DragStartDetails d) {
    _volHintTimer?.cancel();
    setState(() {
      _volAdjusting = true;
      _volStart = muted ? 0 : volume;
      _volStartDx = d.globalPosition.dx;
    });
  }

  void _volDragUpdate(DragUpdateDetails d) {
    if (!_volAdjusting) return;
    _setVolume(volumeFromDrag(_volStart, d.globalPosition.dx - _volStartDx));
  }

  // 长按拖动同样按横向位移调音量（长按后手指滑动的偏移从原点算）。
  void _volLongPressStart(LongPressStartDetails d) {
    _volDragStart(DragStartDetails(globalPosition: d.globalPosition));
  }

  void _volLongPressMove(LongPressMoveUpdateDetails d) {
    if (!_volAdjusting) return;
    _setVolume(volumeFromDrag(_volStart, d.globalPosition.dx - _volStartDx));
  }

  void _volDragEnd([DragEndDetails? _]) {
    if (!_volAdjusting) return;
    _volHintTimer?.cancel();
    setState(() {
      _volAdjusting = false;
      showVol = true; // 松手后短暂保留读数
    });
    _volHintTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => showVol = false);
    });
  }

  // G15：上下滑开始（左亮度 / 右音量），以按下时的值为基准。
  void _swipeStart(DragStartDetails d, SwipeZone zone) {
    _swipeHintTimer?.cancel();
    hapticTap();
    final start =
        zone == SwipeZone.brightness ? brightness : (muted ? 0.0 : volume);
    setState(() {
      _swipeZone = zone;
      _swipeActive = true;
      _swipeShow = true;
      _swipeStartY = d.globalPosition.dy;
      _swipeStartValue = start;
      _swipeValue = start;
      _swipeStep = swipeHapticStep(start);
    });
  }

  void _swipeUpdate(DragUpdateDetails d) {
    if (!_swipeActive) return;
    final zone = _swipeZone;
    if (zone == null) return;
    final h = _stageSize.height > 0
        ? _stageSize.height
        : MediaQuery.of(context).size.height;
    final v = swipeValueFromDrag(
        start: _swipeStartValue,
        dy: d.globalPosition.dy - _swipeStartY,
        height: h);
    final step = swipeHapticStep(v);
    if (step != _swipeStep) {
      _swipeStep = step;
      HapticFeedback.selectionClick();
    }
    setState(() {
      _swipeValue = v;
      if (zone == SwipeZone.brightness) {
        brightness = v;
      } else {
        volume = v;
        muted = v == 0;
        if (v > 0) lastVol = v;
      }
    });
    if (zone == SwipeZone.volume) player.setVolume(v);
  }

  void _swipeEnd() {
    if (!_swipeActive) return;
    _swipeHintTimer?.cancel();
    setState(() => _swipeActive = false);
    _swipeHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _swipeShow = false);
    });
  }

  // 左右两条窄边手势区：中间留给 PageView 上下滑翻页。
  Widget _swipeEdge(SwipeZone zone, double width, EdgeInsets pad) {
    return Positioned(
      left: zone == SwipeZone.brightness ? 0 : null,
      right: zone == SwipeZone.volume ? 0 : null,
      top: pad.top + 64,
      bottom: pad.bottom + 132,
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (d) => _swipeStart(d, zone),
        onVerticalDragUpdate: _swipeUpdate,
        onVerticalDragEnd: (_) => _swipeEnd(),
        onVerticalDragCancel: _swipeEnd,
      ),
    );
  }

  // G15：拖动期间/松手后的轻量读数（图标 + 进度 + 百分比）。
  Widget _swipeHintWidget(EdgeInsets pad) {
    final zone = _swipeZone ?? SwipeZone.brightness;
    final value = _swipeValue.clamp(0.0, 100.0);
    return Positioned(
      left: 0,
      right: 0,
      top: pad.top + 96,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(
                  zone == SwipeZone.brightness
                      ? Icons.brightness_6
                      : (value == 0 ? Icons.volume_off : Icons.volume_up),
                  size: 18,
                  color: Colors.white70),
              const SizedBox(width: 8),
              SizedBox(
                width: 96,
                height: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: value / 100.0,
                    backgroundColor: Colors.white24,
                    valueColor: const AlwaysStoppedAnimation(Colors.white),
                    minHeight: 4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('${swipeLabel(zone)} ${value.round()}%',
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          ),
        ),
      ),
    );
  }

  void toggleLoop() {
    // L6：打开循环时自动关闭连播并记住原状态；关闭循环时恢复到打开前的连播。
    // 不使用 media_kit 原生 PlaylistMode.single（原生 loop-file 会吞掉
    // completed 事件），统一由 completed 回调在 Dart 层重播。
    setState(() => _link = _link.toggleLoop());
    if (_link.nextEnabled) {
      _schedulePreload();
    } else {
      _cancelPreload();
    }
  }

  void toggleAutoplay() {
    // L6：循环开启期间也允许手动切连播，但退出循环仍回到记忆值。
    setState(() => _link = _link.toggleAutoplay());
    if (_link.nextEnabled) {
      _schedulePreload();
    } else {
      _cancelPreload();
    }
  }

  void cycleSpeed() {
    const steps = [0.75, 1.0, 1.25, 1.5, 2.0];
    var i = steps.indexWhere((s) => (s - speed).abs() < 0.001);
    final nextSpeed = steps[(i + 1) % steps.length];
    setState(() => speed = nextSpeed);
    player.setRate(speed);
  }

  Future<void> toggleFs() async {
    if (_fsBusy) return;
    _fsBusy = true;
    setState(() => fs = !fs);
    try {
      if (fs) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        // Windows 使用窗口管理器进入真全屏（无边框、全屏不遮挡任务栏）
        if (Platform.isWindows) {
          try {
            await windowManager.setFullScreen(true);
          } catch (_) {}
        }
        showUi();
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        // M4：退出全屏必须彻底取消自动隐藏计时器，否则旧的计时器到期后
        // 仍会把非全屏的功能区隐藏掉。
        hideTimer?.cancel();
        hideTimer = null;
        if (Platform.isWindows) {
          try {
            await windowManager.setFullScreen(false);
          } catch (_) {}
        }
        setState(() => ui = true);
      }
    } finally {
      // 窗口管理器切换需要一点时间，防抖避免快速连点导致的窗口状态错乱/崩溃
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _fsBusy = false;
    }
  }

  void showUi() {
    if (!mounted) return;
    setState(() => ui = true);
    hideTimer?.cancel();
    hideTimer = null;
    if (!UiAutoHidePolicy.shouldSchedule(fullscreen: fs, uiVisible: ui)) return;
    hideTimer = Timer(Duration(seconds: AppSettings.hideUiSec), () {
      hideTimer = null;
      // M4：任何时刻都已退出全屏就不再隐藏；拖动/悬停则重新计时。
      // L15：全屏下鼠标静止也隐藏；仅拖动进度条时保持显示（不再因悬停而不隐藏）
      if (!UiAutoHidePolicy.shouldHide(
        fullscreen: fs,
        mounted: mounted,
        dragging: dragging,
        barHover: false,
      )) {
        if (mounted && fs) showUi();
        return;
      }
      setState(() => ui = false);
    });
  }

  /// M5：只在状态真正变化时重建，避免滚动通知每帧触发 setState。
  void _setPageSwiping(bool value) {
    if (!mounted || _pageSwiping == value) return;
    setState(() => _pageSwiping = value);
  }

  void onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final dy = e.scrollDelta.dy;
    if (dy == 0) return;
    // 一次翻页后短暂锁定，滚轮惯性/触控板连续事件不会连续跳过多个作品
    if (_wheelLock) return;
    _wheelAcc += dy;
    // 静止 350ms 后清空累计量，避免慢速滑动攒出额外翻页
    _wheelIdle?.cancel();
    _wheelIdle = Timer(const Duration(milliseconds: 350), () {
      _wheelAcc = 0;
    });
    // Windows 鼠标一格约 100；触控板/模拟器会拆成 1~10 的小 delta，
    // 累计到 30 即视为一次翻页，正好一格一次。
    const threshold = 30.0;
    if (_wheelAcc.abs() < threshold) return;
    final dir = _wheelAcc > 0 ? 1 : -1;
    _wheelAcc = 0;
    _wheelLock = true;
    _wheelUnlock?.cancel();
    _wheelUnlock = Timer(const Duration(milliseconds: 260), () {
      _wheelLock = false;
      _wheelAcc = 0;
    });
    _step(dir, instant: true);
  }

  void _stepImage(int dir) {
    final w = _workAt(cur);
    if (w['t'] != 'v') {
      stopAuto();
      final n = (w['m'] as List).length;
      setState(() => _setPicIndex((img + dir).clamp(0, n - 1)));
    } else {
      // 视频：← / → 快退快进 10 秒（时长未知时也尝试 seek）
      var target = pos + Duration(seconds: 10 * dir);
      if (target < Duration.zero) target = Duration.zero;
      if (dur.inMilliseconds > 0 && target > dur) target = dur;
      player.seek(target);
      setState(() => pos = target);
    }
  }

  void doAction(PlayerAction a) {
    switch (a) {
      case PlayerAction.next:
        next();
        break;
      case PlayerAction.prev:
        prev();
        break;
      case PlayerAction.playPause:
        togglePause();
        break;
      case PlayerAction.mute:
        toggleMute();
        break;
      case PlayerAction.fullscreen:
        toggleFs();
        break;
      case PlayerAction.forward:
        _stepImage(1);
        break;
      case PlayerAction.back:
        _stepImage(-1);
        break;
    }
  }

  KeyEventResult onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;
    final down = e is KeyDownEvent;
    final repeat = e is KeyRepeatEvent;
    if (!down && !repeat) return KeyEventResult.ignored;
    // 自定义键位只在按下时触发一次，长按重复不再连发
    if (down) {
      final bound = AppSettings.actionFor(k);
      if (bound != null) {
        doAction(bound);
        return KeyEventResult.handled;
      }
    }
    // 固定键位：方向键翻页/切图，空格暂停，Esc 退出（不随自定义绑定变化）
    final navKey = k == LogicalKeyboardKey.arrowDown ||
        k == LogicalKeyboardKey.arrowUp ||
        k == LogicalKeyboardKey.arrowRight ||
        k == LogicalKeyboardKey.arrowLeft;
    if (navKey) {
      // 应用宝/模拟器长按方向键会发 KeyRepeatEvent（旧实现直接丢弃，必须反复点按）；
      // 这里接受重复事件并节流，长按可以连续翻页但不会一次冲过头。
      final now = DateTime.now().millisecondsSinceEpoch;
      final gap = (k == LogicalKeyboardKey.arrowLeft ||
              k == LogicalKeyboardKey.arrowRight)
          ? 320
          : 180;
      if (repeat && now - _lastKeyNav < gap) return KeyEventResult.handled;
      _lastKeyNav = now;
      if (k == LogicalKeyboardKey.arrowDown) {
        _step(1, instant: true);
      } else if (k == LogicalKeyboardKey.arrowUp) {
        _step(-1, instant: true);
      } else if (k == LogicalKeyboardKey.arrowRight) {
        _stepImage(1);
      } else {
        _stepImage(-1);
      }
      return KeyEventResult.handled;
    }
    if (!down) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.space) {
      togglePause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (fs) {
        toggleFs();
      } else {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // G10：退出播放页前落盘当前进度
    _saveWatchProgress(force: true);
    WatchProgressStore.flush();
    _dropAnim.dispose();
    _heartAnim.dispose();
    autoTimer?.cancel();
    hideTimer?.cancel();
    retryTimer?.cancel();
    _loadTimeout?.cancel();
    _slowBufferTimer?.cancel();
    _wheelUnlock?.cancel();
    _wheelIdle?.cancel();
    _volHintTimer?.cancel();
    _fadeTimer?.cancel();
    _fadeGen++;
    _swipeHintTimer?.cancel();
    _preloadTimer?.cancel();
    _preloadGen++;
    // M9：播放页退出时清掉未完成的作者页拖拽控制器
    _authorDrag?.dispose();
    _authorDrag = null;
    // M2：曾主动锁定方向时恢复系统默认（全部方向），避免影响后续页面。
    if (_orientationForced) {
      try {
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      } catch (_) {}
    }
    // 退出播放页时确保恢复系统 UI 与 Windows 窗口，避免全屏残留
    if (fs) {
      try {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } catch (_) {}
      if (Platform.isWindows) {
        try {
          windowManager.setFullScreen(false);
        } catch (_) {}
      }
    }
    subPos?.cancel();
    subDur?.cancel();
    playGuard?.cancel();
    for (final s in _playerSubs) {
      s.cancel();
    }
    _playerSubs.clear();
    for (final s in _slots) {
      s.player.dispose();
    }
    _preloadCache.clear();
    pc.dispose();
    focus.dispose();
    super.dispose();
  }

  // 视频层：窗口最小化/缩放时约束可能瞬间为 0，直接挂载纹理会让
  // Windows 上的 libmpv 重建输出并崩溃；尺寸过小时用纯黑占位。
  Widget videoView() {
    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth < 2 || c.maxHeight < 2) {
        return const ColoredBox(color: Colors.black);
      }
      return ClipRect(
        child: RepaintBoundary(
          // key 随槽位变化：预缓冲切换后必须重建 Video，才能挂到新控制器
          child: Video(
              key: ValueKey('video-${_active.tag}-$_videoGen'),
              controller: vc,
              controls: NoVideoControls),
        ),
      );
    });
  }

  /// G20：单条作品异常时的占位页。不包含任何播放器调用，竖直滑动
  /// 仍由外层 PageView 处理，因此可以直接滑到下一条。
  Widget _brokenWorkView(dynamic w) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!ui) showUi();
      },
      child: Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.broken_image_outlined,
                  size: 42, color: Colors.white38),
              const SizedBox(height: 12),
              Text('${workField(w, 'ti', '')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70)),
              const SizedBox(height: 8),
              Text(workIssueText(w),
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.white54)),
              const SizedBox(height: 6),
              Text(workDataFailure.detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white38)),
            ]),
          ),
        ),
      ),
    );
  }

  // 长简介/文案：在任务栏内展开缩略全文（H13，参考抖音，不弹独立窗口）
  // 图文单张渲染：GIF 用 Image.network 才能播放动画，其余走缓存图
  Widget picView(String path, {String? lib}) {
    final url = cfg.mediaUrl(path, lib: lib);
    // G12：图片加载失败（弱网/文件损坏）给出重试，而不是空白
    Widget retryBox() => _MediaRetryBox(
          message: '图片加载失败',
          onRetry: () async {
            try {
              await CachedNetworkImage.evictFromCache(url);
            } catch (_) {}
            if (mounted) setState(() => _imgReload++);
          },
        );
    if (isGifPath(path)) {
      return Image.network(url,
          key: ValueKey('gif-$cur-$img-$_imgReload'),
          headers: cfg.headers,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          loadingBuilder: (c, child, p) => p == null
              ? child
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white38)),
          errorBuilder: (_, __, ___) => retryBox());
    }
    return CachedNetworkImage(
        key: ValueKey('pic-$cur-$img-$_imgReload'),
        imageUrl: url,
        httpHeaders: cfg.headers,
        fit: BoxFit.contain,
        placeholder: (_, __) => const Center(
            child: CircularProgressIndicator(color: Colors.white38)),
        errorWidget: (_, __, ___) => retryBox());
  }

  // G14：切图时同步重置缩放（新图从原始大小开始）
  void _setPicIndex(int v) {
    img = v;
    _resetPicZoomState();
  }

  // G14：清理缩放相关临时状态（在 setState 内调用）
  void _resetPicZoomState() {
    _zoomPointers.clear();
    _pinching = false;
    _pinchStartDist = 0;
    _picZoom = PicZoom.initial;
  }

  // G14：放大状态下单击恢复原始大小
  void _resetPicZoom() {
    if (!_picZoom.isZoomed && !_pinching) return;
    setState(_resetPicZoomState);
    showUi();
  }

  void _zoomDown(PointerDownEvent e) {
    _zoomPointers[e.pointer] = e.localPosition;
    if (_zoomPointers.length == 2) _startPinch();
  }

  void _zoomMove(PointerMoveEvent e) {
    final prev = _zoomPointers[e.pointer];
    if (prev == null) return;
    _zoomPointers[e.pointer] = e.localPosition;
    if (_zoomPointers.length >= 2) {
      _updatePinch();
    } else if (_picZoom.isZoomed && _stageSize.width > 0) {
      // 放大后单指拖动查看局部（不会翻页/换图）
      final delta = e.localPosition - prev;
      if (delta != Offset.zero) {
        setState(() => _picZoom = _picZoom.panBy(delta, _stageSize));
      }
    }
  }

  void _zoomUp(PointerEvent e) {
    _zoomPointers.remove(e.pointer);
    if (_zoomPointers.length < 2 && _pinching) {
      setState(() {
        _pinching = false;
        _pinchStartDist = 0;
      });
    }
  }

  void _startPinch() {
    final pts = _zoomPointers.values.take(2).toList();
    final d = (pts[0] - pts[1]).distance;
    if (d < 4) return;
    _pinchStartDist = d;
    _pinchStartZoom = _picZoom;
    final mid = (pts[0] + pts[1]) / 2;
    _pinchStartFocal =
        mid - Offset(_stageSize.width / 2, _stageSize.height / 2);
    // 用户开始缩放时暂停图文自动轮播，避免缩放下图片被切走
    stopAuto();
    if (!_pinching) setState(() => _pinching = true);
  }

  void _updatePinch() {
    if (_pinchStartDist < 4) return;
    final pts = _zoomPointers.values.take(2).toList();
    final d = (pts[0] - pts[1]).distance;
    final target = pinchScale(_pinchStartZoom.scale, _pinchStartDist, d);
    setState(() => _picZoom =
        _pinchStartZoom.scaleTo(target, _pinchStartFocal, _stageSize));
  }

  // H13：展开/收起任务栏内简介
  void toggleCaption() {
    setState(() => captionOpen = !captionOpen);
  }

  // G11：从头播放 —— 清除本作品观看记录并回到开头。
  // 视频直接 seek(0)，图文回到第 1 张；按当前播放/暂停状态继续。
  void _restartPlayback() {
    final w = _workAt(cur);
    final isV = w['t'] == 'v';
    WatchProgressStore.remove(_libFor(w), _watchIdFor(w));
    // G17：从头播放视为新的观看，先移出「继续观看」，位置到 1s 后重新出现
    ContinueWatchingStore.remove(_libFor(w), _watchIdFor(w));
    if (isV) {
      try {
        player.seek(Duration.zero);
      } catch (_) {}
      setState(() => pos = Duration.zero);
      if (paused) {
        // 从头播放视为一次新的观看，直接开始
        setState(() => paused = false);
        try {
          player.setRate(speed);
        } catch (_) {}
        try {
          player.play();
        } catch (_) {}
      }
    } else {
      stopAuto();
      setState(() => _setPicIndex(0));
    }
    hapticTap();
    showUi();
  }

  // G11：长按作品信息区弹出播放菜单（视频区域长按仍是 2 倍速）。
  void _showWorkMenu() {
    final w = _workAt(cur);
    final isV = w['t'] == 'v';
    final lib = _libFor(w);
    final id = _watchIdFor(w);
    final menu = buildPlaybackMenu(
        isVideo: isV, progress: WatchProgressStore.of(lib, id));
    hapticTap();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (('${w['ti'] ?? ''}').isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${w['ti']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.replay),
              title: const Text('从头播放'),
              subtitle: Text(isV ? '清除观看进度并回到 00:00' : '回到第 1 张'),
              onTap: () {
                Navigator.of(ctx).pop();
                _restartPlayback();
              },
            ),
            if (menu.canResume)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: const Text('继续观看'),
                subtitle: Text('上次看到 ${formatMenuPosition(menu.resumeAtMs)}'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _resumePlayback(menu.resumeAtMs);
                },
              ),
            if (menu.canMarkDone)
              ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: const Text('标记为已看完'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _markWatched(w);
                  hapticTap();
                },
              ),
            if (menu.canClear)
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text('清除观看记录', style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  WatchProgressStore.remove(lib, id);
                  ContinueWatchingStore.remove(lib, id);
                },
              ),
            const SizedBox(height: 4),
          ]),
        );
      },
    );
  }

  // G11：跳到记录位置（「继续观看」）
  void _resumePlayback(int at) {
    try {
      player.seek(Duration(milliseconds: at));
    } catch (_) {}
    setState(() => pos = Duration(milliseconds: at));
    if (paused) {
      setState(() => paused = false);
      try {
        player.setRate(speed);
      } catch (_) {}
      try {
        player.play();
      } catch (_) {}
    }
  }

  // J5：视频合集选集——切换章节后重新打开当前作品（保留暂停/连播状态）。
  Future<void> _selectChapter(int k) async {
    final n = workChapterCount(widget.works[cur]);
    if (n <= 1) return;
    final i = k.clamp(0, n - 1);
    if (i == _chapter) return;
    // 先按旧章节落盘，再切章节，避免把旧位置写到新章节记录里
    _saveWatchProgress(force: true);
    setState(() => _chapter = i);
    await open(cur, saveProgress: false);
    hapticTap();
    showUi();
  }

  void _showChapters() {
    final w = _workAt(cur);
    final chs = workChapters(w);
    if (chs.length < 2) return;
    hapticTap();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(children: [
                Text('选集（${chs.length}）',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${_chapter + 1} / ${chs.length}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: chs.length,
                itemBuilder: (_, i) {
                  final selected = i == _chapter;
                  final dur = formatBadgeDuration(
                      chs[i]['du'] is num ? chs[i]['du'] as num : null);
                  return ListTile(
                    dense: true,
                    leading: Icon(
                        selected
                            ? Icons.play_circle_fill
                            : Icons.play_circle_outline,
                        color: selected ? cs.primary : cs.onSurfaceVariant),
                    title: Text(chapterLabel(chs[i], i),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: selected ? cs.primary : null,
                            fontWeight: selected ? FontWeight.w600 : null)),
                    subtitle: dur.isEmpty ? null : Text(dur),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _selectChapter(i);
                    },
                  );
                },
              ),
            ),
          ]),
        );
      },
    );
  }

  String fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // G12：失败提示卡片（标题 + 说明 + 重试），盖在画面上但不影响返回键。
  Widget _failureOverlay() {
    final f = _failure!;
    final icon = f.kind == PlaybackFailureKind.network
        ? Icons.wifi_off_rounded
        : f.kind == PlaybackFailureKind.decode
            ? Icons.broken_image_outlined
            : f.kind == PlaybackFailureKind.data
                ? Icons.hide_image_outlined
                : Icons.error_outline;
    return Positioned.fill(
      // G20：遮罩本身不接收指针事件，失败提示不能挡住 PageView 的
      // 上下滑；只有中间卡片（含重试按钮）可交互。
      child: Stack(children: [
        const Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: Color(0x99000000))),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(
                color: const Color(0xF21C1C1E),
                borderRadius: BorderRadius.circular(18)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 34, color: Colors.white60),
              const SizedBox(height: 10),
              Text(f.title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              const SizedBox(height: 6),
              Text(f.detail,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.4, color: Colors.white60)),
              const SizedBox(height: 14),
              if (f.retryable)
                FilledButton.icon(
                  onPressed: _retryPlayback,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重试'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(120, 38)),
                )
              else if (cur < widget.works.length - 1)
                FilledButton.icon(
                  onPressed: next,
                  icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                  label: const Text('下一条'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(120, 38)),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = _workAt(cur);
    final broken = !workPlayable(w);
    // M3：任务栏平台策略——桌面端无横竖屏按钮，播放/暂停常驻。
    final taskbar =
        taskbarPolicyFor(isAndroid: Platform.isAndroid, isIOS: Platform.isIOS);
    // M5：非全屏拖动切条时功能区整体淡化，松手恢复；全屏沿用隐藏逻辑。
    final chromeOpacity = ChromeFade.opacity(
        uiVisible: ui, fullscreen: fs, swiping: _pageSwiping);
    final chromeMs = ChromeFade.durationMs(swiping: _pageSwiping);
    // 圆点历史上不受 ui 控制（清屏时仍显示），M5 只叠加滑动淡化，避免改变全屏行为。
    final dotsOpacity = ChromeFade.opacity(
        uiVisible: true, fullscreen: fs, swiping: _pageSwiping);
    final isV = w['t'] == 'v';
    final pics = isV ? <String>[] : workMediaPaths(w);
    final idx = pics.isEmpty ? 0 : img.clamp(0, pics.length - 1);
    final progress = (isV && dur.inMilliseconds > 0)
        ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
        : (pics.isEmpty ? 0.0 : (idx + 1) / pics.length);
    // H2：iOS 刘海/灵动岛与横屏左右安全区。视频/图片仍全屏出血，
    // 但返回键、图文圆点、作者/标题信息、音量面板与底部控制栏都要避开安全区。
    final pad = MediaQuery.of(context).padding;
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Listener(
          onPointerSignal: onWheel,
          // 双指轻触/捏合：清屏（再次双指恢复功能区）
          // G14：改为松手时判定「轻触」，捏合缩放过程中不会误切清屏。
          onPointerDown: (e) {
            // 点击画面时确保键盘焦点仍在播放页，避免模拟器丢焦点后方向键失效
            if (!focus.hasFocus) focus.requestFocus();
            pointers++;
            _stagePointers[e.pointer] = e.localPosition;
            if (pointers == 2) {
              _twoFingerAt = DateTime.now();
              _twoFingerMoved = false;
              _twoFingerStarts
                ..clear()
                ..addAll(_stagePointers);
            }
          },
          onPointerMove: (e) {
            final start = _twoFingerStarts[e.pointer];
            if (start != null && pointers >= 2) {
              // 与按下时的位置比较，缓慢拖动也能识别为「移动」而非轻触
              if ((e.localPosition - start).distance > 12) {
                _twoFingerMoved = true;
              }
            }
            _stagePointers[e.pointer] = e.localPosition;
          },
          onPointerUp: (e) {
            _stagePointers.remove(e.pointer);
            if (pointers == 2) {
              final at = _twoFingerAt;
              final isTap = at != null &&
                  !_twoFingerMoved &&
                  DateTime.now().difference(at) <
                      const Duration(milliseconds: 400);
              if (isTap) {
                hapticTap();
                if (ui) {
                  hideTimer?.cancel();
                  setState(() => ui = false);
                } else {
                  showUi();
                }
              }
              _twoFingerAt = null;
              _twoFingerStarts.clear();
            }
            if (pointers > 0) pointers--;
          },
          onPointerCancel: (e) {
            _stagePointers.remove(e.pointer);
            _twoFingerAt = null;
            _twoFingerStarts.clear();
            if (pointers > 0) pointers--;
          },
          child: MouseRegion(
            onHover: (e) {
              // 只在指针实际移动时唤醒功能区，静止后能正常自动隐藏
              final d = (e.localPosition.dx - _hoverDx).abs() +
                  (e.localPosition.dy - _hoverDy).abs();
              _hoverDx = e.localPosition.dx;
              _hoverDy = e.localPosition.dy;
              if (d > 1.5) showUi();
            },
            child: Stack(children: [
              // M5：捕获垂直翻页（同一条视频列表）的拖拽生命周期，
              // 只在「真实拖拽开始 → 滚动结束」之间淡化功能区。
              NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.depth != 0) return false;
                  if (n is ScrollStartNotification && n.dragDetails != null) {
                    _setPageSwiping(true);
                  } else if (n is ScrollEndNotification) {
                    _setPageSwiping(false);
                  }
                  return false;
                },
                child: PageView.builder(
                  controller: pc,
                  // Windows 桌面端由 onWheel 统一翻页；关闭 PageView 自带滚动，
                  // 否则一次滚轮会同时触发原生滚动和手动翻页，跳过多个作品。
                  // G14：图片缩放/捏合期间也禁止翻页，避免缩放时误切作品。
                  physics: (_picZoom.isZoomed ||
                          _pinching ||
                          Platform.isWindows ||
                          Platform.isLinux ||
                          Platform.isMacOS)
                      ? const NeverScrollableScrollPhysics()
                      : const DiziPageScrollPhysics(
                          parent: ClampingScrollPhysics()),
                  // I2：移动端抖音式手感——越界阻尼 + 松手快速吸附（三端一致无回弹）
                  dragStartBehavior: DragStartBehavior.down,
                  scrollDirection: Axis.vertical,
                  itemCount: widget.works.length,
                  onPageChanged: open,
                  itemBuilder: (_, i) {
                    final it = _workAt(i);
                    if (!workPlayable(it)) return _brokenWorkView(it);
                    if (i != cur) {
                      return (it['th'] ?? '').toString().isEmpty
                          ? Container(color: Colors.black)
                          : CachedNetworkImage(
                              imageUrl: cfg.mediaUrl(it['th'].toString(),
                                  lib: _libFor(it)),
                              httpHeaders: cfg.headersFor(_libFor(it)),
                              fit: BoxFit.contain);
                    }
                    if (it['t'] == 'v') {
                      return GestureDetector(
                        onTapUp: (d) => onStageTap(d.localPosition),
                        // M9：抖音式跟手拖拽——向左拖作者页随手指从右侧滑入，
                        // 松手 ≥30% 屏宽或左向速度足够则进入，否则回弹。
                        onHorizontalDragStart: (_) => _authorDragStart(),
                        onHorizontalDragUpdate: (d) => _authorDragUpdate(
                            d.delta.dx, MediaQuery.sizeOf(context).width),
                        onHorizontalDragEnd: (d) =>
                            _authorDragEnd(d.primaryVelocity ?? 0),
                        onHorizontalDragCancel: _authorDragCancel,
                        onLongPressStart: (_) => player.setRate(2.0),
                        onLongPressEnd: (_) => player.setRate(speed),
                        child: Stack(fit: StackFit.expand, children: [
                          if ((it['th'] ?? '').toString().isNotEmpty)
                            CachedNetworkImage(
                                imageUrl: cfg.mediaUrl(it['th'].toString(),
                                    lib: _libFor(it)),
                                httpHeaders: cfg.headersFor(_libFor(it)),
                                fit: BoxFit.contain),
                          videoView(),
                          if (loading)
                            const Center(
                                child: CircularProgressIndicator(
                                    color: Colors.white38)),
                        ]),
                      );
                    }
                    return GestureDetector(
                      onTapUp: (d) => onStageTap(d.localPosition),
                      // G11：图文区没有 2 倍速手势，长按同样弹出播放菜单
                      // G14：放大查看时禁用长按菜单，避免平移误触
                      onLongPress: _picZoom.isZoomed ? null : _showWorkMenu,
                      onHorizontalDragEnd: (d) {
                        // G14：放大后横向拖动是平移图片，不换图
                        if (_picZoom.isZoomed) return;
                        stopAuto();
                        final v = d.primaryVelocity ?? 0;
                        setState(() {
                          if (v < -100) {
                            _setPicIndex((idx + 1).clamp(0, pics.length - 1));
                          } else if (v > 100) {
                            _setPicIndex((idx - 1).clamp(0, pics.length - 1));
                          }
                        });
                      },
                      child: Stack(fit: StackFit.expand, children: [
                        // G14：双指缩放 + 放大后单指拖动查看；单击恢复原大小
                        LayoutBuilder(builder: (_, cons) {
                          _stageSize = cons.biggest;
                          return Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: _zoomDown,
                            onPointerMove: _zoomMove,
                            onPointerUp: _zoomUp,
                            onPointerCancel: _zoomUp,
                            child: ClipRect(
                              child: Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.diagonal3Values(
                                    _picZoom.scale, _picZoom.scale, 1)
                                  ..setTranslationRaw(_picZoom.offset.dx,
                                      _picZoom.offset.dy, 0),
                                child: picView(pics[idx], lib: _curLib),
                              ),
                            ),
                          );
                        }),
                        if (pics.length > 1)
                          Positioned(
                            top: pad.top + 2,
                            right: pad.right + 4,
                            child: AnimatedOpacity(
                              opacity: dotsOpacity,
                              duration: Duration(milliseconds: chromeMs),
                              curve: Curves.easeOut,
                              child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(
                                      pics.length,
                                      (k) => Container(
                                            width: 4,
                                            height: 4,
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 1.5),
                                            decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: k == idx
                                                    ? Colors.white
                                                    : Colors.white24),
                                          ))),
                            ),
                          ),
                      ]),
                    );
                  },
                ),
              ),
              // G12：弱网缓冲提示（延迟出现，避免正常起播闪烁）
              if (_slowBuffer && _failure == null && !loading)
                Positioned(
                  top: pad.top + 14,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.6, color: Colors.white70)),
                              SizedBox(width: 8),
                              Text('网络较慢，正在缓冲…',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.white70)),
                            ]),
                      ),
                    ),
                  ),
                ),
              // G12：加载超时/解码失败/网络失败 —— 给出重试入口
              if (_failure != null) _failureOverlay(),
              // G9：双击位置的红心反馈
              if (_heartPos != null)
                Positioned(
                  left: _heartPos!.dx - 30,
                  top: _heartPos!.dy - 30,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _heartAnim,
                      builder: (_, __) {
                        final t = _heartAnim.value;
                        final opacity = t < 0.7
                            ? 1.0
                            : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
                        return Opacity(
                          opacity: opacity,
                          child: Transform.scale(
                            scale: _heartScale.value,
                            child: const Icon(Icons.favorite,
                                size: 58, color: Color(0xFFFF3B5C)),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              // G15：移动端调光遮罩（只压暗画面，不影响控件）
              if (_mobileSwipe && brightness < 100)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(
                          alpha: dimOpacityForBrightness(brightness)),
                    ),
                  ),
                ),
              // G15：移动端左右窄边上下滑（左亮度 / 右音量），中间仍可翻页
              // I1：移动端音量改由系统音量键控制，右侧音量手势已移除
              if (_mobileSwipe) ...[
                _swipeEdge(SwipeZone.brightness,
                    swipeEdgeWidth(MediaQuery.of(context).size.width), pad),
                if (_swipeHint) _swipeHintWidget(pad),
              ],
              Positioned(
                left: pad.left + 8,
                top: pad.top + 8,
                child: IgnorePointer(
                  ignoring: !ui,
                  child: AnimatedOpacity(
                    opacity: chromeOpacity,
                    duration: Duration(milliseconds: chromeMs),
                    curve: Curves.easeOut,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white70),
                          style: IconButton.styleFrom(
                              backgroundColor: Colors.black45)),
                      // 深页面统一「返回主页」：从作者页/搜索进播放页也能一步回主页。
                      const HomeOverlayButton(),
                    ]),
                  ),
                ),
              ),
              if (paused && !broken)
                const IgnorePointer(
                  child: Center(
                    child:
                        Icon(Icons.play_arrow, size: 76, color: Colors.white30),
                  ),
                ),
              Positioned(
                left: pad.left + 14,
                right: pad.right + 80,
                bottom: pad.bottom + 96,
                child: IgnorePointer(
                  ignoring: !ui,
                  child: AnimatedOpacity(
                    opacity: chromeOpacity,
                    duration: Duration(milliseconds: chromeMs),
                    curve: Curves.easeOut,
                    child: GestureDetector(
                      onTap: openAuthor,
                      // G11：长按信息区弹出播放菜单（视频区长按仍是 2 倍速）
                      onLongPress: _showWorkMenu,
                      child: Row(children: [
                        if ((w['av'] ?? '').toString().isNotEmpty)
                          ClipOval(
                              child: CachedNetworkImage(
                                  imageUrl: cfg.mediaUrl(w['av'].toString(),
                                      lib: _curLib),
                                  httpHeaders: cfg.headersFor(_curLib),
                                  width: 38,
                                  height: 38,
                                  fit: BoxFit.cover))
                        else
                          const CircleAvatar(
                              radius: 19, child: Icon(Icons.person)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Flexible(
                                  child: Text('@${w['a']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                                if (('${w['d'] ?? ''}').isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text('${w['d']}',
                                      style: const TextStyle(
                                          fontSize: 11, color: Colors.white54)),
                                ],
                                // G9：本地喜欢标记，点红心可取消
                                if (_isLiked(w)) ...[
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () => _setLiked(w, false),
                                    child: const Icon(Icons.favorite,
                                        size: 14, color: Color(0xFFFF3B5C)),
                                  ),
                                ],
                              ]),
                              // T2：来源词条（单元库）+ 等级词条，半透明不遮画面
                              if (_meta != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Opacity(
                                    opacity: 0.7,
                                    child: AuthorBadges(
                                      meta: _meta,
                                      name: '${w['a'] ?? ''}',
                                      mediaPath: '${w['av'] ?? ''}',
                                      fallbackId: _curLib,
                                      // 0.9.6：不再回退库名文案，无归属显示 SECRET
                                      fallbackName: '',
                                      works: widget.works
                                          .where((e) =>
                                              e is Map && e['a'] == w['a'])
                                          .length,
                                    ),
                                  ),
                                ),
                              if (workChapterCount(widget.works[cur]) > 1)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                      '第 ${_chapter.clamp(0, workChapterCount(widget.works[cur]) - 1) + 1}/${workChapterCount(widget.works[cur])} 集 · '
                                      '${chapterLabel(workChapters(widget.works[cur])[_chapter.clamp(0, workChapterCount(widget.works[cur]) - 1)], _chapter)}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 10.5,
                                          color: Colors.lightBlueAccent)),
                                ),
                              Row(children: [
                                Expanded(
                                  child: LayoutBuilder(builder: (context, c) {
                                    const style = TextStyle(
                                        fontSize: 12, color: Colors.white70);
                                    const expandWidth = 22.0;
                                    final title = '${w['ti'] ?? ''}';
                                    // F33：按可用宽度实际测量，只有真的截断才
                                    // 显示展开按钮（原按字符数猜测会误判）。
                                    final needsExpand = willOverflowText(
                                        title, style, c.maxWidth - expandWidth,
                                        textScaler:
                                            MediaQuery.textScalerOf(context),
                                        locale: Localizations.maybeLocaleOf(
                                            context));
                                    // H13：展开后任务栏向上拉长，显示缩略全文，
                                    // 不弹独立窗口；再点一次收起。
                                    if (captionOpen) {
                                      return GestureDetector(
                                        // 吸收点击，避免误触进入作者主页
                                        onTap: () {},
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.fromLTRB(
                                              10, 8, 10, 6),
                                          decoration: BoxDecoration(
                                              color: Colors.black45,
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          constraints: BoxConstraints(
                                              maxHeight:
                                                  MediaQuery.sizeOf(context)
                                                          .height *
                                                      0.42),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Flexible(
                                                child: SingleChildScrollView(
                                                  child: SelectableText(title,
                                                      style: style.copyWith(
                                                          fontSize: 13,
                                                          height: 1.5,
                                                          color: Colors.white)),
                                                ),
                                              ),
                                              Align(
                                                alignment:
                                                    Alignment.centerRight,
                                                child: GestureDetector(
                                                  onTap: toggleCaption,
                                                  child: const Padding(
                                                    padding: EdgeInsets.only(
                                                        left: 6,
                                                        top: 4,
                                                        bottom: 2),
                                                    child: Icon(
                                                        Icons.unfold_less,
                                                        size: 16,
                                                        color: Colors.white54),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    return Row(children: [
                                      Expanded(
                                        child: Text(title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: style),
                                      ),
                                      if (needsExpand)
                                        GestureDetector(
                                          onTap: toggleCaption,
                                          child: const Padding(
                                            padding: EdgeInsets.only(
                                                left: 6, top: 2, bottom: 2),
                                            child: Icon(Icons.unfold_more,
                                                size: 16,
                                                color: Colors.white54),
                                          ),
                                        ),
                                    ]);
                                  }),
                                ),
                              ]),
                            ])),
                      ]),
                    ),
                  ),
                ),
              ),
              // H14：不再弹独立音量模块，仅保留一个轻量读数提示（松手后自动消失）
              if (_volumeUi && _volHintVisible && ui && !_swipeHint)
                Positioned(
                  right: pad.right + 16,
                  bottom: pad.bottom + 96,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            muted || volume == 0
                                ? Icons.volume_off
                                : (volume < 50
                                    ? Icons.volume_down
                                    : Icons.volume_up),
                            size: 16,
                            color: Colors.white70),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 84,
                          height: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: (muted ? 0.0 : volume.clamp(0.0, 100.0)) /
                                  100.0,
                              backgroundColor: Colors.white24,
                              valueColor:
                                  const AlwaysStoppedAnimation(Colors.white),
                              minHeight: 4,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 30,
                          child: Text(
                            '${(muted ? 0 : volume).round()}%',
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white70),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
              if (!broken)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: !ui,
                    child: AnimatedOpacity(
                      opacity: chromeOpacity,
                      duration: Duration(milliseconds: chromeMs),
                      curve: Curves.easeOut,
                      child: Container(
                        decoration: const BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black87])),
                        padding: EdgeInsets.only(
                            left: pad.left + 12,
                            right: pad.right + 12,
                            top: 10,
                            bottom: 6 + pad.bottom),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Row(children: [
                            Text(
                                isV
                                    ? '${fmt(pos)} / ${fmt(dur)}'
                                    : '${(dragging && dragPic != null ? dragPic! : idx) + 1}/${pics.length}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white60)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: LayoutBuilder(builder: (ctx, cons) {
                                void seekAt(Offset p) {
                                  if (!isV || dur.inMilliseconds == 0) return;
                                  final f =
                                      (p.dx / cons.maxWidth).clamp(0.0, 1.0);
                                  player.seek(dur * f);
                                }

                                // 图文：按图片数量分段显示进度，当前张高亮
                                if (!isV && pics.length > 1) {
                                  // H1：按下即进入拖动，跨段震动反馈，松手才切换图片；
                                  // 拖动中的目标段放大到与视频进度条一致（7px）。
                                  int picAt(Offset p) => picIndexAtFraction(
                                      p.dx / cons.maxWidth, pics.length);
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTapUp: (d) {
                                      stopAuto();
                                      setState(() =>
                                          _setPicIndex(picAt(d.localPosition)));
                                      hapticTap();
                                    },
                                    onHorizontalDragStart: (d) {
                                      stopAuto();
                                      final k = picAt(d.localPosition);
                                      setState(() {
                                        dragging = true;
                                        dragPic = k;
                                        dragFrac = ((k + 0.5) / pics.length)
                                            .clamp(0.0, 1.0);
                                      });
                                      hapticTap();
                                    },
                                    onHorizontalDragUpdate: (d) {
                                      final f =
                                          (d.localPosition.dx / cons.maxWidth)
                                              .clamp(0.0, 1.0);
                                      final k =
                                          picIndexAtFraction(f, pics.length);
                                      if (k != dragPic) hapticSelect();
                                      setState(() {
                                        dragPic = k;
                                        dragFrac = f;
                                      });
                                    },
                                    onHorizontalDragEnd: (_) {
                                      final k = dragPic;
                                      setState(() {
                                        if (k != null) _setPicIndex(k);
                                        dragging = false;
                                        dragPic = null;
                                        dragFrac = null;
                                      });
                                    },
                                    onHorizontalDragCancel: () {
                                      setState(() {
                                        dragging = false;
                                        dragPic = null;
                                        dragFrac = null;
                                      });
                                    },
                                    child: SizedBox(
                                      height: 30,
                                      child: Row(
                                        children:
                                            List.generate(pics.length, (k) {
                                          final selected =
                                              k == (dragging ? dragPic : idx);
                                          final active = k <=
                                              (dragging
                                                  ? (dragPic ?? idx)
                                                  : idx);
                                          return Expanded(
                                            child: Container(
                                              height: 30,
                                              alignment: Alignment.center,
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 120),
                                                height: dragging
                                                    ? (selected ? 7 : 3)
                                                    : (selected ? 6 : 3),
                                                margin:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 1.5),
                                                decoration: BoxDecoration(
                                                  color: active
                                                      ? (selected
                                                          ? Colors.white
                                                          : Colors.white70)
                                                      : Colors.white24,
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                              ),
                                            ),
                                          );
                                        }),
                                      ),
                                    ),
                                  );
                                }

                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (d) => seekAt(d.localPosition),
                                  onHorizontalDragStart: (_) {
                                    resumeAfterDrag = !paused;
                                    if (!paused) player.pause();
                                    setState(() {
                                      dragging = true;
                                      dragFrac = progress;
                                    });
                                  },
                                  onHorizontalDragUpdate: (d) {
                                    final f =
                                        (d.localPosition.dx / cons.maxWidth)
                                            .clamp(0.0, 1.0);
                                    setState(() => dragFrac = f);
                                  },
                                  onHorizontalDragEnd: (_) {
                                    final f = dragFrac ?? progress;
                                    if (isV && dur.inMilliseconds > 0) {
                                      player.seek(dur * f);
                                      if (resumeAfterDrag) player.play();
                                    } else if (!isV && pics.isNotEmpty) {
                                      setState(() => _setPicIndex(
                                          (f * (pics.length - 1))
                                              .round()
                                              .clamp(0, pics.length - 1)));
                                    }
                                    setState(() {
                                      dragging = false;
                                      dragFrac = null;
                                    });
                                  },
                                  child: MouseRegion(
                                    onEnter: (_) =>
                                        setState(() => barHover = true),
                                    onExit: (_) =>
                                        setState(() => barHover = false),
                                    child: SizedBox(
                                      height: 30,
                                      child: Stack(
                                        alignment: Alignment.centerLeft,
                                        children: [
                                          Container(
                                              height: (dragging || barHover)
                                                  ? 7
                                                  : 3,
                                              color: Colors.white24),
                                          FractionallySizedBox(
                                            alignment: Alignment.centerLeft,
                                            widthFactor: dragFrac ?? progress,
                                            child: Container(
                                                height: (dragging || barHover)
                                                    ? 7
                                                    : 3,
                                                color: dragging
                                                    ? Colors.white
                                                    : Colors.white70),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(width: 8),
                            Text('${cur + 1} / ${widget.works.length}',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white54)),
                          ]),
                          Row(children: [
                            // M2：移动端任务栏按钮较多，窄屏时整体等比缩小，
                            // 避免 390pt 机型溢出；全屏与竖屏下都保持单行。
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // H14：点击=静音切换；长按/左右拖动调音量（不弹模块）
                                      // I1：移动端隐藏音量按钮，音量由系统音量键控制
                                      if (_volumeUi)
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: toggleMute,
                                          onLongPressStart: _volLongPressStart,
                                          onLongPressMoveUpdate:
                                              _volLongPressMove,
                                          onLongPressEnd: (_) => _volDragEnd(),
                                          onHorizontalDragStart: _volDragStart,
                                          onHorizontalDragUpdate:
                                              _volDragUpdate,
                                          onHorizontalDragEnd: _volDragEnd,
                                          child: Tooltip(
                                            message: '点击静音 / 长按拖动调音量',
                                            child: SizedBox(
                                              width: 48,
                                              height: 48,
                                              child: Icon(
                                                  muted || volume == 0
                                                      ? Icons.volume_off
                                                      : (volume < 50
                                                          ? Icons.volume_down
                                                          : Icons.volume_up),
                                                  color: Colors.white70),
                                            ),
                                          ),
                                        ),
                                      // L6：桌面端音量模块常驻任务栏（声音按钮右侧）：
                                      // 细滑杆即时改音量，单击左侧声音按钮仍然是静音切换。
                                      if (_volumeUi)
                                        SizedBox(
                                          key: const ValueKey('volume-module'),
                                          width: 104,
                                          height: 48,
                                          child: Row(children: [
                                            Expanded(
                                              child: SliderTheme(
                                                data: const SliderThemeData(
                                                  trackHeight: 2.5,
                                                  thumbShape:
                                                      RoundSliderThumbShape(
                                                          enabledThumbRadius:
                                                              5),
                                                  overlayShape:
                                                      RoundSliderOverlayShape(
                                                          overlayRadius: 10),
                                                  activeTrackColor:
                                                      Colors.white70,
                                                  inactiveTrackColor:
                                                      Colors.white24,
                                                  thumbColor: Colors.white,
                                                ),
                                                child: Slider(
                                                  value: (muted ? 0.0 : volume)
                                                      .clamp(0.0, 100.0),
                                                  max: 100,
                                                  onChanged: _setVolume,
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 30,
                                              child: Text('${volume.round()}',
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white54)),
                                            ),
                                          ]),
                                        ),
                                      // J5：视频合集章节选择（按「选集」图标 + 当前集数）
                                      if (workChapterCount(w) > 1)
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: _showChapters,
                                          child: Tooltip(
                                            message: '选集',
                                            child: SizedBox(
                                              width: 46,
                                              height: 48,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  const Icon(
                                                      Icons
                                                          .video_library_outlined,
                                                      size: 19,
                                                      color: Colors.white70),
                                                  const SizedBox(height: 1),
                                                  Text(
                                                      '${_chapter + 1}/${workChapterCount(w)}',
                                                      style: const TextStyle(
                                                          fontSize: 9,
                                                          height: 1.0,
                                                          color:
                                                              Colors.white54)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      // M2/M3：播放/暂停常驻任务栏，图标随播放器状态同步。
                                      TaskbarPlayButton(
                                          paused: paused,
                                          onPressed: togglePause),
                                      IconButton(
                                          onPressed: cycleSpeed,
                                          icon: Text('${speed}x',
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white70))),
                                      IconButton(
                                          onPressed: toggleAutoplay,
                                          tooltip: '自动连播',
                                          icon: Icon(Icons.skip_next,
                                              color: autoplay
                                                  ? Colors.white70
                                                  : Colors.white24)),
                                      IconButton(
                                          onPressed: toggleLoop,
                                          tooltip: '单条循环',
                                          icon: Icon(Icons.repeat_one,
                                              color: loopOne
                                                  ? Colors.white70
                                                  : Colors.white24)),
                                      // H15：水滴图标下方常驻当前水滴数；默认灰、点击后变蓝并 +1 弹跳
                                      Tooltip(
                                        message:
                                            '小水滴：今日剩 $dropDayLeft/1，本周剩 $dropWeekLeft/3，累计 $dropTotal',
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: (dropBusy ||
                                                  dropDayLeft <= 0 ||
                                                  dropWeekLeft <= 0)
                                              ? null
                                              : _sendDrop,
                                          child: SizedBox(
                                            width: 46,
                                            height: 48,
                                            child: ScaleTransition(
                                              scale: _dropScale,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  if (dropBusy)
                                                    const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                                strokeWidth: 2,
                                                                color: Colors
                                                                    .white54))
                                                  else
                                                    Icon(Icons.water_drop,
                                                        size: 20,
                                                        color: dropGlow &&
                                                                dropDayLeft >= 0
                                                            ? Colors
                                                                .lightBlueAccent
                                                            : (dropDayLeft >
                                                                        0 &&
                                                                    dropWeekLeft >
                                                                        0
                                                                ? Colors.white38
                                                                : Colors
                                                                    .white24)),
                                                  const SizedBox(height: 1),
                                                  Text('$dropTotal',
                                                      style: TextStyle(
                                                          fontSize: 9,
                                                          height: 1.0,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: dropGlow
                                                              ? Colors
                                                                  .lightBlueAccent
                                                              : (dropDayLeft >
                                                                          0 &&
                                                                      dropWeekLeft >
                                                                          0
                                                                  ? Colors
                                                                      .white54
                                                                  : Colors
                                                                      .white24))),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (taskbar.showRotate)
                                        TaskbarRotateButton(
                                          mode: screenModeOf(
                                              MediaQuery.sizeOf(context)),
                                          onPressed: toggleOrientation,
                                        ),
                                    ]),
                              ),
                            ),
                            IconButton(
                                onPressed: toggleFs,
                                icon: Icon(
                                    fs
                                        ? Icons.fullscreen_exit
                                        : Icons.fullscreen,
                                    color: Colors.white70)),
                          ]),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class RecommendPage extends StatefulWidget {
  const RecommendPage({super.key});
  @override
  State<RecommendPage> createState() => _RecommendPageState();
}

class _RecommendPageState extends State<RecommendPage> {
  List works = [];
  List<Map<String, dynamic>> libs = [];
  final Map<String, LibMeta> metas = {};
  bool loading = true;
  String? err;
  int batch = 0;
  // J11：推荐页支持作者筛选（与总览/排行/搜索共享状态）
  LibMeta? meta;
  Map<String, Set<String>> authorTypes = {};
  bool typesLoading = false;
  final Map<String, int> _authorCount = {};

  @override
  void initState() {
    super.initState();
    authorFilter.addListener(_onSharedFilter);
    load(refresh: false);
  }

  @override
  void dispose() {
    authorFilter.removeListener(_onSharedFilter);
    super.dispose();
  }

  void _onSharedFilter() {
    if (mounted) setState(() {});
  }

  Future<void> load({required bool refresh}) async {
    if (refresh) batch++;
    final seed = DateTime.now().millisecondsSinceEpoch ~/ 1000 + batch * 7919;
    setState(() {
      loading = true;
      err = null;
    });
    try {
      // 推荐改为跨全部已注册库：每个库取一批，按库轮转合并，
      // 避免默认库（抖音收藏）独占整个页面。
      if (libs.isEmpty) {
        try {
          final lr = await http
              .get(cfg.u('/api/libraries'), headers: cfg.headers)
              .timeout(const Duration(seconds: 8));
          if (lr.statusCode == 200) {
            final lj = jsonDecode(lr.body);
            if (lj is Map && lj['libraries'] is List) {
              libs = librariesWithDisplayNames((lj['libraries'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .where((e) => '${e['id'] ?? ''}'.isNotEmpty)
                  .toList());
            }
          }
        } catch (_) {}
      }
      // 0.9.8：推荐改为全部基础库池（服务端 lib=all，约 1.1 万作品，60s 缓存）。
      // 每条作品带 `_lib`（所属基础库），播放/词条按基础库路由。
      final r = await http.get(
          cfg.u('/api/recommend?n=40&seed=$seed', lib: 'all'),
          headers: cfg.headers);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final merged = <Map<String, dynamic>>[];
      for (final w in (j is Map && j['works'] is List)
          ? (j['works'] as List)
          : const []) {
        if (w is! Map) continue;
        final m = Map<String, dynamic>.from(w);
        merged.add({...m, '_lib': '${m['_lib'] ?? cfg.lib}'});
        if (merged.length >= 40) break;
      }
      if (!mounted) return;
      setState(() {
        works = merged;
        _authorCount.clear();
        for (final w in works) {
          if (w is! Map) continue;
          final a = '${w['a'] ?? ''}';
          if (a.isEmpty) continue;
          _authorCount[a] = (_authorCount[a] ?? 0) + 1;
        }
        loading = false;
      });
      _loadMeta();
    } catch (e) {
      if (mounted) {
        setState(() {
          err = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> _loadMeta() async {
    typesLoading = true;
    // 全部基础库的作者类型只需扫一遍默认注册库（服务端按 libid 逐基础库索引）。
    final ids = [cfg.lib];
    LibMeta? m;
    for (final id in ids) {
      try {
        final loaded = await LibMeta.load(id);
        metas[id] = loaded;
        m ??= loaded;
      } catch (_) {}
    }
    final types = await loadAuthorTypes(ids);
    if (!mounted) return;
    setState(() {
      meta = m;
      authorTypes = types;
      typesLoading = false;
    });
  }

  List<AuthorLibNode> get _filterBasics {
    final out = <AuthorLibNode>[];
    for (final b in meta?.basics ?? const <BasicLibRef>[]) {
      out.add(AuthorLibNode(
          id: b.id, name: basicLibLabel(b, b.name), bigId: b.bigId));
    }
    return authorLibNodes(out);
  }

  List<AuthorBigNode> get _filterBigs {
    final out = <AuthorBigNode>[];
    for (final b in _filterBasics) {
      if (b.bigId.isEmpty) continue;
      out.add(
          AuthorBigNode(id: b.bigId, name: meta?.bigNames[b.bigId] ?? b.bigId));
    }
    final seen = <String>{};
    out.removeWhere((e) => !seen.add(e.id));
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Map<String, String> get _filterLibNames =>
      {for (final b in _filterBasics) b.id: b.name};

  Map<String, String> get _filterBigNames =>
      {for (final b in _filterBigs) b.id: b.name};

  /// T2：单元库筛选选项（含顶级 SECRET）。
  List<AuthorLibNode> get _filterUnits {
    final out = <AuthorLibNode>[];
    final seen = <String>{};
    for (final u in meta?.units ?? const <UnitLibrary>[]) {
      if (!seen.add(u.id)) continue;
      out.add(AuthorLibNode(id: u.id, name: meta!.unitNameOf(u.id)));
    }
    return authorLibNodes(out);
  }

  Map<String, String> get _filterUnitNames =>
      {for (final u in _filterUnits) u.id: u.name};

  bool _matches(dynamic raw, AuthorFilterState f) {
    if (raw is! Map) return false;
    final w = Map<String, dynamic>.from(raw);
    final av = '${w['av'] ?? ''}';
    final a = '${w['a'] ?? ''}';
    final type = workFilterType(w);
    final types =
        authorTypes[a] ?? (type == 'other' ? const <String>{} : <String>{type});
    return f.matches(
      basicId: meta?.idFor(av) ?? '',
      bigId: meta?.bigIdFor(av) ?? '',
      unitId: meta?.unitIdFor(av) ?? '',
      grade: meta?.gradeFor(a, _authorCount[a] ?? 0) ?? '',
      workTypes: types,
    );
  }

  /// 统一筛选后的可见作品；筛选未激活时原样返回。
  List get _visibleWorks => applyAuthorFilter(
        works,
        authorFilter.value,
        (w, f) => _matches(w, f),
      );

  Future<void> _openFilter() async {
    if (meta == null) {
      await _loadMeta();
    }
    if (!mounted) return;
    final res = await showAuthorFilterSheet(
      context: context,
      initial: authorFilter.value,
      basics: _filterBasics,
      bigs: _filterBigs,
      units: _filterUnits,
      grades: const ['S', 'A', 'B', 'C', 'D'],
      count: (f) => works.where((w) => _matches(w, f)).length,
    );
    if (res == null || !mounted) return;
    authorFilter.apply(res);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleWorks;
    return Scaffold(
      appBar: AppBar(title: const Text('推荐'), actions: [
        const HomeAction(),
        IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '换一批',
            onPressed: loading ? null : () => load(refresh: true)),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('加载失败：$err'),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: () => load(refresh: false),
                      child: const Text('重试')),
                ]))
              : Column(children: [
                  // J11：推荐与总览/排行/搜索共用同一套作者筛选与状态
                  AuthorFilterBar(
                    filter: authorFilter.value,
                    loading: typesLoading,
                    onOpen: _openFilter,
                    onClear: authorFilter.clearAll,
                    summary: authorFilter.value.isActive
                        ? '${authorFilter.value.summary(basicNames: _filterLibNames, bigNames: _filterBigNames, unitNames: _filterUnitNames)} · 命中 ${visible.length}/${works.length}'
                        : null,
                  ),
                  Expanded(
                    child: works.isEmpty
                        ? const Center(
                            child: Text('暂无推荐',
                                style: TextStyle(color: Colors.grey)))
                        : visible.isEmpty
                            ? const Center(
                                child: Text('没有符合筛选条件的作品',
                                    style: TextStyle(color: Colors.grey)))
                            : RefreshIndicator(
                                onRefresh: () => load(refresh: true),
                                child: GridView.builder(
                                  padding: const EdgeInsets.all(2),
                                  gridDelegate:
                                      const SliverGridDelegateWithMaxCrossAxisExtent(
                                          maxCrossAxisExtent: 180,
                                          childAspectRatio: 3 / 4,
                                          mainAxisSpacing: 2,
                                          crossAxisSpacing: 2),
                                  itemCount: visible.length,
                                  itemBuilder: (_, i) {
                                    final w = visible[i];
                                    return GestureDetector(
                                      onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                              builder: (_) => PlayerPage(
                                                  works: visible, start: i))),
                                      child: _tile(w),
                                    );
                                  },
                                ),
                              ),
                  ),
                ]),
    );
  }

  Widget _tile(dynamic w) {
    return Stack(fit: StackFit.expand, children: [
      (w['th'] ?? '').toString().isEmpty
          ? Container(color: Colors.black26)
          : CachedNetworkImage(
              imageUrl: cfg.mediaUrl(w['th'].toString()),
              httpHeaders: cfg.headers,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(color: Colors.black26)),
      Positioned(
          left: 4,
          top: 4,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              color: Colors.black54,
              child: Text(w['t'] == 'v' ? '视频' : '图文',
                  style: const TextStyle(fontSize: 10)))),
      Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
              padding: const EdgeInsets.fromLTRB(6, 10, 6, 5),
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87])),
              child: Text('@${w['a'] ?? ''} · ${w['d'] ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10)))),
    ]);
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController q = TextEditingController();
  List<Map<String, dynamic>> libs = [];
  String sel = '';
  List all = [];
  final Map<String, LibMeta> metas = {};
  final Map<String, int> authorWorkCount = {};
  bool loading = true;
  String kw = '';
  int _loadToken = 0;
  // J11：搜索页同样支持作者筛选（与总览/排行/推荐共享同一份状态）
  Map<String, Set<String>> authorTypes = {};
  bool typesLoading = false;
  String _typesForSel = '';

  @override
  void initState() {
    super.initState();
    authorFilter.addListener(_onSharedFilter);
    sel = cfg.lib;
    _init();
  }

  @override
  void dispose() {
    authorFilter.removeListener(_onSharedFilter);
    super.dispose();
  }

  void _onSharedFilter() {
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    await loadLibs();
    await loadAll();
  }

  Future<void> loadLibs() async {
    try {
      final r = await http
          .get(cfg.u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final list = librariesWithDisplayNames(
          ((j['libraries'] as List?) ?? const [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList());
      if (!mounted || list.isEmpty) return;
      var next = sel;
      if (next.isEmpty ||
          (next != 'all' && !list.any((e) => e['id'] == next))) {
        next = '${j['default'] ?? list.first['id']}';
      }
      setState(() {
        libs = list;
        sel = next;
      });
    } catch (_) {}
  }

  String _libName(String id) {
    for (final l in libs) {
      if ('${l['id']}' == id) return '${l['name'] ?? l['id']}';
    }
    return id;
  }

  void _select(String id) {
    if (sel == id) return;
    setState(() {
      sel = id;
      loading = true;
      all = [];
    });
    loadAll();
  }

  Future<void> loadAll() async {
    final token = ++_loadToken;
    final targets = sel == 'all'
        ? libs.map((e) => '${e['id']}').toList()
        : [(sel.isEmpty ? cfg.lib : sel)];
    final out = <Map<String, dynamic>>[];
    try {
      for (final lib in targets) {
        try {
          metas[lib] = await LibMeta.load(lib);
        } catch (_) {}
        // T3：作品来源改为基础库 `works.json`（旧 `/api/c/` 收藏夹通道已移除）
        final basics = metas[lib]?.basics ?? const [];
        for (final b in basics) {
          final ws = await _libWorks(lib, b.id);
          for (var i = 0; i < ws.length; i++) {
            out.add({
              'w': ws[i],
              'works': ws,
              'i': i,
              '_lib': lib,
              '_bid': b.id,
              '_rel': b.rel,
            });
          }
        }
      }
    } catch (_) {}
    if (!mounted || token != _loadToken) return;
    authorWorkCount.clear();
    for (final e in out) {
      final w = e['w'];
      final key = '${e['_lib']}|${w is Map ? w['a'] ?? '' : ''}';
      authorWorkCount[key] = (authorWorkCount[key] ?? 0) + 1;
    }
    setState(() {
      all = out;
      loading = false;
    });
    _ensureTypes();
  }

  /// 分页拉取一个基础库的全部作品（搜索用）。失败返回已取到的部分。
  Future<List<dynamic>> _libWorks(String lib, String basicId) async {
    const pageSize = 1000;
    const cap = 40000;
    final ws = <dynamic>[];
    var offset = 0;
    while (offset < cap) {
      try {
        final r = await http
            .get(
                cfg.u(
                    '/api/lib/$basicId/works.json'
                    '?offset=$offset&limit=$pageSize',
                    lib: lib),
                headers: cfg.headers)
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) break;
        final j = jsonDecode(utf8.decode(r.bodyBytes));
        final batch =
            (j is Map && j['works'] is List) ? j['works'] as List : const [];
        ws.addAll(batch);
        offset += batch.length;
        final total =
            (j is Map && j['total'] is num) ? (j['total'] as num).toInt() : 0;
        if (batch.isEmpty || (total > 0 && offset >= total)) break;
      } catch (_) {
        break;
      }
    }
    return ws;
  }

  // ---- J11：作者筛选（与总览/排行/推荐同一状态与组件） ----

  List<AuthorLibNode> get _filterBasics {
    final out = <AuthorLibNode>[];
    for (final m in metas.values) {
      for (final b in m.basics) {
        out.add(AuthorLibNode(
            id: b.id, name: basicLibLabel(b, b.name), bigId: b.bigId));
      }
    }
    return authorLibNodes(out);
  }

  List<AuthorBigNode> get _filterBigs {
    final out = <AuthorBigNode>[];
    final seen = <String>{};
    for (final b in _filterBasics) {
      if (b.bigId.isEmpty || !seen.add(b.bigId)) continue;
      var name = b.bigId;
      for (final m in metas.values) {
        final n = m.bigNames[b.bigId];
        if (n != null && n.isNotEmpty) {
          name = n;
          break;
        }
      }
      out.add(AuthorBigNode(id: b.bigId, name: name));
    }
    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  Map<String, String> get _filterLibNames =>
      {for (final b in _filterBasics) b.id: b.name};

  Map<String, String> get _filterBigNames =>
      {for (final b in _filterBigs) b.id: b.name};

  /// T2：单元库筛选选项（含顶级 SECRET）。
  List<AuthorLibNode> get _filterUnits {
    final out = <AuthorLibNode>[];
    final seen = <String>{};
    for (final m in metas.values) {
      for (final u in m.units) {
        if (!seen.add(u.id)) continue;
        out.add(AuthorLibNode(id: u.id, name: m.unitNameOf(u.id)));
      }
    }
    return authorLibNodes(out);
  }

  Map<String, String> get _filterUnitNames =>
      {for (final u in _filterUnits) u.id: u.name};

  bool _matchesFilter(Map<String, dynamic> e, AuthorFilterState f) {
    final w = e['w'];
    if (w is! Map) return false;
    final lib = '${e['_lib']}';
    final meta = metas[lib];
    final av = '${w['av'] ?? ''}';
    final author = '${w['a'] ?? ''}';
    final type = workFilterType(Map<String, dynamic>.from(w));
    final types = authorTypes[author] ??
        (type == 'other' ? const <String>{} : <String>{type});
    final bid = '${e['_bid'] ?? ''}';
    final known = bid.isNotEmpty ? meta?.basicById(bid) : null;
    return f.matches(
      basicId: known?.id ?? (meta?.idFor(av) ?? ''),
      bigId: known != null && known.bigId.isNotEmpty
          ? known.bigId
          : (meta?.bigIdFor(av) ?? ''),
      unitId: bid.isNotEmpty
          ? (meta?.basicToUnit[bid] ?? '')
          : (meta?.unitIdFor(av) ?? ''),
      grade: meta?.gradeFor(author, authorWorkCount['$lib|$author'] ?? 0) ?? '',
      workTypes: types,
    );
  }

  Future<void> _ensureTypes() async {
    if (typesLoading) return;
    if (_typesForSel == sel && authorTypes.isNotEmpty) return;
    final targets = sel == 'all'
        ? libs.map((e) => '${e['id']}').toList()
        : [sel.isEmpty ? cfg.lib : sel];
    if (targets.isEmpty) return;
    setState(() => typesLoading = true);
    final map = await loadAuthorTypes(targets);
    if (!mounted) return;
    setState(() {
      authorTypes = map;
      _typesForSel = sel;
      typesLoading = false;
    });
  }

  Future<void> _openFilter() async {
    await _ensureTypes();
    if (!mounted) return;
    final res = await showAuthorFilterSheet(
      context: context,
      initial: authorFilter.value,
      basics: _filterBasics,
      bigs: _filterBigs,
      units: _filterUnits,
      grades: const ['S', 'A', 'B', 'C', 'D'],
      count: (f) => all.where((e) => _matchesFilter(e, f)).length,
    );
    if (res == null || !mounted) return;
    authorFilter.apply(res);
  }

  @override
  Widget build(BuildContext context) {
    final base = authorFilter.value.isActive
        ? all.where((e) => _matchesFilter(e, authorFilter.value)).toList()
        : all;
    final res = kw.isEmpty
        ? const []
        : base.where((e) {
            final w = e['w'];
            return '${w['ti']}'.contains(kw) || '${w['a']}'.contains(kw);
          }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('搜索'), actions: const [HomeAction()]),
      body: Column(children: [
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('全部库'),
                  selected: sel == 'all',
                  onSelected: (_) => _select('all'),
                ),
              ),
              for (final l in libs)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${l['name'] ?? l['id']}'),
                    selected: sel == '${l['id']}',
                    onSelected: (_) => _select('${l['id']}'),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: q,
            autofocus: true,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: '标题或作者'),
            onChanged: (v) => setState(() => kw = v.trim()),
          ),
        ),
        AuthorFilterBar(
          filter: authorFilter.value,
          loading: typesLoading,
          onOpen: _openFilter,
          onClear: authorFilter.clearAll,
          summary: authorFilter.value.isActive
              ? '${authorFilter.value.summary(basicNames: _filterLibNames, bigNames: _filterBigNames, unitNames: _filterUnitNames)} · 命中 ${res.length}/${all.length}'
              : null,
        ),
        if (loading) const LinearProgressIndicator(),
        Expanded(
          child: kw.isEmpty
              ? const Center(
                  child: Text('输入关键词，在所选库内搜索',
                      style: TextStyle(color: Colors.grey)))
              : res.isEmpty
                  ? Center(
                      child: Text(
                          authorFilter.value.isActive
                              ? '没有符合筛选条件的结果'
                              : '没有找到相关作品',
                          style: const TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: res.length,
                      itemBuilder: (_, i) {
                        final e = res[i];
                        final w = e['w'];
                        return ListTile(
                          leading: SizedBox(
                              width: 40,
                              height: 54,
                              child: (w['th'] ?? '').toString().isEmpty
                                  ? Container(color: Colors.black26)
                                  : CachedNetworkImage(
                                      imageUrl: cfg.mediaUrl(w['th'].toString(),
                                          lib: '${e['_lib']}'),
                                      httpHeaders:
                                          cfg.headersFor('${e['_lib']}'),
                                      fit: BoxFit.cover)),
                          title: Text('${w['ti']}',
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Builder(builder: (_) {
                            final lib = '${e['_lib']}';
                            final meta = metas[lib];
                            final av = '${w['av'] ?? ''}';
                            final author = '${w['a'] ?? ''}';
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // T2：词条改为单元库（SECRET / 无归属灰色）
                                  AuthorBadges(
                                    meta: meta,
                                    name: author,
                                    mediaPath: av,
                                    basicId: '${e['_bid'] ?? ''}',
                                    fallbackId: lib,
                                    fallbackName: _libName(lib),
                                    works: authorWorkCount['$lib|$author'] ?? 0,
                                  ),
                                  const SizedBox(height: 2),
                                  Text('@${w['a']}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ]);
                          }),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => PlayerPage(
                                      works: e['works'],
                                      start: e['i'],
                                      lib: '${e['_lib']}'))),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

class AuthorPage extends StatefulWidget {
  final String name;
  // 按库筛选后可能合并多个库；默认当前库
  final List<String>? libs;
  const AuthorPage({super.key, required this.name, this.libs});
  @override
  State<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<AuthorPage> {
  String bio = '';
  String av = '';
  // J12：没有现成头像时，从作品图里自动挑一张兜底（中心裁剪）。
  String fallbackAv = '';
  List works = [];
  // J6：按作品类型筛选（可多选，空集合=全部）
  final Set<String> typeFilter = <String>{};
  List filteredWorks = [];
  Map<String, int> typeCounts = {};
  String primaryLib = '';
  bool loading = true;
  // 该库是否配置了爬虫脚本；没有脚本时禁用联网同步。
  bool _hasCrawler = false;
  bool syncing = false;
  LibMeta? meta;
  Timer? syncTimer;

  List<String> get _libs =>
      (widget.libs == null || widget.libs!.isEmpty) ? [cfg.lib] : widget.libs!;

  String get displayAv => av.isNotEmpty ? av : fallbackAv;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    super.dispose();
  }

  // 只有配置了爬虫脚本的库才允许联网同步。
  bool get _canSync => cfg.base.isNotEmpty && _hasCrawler;

  Future<void> _syncAuthor() async {
    if (syncing || !_canSync) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('同步作者 @${widget.name}'),
        content: const Text(
            '将立即抓取该作者的全部作品（已入库的跳过），并补全头像、简介、封面。\n\n同步在 NAS 后台运行，作品多时耗时较长。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('开始同步')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final j = await startServerSync(
        target: 'author', author: widget.name, lib: primaryLib, full: true);
    if (j == null || j['ok'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('同步启动失败：${j?['error'] ?? '网络错误'}')));
      }
      return;
    }
    setState(() => syncing = true);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已开始同步该作者，完成后自动刷新')));
    }
    syncTimer?.cancel();
    var tries = 0;
    syncTimer = Timer.periodic(const Duration(seconds: 4), (t) async {
      tries++;
      final s = await serverSyncStatus();
      if (!mounted) {
        t.cancel();
        return;
      }
      if (s == null) {
        if (tries > 5) {
          t.cancel();
          setState(() => syncing = false);
        }
        return;
      }
      if (s['running'] == true) return;
      t.cancel();
      setState(() => syncing = false);
      final code = s['exit'];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(code == 0 ? '作者同步完成' : '作者同步结束（退出码 $code）')));
      }
      await load();
    });
  }

  Future<void> load() async {
    final seen = <String>{};
    works = [];
    bio = '';
    av = '';
    fallbackAv = '';
    primaryLib = '';
    for (final lib in _libs) {
      try {
        final r = await http.get(cfg.u('/api/authors.json', lib: lib),
            headers: cfg.headers);
        if (r.statusCode != 200) continue;
        final idx = jsonDecode(r.body) as Map;
        final info = idx[widget.name];
        if (info == null) continue;
        final d = await http.get(cfg.u('/api/a/${info['i']}.json', lib: lib),
            headers: cfg.headers);
        if (d.statusCode != 200) continue;
        final m = jsonDecode(d.body);
        if (bio.isEmpty) bio = (m['bio'] ?? '').toString();
        if (av.isEmpty) av = (m['av'] ?? '').toString();
        if (primaryLib.isEmpty) primaryLib = lib;
        for (final w in ((m['works'] as List?) ?? const [])) {
          final id = '${(w as Map)['id'] ?? ''}';
          if (id.isNotEmpty && !seen.add(id)) continue;
          works.add({...Map<String, dynamic>.from(w), '_lib': lib});
        }
        postStat('visit', widget.name, lib: lib);
      } catch (_) {}
    }
    if (primaryLib.isNotEmpty) {
      try {
        meta = await LibMeta.load(primaryLib);
      } catch (_) {}
      // 没有配置爬虫脚本的库：禁用联网同步按钮。
      try {
        final cr = await http.get(
            Uri.parse('${cfg.baseFor(primaryLib)}/api/crawler'
                '?lib=${Uri.encodeQueryComponent(primaryLib)}'),
            headers: cfg.headersFor(primaryLib)).timeout(const Duration(seconds: 8));
        if (cr.statusCode == 200) {
          final cj = jsonDecode(cr.body);
          final scripts = (cj is Map ? cj['scripts'] : null);
          _hasCrawler = scripts is List && scripts.isNotEmpty;
        }
      } catch (_) {}
    }
    fallbackAv =
        pickFallbackAvatar(avatarCandidatesFromWorks(works.whereType<Map>())) ??
            '';
    if (mounted) {
      setState(() {
        loading = false;
        _refreshFilter();
      });
    }
  }

  // 仅在数据加载/筛选变化时重算，避免观看进度刷新时反复重建列表
  void _refreshFilter() {
    filteredWorks = filterWorksByType(works, typeFilter);
    typeCounts = workTypeCounts(works);
  }

  void _toggleType(String type) {
    setState(() {
      if (!typeFilter.add(type)) typeFilter.remove(type);
      _refreshFilter();
    });
  }

  void _clearTypeFilter() {
    if (typeFilter.isEmpty) return;
    setState(() {
      typeFilter.clear();
      _refreshFilter();
    });
  }

  // 点击头像放大查看（可双指缩放，点任意处关闭）
  void _showAvatar(BuildContext context) {
    final src = displayAv;
    if (src.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: CachedNetworkImage(
              imageUrl: cfg.mediaUrl(src,
                  lib: primaryLib.isEmpty ? null : primaryLib),
              httpHeaders:
                  cfg.headersFor(primaryLib.isEmpty ? null : primaryLib),
              fit: BoxFit.contain,
              placeholder: (_, __) =>
                  const CircularProgressIndicator(color: Colors.white38),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.name}'), actions: [
        const HomeAction(),
        if (_canSync)
          IconButton(
              tooltip: syncing ? '同步中…' : '同步该作者',
              onPressed: syncing ? null : _syncAuthor,
              icon: syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync)),
      ]),
      body: loading
          ? const _AuthorPageSkeleton()
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _showAvatar(context),
                        child: AuthorAvatar(
                          name: widget.name,
                          mediaPath: displayAv,
                          lib: primaryLib.isEmpty ? null : primaryLib,
                          size: AuthorAvatar.headerSize,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            // T2：作者主页词条改为单元库（SECRET / 无归属灰色）
                            AuthorBadges(
                              meta: meta,
                              name: widget.name,
                              mediaPath: displayAv,
                              fallbackId:
                                  primaryLib.isEmpty ? cfg.lib : primaryLib,
                              // 0.9.6：不再回退库名文案，无归属显示 SECRET
                              fallbackName: '',
                              works: works.length,
                            ),
                            const SizedBox(height: 6),
                            const Text('作者简介',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 6),
                            Text(bio.isEmpty ? '（暂无简介）' : bio,
                                maxLines: 6,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)),
                          ])),
                    ]),
              ),
              if (_canSync)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
                  child: Row(children: [
                    const Icon(Icons.cloud_sync_outlined,
                        size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    const Expanded(
                        child: Text('同步会立即爬取该作者的全部作品',
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey))),
                  ]),
                ),
              const Divider(height: 1),
              if (works.isNotEmpty)
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Center(
                        child: FilterChip(
                            label: Text('全部 ${works.length}',
                                style: const TextStyle(fontSize: 12)),
                            selected: typeFilter.isEmpty,
                            showCheckmark: false,
                            onSelected: (_) => _clearTypeFilter()),
                      ),
                      for (final type in workFilterOrder)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Center(
                            child: FilterChip(
                                label: Text(
                                    '${workFilterLabel(type)} ${typeCounts[type] ?? 0}',
                                    style: const TextStyle(fontSize: 12)),
                                selected: typeFilter.contains(type),
                                showCheckmark: false,
                                onSelected: (typeCounts[type] ?? 0) == 0
                                    ? null
                                    : (_) => _toggleType(type)),
                          ),
                        ),
                      if (typeFilter.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Center(
                            child: TextButton(
                                onPressed: _clearTypeFilter,
                                child: const Text('清除',
                                    style: TextStyle(fontSize: 12))),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                  child: WorkGrid(
                      works: filteredWorks,
                      lib: primaryLib.isEmpty ? null : primaryLib)),
            ]),
    );
  }
}

// G19：骨架屏占位（首屏/图片加载时避免白屏）
class _SkeletonPulse extends StatefulWidget {
  final Widget child;
  const _SkeletonPulse({required this.child});
  @override
  State<_SkeletonPulse> createState() => _SkeletonPulseState();
}

class _SkeletonPulseState extends State<_SkeletonPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  late final Animation<double> _a = Tween<double>(begin: 0.35, end: 0.8)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _a, child: widget.child);
}

class SkeletonBlock extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? radius;
  const SkeletonBlock({super.key, this.width, this.height, this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
        borderRadius: radius ?? BorderRadius.circular(8),
      ),
    );
  }
}

// 网格骨架：与 WorkGrid 相同的网格密度，用于收藏夹/作者页首屏
class WorkGridSkeleton extends StatelessWidget {
  final int count;
  const WorkGridSkeleton({super.key, this.count = 18});

  @override
  Widget build(BuildContext context) {
    return _SkeletonPulse(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: 3 / 4,
            mainAxisSpacing: 2,
            crossAxisSpacing: 2),
        itemCount: count,
        itemBuilder: (_, __) => const SkeletonBlock(radius: BorderRadius.zero),
      ),
    );
  }
}

// 作者主页骨架：头像/简介占位 + 作品网格
class _AuthorPageSkeleton extends StatelessWidget {
  const _AuthorPageSkeleton();

  @override
  Widget build(BuildContext context) {
    return _SkeletonPulse(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SkeletonBlock(
                width: 64,
                height: 64,
                radius: BorderRadius.all(Radius.circular(32))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBlock(width: 64, height: 10),
                    SizedBox(height: 10),
                    SkeletonBlock(width: 220, height: 12),
                    SizedBox(height: 8),
                    SkeletonBlock(width: 160, height: 12),
                  ]),
            ),
          ]),
        ),
        const Divider(height: 1),
        const Expanded(child: WorkGridSkeleton(count: 12)),
      ]),
    );
  }
}

class WorkGrid extends StatefulWidget {
  final List works;
  final String? lib;
  // T3：已移除旧「收藏夹」idx/名称传参链
  const WorkGrid({super.key, required this.works, this.lib});

  @override
  State<WorkGrid> createState() => _WorkGridState();
}

class _WorkGridState extends State<WorkGrid> {
  final ScrollController _scroll = ScrollController();
  int _shown = 0;
  @override
  void initState() {
    super.initState();
    _shown = initialGridCount(widget.works.length);
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void didUpdateWidget(covariant WorkGrid old) {
    super.didUpdateWidget(old);
    if (!identical(old.works, widget.works) ||
        old.works.length != widget.works.length) {
      // 重新加载/筛选后回到首屏分页，避免沿用上一个列表的滚动位置
      _shown = initialGridCount(widget.works.length);
    }
    if (_shown > widget.works.length) _shown = widget.works.length;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_shown >= widget.works.length) return;
    final p = _scroll.position;
    if (shouldLoadNextPage(
        pixels: p.pixels,
        maxScrollExtent: p.maxScrollExtent,
        viewportDimension: p.viewportDimension)) {
      setState(() => _shown = nextGridCount(_shown, widget.works.length));
    }
  }

  String _libFor(dynamic w) =>
      '${(w is Map ? w['_lib'] : null) ?? widget.lib ?? cfg.lib}';

  @override
  Widget build(BuildContext context) {
    // G10：监听本地观看记录，完成后角标与进度条自动刷新
    return ValueListenableBuilder<int>(
        valueListenable: WatchProgressStore.revision,
        builder: (context, _, __) => _buildGrid(context));
  }

  Widget _buildGrid(BuildContext context) {
    final works = widget.works;
    if (works.isEmpty) {
      return const Center(
          child: Text('暂无作品', style: TextStyle(color: Colors.grey)));
    }
    final total = works.length;
    final shown = _shown > total ? total : _shown;
    return GridView.builder(
      controller: _scroll,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 3 / 4,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2),
      itemCount: shown,
      itemBuilder: (_, i) {
        final w = works[i];
        final wp = WatchProgressStore.of(
            _libFor(w), '${(w is Map ? w['id'] : null) ?? ''}');
        // G13：视频右下角显示时长，图文显示图片张数
        return WorkCard(
          title: '${w['ti'] ?? ''}',
          typeLabel: workTypeLabel(w),
          coverUrl: (w['th'] ?? '').toString().isEmpty
              ? ''
              : cfg.mediaUrl(w['th'].toString(), lib: _libFor(w)),
          headers: cfg.headersFor(_libFor(w)),
          badge: workCoverBadge(w),
          done: wp != null && wp.done,
          progress: (wp != null && !wp.done) ? wp.fraction : 0,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  PlayerPage(works: works, start: i, lib: _libFor(w)))),
        );
      },
    );
  }
}
