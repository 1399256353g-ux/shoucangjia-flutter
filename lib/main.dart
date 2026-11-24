import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, Platform;
import 'dart:math' show Random, max, min;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import 'api_url.dart';
import 'basic_auth.dart';
import 'rank_medal.dart';
import 'time_labels.dart';
import 'cover_admin.dart';
import 'haptics.dart';
import 'cover_cache.dart';
import 'cover_crop_page.dart';
import 'cover_history.dart';
import 'cover_menu.dart';
import 'cover_upload.dart';
import 'deleted_monitor.dart';
import 'deleted_cover.dart';
import 'sync_ledger.dart';
import 'concurrency.dart';
import 'breadcrumb.dart';
import 'crash_guard.dart';
import 'crash_reports_page.dart';
import 'decode_plan.dart';
import 'work_cover.dart';
import 'media_resize.dart';
import 'recommend_grid.dart';
import 'horizontal_chip_bar.dart';
import 'cache_settings.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'author_filter.dart';
import 'author_drag.dart';
import 'author_merge.dart';
import 'author_avatar.dart';
import 'author_avatar_store.dart';
import 'author_filter_bar.dart';
import 'author_filter_ui.dart';
import 'author_grid.dart';
import 'author_grade.dart';
import 'basic_lib_page.dart';
import 'folder_structure_page.dart';
import 'background_pause.dart';
import 'collection_sync.dart';
import 'connection_status.dart';
import 'continue_watching.dart';
import 'cover_badges.dart';
import 'decode_fallback.dart';
import 'home_action.dart';
import 'lib_names.dart';
import 'infinite.dart';
import 'library_badge.dart';
import 'lib_id.dart';
export 'library_badge.dart' show LibBadgeChip, LibEntryKind;
import 'library_corner_badge.dart';
import 'home_top_bar.dart';
import 'taskbar_layout.dart';
import 'library_refresh.dart';
import 'library_revision.dart';
import 'refresh_all.dart';
import 'library_rank.dart';
import 'lib_cover.dart';
import 'loop_link.dart';
import 'playback_prefs.dart';
import 'json_isolate.dart';
import 'library_tree.dart';
import 'unit_crawler.dart';
import 'unit_crawler_page.dart';
import 'unit_author_mount_page.dart';
import 'unit_library.dart';
import 'unit_library_view.dart';
import 'header_collapse.dart';
import 'work_card.dart';
import 'work_key.dart';
import 'multi_server.dart';
import 'playback_flow.dart';
import 'playback_state.dart';
import 'pic_zoom.dart';
import 'playback_error.dart';
import 'mpv_log_digest.dart';
import 'perf_diagnostics.dart';
import 'text_fit.dart';
import 'esc_back.dart';
import 'top_node.dart';
import 'thumb_image.dart';
import 'thumb_prefetch.dart';
import 'ui_auto_hide.dart';
import 'ui_fade.dart';
import 'immersive.dart';
import 'interval_label.dart';
import 'instant_route.dart';
import 'gesture_verdict.dart';
import 'volume_control.dart';
import 'playback_menu.dart';
import 'player_controls.dart';
import 'player_layers.dart';
import 'pause_trace.dart';
import 'prefs_json.dart';
import 'preload_policy.dart';
import 'preload_plan.dart';
import 'preload_pool.dart';
import 'video_prefetch.dart';
import 'video_layout.dart';
import 'swipe_physics.dart';
import 'stage_tap.dart';
import 'star_store.dart';
import 'start_fade.dart';
import 'source_lib.dart';
import 'watch_progress.dart';
import 'work_author.dart';
import 'work_forms.dart';
import 'work_plays.dart';
import 'work_safety.dart';
import 'http_json.dart';
import 'http_error_text.dart';
import 'error_text.dart';
import 'load_error_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final perf = PerfDiagnostics.instance..markAppStart();
  // 0.9.23：先装崩溃兜底，后面任何初始化出错都能记下来而不是整屏灰掉
  installCrashGuard();
  // 诊断日志目录：Android 的 systemTemp 不可写，crash.log / pause.log 会
  // 静默丢失。启动时一次性把 CrashLog/PauseTrace 落到应用支持目录。
  if (!Platform.isWindows) {
    try {
      final logDir = await getApplicationSupportDirectory();
      CrashLog.logDirOverride = logDir.path;
    } catch (_) {}
  }
  // 崩溃前现场：原生崩溃不会进 FlutterError，这里把关键动作落盘。
  await Breadcrumb.init();
  if (Breadcrumb.lastSessionCrashed && Breadcrumb.lastSessionTail.isNotEmpty) {
    CrashLog.instance.record(
      '疑似原生崩溃，最后动作：${Breadcrumb.lastSessionTail.last}',
      kind: 'native',
    );
  }
  // owner 2026-11-18：非全屏也要铺到屏幕最顶端，与灵动岛融为一体。
  // 透明状态栏 + edge-to-edge，播放页舞台本身不加顶部内边距。
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ));
    } catch (_) {}
  }
  // 作者头像索引：卡片、作者主页、播放页共用同一份兜底数据。
  ensureAuthorAvatarsLoaded();
  perf.step('crash_guard');
  MediaKit.ensureInitialized();
  perf.step('media_kit');
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  // G10：先载入观看记录，列表首帧就能显示「已看完」角标
  await WatchProgressStore.ensureLoaded();
  perf.step('watch_progress');
  // G17：载入「继续观看」，主页首帧直接显示
  await ContinueWatchingStore.ensureLoaded();
  perf.step('continue_watching');
  // L5-C：载入本机播放量，基础库自动封面首帧即可用
  await WorkPlaysStore.ensureLoaded();
  perf.step('work_plays');
  // T4：封面缓存落 E 盘（Windows），启动时清理过期/超限条目
  // iOS 卡死定位：清理要遍历整个缓存目录（每文件一次 stat），
  // 原先挡住首帧；现在只做必要初始化，清理改到首帧之后异步跑。
  await DiziCache.init(sweepOnStart: false);
  perf.step('cache');
  // 0.9.41：本机「手动作者头像」覆盖，首帧头像就按覆盖显示
  await AuthorAvatarStore.instance.load();
  perf.step('author_avatar');
  // 退到后台/退出前再轻量清理一次（不阻塞退出）
  AppLifecycleListener(
    onPause: DiziCache.sweepOnExit,
    onDetach: DiziCache.sweepOnExit,
  );
  // 关于页显示的版本号来自构建信息，不再硬编码
  await loadAppVersion();
  perf.step('app_version');
  runApp(const App());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    perf.markFirstFrame();
    // 首帧后再清理缓存，避免冷启动卡在目录扫描上。
    unawaited(DiziCache.sweep());
  });
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
      {String? user, String? pass, String? server, String? label}) {
    final b = normalizeBase(base);
    if (libId.isEmpty || b.isEmpty) return;
    _bindings[libId] = {
      'base': b,
      'user': user ?? this.user,
      'pass': pass ?? this.pass,
      'server': server ?? '',
      'label': label ?? '',
    };
  }

  /// 绑定表取字段的唯一入口：`libId` 省略时用当前库，未绑定时用 [fallback]。
  ///
  /// 第十一批之前 `baseFor` / `serverIdFor` / `serverLabelFor` / `headersFor`
  /// 各自抄了一遍「先算实际库 id、再查 `_bindings`」的两行同体代码——
  /// 其中一段写错就会变成「某个库的地基来自另一个库」这种极难定位的串库现象。
  String _bindingOf(String? libId, String key, {String fallback = ''}) {
    final l = libId ?? lib;
    return _bindings[l]?[key] ?? fallback;
  }

  String baseFor([String? libId]) =>
      _bindingOf(libId, 'base', fallback: base);

  /// 该库所属连接的 id；未绑定时回落到当前连接。
  ///
  /// owner 2026-11-24：首页卡片必须按「连接」归组，否则层级会错位——
  /// 节点没有连接标识时，`buildUnitTree` 会把第一层目录当媒体库卡片。
  String serverIdFor([String? libId]) => _bindingOf(libId, 'server');

  /// 该库所属连接的显示名；未绑定时返回空串（由调用方决定兜底文案）。
  String serverLabelFor([String? libId]) => _bindingOf(libId, 'label');

  /// P5：断开某条连接后，清掉它名下的库路由与凭据，
  /// 否则已缓存的 `baseFor/headersFor` 仍会带着旧密码继续请求该服务端。
  void dropServerBindings(String serverId) {
    if (serverId.isEmpty) return;
    _bindings.removeWhere((_, v) => '${v['server'] ?? ''}' == serverId);
  }

  Map<String, String> headersFor([String? libId]) {
    final u = _bindingOf(libId, 'user', fallback: user);
    final p = _bindingOf(libId, 'pass', fallback: pass);
    return {'Authorization': basicAuthHeader(u, p)};
  }

  /// 当前库所在连接的认证；没有绑定则回落到当前连接。
  Map<String, String> get headers => headersFor(lib);
  // lib 省略时用当前库；显式传入可查询其他库
  Uri u(String path, {String? lib}) =>
      Uri.parse(libApiUrl(baseFor(lib ?? this.lib), path, lib ?? this.lib));

  // 媒体路径统一带库前缀：/media/<lib>/<相对路径>
  String media(String p, {String? lib}) {
    final l = lib ?? this.lib;
    final path = p.trim();
    if (path.isEmpty) return path;
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    // 服务端接口地址（`/api/thumb/<lib>/<id>` 等）不是媒体文件：
    // 扫描器会把这类地址直接写进作品的 `th`，若再套 `/media/<lib>/` 就变成
    // `/media/<lib>/api/thumb/...` —— 服务端把 `api` 当库内子目录 → 必然 404。
    // 实测 2026-11-23：2288 条图文作品是这种 `th`，对应「comics / AI 单图无封面」。
    if (path.startsWith('/api/')) return path;
    if (l.isEmpty) return path;
    // 相对路径（如手动封面 `_cover/v1.jpg`）必须补成 /media/<lib>/...，
    // 否则会被直接拼到域名后面变成 `http://ip:8090_cover/...`，永远加载不出来。
    if (!path.startsWith('/media/')) {
      final rel = path.replaceFirst(RegExp(r'^/+'), '');
      return '/media/${Uri.encodeComponent(l)}/$rel';
    }
    final rest = path.substring(7);
    // 已带库段的媒体路径是自描述的：`/media/lib-012/...` 的库段就是
    // 服务端路由依据（gallery_server 先看第一段是不是库 id）。
    // 若再套当前库会得到 `/media/<当前库>/lib-012/...`，服务端把
    // `lib-012` 当普通子目录拼进当前库根 → 404。主页单元库封面走的正是
    // `cv` 下发的 `/media/lib-0xx/...`，默认库是 `douyin`，因此长期 404、
    // 卡片只显示默认图标。已知库段一律原样保留。
    final slash = rest.indexOf('/');
    final head = slash >= 0 ? rest.substring(0, slash) : rest;
    if (head.isNotEmpty && (_bindings.containsKey(head) || head == l)) {
      return path;
    }
    return '/media/${Uri.encodeComponent(l)}/$rest';
  }

  /// 媒体绝对地址：按作品所属库路由到对应 IP。
  String mediaUrl(String p, {String? lib}) =>
      '${baseFor(lib)}${encodeMediaPath(media(p, lib: lib))}';
}

final cfg = Cfg();

/// 应用版本（运行时读取，避免像以前那样硬编码成 0.9.0）。
String appVersion = '';

Future<void> loadAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    if (info.version.isNotEmpty) appVersion = info.version;
  } catch (_) {
    // 测试环境或平台通道不可用时保持为空，界面退化为不显示版本号
  }
}

/// 媒体路径转义：只处理会让 `Uri.parse` 把一个文件名断成片段/查询的字符。
///
/// NAS 上的文件名可能带 `#`、`?` 或空格（如 `1#花絮.mp4`），直接拼进 URL 后
/// `Uri.parse` 会把 `#` 之后当 fragment、`?` 之后当 query，请求到的就是另一个路径，
/// 表现为封面 404 / 播放失败。这里按字符做最小转义：
/// - 已有合法 `%XX` 原样保留，避免二次编码（`%25`）；
/// - 孤立 `%`（后面不是两位十六进制）转成 `%25`；
/// - `#`、`?`、空格、控制字符转义成 `%XX`；
/// - 其余字符（含中文、`/` 分段符）不动，交给 Uri 自己编码。
String encodeMediaPath(String path) {
  if (path.isEmpty) return path;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final hex2 = RegExp(r'^[0-9A-Fa-f]{2}$');
  final out = StringBuffer();
  for (var i = 0; i < path.length; i++) {
    final ch = path[i];
    if (ch == '%') {
      final hex = i + 2 < path.length ? path.substring(i + 1, i + 3) : '';
      if (hex2.hasMatch(hex)) {
        out.write(path.substring(i, i + 3));
        i += 2;
      } else {
        out.write('%25');
      }
      continue;
    }
    final code = ch.codeUnitAt(0);
    if (ch == '#' || ch == '?' || ch == ' ' || ch == '\u007f' || code < 0x20) {
      out.write(Uri.encodeComponent(ch));
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}

/// 全局作者头像索引：作者名 → `av` 路径（来自 `/api/authors.json`）。
///
/// 作品的 `av` 只有部分条目带；没有时 `avatarFor` 之前会直接落到默认头像。
/// 作者级头像在 authors.json 里是全的，这里补一层兜底。
final Map<String, String> authorAvatarIndex = <String, String>{};
bool _authorAvatarLoading = false;
bool _authorAvatarLoaded = false;

/// B2：作者头像索引是异步补进来的，索引到位后通知已渲染的头像/播放页重建。
///
/// 之前的实现只在启动时 fire-and-forget 拉一次，网络慢于首帧时，
/// 卡片和播放页会一直停在默认人形占位，直到别的状态变化才刷新。
final ValueNotifier<int> authorAvatarRevision = ValueNotifier<int>(0);

Future<void> ensureAuthorAvatarsLoaded() async {
  if (_authorAvatarLoaded || _authorAvatarLoading) return;
  _authorAvatarLoading = true;
  try {
    final r = await http
        .get(cfg.u('/api/authors.json', lib: 'all'), headers: cfg.headers)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode == 200) {
      final m = jsonOf(r);
      if (m is Map) {
        for (final e in m.entries) {
          final v = e.value;
          if (v is! Map) continue;
          final av = '${v['av'] ?? ''}'.trim();
          if (av.isNotEmpty) authorAvatarIndex['${e.key}'] = av;
        }
        _authorAvatarLoaded = true;
      }
    }
  } catch (_) {
    // 失败保持未加载，下次进播放页再试。
  } finally {
    _authorAvatarLoading = false;
    // 索引有变化才通知，避免无谓重建。
    if (_authorAvatarLoaded) authorAvatarRevision.value++;
  }
}

final navKey = GlobalKey<NavigatorState>();

/// 封面设置成功后的刷新信号：主页库卡片据此重新拉取封面索引。
final ValueNotifier<int> coverRevision = ValueNotifier<int>(0);

/// C2：卡片上的「本地选图作封面」。拼当前库连接与鉴权，成功后通知刷新。
Future<CoverUploadResult> uploadCoverFromPicker({
  required String libId,
  String unitRel = '',
}) async {
  // owner 2026-11-18：Windows 在全屏/无边框窗口下调用系统文件对话框会直接
  // 崩溃（对话框还没弹出就没了）。先退全屏、等窗口稳定，再开对话框。
  if (Platform.isWindows) {
    try {
      Breadcrumb.mark('cover:pre_pick');
      if (await windowManager.isFullScreen()) {
        await windowManager.setFullScreen(false);
        await Future<void>.delayed(const Duration(milliseconds: 280));
      }
    } catch (_) {}
  }
  Breadcrumb.mark('cover:open_dialog', unitRel.isEmpty ? 'lib' : 'unit');
  final r = await pickAndUploadCover(
    url: cfg.u('/api/cover/upload', lib: libId).toString(),
    headers: cfg.headersFor(libId),
    libId: libId,
    unitRel: unitRel,
  );
  if (r.ok) coverRevision.value++;
  return r;
}

/// J9：作者来源词条所需的基础库映射与统计。
/// 一次加载后按库缓存，词条显示「基础库」名称（如「🦶」），不是大库名。
class LibMeta {
  final List<BasicLibRef> basics;

  /// 0.9.9：库根坐标系下的**全部**基础库（含其它单元库下的）。
  /// `basics` 只覆盖当前注册库目录，作者总览/排行榜/推荐/搜索的筛选与词条
  /// 需要跨全部基础库，否则非当前库的作者会落到 SECRET 或无法被筛到。
  final List<BasicLibRef> allBasics;
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
    this.allBasics = const [],
    this.bigNames = const {},
    this.unitTree,
    this.units = const [],
    this.basicToUnit = const {},
  });

  /// 跨库口径的基础库列表（全量优先，缺失时回落到当前库）。
  List<BasicLibRef> get filterBasics =>
      allBasics.isNotEmpty ? allBasics : basics;

  /// P3：顶级节点列表（＝每个连接的媒体库根，即单元库树的直接子节点）。
  ///
  /// 只由结构算出（根的直接子节点），不看任何目录名文本。
  List<UnitLibrary> get tops => [
        for (final c in (unitTree?.children ?? const <UnitLibrary>[]))
          if (!c.isEmpty) c,
      ];

  /// P3：单元库 → 所属顶级节点 id。顶级节点自身返回自己。
  String topIdFor(String unitId) {
    if (unitId.isEmpty) return '';
    final rel = relOf(unitId);
    final pre = 'node:$rel';
    final t = lookupByLibId(LibraryBadge.topOfUnit, unitId);
    if (t != null) return t;
    // 注册表未加载时兑底：只接受「本身就是顶级」的精确命中，不猜。
    for (final top in tops) {
      if (top.id == unitId || top.id == rel || top.id == pre) return top.id;
    }
    return '';
  }

  /// P3：基础库 → 所属顶级节点 id（经基础库→单元库→顶级节点）。
  String topIdForBasic(String basicId) {
    final unit = basicToUnit[basicId] ?? '';
    return topIdFor(unit);
  }

  static final Map<String, LibMeta> cache = <String, LibMeta>{};
  static final Map<String, Future<LibMeta>> _loading =
      <String, Future<LibMeta>>{};
  static final Map<String, DateTime> _cachedAt = <String, DateTime>{};

  /// 缓存有效期：服务端改了单元库名/节点后最多 5 分钟生效，无需重启 App。
  static const Duration cacheTtl = Duration(minutes: 5);

  static Future<LibMeta> load(String lib, {bool force = false}) {
    final hit = cache[lib];
    final at = _cachedAt[lib];
    if (!force &&
        hit != null &&
        at != null &&
        DateTime.now().difference(at) < cacheTtl) {
      return Future.value(hit);
    }
    return _loading.putIfAbsent(lib, () async {
      var basics = const <BasicLibRef>[];
      var allBasics = const <BasicLibRef>[];
      var stats = <String, dynamic>{};
      var bigNames = <String, String>{};
      UnitLibrary? unitTree;
      var units = const <UnitLibrary>[];
      var basicToUnit = const <String, String>{};
      try {
        final rs = await Future.wait([
          http.get(
              cfg.u(
                  '/api/libraries.json?t=${DateTime.now().millisecondsSinceEpoch}',
                  lib: lib),
              headers: cfg.headers),
          http.get(cfg.u('/api/libraries', lib: lib), headers: cfg.headers),
          http.get(cfg.u('/api/author_stats.json', lib: lib),
              headers: cfg.headers),
          http.get(cfg.u('/api/nodes', lib: lib), headers: cfg.headers),
        ]).timeout(const Duration(seconds: 10));
        if (rs[0].statusCode == 200 && rs[1].statusCode == 200) {
          final lj = jsonOf(rs[0]);
          final reg = jsonOf(rs[1]);
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
              // owner 2026-11-22：顶级节点名＝媒体库根目录名（不是内置常量）。
              TopNodeName.setFromRoot(root);
              final basicList = <BasicLib>[
                for (final b in basics) basicLibFromRef(b),
              ];
              var unitBasics = basicList;
              var rootBasics = const <BasicLibRef>[];
              if (root.isNotEmpty) {
                // 以库根为坐标系取**全部**基础库（39 个），既给单元库归属，
                // 也给作者筛选/词条用。
                rootBasics = basicsUnderBase(ljm, root);
                if (rootBasics.isNotEmpty) {
                  unitBasics = <BasicLib>[
                    for (final b in rootBasics) basicLibFromRef(b),
                  ];
                }
              }
              allBasics = rootBasics.isNotEmpty ? rootBasics : basics;
              // 单元库＝owner 在「文件结构」里勾选的节点文件夹（/api/nodes），
              // 与主页使用同一份来源；只有节点为空时才退回 v2 分组。
              final marks = <String>[];
              final markCovers = <String, String>{};
              if (rs[3].statusCode == 200) {
                try {
                  final nj = jsonOf(rs[3]);
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
                  // 0.9.36：手动节点模式下单元库封面指针也随 /api/nodes 下发
                  // （`covers: {rel: "/media/..."}`），按 rel 收进映射表。
                  final cm = nj is Map ? nj['covers'] : null;
                  if (cm is Map) {
                    for (final e in cm.entries) {
                      final k = '${e.key}'.trim();
                      final v = '${e.value ?? ''}'.trim();
                      if (k.isEmpty || v.isEmpty) continue;
                      markCovers[k] = v;
                    }
                  }
                } catch (_) {}
              }
              final nodes = marks.isEmpty
                  ? nodesFromV2(ljm, root: base)
                  : nodesFromMarks(marks,
                      covers: markCovers,
                      serverBase: cfg.base,
                      serverId: cfg.serverIdFor(cfg.lib),
                      serverLabel: cfg.serverLabelFor(cfg.lib));
              final tree = buildUnitTree(
                  nodes: nodes,
                  basics: unitBasics,
                  topName: TopNodeName.current);
              if (tree != null) {
                unitTree = tree;
                units = flattenUnits(tree);
                basicToUnit = unitOfBasics(tree);
                // T5：任何页面加载 LibMeta 都刷新全局词条注册表，
                // 保证作者主页/播放页与主页/基础库卡取同一份单元库词条。
                // 只接受「有下级单元库」的完整树，避免个别基础库作用域
                // 的退化树（全部落 SECRET）覆盖掉主页的好映射。
                if (tree.children.isNotEmpty ||
                    UnitBadgeRegistry.keys.isEmpty) {
                  UnitBadgeRegistry.setFrom(tree);
                }
              }
            }
          }
        }
        if (rs[2].statusCode == 200) {
          final sj = jsonOf(rs[2]);
          if (sj is Map && sj['authors'] is Map) {
            stats = Map<String, dynamic>.from(sj['authors'] as Map);
          }
        }
      } catch (_) {}
      final meta = LibMeta(
          basics: basics,
          allBasics: allBasics,
          stats: stats,
          bigNames: bigNames,
          unitTree: unitTree,
          units: units,
          basicToUnit: basicToUnit);
      cache[lib] = meta;
      _cachedAt[lib] = DateTime.now();
      _loading.remove(lib);
      return meta;
    });
  }

  /// 基础库词条显示名：路径命中基础库时用其名称，否则回落到传入的库名。
  String labelFor(String mediaPath, String fallback) {
    final b = basicLibForMedia(basics, mediaPath) ??
        basicLibForMedia(allBasics, mediaPath);
    if (b == null) return '';
    return basicLibLabel(b, fallback);
  }

  /// 作者所属基础库 id（用于配色）；未命中返回空。
  String idFor(String mediaPath) =>
      basicLibForMedia(basics, mediaPath)?.id ??
      basicLibForMedia(allBasics, mediaPath)?.id ??
      '';

  /// 作者所属基础库 id：兼容库作用域路径（`/media/lib-015/...`）。
  String basicIdForPath(String mediaPath) {
    final id = basicIdForMedia(basics, mediaPath);
    if (id.isNotEmpty) return id;
    return basicIdForMedia(allBasics, mediaPath);
  }

  /// 按基础库 id 取词条（搜索结果直接带 `_bid`，无需按路径反查）。
  BasicLibRef? basicById(String id) {
    for (final b in [...basics, ...allBasics]) {
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
    if (id == 'secret') return TopNodeName.current;
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

  List<String> get order => filterBasics.map((e) => e.id).toList();

  Map<String, String> get names => {
        for (final b in filterBasics) b.id: basicLibLabel(b, b.name),
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
          .get(
              cfg.u(
                  '/api/libraries.json?t=${DateTime.now().millisecondsSinceEpoch}',
                  lib: lib),
              headers: cfg.headers)
          .timeout(const Duration(seconds: 12));
      if (lj.statusCode != 200) return <String, Set<String>>{};
      final regJson = jsonOf(reg);
      var base = '';
      if (regJson is Map && regJson['libraries'] is List) {
        for (final e in regJson['libraries'] as List) {
          if (e is Map && '${e['id']}' == lib) {
            base = '${e['base'] ?? ''}';
            break;
          }
        }
      }
      final libJson = jsonOf(lj);
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
    return authorTypesFromIndex(jsonOf(r));
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
    final j = jsonOf(r);
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
    final j = jsonOf(r);
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
    final j = jsonOf(r);
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
    final j = jsonOf(r);
    if (j is Map) {
      return {'status': r.statusCode, ...Map<String, dynamic>.from(j)};
    }
  } catch (_) {}
  return null;
}

// ---------------------------------------------------------------------------
// NEXT_BATCH E（K2/K3/K7）：作品管理多选、手动名单、单元库标记剪枝。
// 以下纯函数不碰网络与 UI，便于单测；卡片/页面只调用它们。
// ---------------------------------------------------------------------------

/// K2：切换一个作品的选择状态（幂等、自动去重）。
Set<String> toggleWorkSelection(Set<String> selected, String id) {
  final next = Set<String>.from(selected);
  if (id.isEmpty) return next;
  if (!next.remove(id)) next.add(id);
  return next;
}

/// K2：当前列表是否已全选（空列表不算全选）。
bool allWorksSelected(Set<String> selected, Iterable<String> ids) {
  final list = ids.where((e) => e.isNotEmpty).toSet();
  return list.isNotEmpty && list.every(selected.contains);
}

/// K2：全选 / 取消全选切换；已全选则清空，否则选中全部（去重）。
Set<String> toggleSelectAllWorks(Set<String> selected, Iterable<String> ids) {
  if (allWorksSelected(selected, ids)) return <String>{};
  return ids.where((e) => e.isNotEmpty).toSet();
}

/// K2：批量删除按钮是否可用。
bool canBatchDelete(Set<String> selected) => selected.isNotEmpty;

/// K2：批量移动按钮是否可用（有选中且已选目标文件夹）。
bool canBatchMove(Set<String> selected, String? targetRel) =>
    selected.isNotEmpty && (targetRel ?? '').trim().isNotEmpty;

/// K2：删除确认文案（作品数 + 预检文件数）。
String batchDeleteConfirmText(int works, int files) =>
    '将删除 $works 个作品（$files 个文件）。\n文件会移到库内回收站，并记入手动名单，'
    '可在「内容维护」里撤销。';

/// K2：移动确认文案。
String batchMoveConfirmText(int works, String targetRel) =>
    '将移动 $works 个作品到「$targetRel」。\n只允许同作者、同单元库内移动，'
    '由服务端校验；移动结果会记入手动名单。';

/// K3：来源文案，优先级与 J19 一致（手动 > 爬虫）。
String workSourceLabel({required bool manual}) => manual ? '手动' : '爬虫';

/// K7：剪掉已不存在的单元库标记，保留原顺序并去重。
List<String> pruneUnitMarks(
    Iterable<String> existingIds, Iterable<String> marks) {
  final keep = existingIds.where((e) => e.isNotEmpty).toSet();
  final out = <String>[];
  final seen = <String>{};
  for (final m in marks) {
    if (m.isEmpty || !keep.contains(m) || !seen.add(m)) continue;
    out.add(m);
  }
  return out;
}

/// K7：存在但顺序/数量与剪枝结果不一致时返回 true（用于判断是否要写回）。
bool unitMarksNeedPrune(Iterable<String> existingIds, Iterable<String> marks) {
  final pruned = pruneUnitMarks(existingIds, marks);
  final src = marks.toList();
  if (pruned.length != src.length) return true;
  for (var i = 0; i < pruned.length; i++) {
    if (pruned[i] != src[i]) return true;
  }
  return false;
}

/// K7：收集单元库树里全部节点 id（含根）。
Set<String> unitIdsOf(UnitLibrary? root) {
  final out = <String>{};
  void walk(UnitLibrary u) {
    out.add(u.id);
    for (final c in u.children) {
      walk(c);
    }
  }

  if (root != null) walk(root);
  return out;
}

/// K3：读取某个基础库的手动名单（作品 id 集合）。
/// 失败返回空集合，不阻断页面加载。
Future<Set<String>> fetchManualWorkIds(String lib) async {
  if (cfg.baseFor(lib).isEmpty || lib.isEmpty) return <String>{};
  try {
    final r = await http
        .get(cfg.u('/api/work/manual', lib: lib), headers: cfg.headersFor(lib))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return <String>{};
    final j = jsonOf(r);
    final list = (j is Map ? j['works'] : null);
    if (list is! List) return <String>{};
    return list
        .whereType<Map>()
        .map((e) => '${e['id'] ?? ''}')
        .where((e) => e.isNotEmpty)
        .toSet();
  } catch (_) {
    return <String>{};
  }
}

/// K2/K3：作品删除请求。`dry:true` 只预检，`confirm:true` 才执行；
/// 客户端发起的手动操作固定带 `manual:true` 记入名单。
Future<Map<String, dynamic>?> postWorkDelete(String lib, String id,
    {bool confirm = false}) async {
  if (cfg.baseFor(lib).isEmpty || lib.isEmpty || id.isEmpty) return null;
  try {
    final r = await http
        .post(cfg.u('/api/work/delete', lib: lib),
            headers: {
              ...cfg.headersFor(lib),
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'lib': lib,
              'id': id,
              'dry': !confirm,
              'confirm': confirm,
              'manual': true,
            }))
        .timeout(const Duration(seconds: 20));
    final j = jsonOf(r);
    if (j is Map) {
      return {'status': r.statusCode, ...Map<String, dynamic>.from(j)};
    }
    return {
      'status': r.statusCode,
      'ok': false,
      // 文案单一出口：以前这里手拼 `HTTP ${r.statusCode}`，
      // 同一个 500 在「服务端写入失败」的页面与这里两种说法。
      'error': httpErrorText(r.statusCode)
    };
  } catch (e) {
    return {'ok': false, 'error': errorText(e)};
  }
}

/// K2/K3：作品移动请求（同作者同单元库由服务端校验）。
Future<Map<String, dynamic>?> postWorkMove(String lib, String id, String toRel,
    {bool confirm = false}) async {
  if (cfg.baseFor(lib).isEmpty || lib.isEmpty || id.isEmpty || toRel.isEmpty) {
    return null;
  }
  try {
    final r = await http
        .post(cfg.u('/api/work/move', lib: lib),
            headers: {
              ...cfg.headersFor(lib),
              'Content-Type': 'application/json'
            },
            body: jsonEncode({
              'lib': lib,
              'id': id,
              'to': toRel,
              'dry': !confirm,
              'confirm': confirm,
              'manual': true,
            }))
        .timeout(const Duration(seconds: 20));
    final j = jsonOf(r);
    if (j is Map) {
      return {'status': r.statusCode, ...Map<String, dynamic>.from(j)};
    }
    return {
      'status': r.statusCode,
      'ok': false,
      // 文案单一出口：以前这里手拼 `HTTP ${r.statusCode}`，
      // 同一个 500 在「服务端写入失败」的页面与这里两种说法。
      'error': httpErrorText(r.statusCode)
    };
  } catch (e) {
    return {'ok': false, 'error': errorText(e)};
  }
}

/// K2：从作品媒体路径推断作者目录前缀（VID/PIC 之前的段）。
/// 路径形如 `/media/<lib>/<rel>`，先去掉 `/media/` 与库 id 再取前缀。
String authorPrefixOfMedia(String path) {
  var p = path.trim();
  if (p.startsWith('/media/')) {
    p = p.substring(7);
    final at = p.indexOf('/');
    if (at > 0) p = p.substring(at + 1);
  }
  final segs = p.split('/').where((e) => e.isNotEmpty).toList();
  final i = segs
      .indexWhere((s) => s == 'VID' || s == 'PIC' || s == 'vid' || s == 'pic');
  if (i > 0) return segs.sublist(0, i).join('/');
  return segs.length > 1 ? segs.sublist(0, segs.length - 1).join('/') : '';
}

/// K2：目标文件夹候选列表（`/api/cat/tree` 的 dirs 拍平），
/// 只保留与作者前缀一致的目录，避免把作品移到别的作者下。
List<String> moveTargetCandidates(dynamic catTree, String authorPrefix) {
  final out = <String>[];
  final prefix = authorPrefix.trim();
  void walk(List dirs) {
    for (final d in dirs) {
      if (d is! Map) continue;
      final rel = '${d['rel'] ?? ''}'.trim();
      if (rel.isEmpty) continue;
      if (prefix.isEmpty || rel == prefix || rel.startsWith('$prefix/')) {
        out.add(rel);
      }
      final kids = d['dirs'];
      if (kids is List) walk(kids);
    }
  }

  if (catTree is Map && catTree['dirs'] is List) walk(catTree['dirs'] as List);
  return out;
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  bool ready = false;

  @override
  void initState() {
    super.initState();
    // 崩溃判定的另一端：必须有人在进程销毁前写入 clean_exit，
    // 否则每次冷启动都会把上一轮读成「疑似原生崩溃」。
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 崩溃判定的另一端就在这里。
    //
    // 判定是「最后一行不是 clean_exit ⇒ 疑似原生崩溃」。Android 从最近任务
    // 划掉进程、系统 OOM 回收，都不会给 detached——旧实现只在 detached 写标记，
    // 于是**每一次正常关闭都会被读成崩溃**（这是本轮修的真 bug）。
    // 所以标记必须在「进程还能跑、但已不再掌握前台」的那一刻写下来：
    // 进入 paused 即视为正常退出；之后若在前台原生崩溃，最后一行就不是
    // clean_exit，仍然能报出来。
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      unawaited(Breadcrumb.cleanExit());
      return;
    }
    // 回到前台后必须盖掉那条 clean_exit：否则「切后台 → 回前台 → 原生崩溃」
    // 这一整段会被当成正常退出，崩溃又静默了。写一行普通标记即可。
    if (state == AppLifecycleState.resumed) {
      Breadcrumb.mark('app:resumed');
    }
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
      await savePrefString('servers_v1', encodeServers(servers));
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
    final loaded = decodeBindings(sp.getString('lib_bindings_v1'));
    cfg.setBindings(loaded);
    // P5：断连清密码必须在**重启后**仍然成立。`_disconnect` 只改了内存与
    // 连接表，绑定表（含旧密码）还落在 `lib_bindings_v1` 里；这里按在线
    // 连接修剪一次并回写，不让旧密码借重启复活。用编码后逐字比对，
    // 不只比条数——密码改过、label 变过也要回写。
    final pruned = pruneBindings(loaded, liveServers(servers));
    if (encodeBindings(pruned) != encodeBindings(loaded)) {
      cfg.setBindings(pruned);
      await savePrefString('lib_bindings_v1', encodeBindings(pruned));
    }
    cfg.lib = sp.getString('lib') ?? '';
    await AppSettings.load();
    await LibraryCornerBadge.load();
    // P1：词条配色与四层级外观必须在首帧前就位，否则首屏卡片会先闪默认色。
    await LibraryBadge.load();
    // P6：等级配置以服务端为准；这里先用本机只读缓存，联网后再覆写一次。
    await AuthorGrade.load();
    unawaited(syncAuthorGradeFromServer());
    await RecommendCountSettings.load();
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
        // 输入框有焦点时 TextField 的默认 Esc 映射会拦掉下面的 shortcuts，
        // 这里往下沉一层，保证「部分页面 Esc 返回失效」不再出现。
        builder: (context, child) => EscBackScope(
            navKey: navKey, child: child ?? const SizedBox.shrink()),
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
    await savePrefString('servers_v1', encodeServers(servers));
    await savePrefString('active_server_v1', activeId);
    // 当前连接必须是在线的：断连的那条不能继续带着旧地址/密码当全局默认。
    final live = liveServers(servers);
    ServerConn? active;
    for (final s in live) {
      if (s.id == activeId) active = s;
    }
    active ??= live.isEmpty ? null : live.first;
    if (active != null) {
      cfg.base = active.base;
      cfg.user = active.user;
      cfg.pass = active.pass;
      await savePrefString('base', active.base);
      await savePrefString('user', active.user);
      await savePrefString('pass', active.pass);
    } else {
      cfg.base = '';
      cfg.pass = '';
      await savePrefString('base', '');
      await savePrefString('pass', '');
    }
    connectionRevision.value++;
  }

  Future<void> _test(ServerConn s) async {
    setState(() => testing.add(s.id));
    final sw = Stopwatch()..start();
    try {
      final headers = {
        'Authorization': basicAuthHeader(s.user, s.pass),
      };
      final rs = await Future.wait([
        http
            .get(Uri.parse('${s.base}/api/index.json'), headers: headers)
            .timeout(const Duration(seconds: 8)),
        http
            .get(
                Uri.parse(
                    '${s.base}/api/libraries.json?t=${DateTime.now().millisecondsSinceEpoch}'),
                headers: headers)
            .timeout(const Duration(seconds: 8)),
      ]);
      if (rs[0].statusCode != 200) throw Exception(httpErrorText(rs[0].statusCode));
      final cols =
          (jsonOf(rs[0])['collections'] as List?)?.length ?? 0;
      var basics = 0;
      if (rs[1].statusCode == 200) {
        final j = jsonOf(rs[1]);
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
        TextEditingController(text: old?.base ?? '');
    final user = TextEditingController(text: old?.user ?? '');
    final pass = TextEditingController(text: old?.pass ?? '');
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
                    labelText: '地址', hintText: 'http://<服务器地址>:8090')),
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

  /// P5：关闭连接＝与该服务端断连（清密码、不再请求），右上角变叉号。
  Future<void> _disconnect(ServerConn s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('断开「${s.title}」？'),
        content: const Text('断开后不再向该地址发送任何请求，该连接的库从主页移除；'
            '本机保存的密码会立即清除。重新开启需要重新输入密码。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('断开')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      servers = [
        for (final x in servers) x.id == s.id ? disconnectServer(x) : x,
      ];
      testMsg.remove(s.id);
      testOk.remove(s.id);
    });
    cfg.dropServerBindings(s.id);
    await _persist();
  }

  /// P5：重新连接必须先输入密码，不复用旧凭据。
  Future<void> _reconnect(ServerConn s) async {
    final pass = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('连接「${s.title}」'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.base,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 12),
          TextField(
            controller: pass,
            obscureText: true,
            autofocus: true,
            decoration:
                InputDecoration(labelText: '密码', hintText: '账号 ${s.user}'),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, pass.text),
              child: const Text('连接')),
        ],
      ),
    );
    if (pw == null) return;
    if (pw.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('密码不能为空')));
      }
      return;
    }
    final next = reconnectServer(s, pw);
    setState(() {
      servers = [for (final x in servers) x.id == s.id ? next : x];
      testMsg.remove(s.id);
      testOk.remove(s.id);
    });
    await _persist();
    if (!mounted) return;
    await _test(next);
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
      appBar: AppBar(title: const Text('网络连接'), actions: [
        IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加连接',
            onPressed: () => _edit()),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            '可添加多个 NAS 地址（IP）。主页与媒体库会聚合所有可见连接的库；'
            '同名/同 id 的库只显示一份。关闭一条连接＝与该服务端断连：'
            '不再发请求、密码立即清除，重新开启需重新输入密码。',
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
    final live = s.enabled;
    final msg = testMsg[s.id];
    final ok = testOk[s.id];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // P5：连接状态角标——已连接对钩 / 已断连叉号。
            Icon(
                !live
                    ? Icons.link_off
                    : (isActive ? Icons.check_circle : Icons.dns_outlined),
                size: 20,
                color: !live ? Colors.grey : (isActive ? Colors.green : null)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(s.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
            if (!live)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text('已断连',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              )
            else if (isActive)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Text('当前',
                    style: TextStyle(fontSize: 11, color: Colors.green)),
              ),
            Switch(
                value: live,
                onChanged: (v) =>
                    v ? _reconnect(s) : _disconnect(s),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ]),
          Text(s.base,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(
              '账号：${s.user} · ${live ? '已连接，库参与聚合' : '已断连，密码已清除'}',
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
            if (live) ...[
              TextButton(
                  onPressed: () => _activate(s),
                  child: Text(isActive ? '当前连接' : '设为当前')),
              TextButton(
                  onPressed: testing.contains(s.id) ? null : () => _test(s),
                  child: Text(testing.contains(s.id) ? '测试中…' : '测试')),
            ] else
              TextButton(
                  onPressed: () => _reconnect(s), child: const Text('连接')),
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

/// P1：词条配色页的分组标题。
class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary)),
      );
}

/// A2：非末梢单元库的自定义色不分发给下级时，名字后的可见标记。
///
/// 为什么是组件而不是 subtitle 里再加一句：subtitle 是连续文案，看完即忘；
/// 「已设色但不生效」是让人误判下发规则的唯一原因，必须在名字旁就能看到。
class _NoDistributeMark extends StatelessWidget {
  const _NoDistributeMark();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.error;
    return Tooltip(
      message: '非末梢单元库：该色只作用于本层，不会分发给下级',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: c.withValues(alpha: 0.75)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text('仅本层',
            style: TextStyle(fontSize: 10, height: 1.2, color: c)),
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
  /// 0.9.9：词条配色按**单元库**（作者来源词条）配置，不再按旧注册库。
  List<UnitLibrary> units = const [];

  /// P1：顶级单元库（媒体库根）与末梢基础库各一组，配合向下继承。
  List<UnitLibrary> tops = const [];
  List<BasicLib> basics = const [];

  /// P2：按顶级单元库分组——每个顶级单元库下的单元库与基础库，
  /// 只按树结构归组，不看任何目录名文本。
  final Map<String, List<UnitLibrary>> unitsByTop = <String, List<UnitLibrary>>{};
  final Map<String, List<BasicLib>> basicsByTop = <String, List<BasicLib>>{};
  List<UnitLibrary> otherUnits = const [];
  List<BasicLib> otherBasics = const [];
  LibMeta? meta;
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
      final m = await LibMeta.load(cfg.lib);
      if (!mounted) return;
      final root = m.unitTree;
      setState(() {
        meta = m;
        // 顶级 SECRET 只承载「无归属基础库」兜底，不参与逐库配色。
        units = [
          for (final u in m.units)
            if (u.id != 'secret') u
        ];
        // P1：顶级单元库＝媒体库根＝SECRET 的直接子节点（结构事实，不看名字）。
        tops = [
          for (final u in (root?.children ?? const <UnitLibrary>[]))
            if (!u.isEmpty) u
        ];
        basics = [
          for (final u in m.units)
            if (u.id != 'secret') ...u.basics
        ];
        // P2：按顶级单元库分组（结构归组）。子单元库顺序按树深度优先；
        // 不属于任何顶级单元库的单元库归入「其它」。
        unitsByTop.clear();
        basicsByTop.clear();
        final grouped = <String>{};
        void walk(UnitLibrary u, String topId) {
          final list = unitsByTop.putIfAbsent(topId, () => <UnitLibrary>[]);
          if (u.id != topId && u.basics.isNotEmpty) list.add(u);
          if (u.basics.isNotEmpty) {
            basicsByTop.putIfAbsent(topId, () => <BasicLib>[]).addAll(u.basics);
          }
          grouped.add(u.id);
          for (final c in u.children) {
            walk(c, topId);
          }
        }

        for (final t in tops) {
          walk(t, t.id);
        }
        otherUnits = [
          for (final u in units)
            if (!grouped.contains(u.id)) u
        ];
        otherBasics = [
          for (final u in otherUnits) ...u.basics
        ];
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          err = errorText(e);
          loading = false;
        });
      }
    }
  }

  /// 配色顺序：与卡片同源。此前这里是 `meta.unitOrder`（只含带基础库的
  /// 单元库），而卡片走的是注册表 `flattenUnits` 顺序——同一个单元库两边
  /// 自动色可能不同。统一走 [UnitBadgeRegistry.orderOr]。
  List<String> get _order => UnitBadgeRegistry.orderOr(
      meta?.unitOrder ?? [for (final u in units) u.id]);

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
              ? LoadErrorView(
                  message: '加载失败：$err',
                  onRetry: _loadLibs)
              : ListView(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                    child: Text(
                        '词条按三层组织：顶级单元库（媒体库根）设色后向下继承给其下所有'
                        '单元库/基础库；单元库可各自覆盖；基础库自己的颜色优先级最高。'
                        '分发规则：只有末梢单元库（没有下级单元库）的设色会向下分发，'
                        '非末梢单元库的设色只作用于本层，作品/作者仍取末梢或继承色。'
                        '四种层级形状与尺寸一致，只用边框/底纹区分。',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  const _SectionHeader('词条外观（四层级边框 / 底纹）'),
                  _entryStyleSection(),
                  const SizedBox(height: 8),
                  const _SectionHeader('按媒体库设置词条色'),
                  // P2：按顶级单元库分类——每个媒体库根一节，展开就是它的
                  // 单元库与基础库；不依赖任何名称文本，只按树结构归组。
                  for (final t in tops) _topSection(t),
                  if (tops.isEmpty && units.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('未发现单元库：请先在「文件结构」里勾选节点文件夹。',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ),
                  if (otherUnits.isNotEmpty || otherBasics.isNotEmpty) ...[
                    const _SectionHeader('其它（不属于任何顶级单元库）'),
                    for (final u in otherUnits) _libTile(u),
                    for (final b in otherBasics) _basicTile(b),
                  ],
                  const SizedBox(height: 24),
                ]),
    );
  }

  /// P2：一个顶级单元库的分组——它自己的词条、下级单元库、基础库。
  Widget _entryStyleSection() {
    const labels = <LibEntryKind, String>{
      LibEntryKind.top: '顶级单元库（媒体库根）',
      LibEntryKind.unit: '单元库',
      LibEntryKind.basic: '基础库（末梢）',
      LibEntryKind.other: '其它（作者卡等）',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
              '四种词条的圆角、内边距、字号固定一致，只能调边框粗细、'
              '边框深浅与底纹浓度（颜色仍在下方按库设置）。'
              '调完即时生效，也可单层级恢复默认。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        for (final kind in LibEntryKind.values)
          _entryStyleTile(kind, labels[kind] ?? kind.name),
      ],
    );
  }

  Widget _entryStyleTile(LibEntryKind kind, String label) {
    final st = LibraryBadge.styleFor(kind);
    final custom = LibraryBadge.isStyleCustom(kind);
    return ListTile(
      dense: true,
      title: Row(children: [
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        // 预览用该层级真实外观（底色用中性色，只看边框/底纹）。
        LibBadgeChip(label: label, color: 0xFF8B5CF6, kind: kind),
      ]),
      subtitle: Text(
          '边宽 ${st.borderWidth.toStringAsFixed(1)} · '
          '边框透明度 ${(st.borderAlpha * 100).round()}% · '
          '底纹浓度 ${(st.fillAlpha * 100).round()}%',
          style: const TextStyle(fontSize: 11)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (custom)
          IconButton(
            tooltip: '恢复默认',
            icon: const Icon(Icons.restart_alt, size: 18),
            onPressed: () async {
              await LibraryBadge.resetStyle(kind);
              if (mounted) setState(() {});
            },
          ),
        Text(custom ? '自定义' : '默认',
            style: TextStyle(
                fontSize: 12,
                color: custom ? Colors.lightBlueAccent : Colors.grey)),
      ]),
      onTap: () async {
        final v = await _showEntryStyleDialog(kind, label, st);
        if (v == null) return;
        await LibraryBadge.setStyle(kind, v);
        if (mounted) setState(() {});
      },
    );
  }

  /// 只给三个参数（边宽 / 边框透明 / 底纹）；没有圆角与尺寸入口。
  Future<EntryStyle?> _showEntryStyleDialog(
      LibEntryKind kind, String label, EntryStyle initial) async {
    var w = initial.borderWidth;
    var ba = initial.borderAlpha;
    var fa = initial.fillAlpha;
    return showDialog<EntryStyle>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('$label · 词条外观'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _sliderRow('边框粗细', w, 0, 3, 31, (v) => setDlg(() => w = v),
                '${w.toStringAsFixed(1)}dp'),
            _sliderRow('边框深浅', ba, 0, 1, 20, (v) => setDlg(() => ba = v),
                '${(ba * 100).round()}%'),
            _sliderRow('底纹浓度', fa, 0, 1, 20, (v) => setDlg(() => fa = v),
                '${(fa * 100).round()}%'),
            const SizedBox(height: 8),
            Center(
              child: LibBadgeChip(
                  label: label,
                  color: 0xFF8B5CF6,
                  kind: kind),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.of(ctx)
                    .pop(kDefaultEntryStyle[kind]),
                child: const Text('默认')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(EntryStyle(
                    borderWidth: w, borderAlpha: ba, fillAlpha: fa)),
                child: const Text('确定')),
          ],
        ),
      ),
    );
  }

  Widget _sliderRow(String label, double value, double min, double max,
      int divisions, ValueChanged<double> onChanged, String shown) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
        Text(shown, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
      Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged),
    ]);
  }

  Widget _topSection(UnitLibrary top) {
    final subUnits = unitsByTop[top.id] ?? const <UnitLibrary>[];
    final subBasics = basicsByTop[top.id] ?? const <BasicLib>[];
    final name = top.name.isEmpty ? top.id : top.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader('顶级单元库 · $name'),
        _libTile(top, isTop: true),
        if (subUnits.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text('单元库',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey)),
          ),
        for (final u in subUnits) _libTile(u, indent: true),
        if (subBasics.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Text('基础库（末梢，优先级最高）',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey)),
          ),
        for (final b in subBasics) _basicTile(b, indent: true),
      ],
    );
  }

  Widget _libTile(UnitLibrary u, {bool isTop = false, bool indent = false}) {
    final id = u.id;
    final name = u.name.isEmpty ? id : u.name;
    // D1：自定义色可能以 rel / node:rel 任一形式落盘，统一用归一化查询，
    // 避免状态显示「自定义」但色块仍是自动色。
    final color = isTop
        ? (LibraryBadge.topColorFor(id) ??
            LibraryBadge.colorForUnit(id, order: _order))
        : LibraryBadge.colorForUnit(id, order: _order);
    final emoji = LibraryBadge.emojiFor(id);
    final overridden =
        isTop ? LibraryBadge.topColorFor(id) != null : LibraryBadge.customColorFor(id) != null;
    final inheritedOnly = !isTop && LibraryBadge.customColorFor(id) == null &&
        LibraryBadge.topColorFor(lookupByLibId(LibraryBadge.topOfUnit, id) ?? '') !=
            null;
    // P1：只有末梢单元库能向下分发；非末梢的自定义色只作用于本层。
    // 查表走 lookupByLibId：`node:rel` / `rel` 两种 id 形式都是同一份数据。
    final leaf = lookupByLibId(LibraryBadge.leafUnits, id) ?? true;
    final distributeNote = isTop
        ? '向下继承'
        : (leaf ? '可分发给下级' : '非末梢 · 仅本层');
    return ListTile(
      contentPadding: indent ? const EdgeInsets.fromLTRB(40, 0, 16, 0) : null,
      leading: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
            color: Color(color), borderRadius: BorderRadius.circular(7)),
      ),
      title: Row(children: [
        Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        LibBadgeChip(
            label: name,
            color: color,
            unitId: id,
            kind: isTop ? LibEntryKind.top : LibEntryKind.unit),
        // A2：非末梢单元库设了色也不向下一层分发。此前只有 subtitle 一句话，
        // 用户设完仍以为下级会变——这里在名字后面直接挂一个可见标记，
        // 只在「已自定义且不分发」时出现，不占常态一行。
        if (!isTop && !leaf && overridden)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: _NoDistributeMark(),
          ),
      ]),
      subtitle: Text(
          '${u.basicCount} 个基础库 · $distributeNote · $id'
          '${emoji.isEmpty ? '' : ' · 后缀 $emoji'}',
          style: const TextStyle(fontSize: 11)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (emoji.isNotEmpty)
            Text(emoji, style: const TextStyle(fontSize: 16, height: 1.1)),
          Text(
            overridden ? '自定义' : (inheritedOnly ? '继承顶级' : '自动'),
            style: TextStyle(
                fontSize: 12,
                color: overridden
                    ? Colors.lightBlueAccent
                    : (inheritedOnly ? Colors.amber : Colors.grey)),
          ),
        ],
      ),
      onTap: () async {
        final chosen = await _showBadgeDialog(name, id, color,
            kind: isTop ? LibEntryKind.top : LibEntryKind.unit,
            note: isTop
                ? '该色会向下继承给整个媒体库（单元库/基础库/作者）。'
                : (leaf
                    ? '末梢单元库：该色会分发给它的基础库/作品/作者。'
                    : '非末梢单元库：该色只作用于本层单元库，'
                        '不会分发给下级（下级作品归更深的单元库）。'));
        if (chosen == null) return;
        if (chosen.reset) {
          if (isTop) {
            await LibraryBadge.setTopColor(id, null);
          } else {
            await LibraryBadge.setColor(id, null);
          }
          await LibraryBadge.setEmoji(id, null);
        } else {
          if (isTop) {
            await LibraryBadge.setTopColor(id, chosen.color);
          } else {
            await LibraryBadge.setColor(id, chosen.color);
          }
          await LibraryBadge.setEmoji(id, chosen.emoji);
        }
        if (mounted) setState(() {});
      },
    );
  }

  /// P1：末梢基础库词条——自己设色优先，否则继承单元库/顶级单元库。
  Widget _basicTile(BasicLib b, {bool indent = false}) {
    final unitId = meta?.basicToUnit[b.id] ?? '';
    final color = LibraryBadge.basicColorFor(b.id, unitId, order: _order);
    final own = LibraryBadge.basicCustom[b.id] != null;
    final name = LibraryBadge.stripIndex(b.name);
    return ListTile(
      dense: true,
      contentPadding: indent ? const EdgeInsets.fromLTRB(48, 0, 16, 0) : null,
      leading: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
            color: Color(color), borderRadius: BorderRadius.circular(7)),
      ),
      title: Row(children: [
        Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        LibBadgeChip(
            label: name,
            color: color,
            unitId: unitId,
            kind: LibEntryKind.basic),
      ]),
      subtitle: Text('${b.authors} 作者 · ${b.works} 作品 · ${b.id}',
          style: const TextStyle(fontSize: 11)),
      trailing: Text(own ? '自定义' : '继承',
          style: TextStyle(
              fontSize: 12,
              color: own ? Colors.lightBlueAccent : Colors.grey)),
      onTap: () async {
        final chosen = await _showBadgeDialog(name, b.id, color,
            kind: LibEntryKind.basic, topLevelOnly: true);
        if (chosen == null) return;
        await LibraryBadge.setBasicColor(b.id, chosen.reset ? null : chosen.color);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _hsvSlider({
    required String label,
    required double value,
    required double max,
    required List<Color> colors,
    required ValueChanged<double> onChanged,
  }) {
    return Row(children: [
      SizedBox(
          width: 48,
          child: Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey))),
      Expanded(
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 10,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          ),
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            activeColor: Colors.white24,
            inactiveColor: Colors.white10,
            onChanged: onChanged,
          ),
        ),
      ),
      SizedBox(
        width: 40,
        child: Text(value.toStringAsFixed(max > 1 ? 0 : 2),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ),
    ]);
  }

  /// 词条样式（颜色 + emoji 后缀）编辑；返回 null 表示取消。
  ///
  /// [kind] 只影响预览词条的层级外观；[topLevelOnly] 表示该层级不支持
  /// emoji 后缀（基础库），只调颜色。
  Future<_BadgeDraft?> _showBadgeDialog(
      String name, String id, int autoColor,
      {LibEntryKind kind = LibEntryKind.unit,
      bool topLevelOnly = false,
      String note = ''}) async {
    var current = LibraryBadge.customColorFor(id) ?? autoColor;
    var hsv = HSVColor.fromColor(Color(current));
    var currentEmoji = LibraryBadge.emojiFor(id);
    // D1：点「恢复自动」后必须真的清掉自定义色，而不是把当前自动色存成自定义。
    var reset = false;
    final emojiEdit = TextEditingController(text: currentEmoji);
    return showDialog<_BadgeDraft>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('「$name」词条样式'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                LibBadgeChip(
                    label: name,
                    color: current,
                    unitId: currentEmoji.isEmpty ? '' : id,
                    kind: kind),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(note,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('颜色',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (var i = 0; i < LibraryBadge.palette.length; i++)
                    GestureDetector(
                      onTap: () => setLocal(() {
                        current = LibraryBadge.palette[i];
                        reset = false;
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
                            ? const Icon(Icons.check,
                                size: 18, color: Colors.white)
                            : null,
                      ),
                    ),
                ]),
                const SizedBox(height: 10),
                // 全色盘：色相 / 饱和度 / 明度，任意颜色都能调出来。
                _hsvSlider(
                  label: '色相',
                  value: hsv.hue,
                  max: 360,
                  colors: const [
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                  onChanged: (v) => setLocal(() {
                    hsv = hsv.withHue(v);
                    current = hsv.toColor().toARGB32();
                    reset = false;
                  }),
                ),
                _hsvSlider(
                  label: '饱和度',
                  value: hsv.saturation,
                  max: 1,
                  colors: [
                    HSVColor.fromAHSV(1, hsv.hue, 0, hsv.value).toColor(),
                    HSVColor.fromAHSV(1, hsv.hue, 1, hsv.value).toColor(),
                  ],
                  onChanged: (v) => setLocal(() {
                    hsv = hsv.withSaturation(v);
                    current = hsv.toColor().toARGB32();
                    reset = false;
                  }),
                ),
                _hsvSlider(
                  label: '明度',
                  value: hsv.value,
                  max: 1,
                  colors: [
                    HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 0).toColor(),
                    HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, 1).toColor(),
                  ],
                  onChanged: (v) => setLocal(() {
                    hsv = hsv.withValue(v);
                    current = hsv.toColor().toARGB32();
                    reset = false;
                  }),
                ),
                if (!topLevelOnly) ...[
                const SizedBox(height: 14),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('emoji 后缀（可留空；支持任意标准 emoji，可直接输入）',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: emojiEdit,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: '输入或粘贴任意 emoji',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setLocal(() {
                    currentEmoji = LibraryBadge.sanitizeEmoji(v);
                    reset = false;
                  }),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in LibraryBadge.emojiChoices)
                    GestureDetector(
                      onTap: () => setLocal(() {
                        currentEmoji = currentEmoji == e ? '' : e;
                        emojiEdit.text = currentEmoji;
                        reset = false;
                      }),
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: currentEmoji == e
                                ? Colors.lightBlueAccent
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Text(e, style: const TextStyle(fontSize: 17)),
                      ),
                    ),
                ]),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setLocal(() {
                      current = autoColor;
                      hsv = HSVColor.fromColor(Color(autoColor));
                      currentEmoji = '';
                      emojiEdit.text = '';
                      reset = true;
                    }),
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: Text(topLevelOnly
                        ? '恢复继承/自动'
                        : '恢复自动（颜色 + 后缀）'),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(_BadgeDraft(
                    color: current, emoji: currentEmoji, reset: reset)),
                child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}

/// 词条样式编辑结果；[reset] 为 true 时颜色与 emoji 后缀都恢复自动。
class _BadgeDraft {
  final int color;
  final String emoji;
  final bool reset;
  const _BadgeDraft(
      {required this.color, required this.emoji, this.reset = false});
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
    // 配色顺序：全局单元库顺序优先（与基础库卡同源），没有时才用调用方的。
    final colorOrder = UnitBadgeRegistry.orderOr(order);
    return Wrap(
      spacing: 3,
      runSpacing: 3,
      children: [
        for (var i = 0; i < labels.length; i++)
          LibBadgeChip(
            label: labels[i],
            unitId: i < shown.length ? shown[i] : '',
            kind: i < shown.length
                ? LibraryBadge.entryKindOfUnit(shown[i])
                : LibEntryKind.other,
            color: (labels[i].startsWith('+') ||
                    (i < shown.length && grayIds.contains(shown[i])))
                ? LibraryBadge.gray
                : LibraryBadge.colorForUnit(i < shown.length ? shown[i] : '',
                    order: colorOrder),
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

  /// T5：词条唯一来源。调用方传入与基础库卡片同一份映射
  /// （[unitLabelByBasic] / [unitKeyByBasic]）；为空时用全局
  /// [UnitBadgeRegistry]（主页加载单元库时写入），再退回 [meta]。
  final Map<String, String> unitLabels;
  final Map<String, String> unitKeys;
  const UnitBadges({
    super.key,
    required this.meta,
    required this.mediaPath,
    required this.fallbackId,
    required this.fallbackName,
    this.basicId = '',
    this.grade = '',
    this.unitLabels = const {},
    this.unitKeys = const {},
  });

  /// 基础库 → 所属单元库 id。
  String _unitKeyOf(String basic) {
    if (basic.isEmpty) return '';
    return unitKeys[basic] ??
        UnitBadgeRegistry.keys[basic] ??
        meta?.basicToUnit[basic] ??
        '';
  }

  /// 单元库 id → 名称。
  String _unitNameOf(String basic, String unitId) {
    final direct = unitLabels[basic] ?? UnitBadgeRegistry.labels[basic];
    if (direct != null && direct.isNotEmpty) return direct;
    return meta?.unitNameOf(unitId) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final basic =
        basicId.isNotEmpty ? basicId : (meta?.basicIdForPath(mediaPath) ?? '');
    var unitId = _unitKeyOf(basic);
    // 没有基础库归属时才按节点路径解析（旧数据 / 非基础库媒体）。
    if (unitId.isEmpty && basic.isEmpty && mediaPath.isNotEmpty) {
      unitId = meta?.unitIdFor(mediaPath) ?? '';
    }
    // 不再回退到「库名」词条（抖音收藏已废弃）；没有单元库归属就显示
    // 顶级节点词条（名称来自媒体库根目录）。
    final id = unitId.isEmpty ? 'secret' : unitId;
    final label = unitId.isEmpty || unitId == 'secret'
        ? TopNodeName.current
        : _unitNameOf(basic, unitId);
    final names = <String, String>{...?meta?.unitNames, id: label};
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
    // 0.9.41：手动设置的本机头像优先于爬虫/自动结果（owner 指定优先级）。
    return AnimatedBuilder(
      // B2：作者级头像索引异步到位后也要重建，否则一直停在首字母占位。
      animation: Listenable.merge(
          <Listenable>[AuthorAvatarStore.instance, authorAvatarRevision]),
      builder: (context, _) => _buildWith(context,
          override: AuthorAvatarStore.instance.pathFor(name) ?? ''),
    );
  }

  Widget _buildWith(BuildContext context, {required String override}) {
    // 覆盖图可能来自别的基础库：按路径里的库前缀路由/取鉴权，避免拼错地址。
    final overLib = override.isEmpty ? '' : libOfMediaPath(override);
    // owner 2026-11-18：作者主页/作者总览也要吃「作者级头像」兜底——
    // 卡片上能显示的头像，播放页与主页必须一致，不再只依赖调用方传入。
    final authorAv = override.isEmpty && mediaPath.isEmpty
        ? (authorAvatarIndex[name] ?? '')
        : '';
    final src = override.isNotEmpty
        ? override
        : (mediaPath.isNotEmpty ? mediaPath : authorAv);
    final srcLib =
        override.isNotEmpty ? (overLib.isEmpty ? lib : overLib) : lib;
    // 统一占位：无图/加载中/失败都不空白，用首字母圆形占位（emoji 安全）。
    final placeholder = AvatarLetterPlaceholder(name: name, size: size);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: src.isEmpty
            ? placeholder
            : CachedNetworkImage(
                cacheManager: DiziCache.manager,
                // 头像最大显示 64dp：要 200px 缩图即可（服务端 `w=`）。
                imageUrl: withImageWidth(
                    cfg.mediaUrl(src, lib: srcLib), kAvatarImageWidth),
                httpHeaders: cfg.headersFor(srcLib),
                fit: BoxFit.cover,
                // 按实际显示尺寸 × 像素比解码，避免整张大图进内存
                memCacheWidth: avatarDecodeWidth(
                    displaySize: size,
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context)),
                fadeInDuration: Duration.zero,
                placeholder: (_, __) => placeholder,
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

  /// T5：与基础库卡片同一份「基础库 → 单元库」映射（词条同源）。
  final Map<String, String> unitLabels;
  final Map<String, String> unitKeys;

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
    this.unitLabels = const {},
    this.unitKeys = const {},
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
      unitLabels: unitLabels,
      unitKeys: unitKeys,
    );
  }
}

/// P6：作者等级查看页——**只读**。
///
/// 等级门槛与权重由服务端 `/api/author-grade.json` 保存并下发，
/// App 内不再提供任何修改入口；这里只展示当前生效值并把服务端最新值拉一次。
/// 需要修改请在服务端改（改完所有客户端一致生效）。
class AuthorGradeSettingsPage extends StatefulWidget {
  const AuthorGradeSettingsPage({super.key});
  @override
  State<AuthorGradeSettingsPage> createState() =>
      _AuthorGradeSettingsPageState();
}

class _AuthorGradeSettingsPageState extends State<AuthorGradeSettingsPage> {
  bool _ready = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _note = null);
    // 先用本机只读缓存立即出图，再向服务端确认一次。
    await AuthorGrade.load();
    final ok = await syncAuthorGradeFromServer();
    if (!mounted) return;
    setState(() {
      _ready = true;
      _note = ok ? null : '未能从服务端读取等级配置，显示上次同步值';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作者等级'), actions: [
        IconButton(
            tooltip: '从服务端刷新',
            onPressed: _ready ? _refresh : null,
            icon: const Icon(Icons.refresh)),
      ]),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              const Text('等级词条', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  '作者卡片库词条后显示 D–S 等级。分数 = 播放×权重 + 水滴×权重 + '
                  '作品×权重；达到门槛即升一级。等级配置（含 D–S 配色）由服务端'
                  '统一管理，此处只读，修改后所有客户端同步生效。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              if (_note != null) ...[
                const SizedBox(height: 6),
                Text(_note!,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.orangeAccent)),
              ],
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
              _kv('播放权重', '${AuthorGrade.playWeight}'),
              _kv('水滴权重', '${AuthorGrade.dropWeight}'),
              _kv('作品权重', '${AuthorGrade.workWeight}'),
              const SizedBox(height: 12),
              const Text('等级门槛（分数）',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (var i = 1; i < AuthorGrade.grades.length; i++)
                _kv('${AuthorGrade.grades[i - 1]} → ${AuthorGrade.grades[i]}',
                    '≥${AuthorGrade.thresholds[i - 1]}'),
              const SizedBox(height: 12),
              Text(
                  '示例：播放 100、水滴 5、作品 10 → '
                  '${AuthorGrade.score(plays: 100, drops: 5, works: 10)} 分 → '
                  '${AuthorGrade.gradeFor(plays: 100, drops: 5, works: 10)} 级',
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 20),
              const Text(
                  '服务端文件：<媒体库元数据目录>/author-grade.json\n'
                  '接口：GET / PUT /api/author-grade.json（写入需鉴权）\n'
                  '字段：play/drop/work（权重）· t（4 个门槛）· c（5 个 ARGB 配色）',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(fontSize: 13))),
          Text(v, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ]),
      );
}


/// 删除监测页：展示服务端 `_deleted.log` 的只读记录。
/// 诊断页：显示本次运行的「最后动作」记录，用于定位原生崩溃、
/// 播放异常停止、封面缺失等没有 Dart 堆栈的问题。
/// 诊断（合并页）：把原来的「诊断」（面包屑动作记录）与
/// 「诊断信息」（错误记录 + 缩图缓存）两个入口合成一个。
///
/// 两个 tab 各自保持原有行为与数据源，只是入口不再分裂：
/// -「动作记录」：`Breadcrumb` 落盘的最近动作，用于定位原生崩溃/停播；
/// -「错误记录」：[CrashReportsPage]，内存里的错误 + 缩图缓存清理。
class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({
    super.key,
    this.detail = '',
    this.cacheStatsUri,
    this.cachePruneUri,
    this.cacheHeaders = const {},
  });

  final String detail;
  final Uri? cacheStatsUri;
  final Uri? cachePruneUri;
  final Map<String, String> cacheHeaders;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('诊断'),
          bottom: const TabBar(tabs: [
            Tab(text: '动作记录'),
            Tab(text: '错误记录'),
            Tab(text: '性能计数'),
          ]),
        ),
        body: TabBarView(children: [
          const _BreadcrumbTab(),
          CrashReportsPage(
            detail: detail,
            cacheStatsUri: cacheStatsUri,
            cachePruneUri: cachePruneUri,
            cacheHeaders: cacheHeaders,
            // 合并后不再自带 Scaffold/AppBar（外层已有）。
            embedded: true,
          ),
          const _PerfTab(),
        ]),
      ),
    );
  }
}

/// 性能计数 tab：只显示**数字**（首帧毫秒、槽位峰值、解码并发、页面耗时）。
///
/// 这些计数以前只写进本地 `perf.log`，验收时必须把日志文件拷出来才能看；
/// 而「起播耗时 / 重建次数 / 并发峰值」正是 owner 定的量化判据（不看画面）。
/// 页面直接读 [PerfDiagnostics.instance] 的同一份数据，判据与落盘内容
/// 不会出现两套口径。
///
/// 全部是计数与毫秒数，不含任何媒体路径、文件名或作者名——截图/复制
/// 这段输出不会泄露内容。
class _PerfTab extends StatelessWidget {
  const _PerfTab();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: perfRevision,
      builder: (context, _, __) {
        final p = PerfDiagnostics.instance;
        final snap = p.snapshot();
        final lines = p.timeline.reversed.toList(growable: false);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 14, runSpacing: 6, children: [
                for (final e in snap.entries)
                  Text('${e.key}=${e.value}',
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace')),
              ]),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: lines.isEmpty
                ? const Center(child: Text('暂无性能记录'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: SelectableText(
                        lines[i],
                        style: const TextStyle(
                            fontSize: 11.5, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
          ),
        ]);
      },
    );
  }
}

class _BreadcrumbTab extends StatefulWidget {
  const _BreadcrumbTab();
  @override
  State<_BreadcrumbTab> createState() => _BreadcrumbTabState();
}

class _BreadcrumbTabState extends State<_BreadcrumbTab> {
  List<String> _lines = const <String>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Breadcrumb.readTail(lines: 80);
    if (!mounted) return;
    setState(() {
      _lines = l.reversed.toList(growable: false);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Align(
        alignment: Alignment.centerRight,
        child: IconButton(
            tooltip: '刷新', onPressed: _load, icon: const Icon(Icons.refresh)),
      ),
      Expanded(
        child: _lines.isEmpty
            ? const Center(child: Text('暂无记录'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: _lines.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: SelectableText(
                    _lines[i],
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                ),
              ),
      ),
    ]);
  }
}

class DeletedMonitorPage extends StatefulWidget {
  const DeletedMonitorPage({super.key});
  @override
  State<DeletedMonitorPage> createState() => _DeletedMonitorPageState();
}

class _DeletedMonitorPageState extends State<DeletedMonitorPage> {
  DeletedReport report = DeletedReport.empty;
  bool loading = true;
  String? err;

  /// 作者头像索引（`/api/authors.json`）。删除记录的本地媒体通常已被清理，
  /// 服务端下发的记录里就没有 `th`/`cv`；此时按 `deleted_cover.dart` 的规则
  /// 退回作者头像，列表才不会整列「图片不可用」。
  Map<String, dynamic> _authorIdx = const {};

  bool checking = false;

  /// C2（owner 2026-11-24）：顶级单元库＝媒体库根，作为删除记录的一级筛选。
  /// 记录只带基础库 id（`libId`），经 LibMeta 映射到所属顶级单元库。
  LibMeta? _meta;
  String topFilter = '';

  @override
  void initState() {
    super.initState();
    _loadAuthorIdx();
    _loadMeta();
    load();
  }

  /// 拉一次库树，供「顶级单元库」筛选把基础库映射到媒体库根。
  Future<void> _loadMeta() async {
    if (cfg.base.isEmpty) return;
    try {
      final m = await LibMeta.load(cfg.lib);
      if (!mounted) return;
      setState(() => _meta = m);
    } catch (_) {}
  }

  /// 记录 → 所属顶级单元库 id；拿不到返回空串（不猜、不归入「其它」）。
  String _topOf(DeletedEntry e) {
    final m = _meta;
    if (m == null) return '';
    final lib = e.libId.trim();
    if (lib.isEmpty) return '';
    return m.topIdForBasic(lib);
  }

  /// 记录里实际出现的顶级单元库（按首次出现顺序，带条数）。
  List<MapEntry<String, int>> get _topOptions {
    final counts = <String, int>{};
    final order = <String>[];
    for (final e in report.items) {
      final t = _topOf(e);
      if (t.isEmpty) continue;
      if (!counts.containsKey(t)) order.add(t);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return [for (final k in order) MapEntry(k, counts[k] ?? 0)];
  }

  String _topLabel(String id) {
    for (final t in _meta?.tops ?? const <UnitLibrary>[]) {
      if (t.id == id) return t.name.isEmpty ? id : t.name;
    }
    return id;
  }

  void _setTopFilter(String t) {
    if (topFilter == t) return;
    setState(() => topFilter = t);
  }

  /// 当前筛选下要显示的记录。
  List<DeletedEntry> get _visibleItems => topFilter.isEmpty
      ? report.items
      : [
          for (final e in report.items)
            if (_topOf(e) == topFilter) e
        ];

  /// 拉一次作者索引供预览图兜底；失败不影响列表（只是回落到占位图标）。
  Future<void> _loadAuthorIdx() async {
    if (cfg.base.isEmpty) return;
    try {
      final r = await http
          .get(cfg.u('/api/authors.json'), headers: cfg.headers)
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final j = jsonOf(r);
      if (j is! Map || !mounted) return;
      setState(() => _authorIdx = Map<String, dynamic>.from(j));
    } catch (_) {}
  }

  /// 触发爬虫脚本（dy_prune.js）立即扫描平台已删除的作品。
  Future<void> _runCheck() async {
    if (checking) return;
    setState(() => checking = true);
    try {
      final r = await http
          .post(cfg.u('/api/deleted/check'), headers: cfg.headers)
          .timeout(const Duration(seconds: 15));
      final j = jsonOf(r);
      throwIfApiFailed(r.statusCode, j);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已开始检测平台删除的作品，完成后自动刷新')));
      await Future<void>.delayed(const Duration(seconds: 5));
      if (mounted) await load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('检测启动失败：$e')));
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
    });
    // 读取链路：带当前库参数的正式地址 → 不带库参数 → 抖音库。
    // 旧记录为空时先确认是「服务端确实没有」还是「请求落到了别的库」，
    // 不再把空列表直接当成「暂无删除记录」。
    final attempts = <Uri>[];
    void addAttempt(Uri u) {
      if (!attempts.any((e) => e.toString() == u.toString())) attempts.add(u);
    }

    if (cfg.base.isNotEmpty) {
      addAttempt(cfg.u('/api/deleted.json'));
      addAttempt(Uri.parse(joinApiUrl(cfg.base, '/api/deleted.json')));
      if (cfg.lib != 'douyin') {
        addAttempt(Uri.parse(
            joinApiUrl(cfg.base, '/api/deleted.json', query: {'lib': 'douyin'})));
      }
    }
    DeletedReport best = DeletedReport.empty;
    Object? lastErr;
    var anyOk = false;
    for (final uri in attempts) {
      try {
        final r = await http
            .get(uri, headers: cfg.headers)
            .timeout(const Duration(seconds: 12));
        if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
        dynamic raw;
        try {
          // 解析放 isolate：删除记录可能很多，避免在 UI 线程解码 JSON。
          raw = await parseJsonMapAsync(r.bodyBytes);
        } catch (_) {
          // 兼容旧服务端/代理返回顶层数组的情况。
          raw = jsonOf(r);
        }
        final parsed = parseDeletedReport(raw, source: uri.toString());
        anyOk = true;
        if (parsed.items.length > best.items.length ||
            (parsed.items.length == best.items.length &&
                parsed.total > best.total)) {
          best = parsed;
        }
        if (best.items.isNotEmpty) break;
      } catch (e) {
        lastErr = e;
      }
    }
    if (!mounted) return;
    if (!anyOk) {
      setState(() {
        err = lastErr == null ? '未配置服务器地址' : '$lastErr';
        loading = false;
      });
      return;
    }
    setState(() {
      report = best;
      loading = false;
      err = null;
    });
  }

  Widget _cover(DeletedEntry e) {
    // 记录里的 `th`/`cv` 常常已被清理（本地媒体也删了）：按 deleted_cover
    // 的规则退回作者头像，仍然没有才显示占位图标。
    final path = deletedCoverPath({
      'th': e.cover,
      'a': e.author,
    }, _authorIdx);
    if (path.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        color: Colors.black26,
        child: const Icon(Icons.image_not_supported_outlined, size: 20),
      );
    }
    // 删除记录可能来自其他单元库；`/media/<lib>/...` 里的 lib 必须原样保留，
    // 不能按当前库重新前缀，否则会 404 成空白缩略图。
    final mediaLib = libOfMediaPath(path);
    final lib = mediaLib.isEmpty ? cfg.lib : mediaLib;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        cacheManager: DiziCache.manager,
        imageUrl: cfg.mediaUrl(path, lib: lib),
        httpHeaders: cfg.headersFor(lib),
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        memCacheWidth: 160,
        fadeInDuration: Duration.zero,
        errorWidget: (_, __, ___) => Container(
          width: 56,
          height: 56,
          color: Colors.black26,
          child: const Icon(Icons.broken_image_outlined, size: 20),
        ),
      ),
    );
  }

  /// 按「同步批次」分组展示：每条记录都归到发现它的那一轮同步，
  /// 组头直接写明「本次同步 · 11-20 22:57」，不再只有一串时间。
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 单击整行：用 `libId`+`workId` 打开作品；作品不在本地索引时给明确提示，
  /// 不再像以前那样把「打开作品」错做成「进作者页」。
  Future<void> _openDeletedWork(DeletedEntry e) async {
    final uri = deletedWorkUri(cfg.base, e);
    if (uri == null) {
      _toast(kDeletedNotLocalMessage);
      return;
    }
    final lib = e.libId.trim().isEmpty ? cfg.lib : e.libId.trim();
    try {
      final r = await http
          .get(uri, headers: cfg.headersFor(lib))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (r.statusCode == 404) {
        _toast(kDeletedNotLocalMessage);
        return;
      }
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      dynamic raw;
      try {
        raw = await parseJsonMapAsync(r.bodyBytes);
      } catch (_) {
        raw = jsonOf(r);
      }
      final m = raw is Map ? raw : const <dynamic, dynamic>{};
      final work = m['work'];
      if (work is! Map) {
        _toast(kDeletedNotLocalMessage);
        return;
      }
      final list = <Map<String, dynamic>>[];
      final ws = m['works'];
      if (ws is List) {
        for (final w in ws) {
          if (w is Map) {
            list.add({...Map<String, dynamic>.from(w), '_lib': lib});
          }
        }
      }
      if (list.isEmpty) {
        list.add({...Map<String, dynamic>.from(work), '_lib': lib});
      }
      var start = m['index'] is num ? (m['index'] as num).toInt() : 0;
      start = start.clamp(0, list.length - 1);
      // 服务端索引可能与作者文件顺序略有差异：以被点的作品为准。
      final want = e.workId.trim();
      if (want.isNotEmpty) {
        final i = list.indexWhere((w) => '${w['id'] ?? ''}' == want);
        if (i >= 0) start = i;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlayerPage(works: list, start: start, lib: lib),
      ));
    } catch (err) {
      if (mounted) _toast('打开作品失败：$err');
    }
  }

  /// 抓取失败的记录可重试：服务端按 id 再跑一次对应单元库的爬虫。
  Future<void> _retryDeleted(DeletedEntry e) async {
    final id = e.workId.trim();
    if (id.isEmpty) {
      _toast('该记录没有作品 id，无法重试');
      return;
    }
    final body = syncRetryBody(ids: [id]);
    if (e.libId.trim().isNotEmpty) body['lib'] = e.libId.trim();
    try {
      final r = await http
          .post(syncRetryUri(cfg.base),
              headers: {
                ...cfg.headers,
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      dynamic parsed;
      try {
        parsed = jsonOf(r);
      } catch (_) {}
      _toast(syncRetryResultLabel(r.statusCode, parsed));
    } catch (err) {
      _toast('重试失败：$err');
    }
  }

  /// 三态小标签：已删除（曾落地）/ 抓取失败（可重试）/ 已落地。
  Widget _stateChip(DeletedState s) {
    final cs = Theme.of(context).colorScheme;
    final (color, icon) = switch (s) {
      DeletedState.failed => (Colors.orange.shade800, Icons.error_outline),
      DeletedState.landed => (Colors.green.shade700, Icons.download_done),
      DeletedState.deleted => (cs.error, Icons.delete_outline),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color),
        const SizedBox(width: 2),
        Text(deletedStateLabel(s),
            style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }

  /// owner 2026-11-24：只按当前筛选（顶级单元库）分组展示。
  Widget _groupedList() {
    final groups = groupDeletedBySync(_visibleItems);
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
            child: Row(children: [
              Icon(Icons.sync, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    '本次同步 · ${g.label.isEmpty ? '时间未知' : g.label}'
                    ' · ${g.items.length} 条',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary)),
              ),
            ]),
          ),
          for (final e in g.items) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: _cover(e),
              title: Text(e.title.trim().isEmpty ? '（无标题）' : e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${e.author.isEmpty ? '作者未知' : '@${e.author}'}'
                        '${e.date.isEmpty ? '' : ' · ${e.date}'}'
                        '${e.collection.isEmpty ? '' : ' · ${e.collection}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11)),
                    const SizedBox(height: 2),
                    Row(children: [
                      _stateChip(e.state),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(e.foundLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant
                                    .withValues(alpha: 0.8))),
                      ),
                    ]),
                  ]),
              isThreeLine: true,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (e.state == DeletedState.failed)
                  IconButton(
                    key: ValueKey('deleted-retry-${e.workId}'),
                    tooltip: '重试抓取',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.replay, size: 18),
                    onPressed: () => _retryDeleted(e),
                  ),
                IconButton(
                  tooltip: '复制作品链接',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.link, size: 18),
                  onPressed: e.link.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(ClipboardData(text: e.link));
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('链接已复制')));
                        },
                ),
                IconButton(
                  key: ValueKey('deleted-author-${e.workId}'),
                  tooltip: '进入作者页',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.person_outline, size: 18),
                  onPressed: e.author.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => AuthorPage(
                                  name: e.author,
                                  libs: [
                                    e.libId.trim().isEmpty
                                        ? cfg.lib
                                        : e.libId.trim()
                                  ]))),
                ),
              ]),
              onTap: () => _openDeletedWork(e),
            ),
            const Divider(height: 1),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stats = DeletedStats.of(report.items);
    return Scaffold(
      appBar: AppBar(title: const Text('删除监测'), actions: [
        IconButton(
            tooltip: '立即检测（爬虫扫描平台已删除作品）',
            onPressed: checking ? null : _runCheck,
            icon: checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.travel_explore)),
        IconButton(
            tooltip: '刷新',
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh)),
        const HomeAction(),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? LoadErrorView(
                  message: '加载失败：$err',
                  onRetry: load)
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: Row(children: [
                      const Icon(Icons.delete_outline,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            '共 ${report.total} 条'
                            '${report.items.length == report.total ? '' : '（展示 ${report.items.length}）'}'
                            ' · ${stats.label}'
                            '${report.updatedLabel.isEmpty ? '' : ' · 日志更新 ${report.updatedLabel}'}'
                            '${report.lastDiscoveryLabel.isEmpty ? '' : ' · 最近同步发现 ${report.lastDiscoveryLabel}'}'
                            ' · 只读记录，不删除媒体',
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                      ),
                    ]),
                  ),
                  // C2（owner 2026-11-24）：顶级单元库（＝媒体库根）一级筛选。
                  // 只在记录真的冲越多于一个媒体库时才出现；单库常态不多占一行。
                  if (_topOptions.length > 1)
                    HorizontalChipBar(
                      key: const ValueKey('deleted-top-filter'),
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        Center(
                          child: FilterChip(
                              label: Text('全部媒体库 ${report.items.length}',
                                  style: const TextStyle(fontSize: 12)),
                              selected: topFilter.isEmpty,
                              showCheckmark: false,
                              onSelected: (_) => _setTopFilter('')),
                        ),
                        for (final o in _topOptions)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Center(
                              child: FilterChip(
                                  key: ValueKey('deleted-top-${o.key}'),
                                  label: Text(
                                      '${LibraryBadge.stripIndex(_topLabel(o.key))} ${o.value}',
                                      style: const TextStyle(fontSize: 12)),
                                  selected: topFilter == o.key,
                                  showCheckmark: false,
                                  onSelected: (_) => _setTopFilter(o.key)),
                            ),
                          ),
                      ],
                    ),
                  if (report.items.isEmpty)
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(
                                report.total > 0
                                    ? Icons.warning_amber_rounded
                                    : Icons.delete_outline,
                                size: 34,
                                color: Colors.grey),
                            const SizedBox(height: 10),
                            Text(
                                report.total > 0
                                    ? '服务端记录总数 ${report.total}，但未解析到条目'
                                    : '暂无删除记录',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 6),
                            Text(
                                report.total > 0
                                    ? '已自动回退读取链路仍为空，请点「刷新」重试。'
                                    : '平台删除/取消收藏的作品会按同步批次出现在这里。',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            if (report.total > 0) ...[
                              const SizedBox(height: 12),
                              FilledButton(
                                  onPressed: load, child: const Text('重新读取')),
                            ],
                          ]),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: _groupedList(),
                    ),
                ]),
    );
  }
}

/// 设置：是否自动省略库名/词条前的序号（`(1) 名称` → `名称`）。
class _StripIndexTile extends StatefulWidget {
  const _StripIndexTile();
  @override
  State<_StripIndexTile> createState() => _StripIndexTileState();
}

class _StripIndexTileState extends State<_StripIndexTile> {
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.format_list_numbered),
      title: const Text('词条省略序号'),
      subtitle: const Text('显示单元库/基础库词条时自动去掉名称前的「(1) 」编号'),
      value: AppSettings.stripLibIndex,
      onChanged: (v) async {
        setState(() => AppSettings.stripLibIndex = v);
        await AppSettings.save();
      },
    );
  }
}

/// 推荐页每批数量：0 或空 = 默认 40，上限 500（服务端上限 1000）。
const int kRecommendDefaultCount = 40;
const int kRecommendMaxCount = 500;
const String kRecommendCountPrefsKey = 'recommend_n_v1';

/// 容错解析用户输入：空/非数字 → 默认 40；数字夹紧到 0..500。
int parseRecommendCount(dynamic raw) {
  if (raw == null) return kRecommendDefaultCount;
  if (raw is num) {
    if (raw.isNaN || raw.isInfinite) return kRecommendDefaultCount;
    return raw.round().clamp(0, kRecommendMaxCount);
  }
  final s = '$raw'.trim();
  if (s.isEmpty) return kRecommendDefaultCount;
  final v = int.tryParse(s.replaceAll(RegExp(r'[^0-9-]'), ''));
  if (v == null) return kRecommendDefaultCount;
  return v.clamp(0, kRecommendMaxCount);
}

/// 实际请求数量：0（用户设为「默认」）或空时用 40。
int recommendRequestCount(int raw) =>
    raw <= 0 ? kRecommendDefaultCount : raw.clamp(1, kRecommendMaxCount);

/// 推荐作品去重键：库 + 作品 id（无库时只用 id）。
String recommendWorkKey(dynamic w) {
  if (w is! Map) return '';
  final id = '${w['id'] ?? ''}';
  if (id.isEmpty) return '';
  final lib = '${w['_lib'] ?? ''}';
  return lib.isEmpty ? id : '$lib|$id';
}

/// 续播合并：把 [incoming] 追加到 [existing] 尾部，按作品 id 去重，
/// 保留原有顺序；没有 id 的条目无法判重，按原样保留。
List mergeRecommendPages(List existing, List incoming) {
  final out = <dynamic>[];
  final seen = <String>{};
  void addAll(List src) {
    for (final w in src) {
      final k = recommendWorkKey(w);
      if (k.isNotEmpty && !seen.add(k)) continue;
      out.add(w);
    }
  }

  addAll(existing);
  addAll(incoming);
  return out;
}

/// 生成未用过的推荐 seed：同一秒内多次续播也不会重复请求同一批。
int nextRecommendSeed({
  required int nowSeconds,
  required int seq,
  required Set<int> used,
}) {
  var s = seq;
  var seed = nowSeconds + s * 7919;
  while (used.contains(seed)) {
    s++;
    seed = nowSeconds + s * 7919;
  }
  return seed;
}

/// 推荐数量设置：持久化到本机 SharedPreferences。
class RecommendCountSettings {
  /// 用户原始值（0 表示默认 40）。
  static int raw = kRecommendDefaultCount;

  /// 实际请求数量（已把 0 折算为 40）。
  static int get value => recommendRequestCount(raw);

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      raw = parseRecommendCount(sp.get(kRecommendCountPrefsKey));
    } catch (_) {
      raw = kRecommendDefaultCount;
    }
  }

  /// 保存并返回夹紧后的原始值。
  static Future<int> save(dynamic input) async {
    raw = parseRecommendCount(input);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(kRecommendCountPrefsKey, raw);
    } catch (_) {}
    return raw;
  }
}

/// 设置：推荐页每批数量（0/空 = 默认 40）。
class _RecommendCountTile extends StatefulWidget {
  const _RecommendCountTile();
  @override
  State<_RecommendCountTile> createState() => _RecommendCountTileState();
}

class _RecommendCountTileState extends State<_RecommendCountTile> {
  Future<void> _edit() async {
    final ctrl = TextEditingController(
        text: RecommendCountSettings.raw == 0
            ? ''
            : '${RecommendCountSettings.raw}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('推荐数量'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '每次推荐作品数',
            helperText: '0–500，0 或留空 = 默认 40',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final v = await RecommendCountSettings.save(ctrl.text);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(v == 0 ? '已设为默认 40' : '已设为 $v 个')));
  }

  @override
  Widget build(BuildContext context) {
    final v = RecommendCountSettings.raw;
    return ListTile(
      leading: const Icon(Icons.auto_awesome_outlined),
      title: const Text('推荐数量'),
      subtitle: Text(v == 0 ? '默认 40 个 · 续播自动追加' : '$v 个 · 0–500 · 续播自动追加'),
      onTap: _edit,
    );
  }
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
          title: const Text('网络连接'),
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
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const MediaCrawlerSettingsPage())),
        ),
        // 诊断合并：动作记录（Breadcrumb）+ 错误记录（CrashLog + 缩图缓存）
        // 收到同一个页面，两个 tab；入口只留一个。
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: const Text('诊断'),
          subtitle: const Text('动作记录 + 错误记录 · 崩溃/停播/封面异常排查'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DiagnosticsPage(
                    detail: cfg.base.isEmpty
                        ? '未连接服务器'
                        : '${cfg.base} · '
                            '${cfg.libName.isEmpty ? cfg.lib : cfg.libName}',
                    cacheStatsUri:
                        cfg.base.isEmpty ? null : cfg.u('/api/cache/stats'),
                    cachePruneUri:
                        cfg.base.isEmpty ? null : cfg.u('/api/cache/prune'),
                    cacheHeaders: cfg.headers,
                  ))),
        ),
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('作者等级'),
          subtitle: const Text('D–S 等级词条 · 播放/水滴加权、门槛可调'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const AuthorGradeSettingsPage())),
        ),

        // P2：所有「外观 / 词条 / 角标 / 按键 / 播放 / 缓存」收拢到一个入口，
        // 设置首层只留连接、库、诊断、自定义、关于，避免长列表找不到东西。
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('自定义'),
          subtitle: const Text('主题外观 · 词条配色 · 库角标 · 按键绑定 · 播放设置 · 缓存'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CustomizationHubPage())),
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('删除监测'),
          subtitle: const Text('已删除 / 取消收藏的作品记录 · 只读日志，不动媒体'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeletedMonitorPage())),
        ),
        const _StripIndexTile(),
        const _RecommendCountTile(),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('关于 Dizi'),
          subtitle: Text(appVersion.isEmpty
              ? '本地媒体库客户端'
              : '本地媒体库客户端 $appVersion'),
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'Dizi',
            applicationVersion: appVersion,
            children: const [Text('本地媒体库客户端')],
          ),
        ),
      ]),
    );
  }
}

/// P2：「设置 → 自定义」总入口。
///
/// 把外观类设置（主题/词条配色/库角标/按键/播放/缓存）收进一层，
/// 设置首层只留「连接 · 库 · 诊断 · 自定义 · 关于」，长列表不再难找。
class CustomizationHubPage extends StatelessWidget {
  const CustomizationHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自定义')),
      body: ListView(children: [
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('主题外观'),
          subtitle: const Text('多套配色 · 点击即时预览，不用重启'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ThemeSettingsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.sell_outlined),
          title: const Text('库词条配色'),
          subtitle: const Text('按顶级单元库分类 · 向下继承 · 末梢才分发'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LibraryBadgeColorsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.workspaces_outline),
          title: const Text('库角标'),
          subtitle: const Text('顶级单元库 / 单元库 / 基础库的图案与颜色 · 立即生效'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const CornerBadgeSettingsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.keyboard),
          title: const Text('按键绑定'),
          subtitle: const Text('桌面/硬件键盘快捷键 · 支持组合键'),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const KeyBindingsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('播放设置'),
          subtitle: const Text('默认倍速 · 图文间隔 · 全屏隐藏时间'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PlaybackSettingsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('缓存'),
          subtitle: const Text('封面缓存目录 · 上限与自动清理 · 立即清空'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CacheSettingsPage())),
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
                  // owner 2026-11-18：色卡改小，一屏多放几个主题。
                  crossAxisCount: 3,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.05,
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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: spec.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          padding: const EdgeInsets.all(8),
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
      width: 9,
      height: 9,
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
      appBar: AppBar(title: const Text('播放设置'), actions: [
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
        const Divider(height: 32),
        const Text('视频填充', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          for (final m in VideoFit.values)
            ChoiceChip(
              // 默认（未手动覆盖）在竖屏内容上等同于铺满。
              label: Text(m == VideoFit.fill ? '铺满' : '适应'),
              selected: (AppSettings.videoFitOverride ?? VideoFit.fill) == m,
              onSelected: (_) {
                setState(() => AppSettings.videoFitOverride = m);
                _persist();
              },
            ),
        ]),
        const Text(
            '铺满：竖屏视频裁剪填满屏幕（默认）；适应：始终按源比例完整显示，横屏/方形视频自动留黑边。手动选择后优先于按比例自动判定。',
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
    final combo = await showDialog<KeyCombo>(
      context: context,
      builder: (_) => _KeyCaptureDialog(action: action),
    );
    if (combo == null || !mounted) return;
    final bad = AppSettings.bindComboError(combo);
    if (bad != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(bad)));
      return;
    }
    AppSettings.bindCombo(action, combo);
    setState(() {});
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
              '点击任意一行，按下新的按键即可绑定；需要组合键时按住 Ctrl / Shift / Alt / Win '
              '再按主键（如 Ctrl+Shift+F）。冲突按「修饰键+主键」整体判断，'
              'Ctrl+J 不会与单键 J 冲突。（需硬件键盘；触屏设备可忽略）'
              '方向键与 Esc 是固定键位，不允许绑定；已保存的旧配置里这类绑定会被丢弃。',
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
  /// 当前按住的修饰键掩码，仅用于弹窗里的即时提示。
  int _liveMods = 0;

  /// 上一次被拒绝的原因（按了保留键时显示，下一次按键清空）。
  String? _hint;

  void _syncMods() {
    final m = AppSettings.currentMods();
    if (m != _liveMods && mounted) setState(() => _liveMods = m);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) {
      _syncMods();
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    // 已显示过的拒绝原因只服务于上一次按键，这里先清空。
    if (_hint != null) setState(() => _hint = null);
    // 修饰键本身只更新提示，等主键到了才确认绑定。
    // 注意：这不是第二道准入闸门——按修饰键不能算「一次绑定尝试」，
    // 所以不能落到 bindComboError（那会立刻报错）；准入只看下面的 combo。
    if (AppSettings.isModifierKeyId(k.keyId)) {
      _syncMods();
      return KeyEventResult.handled;
    }
    final combo = KeyCombo(k.keyId, AppSettings.currentMods());
    // 保留键当场提示，不关闭弹窗（与绑定层同一条准入规则）。
    final bad = AppSettings.bindComboError(combo);
    if (bad != null) {
      setState(() => _hint = bad);
      return KeyEventResult.handled;
    }
    Navigator.of(context).pop(combo);
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
          height: 96,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              borderRadius: BorderRadius.circular(10)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.keyboard,
                size: 26,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
                _hint ??
                    (_liveMods == 0
                        ? '请按下要绑定的按键…'
                        : '${AppSettings.modsParts(_liveMods).join('+')}+ … 请按主键'),
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

class CornerBadgeSettingsPage extends StatefulWidget {
  const CornerBadgeSettingsPage({super.key});
  @override
  State<CornerBadgeSettingsPage> createState() =>
      _CornerBadgeSettingsPageState();
}

class _CornerBadgeSettingsPageState extends State<CornerBadgeSettingsPage> {
  static const _kindLabels = <LibBadgeKind, String>{
    LibBadgeKind.top: '顶级单元库（媒体库根）',
    LibBadgeKind.unit: '单元库（中间层）',
    LibBadgeKind.basic: '基础库（末梢）',
    LibBadgeKind.other: '其它（非库语境）',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('库角标')),
      body: ListView(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Text(
              '角标显示在库卡片左上角，表示库的种类。所有层级形状与尺寸一致，'
              '只有图案与颜色不同；改完立即生效。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        const Divider(height: 1),
        for (final kind in LibBadgeKind.values)
          _kindTile(context, kind),
      ]),
    );
  }

  Widget _kindTile(BuildContext context, LibBadgeKind kind) {
    final argb = LibraryCornerBadge.colorFor(kind);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
        leading: LibCornerBadge(kind: kind),
        title: Text(_kindLabels[kind] ?? kind.name),
        subtitle: Text(
            '图案：${kCornerPatternNames[LibraryCornerBadge.patternFor(kind)]}'),
        trailing: TextButton(
          onPressed: () async {
            await LibraryCornerBadge.resetKind(kind);
            setState(() {});
          },
          child: const Text('恢复默认'),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < kCornerPatternNames.length; i++)
            GestureDetector(
              onTap: () async {
                await LibraryCornerBadge.setPattern(kind, i);
                setState(() {});
              },
              child: Container(
                width: 56,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: LibraryCornerBadge.patternFor(kind) == i
                        ? Colors.lightBlueAccent
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(children: [
                  LibCornerBadge(kind: kind),
                  const SizedBox(height: 4),
                  Text(kCornerPatternNames[i],
                      style:
                          const TextStyle(fontSize: 9, color: Colors.grey)),
                ]),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in LibraryBadge.palette)
            GestureDetector(
              onTap: () async {
                await LibraryCornerBadge.setColor(kind, c);
                setState(() {});
              },
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Color(c),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: argb == c ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: argb == c
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
        ]),
      ),
      const Divider(height: 1),
    ]);
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
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      _apply(jsonMapOf(r), setLoading: true);
    } catch (e) {
      if (mounted) setState(() => err = errorText(e));
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
    if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
    return jsonMapOf(r);
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
      if (mounted && seq == _seq) _toast('保存失败：${errorText(e)}');
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
              ? LoadErrorView(
                  message: '加载失败：$err',
                  onRetry: load)
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

  /// 主页单元库菜单的滚动控制器。刷新时列表必须保持挂载，否则位置归零。
  final ScrollController _menuScroll = ScrollController();

  /// 是否已经有过一次成功的快照。
  /// 结构：首载（无快照）才整页转圈；之后所有 load() 都是后台刷新，
  /// 列表与滚动位置一律保留 —— 这是「菜单滚动位置记忆」的根因所在。
  bool _hasSnapshot = false;
  bool _refreshing = false;

  /// J2：大库/基础库两级选择。v1 服务端没有 bigLibraries 时为 null，走原列表。
  LibraryTree? tree;

  /// P5：本次加载用到的「已连接」连接（只用于聚合与请求）。
  ///
  /// [shownServers] 是磁盘上全部连接（含已断连），断连数量用于左上角叉号。
  /// 两者分开存：断连的连接绝不能混进 [servers]，否则又会被拿去请求。
  List<ServerConn> shownServers = [];
  int disconnected = 0;

  /// L5：单元库树（节点文件夹＝单元库，SECRET 顶级）。
  UnitLibrary? unitTree;
  Set<String> expanded = <String>{};
  List<String> stars = <String>[];

  /// G：服务端 `/api/libraries.json` 下发的基础库第一张作品封面（`fc`）
  /// 现在由 `BasicLib.firstCover` 携带（单一来源），不再另存一份映射。

  @override
  void initState() {
    super.initState();
    // 0.9.75：不再监听全局播放量 revision——库卡片的封面由卡片自己按库
    // 监听并重算（coverUrlOf），整页 setState 会把整个网格重建一遍。
    // 0.9.6：星标是全局状态，任何页面切换后本页都要跟着刷新。
    StarStore.instance.addListener(_onStarsChanged);
    // 封面设置成功后立即刷新库卡片，不必等手动刷新/重启。
    coverRevision.addListener(_onCoverChanged);
    load();
  }

  @override
  void dispose() {
    StarStore.instance.removeListener(_onStarsChanged);
    coverRevision.removeListener(_onCoverChanged);
    _menuScroll.dispose();
    super.dispose();
  }

  void _onCoverChanged() {
    if (mounted) load();
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

  /// L5-C：基础库封面 URL。手动 `_cover/` > 爬虫封面（`cv`）> 自动封面
  /// （本机播放量最高的作品，有图文作品时优先图文图片）。
  String _basicCoverUrl(BasicLib b) {
    final top = topPlayed(WorkPlaysStore.countsFor(b.id));
    // owner 2026-11-21：基础库的封面在「库根/_cover/」下，而 cfg.mediaUrl 的
    // `/media/<库id>/` 已经指向库根；再拼 rel 会变成 `<rel>/_cover/...` → 404。
    // 实测：不带 rel 的地址返回 200 image/jpeg。
    final pick = pickBasicCover(
      rel: '',
      version: b.coverVersion,
      ext: b.coverExt,
      bestThumb: top?.thumb ?? '',
      crawlerThumb: b.crawlerCover,
      // G：没手动封面、没播放数据时用服务端下发的第一张作品封面。
      firstThumb: b.firstCover,
    );
    if (pick.isEmpty) {
      // 兜底：只要服务端给了爬虫封面（cv），就直接用它，避免任何挑选逻辑
      // 把封面吞掉后卡片一直显示默认图。
      final cv = b.crawlerCover.trim();
      if (cv.isEmpty) {
        // 诊断：区分「服务端没下发 cv」和「下发了但拼接失败」。
        CrashLog.instance.record(
          '封面缺失 ${b.id} cv=(空) rel=${b.rel}',
          kind: 'cover',
        );
      }
      return cv.isEmpty ? '' : cfg.mediaUrl(cv, lib: b.id);
    }
    return cfg.mediaUrl(pick.path, lib: b.id);
  }

  /// 0.9.9 自动生成规则：单元库取整棵子树里本机播放量最高的基础库。
  BasicLib? _topPlayedBasic(UnitLibrary u) {
    BasicLib? best;
    var bestPlays = -1;
    for (final b in u.allBasics) {
      final plays = WorkPlaysStore.countsFor(b.id)
          .values
          .fold<int>(0, (n, p) => n + p.count);
      if (plays > bestPlays) {
        bestPlays = plays;
        best = b;
      }
    }
    return best;
  }

  Uri _u(String path, [String? lib, String? atBase]) {
    // 第十四批：拼接规则统一在 api_url（补协议、去尾斜杠、path 带 `?` 用 `&`）。
    return Uri.parse(
        libApiUrl(atBase ?? cfg.baseFor(lib), path, lib ?? cfg.lib));
  }

  /// 最近一次库级快速刷新的时间（防抖用，不新增定时器）。
  final Map<String, DateTime> _libRefreshAt = <String, DateTime>{};

  /// owner 2026-11-22：卡片「快速刷新」——重建该库索引 → 重拉库快照
  /// → 清该库封面缓存 → 刷新打开中的列表。
  ///
  /// [unitRel] 仅用于在服务端按单元库口径重建；索引重建始终针对基础库 id
  /// （单元库没有自己的 libidx）。
  Future<String?> _quickRefresh(String libId, String unitRel) async {
    final id = libId.trim();
    if (id.isEmpty) return '该卡片没有可刷新的库';
    final now = DateTime.now();
    if (!libRefreshAllowed(now, _libRefreshAt[id])) return null;
    _libRefreshAt[id] = now;
    final base = cfg.baseFor(id);
    final headers = cfg.headersFor(id);
    final out = await runLibRefresh(
      lib: id,
      reloadLibraries: load,
      clearLibCovers: () => DiziCache.evictLib(id),
      onBumpRevision: () {
        LibDataRevision.bump(id);
        coverRevision.value++;
      },
      reloadOpenLists: null,
      reindex: (body) async {
        final uri = Uri.parse(libApiUrl(base, '/api/reindex', id));
        final r = await http
            .post(uri,
                headers: {...headers, 'Content-Type': 'application/json'},
                body: jsonEncode(body))
            .timeout(const Duration(seconds: 60));
        dynamic parsed;
        try {
          parsed = jsonOf(r);
        } catch (_) {}
        return (status: r.statusCode, body: parsed);
      },
    );
    return out.message;
  }

  Future<void> load() async {
    setState(() {
      err = null;
      warn = null;
      // 已有快照时只标记刷新：列表保持挂载，滚动位置与首屏内容都不动。
      if (_hasSnapshot) {
        _refreshing = true;
      } else {
        loading = true;
      }
    });
    try {
      final sp = await SharedPreferences.getInstance();
      final all = migrateLegacy(
        servers: decodeServers(sp.getString('servers_v1')),
        base: sp.getString('base') ?? cfg.base,
        user: sp.getString('user') ?? cfg.user,
        pass: sp.getString('pass') ?? cfg.pass,
      );
      // P5：断连的连接不参与聚合，也不发任何请求。
      final visible = liveServers(all);
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
          'Authorization': basicAuthHeader(s.user, s.pass),
        };
        try {
          final rs = await Future.wait([
            http
                .get(Uri.parse('${s.base}/api/libraries'), headers: h)
                .timeout(const Duration(seconds: 10)),
            http
                .get(
                    Uri.parse(
                        '${s.base}/api/libraries.json?t=${DateTime.now().millisecondsSinceEpoch}'),
                    headers: h)
                .timeout(const Duration(seconds: 10)),
          ]);
          var list = <Map<String, dynamic>>[];
          var def = '';
          if (rs[0].statusCode == 200) {
            // 首页库列表可能上千条：解析放 isolate，避免卡首帧。
            final j = await parseJsonMapAsync(rs[0].bodyBytes);
            if (j.isNotEmpty) {
              list = librariesWithDisplayNames(
                  ((j['libraries'] as List?) ?? const [])
                      .map((e) => Map<String, dynamic>.from(e as Map))
                      .toList());
              def = '${j['default'] ?? ''}';
            }
          }
          Map<String, dynamic>? treeJson;
          if (rs[1].statusCode == 200) {
            final j = jsonOf(rs[1]);
            if (j is Map) treeJson = Map<String, dynamic>.from(j);
          }
          if (def.isNotEmpty && defaultId == null) defaultId = def;
          snaps
              .add(ServerLibraries(server: s, libraries: list, tree: treeJson));
        } catch (e) {
          snaps.add(ServerLibraries(server: s, error: errorText(e)));
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
          // 绑定记录的字段集合只有 multi_server.dart 的 bindingEntry 一处定义。
          bindings[id] = bindingEntry(s);
        }
      }
      cfg.setBindings(bindings);
      await savePrefString('lib_bindings_v1', encodeBindings(bindings));
      final failures =
          snaps.where((s) => s.error != null).map((s) => s.server.title);
      if (!mounted) return;
      setState(() {
        servers = use;
        shownServers = all;
        disconnected = disconnectedCount(all);
        libs = merged;
        _hasSnapshot = true;
        if (failures.isNotEmpty) {
          warn = '部分连接失败：${failures.join('、')}（其余库已照常显示）';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          // 刷新失败时保留上次结果，不把已显示的菜单换成错误页。
          if (_hasSnapshot) {
            warn = '刷新失败：$e（显示的是上次结果）';
          } else {
            err = errorText(e);
          }
        });
      }
    }
    await _loadTree();
    if (mounted) {
      setState(() {
        loading = false;
        _refreshing = false;
      });
    }
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
          'Authorization': basicAuthHeader(s.user, s.pass),
        };
        try {
          final r = await http
              .get(
                  Uri.parse(
                      '${s.base}/api/libraries.json?t=${DateTime.now().millisecondsSinceEpoch}'),
                  headers: h)
              .timeout(const Duration(seconds: 8));
          if (r.statusCode != 200) continue;
          final j = jsonOf(r);
          if (j is! Map) continue;
          // owner 2026-11-22：顶级节点名＝媒体库根目录名。先到先用，
          // 多个连接时以首条连接（servers.first，与文件结构页一致）为准。
          if (identical(s, servers.first)) {
            TopNodeName.setFromRoot('${j['root'] ?? ''}');
          }
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
      final t = LibraryTree.parse(merged);
      // 节点文件夹由 owner 在「文件结构」里指定；默认为空 = 只有顶级 SECRET。
      final marked = await _fetchMarkedNodes();
      // owner 2026-11-24：这里原来内联造节点、不带连接标识，于是 buildUnitTree
      // 走进「无连接信息」回退分支，把第一层目录当卡片却标成「媒体库」——
      // 首页层级错位的真正根因就在这一处（不是 LibMeta.load）。
      // 标记节点来自 servers.first（_fetchMarkedNodes 的取数口径），
      // 因此连接标识也必须取同一条连接，不能留空。
      final firstServer = servers.isEmpty ? null : servers.first;
      final nodes = marked.rels
          .map((rel) => LibNode(
                id: 'node:$rel',
                rel: rel,
                name: splitRel(rel).isEmpty ? rel : splitRel(rel).last,
                // owner 2026-11-24：必须带上服务端下发的封面指针，
                // 否则选完过往封面返回界面就回落到自动封面。
                coverUrl: marked.covers[rel] ?? '',
                // serverId 必须是连接 id（buildUnitTree 按它归组），
                // 不能写成 cardLabel——那会让分层再次错位。
                serverId: firstServer?.id ?? '',
                serverBase: firstServer?.base ?? '',
                serverLabel: firstServer?.cardLabel ?? '',
              ))
          .toList(growable: false);
      final units = buildUnitTree(
        nodes: nodes,
        basics: t?.allBasics ?? const <BasicLib>[],
        topName: TopNodeName.current,
      );
      // K7：单元库被删除/重建后，清掉已不存在节点的星标（标记只存本机
      // SharedPreferences，不写 NAS）。树拿不到时（网络失败）不动标记。
      var kept = saved;
      if (units != null && unitMarksNeedPrune(unitIdsOf(units), saved)) {
        final pruned = pruneUnitMarks(unitIdsOf(units), saved);
        for (final stale in saved.where((e) => !pruned.contains(e))) {
          await StarStore.instance.toggle(stale);
        }
        kept = StarStore.instance.ordered;
      }
      if (!mounted) return;
      setState(() {
        stars = kept;
        tree = t;
        unitTree = units;
        if (units != null) UnitBadgeRegistry.setFrom(units);
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

  /// owner 2026-11-23：卡片封面合并入口所接的服务端动作。
  /// [libId] 是封面文件所在的库（单元库取子树第一个基础库）；
  /// [unitRel] 非空表示单元库封面（指针在 unit-covers.json）。
  CoverMenuActions? _coverMenuFor(String libId, String unitRel) {
    if (libId.trim().isEmpty) return null;
    final headers = cfg.headersFor(libId);
    Uri versionsUri() {
      final base = cfg.u('/api/cover/versions', lib: libId);
      if (unitRel.isEmpty) return base;
      final sep = base.toString().contains('?') ? '&' : '?';
      return Uri.parse(
          '$base${sep}unitRel=${Uri.encodeQueryComponent(unitRel)}');
    }

    final restoreUri = cfg.u('/api/cover/restore', lib: libId);
    final clearUri = cfg.u('/api/cover/clear', lib: libId);
    return CoverMenuActions(
      libId: libId,
      unitRel: unitRel,
      headers: headers,
      urlOf: (p) => cfg.mediaUrl(p, lib: libId),
      pickLocal: () => uploadCoverFromPicker(libId: libId, unitRel: unitRel),
      listVersions: () =>
          fetchCoverVersions(url: versionsUri(), headers: headers),
      restore: (v) => restoreCoverVersion(
        url: restoreUri,
        headers: headers,
        libId: libId,
        unitRel: unitRel,
        version: v.version,
        ext: v.ext,
      ),
      restoreAuto: () => clearCustomCover(
        url: clearUri,
        headers: headers,
        libId: libId,
        unitRel: unitRel,
        hard: false,
      ),
      clearAll: () => clearCustomCover(
        url: clearUri,
        headers: headers,
        libId: libId,
        unitRel: unitRel,
        hard: true,
      ),
      onChanged: () => coverRevision.value++,
    );
  }

  /// G：单元库子树里第一个非空的 `fc`（第一张作品封面）。
  ({String lib, String path})? _firstFcOfUnit(UnitLibrary u) {
    for (final b in u.allBasics) {
      final fc = b.firstCover.trim();
      if (fc.isNotEmpty) return (lib: b.id, path: fc);
    }
    return null;
  }

  /// P3：顶级单元库卡片的连接状态。只按节点自带的连接标识查当前连接表，
  /// 不看任何目录名文本；查不到就不显示（不猜）。
  String _topNodeStatus(UnitLibrary u) {
    final id = u.node.serverId.trim();
    if (id.isEmpty) return '';
    for (final s in shownServers) {
      if (s.id != id) continue;
      return s.enabled ? '已连接' : '已断连';
    }
    return '';
  }

  /// P3：首页顶级单元库卡片专用封面——**只认 owner 设过的封面**。
  ///
  /// 顺序：服务端 `cover.u`（owner 手动指定）> 自定义 `_cover/<version>`。
  /// 两者都没有就返回空串，卡片用词条色块占位；不取爬虫封面/作品图，
  /// 避免首页把某个作者的封面当成媒体库封面。
  String _topNodeCoverUrl(UnitLibrary u) {
    final pick = u.node.coverUrl.trim();
    if (pick.isNotEmpty) {
      final ownLib = libOfMediaPath(pick);
      final url = cfg.mediaUrl(pick, lib: ownLib.isEmpty ? null : ownLib);
      if (url.isNotEmpty) return url;
    }
    final custom = coverImageRel(u.rel, u.node.coverVersion, ext: u.node.coverExt);
    if (custom.isEmpty) return '';
    return cfg.mediaUrl(custom, lib: u.allBasics.isEmpty ? null : u.allBasics.first.id);
  }

  /// L5-C：单元库封面。
  /// 0.9.35：owner 手动设置的单元库封面（服务端 `unit-covers.json` → `cover.u`）
  /// 优先 > 手动 `_cover/` > 子树最高播放基础库的封面 > 第一个有封面的基础库。
  String _unitCoverUrl(UnitLibrary u) {
    final pick = u.node.coverUrl.trim();
    if (pick.isNotEmpty) {
      final ownLib = libOfMediaPath(pick);
      final url = cfg.mediaUrl(pick, lib: ownLib.isEmpty ? null : ownLib);
      if (url.isNotEmpty) return url;
    }
    // owner 2026-11-21：单元库以前只传 firstThumb（服务端 `fc`，常指向视频），
    // 从没把「爬虫封面 cv」传进来 —— 而 cv 才是真正有图片的那条链路。
    // 这就是单元库卡片长期灰着的原因。
    String crawlerOfUnit() {
      for (final b in u.allBasics) {
        final cv = b.crawlerCover.trim();
        if (cv.isNotEmpty) return cv;
      }
      return '';
    }

    final custom = pickUnitCover(
        rel: u.rel,
        version: u.node.coverVersion,
        ext: u.node.coverExt,
        crawlerThumb: crawlerOfUnit(),
        firstThumb: _firstFcOfUnit(u)?.path ?? '');
    if (!custom.isEmpty) {
      // 子树第一张作品封面按所属基础库路由；自定义 `_cover/` 保持原解析。
      final fc = _firstFcOfUnit(u);
      return custom.custom
          ? cfg.mediaUrl(custom.path)
          : cfg.mediaUrl(custom.path,
              lib: fc != null && custom.path == fc.path ? fc.lib : null);
    }
    // 自动生成：整棵子树里本机播放量最高的基础库，走该基础库完整封面链
    // （手动 > 爬虫 > 自动），并按基础库所属连接解析媒体地址。
    final top = _topPlayedBasic(u);
    if (top != null) {
      final fallback = _basicCoverUrl(top);
      if (fallback.isNotEmpty) return fallback;
    }
    // 新设备/没播放记录时 `_topPlayedBasic` 会给出一个空封面；
    // 继续在子树里找第一个真的有封面的基础库（自定义/爬虫/作品图），
    // 否则单元库卡片会一直是默认图标。
    for (final b in u.allBasics) {
      if (identical(b, top)) continue;
      final fallback = _basicCoverUrl(b);
      if (fallback.isNotEmpty) return fallback;
    }
    CrashLog.instance.record('cover-unit rel=${u.rel} EMPTY', kind: 'cover');
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
        headersOf: cfg.headersFor,
        coverUploader: uploadCoverFromPicker,
        coverMenuOf: _coverMenuFor,
        onConfigureUnit: _openUnitCrawler,
        refreshOf: _quickRefresh,
      ),
    ));
  }

  /// 鉴权头。格式只有 `basicAuthHeader` 一个出处。
  String _authFor(ServerConn s) => basicAuthHeader(s.user, s.pass);

  /// 读取 owner 指定的节点文件夹（服务端 nodes.json）；失败时按「只有 SECRET」处理。
  Future<MarkedNodes> _fetchMarkedNodes() async {
    if (servers.isEmpty) return const MarkedNodes([], {});
    final s = servers.first;
    try {
      final r = await http.get(Uri.parse('${s.base}/api/nodes'), headers: {
        'Authorization': _authFor(s),
      }).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return const MarkedNodes([], {});
      final j = jsonOf(r);
      final list = (j is Map) ? j['nodes'] : null;
      if (list is! List) return const MarkedNodes([], {});
      // owner 2026-11-24：把 `/api/nodes` 的 covers 映射一并带出，
      // 否则 LibNode.coverUrl 恒为空，手动设过的单元库封面永远不生效
      // （选完过往封面返回界面就回落到自动封面）。
      final rels = list
          .map((e) =>
              (e is Map ? '${e['rel'] ?? e['path'] ?? e['name'] ?? ''}' : '$e')
                  .trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final covers = <String, String>{};
      final cm = (j is Map) ? j['covers'] : null;
      if (cm is Map) {
        for (final e in cm.entries) {
          final k = '${e.key}'.trim();
          final v = '${e.value ?? ''}'.trim();
          if (k.isEmpty || v.isEmpty) continue;
          if (!v.startsWith('/media/')) continue;
          covers[k] = v;
        }
      }
      return MarkedNodes(rels, covers);
    } catch (_) {
      return const MarkedNodes([], {});
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
        headersOf: cfg.headersFor,
        onOpenUnit: (sub) => Navigator.of(c).push(MaterialPageRoute<void>(
          builder: (_) => UnitLibraryPage(
            unit: sub,
            stars: stars.toSet(),
            headersOf: cfg.headersFor,
            onOpenUnit: (s2) => _openUnit(s2),
            onToggleUnitStar: _toggleUnitStar,
            onTapBasic: (b) => _showBasicOn(c, b),
            coverOf: _coverUrlFor,
            unitCoverOf: _unitCoverUrl,
            onConfigureUnit: _openUnitCrawler,
            onMountAuthors: _openUnitAuthorMount,
            coverUploader: uploadCoverFromPicker,
            coverMenuOf: _coverMenuFor,
            refreshOf: _quickRefresh,
          ),
        )),
        onToggleUnitStar: _toggleUnitStar,
        onTapBasic: (b) => _showBasicOn(c, b),
        coverOf: _coverUrlFor,
        unitCoverOf: _unitCoverUrl,
        onConfigureUnit: _openUnitCrawler,
        onMountAuthors: _openUnitAuthorMount,
        coverUploader: uploadCoverFromPicker,
        coverMenuOf: _coverMenuFor,
        refreshOf: _quickRefresh,
      ),
    ));
  }

  /// A1：打开作者文件夹挂载面板（合并/拆分/新建作者目录）。
  ///
  /// 鉴权头沿用该单元库第一个基础库的连接——与爬虫配置、封面请求同一口径，
  /// 避免在一个页面里出现「用的不是同一个连接」的情况。
  void _openUnitAuthorMount(UnitLibrary u) {
    if (u.rel.trim().isEmpty) return;
    final base = u.node.serverBase.isNotEmpty
        ? u.node.serverBase
        : cfg.baseFor(u.basics.isNotEmpty ? u.basics.first.id : null);
    var headers =
        cfg.headersFor(u.basics.isNotEmpty ? u.basics.first.id : null);
    for (final s in servers) {
      if (s.base == base) {
        headers = {'Authorization': basicAuthHeader(s.user, s.pass)};
        break;
      }
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UnitAuthorMountPage(
        unit: u,
        base: base,
        headers: headers,
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
          'Authorization': basicAuthHeader(s.user, s.pass),
        };
        break;
      }
    }
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UnitCrawlerPage(
        unit: u,
        base: base,
        headers: headers,
        libId: u.basics.isNotEmpty ? u.basics.first.id : cfg.lib,
      ),
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
            : LibraryBadge.colorForUnit(unit.id,
                order: UnitBadgeRegistry.orderOr(unitOrder)),
        onOpenAuthor: (name) => Navigator.of(context).push(
            MaterialPageRoute<void>(
                builder: (_) => AuthorPage(name: name, libs: [b.id]))),
        onPlay: (works, index) => Navigator.of(context).push(instantRoute<void>(
            (_) => PlayerPage(works: works, start: index, lib: b.id))),
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
          server: '${l['_serverId'] ?? ''}',
          label: '${l['_serverLabel'] ?? ''}');
    }
    await savePrefString('lib', cfg.lib);
    await savePrefString('lib_bindings_v1', encodeBindings(cfg._bindings));
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
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已将「${l['name']}」设为当前媒体库')));
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
      final j = jsonOf(r);
      throwIfApiFailed(r.statusCode, j);
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
      final j = jsonOf(r);
      throwIfApiFailed(r.statusCode, j);
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
              tooltip: '网络连接',
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
    if (err != null) return LoadErrorView(message: '加载失败：$err');
    if (loading) return const Center(child: CircularProgressIndicator());
    final list = ListView(
      controller: _menuScroll,
      key: const PageStorageKey<String>('lib-menu-list'),
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
              '聚合 ${servers.length} 条连接'
              '${disconnected > 0 ? ' · 已断连 $disconnected 条' : ''}'
              ' · ${libs.length} 个已注册库（同 id 只显示一次）',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ),
        if (unitTree != null)
          UnitLibraryHomeView(
            tree: unitTree!,
            stars: stars.toSet(),
            headersOf: cfg.headersFor,
            onOpenUnit: _openUnit,
            onToggleUnitStar: _toggleUnitStar,
            onTapBasic: _showBasic,
            onOpenStars: _openStars,
            unitCoverOf: (u) => _unitCoverUrl(u),
            topCoverOf: (u) => _topNodeCoverUrl(u),
            statusOf: _topNodeStatus,
            coverUploader: uploadCoverFromPicker,
            coverMenuOf: _coverMenuFor,
            refreshOf: _quickRefresh,
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
    // 后台刷新：不换树、不改高度，只在顶部盖一条细进度条。
    if (!_refreshing) return list;
    return Stack(children: [
      list,
      const Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: LinearProgressIndicator(minHeight: 2),
      ),
    ]);
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
          const PopupMenuItem(value: 'default', child: Text('设为当前媒体库')),
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


/// 「文件结构」里勾选的节点 + 服务端下发的封面指针。
///
/// owner 2026-11-24：把 rel 列表和 covers 映射一起返回，
/// 否则单元库手动封面在首页永远不生效。
class MarkedNodes {
  final List<String> rels;

  /// rel → `/media/<lib>/_cover/<version>.<ext>`（owner 设过的单元库封面）。
  final Map<String, String> covers;

  const MarkedNodes(this.rels, this.covers);
}
/// 设置 → 媒体库与爬虫：独立管理页，不再打开主页（避免套叠重复）。
class MediaCrawlerSettingsPage extends StatefulWidget {
  const MediaCrawlerSettingsPage({super.key});
  @override
  State<MediaCrawlerSettingsPage> createState() =>
      _MediaCrawlerSettingsPageState();
}

class _MediaCrawlerSettingsPageState extends State<MediaCrawlerSettingsPage> {
  List<Map<String, dynamic>> libs = [];
  final Map<String, Map<String, dynamic>> crawlers = {};
  bool loading = true;
  String? err;
  // H：节点/单元库列表与「是否有爬虫脚本」，同步源不再只有 douyin。
  List<UnitLibrary> units = const [];
  Map<String, bool> unitFlags = const {};

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
          .get(Uri.parse('${cfg.base}/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      final j = jsonMapOf(r);
      final list = ((j['libraries'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      crawlers.clear();
      for (final l in list) {
        final id = '${l['id']}';
        try {
          final cr = await http
              .get(Uri.parse(libApiUrl(cfg.base, '/api/crawler', id)),
                  headers: cfg.headersFor(id))
              .timeout(const Duration(seconds: 8));
          if (cr.statusCode == 200) {
            final cj = jsonOf(cr);
            if (cj is Map) {
              crawlers[id] = Map<String, dynamic>.from(cj);
            }
          }
        } catch (_) {}
      }
      // H：同步源适配单元库——列出所有节点文件夹，并标记是否有爬虫脚本。
      var unitList = const <UnitLibrary>[];
      var flags = const <String, bool>{};
      try {
        final m = await LibMeta.load(cfg.lib);
        unitList = [
          for (final u in m.units)
            if (u.id != 'secret') u
        ];
      } catch (_) {}
      try {
        final nr = await http
            .get(Uri.parse('${cfg.base}/api/nodes'), headers: cfg.headers)
            .timeout(const Duration(seconds: 8));
        if (nr.statusCode == 200) {
          flags = unitCrawlerFlags(jsonOf(nr));
        }
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        libs = list;
        units = unitList;
        unitFlags = flags;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          err = errorText(e);
          loading = false;
        });
      }
    }
  }

  Map _cfgOf(Map<String, dynamic>? j) =>
      (j != null && j['crawler'] is Map) ? j['crawler'] as Map : const {};

  int _scriptCount(Map<String, dynamic>? j) {
    final s = j == null ? null : j['scripts'];
    return s is List ? s.length : 0;
  }

  String _freqText(Map<String, dynamic>? j) {
    final iv = (_cfgOf(j)['intervalMin'] as num?)?.toInt() ?? 0;
    if (iv <= 0) return '不自动抓取';
    return everyMinutesLabel(iv);
  }

  /// H：单个单元库的配置入口；没有脚本时置灰并写明 J17 原因。
  Widget _unitTile(UnitLibrary u) {
    final has = unitFlags[u.rel] == true ||
        unitFlags[u.id.replaceFirst('node:', '')] == true;
    return ListTile(
      enabled: has,
      leading: Icon(
        has ? Icons.folder_copy_outlined : Icons.folder_off_outlined,
        color: has ? null : Colors.grey,
      ),
      title: Text(u.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        has ? '已配置爬虫脚本 · 可单独设置同步频率' : '无爬虫脚本（J17：同步设置不可用）',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            TextStyle(fontSize: 11, color: has ? Colors.grey : Colors.orange),
      ),
      trailing: Icon(Icons.chevron_right,
          color: has ? null : Colors.grey.withValues(alpha: 0.4)),
      onTap: has
          ? () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => UnitCrawlerPage(
                        unit: u,
                        base: cfg.base,
                        headers: cfg.headers,
                        libId: cfg.lib,
                      )));
              load();
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final withScripts =
        crawlers.values.where((c) => _scriptCount(c) > 0).length;
    return Scaffold(
      appBar: AppBar(title: const Text('媒体库与爬虫'), actions: [
        IconButton(
            tooltip: '刷新', onPressed: load, icon: const Icon(Icons.refresh)),
        const HomeAction(),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : err != null
              ? LoadErrorView(message: '加载失败：$err')
              : ListView(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text('${libs.length} 个库 · $withScripts 个已配置爬虫脚本',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  if (units.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text('单元库（节点文件夹）',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    for (final u in units) _unitTile(u),
                  ],
                  for (final l in libs)
                    ListTile(
                      leading: const Icon(Icons.library_books_outlined),
                      title: Text(
                          displayLibraryName(
                              '${l['id']}', '${l['name'] ?? l['id']}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${l['id']} · ${_freqText(crawlers['${l['id']}'])}'
                          ' · 脚本 ${_scriptCount(crawlers['${l['id']}'])} 个',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11)),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'crawler') {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => CrawlerConfigPage(lib: l)));
                            load();
                          } else if (v == 'maint') {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => MaintenancePage(lib: l)));
                            load();
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'crawler', child: Text('爬虫配置')),
                          PopupMenuItem(value: 'maint', child: Text('维护检查')),
                        ],
                      ),
                    ),
                ]),
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

  Uri _u(String path) => Uri.parse(libApiUrl(cfg.baseFor(libId), path, libId));

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
      final j = jsonMapOf(r);
      throwIfApiFailed(r.statusCode, j);
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
      if (mounted) setState(() => err = errorText(e));
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
      final j = jsonOf(r);
      throwIfApiFailed(r.statusCode, j);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('爬虫配置已保存')));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：${errorText(e)}')));
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
          ? LoadErrorView(message: '加载失败：$err')
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
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                          : '当前：${everyMinutesLabel(intervalMin)}抓取一次',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
  Uri _u(String path) => Uri.parse(libApiUrl(cfg.baseFor(libId), path, libId));

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
          .get(Uri.parse(withQueryFlag('${_u('/api/maintenance')}', deep ? 'deep=1' : '')),
              headers: cfg.headersFor(libId))
          .timeout(Duration(seconds: deep ? 90 : 15));
      final j = jsonMapOf(r);
      throwIfApiFailed(r.statusCode, j);
      if (mounted) setState(() => data = j);
    } catch (e) {
      if (mounted) setState(() => err = errorText(e));
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
      final j = jsonOf(r);
      throwIfApiFailed(r.statusCode, j);
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
          ? LoadErrorView(message: '加载失败：$err')
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

  /// 总刷新进行中：按钮转圈并禁用重复点击（防抖由 [kTotalRefreshCooldown]
  /// 与这个标志一起保证，不新增定时器）。
  bool _refreshing = false;
  DateTime? _lastRefreshAt;

  @override
  void initState() {
    super.initState();
    _syncCurrentLib();
  }

  /// 顶部「总刷新」：连接探活 → 库列表 → 封面缓存 → 作者索引。
  ///
  /// 完成后只 bump [_libEpoch] 让主页重新拉一次快照（保持滚动位置的逻辑在
  /// `_LibraryPageState.load` 里），并用 SnackBar 报结果。
  Future<void> _totalRefresh() async {
    if (_refreshing) return;
    final now = DateTime.now();
    if (!totalRefreshAllowed(now, _lastRefreshAt)) return;
    _lastRefreshAt = now;
    setState(() => _refreshing = true);
    TotalRefreshOutcome? out;
    try {
      out = await performTotalRefresh();
    } catch (e) {
      out = TotalRefreshOutcome(
          servers: 0, online: 0, libraries: 0, firstError: errorText(e));
    }
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      _libEpoch++;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 2),
      content: Text(out.message),
    ));
  }

  /// 只同步「当前库」指向服务端默认库，用于播放/同步路由；不拉收藏夹列表。
  Future<void> _syncCurrentLib() async {
    try {
      final r = await http
          .get(cfg.u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final lj = jsonMapOf(r);
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
        await savePrefString('lib', cfg.lib);
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
        // P5：左上角连接状态图标（断连即叉号，点击进网络连接设置）。
        leading: ConnectionStatusIcon(
          onTap: () async {
            await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()));
            if (!mounted) return;
            setState(() => _libEpoch++);
          },
        ),
        title: const Text('媒体库'),
        // 手机版顶部排布：总刷新常驻、搜索次之，其余收进「⋯」；
        // 可见按钮数量由可用宽度算出（≤4 个），触达区 44dp。
        actions: [
          const HomeAction(),
          HomeTopBar(
            refreshing: _refreshing,
            actions: [
              TopBarAction(
                id: 'refresh',
                tooltip: '总刷新',
                icon: Icons.refresh,
                onPressed: _totalRefresh,
              ),
              TopBarAction(
                id: 'search',
                tooltip: '搜索',
                icon: Icons.search,
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const SearchPage())),
              ),
              TopBarAction(
                id: 'folders',
                tooltip: '文件结构 / 节点文件夹',
                icon: Icons.account_tree_outlined,
                onPressed: _openFolders,
              ),
              TopBarAction(
                id: 'recommend',
                tooltip: '推荐',
                icon: Icons.auto_awesome,
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RecommendPage())),
              ),
              TopBarAction(
                id: 'authors',
                tooltip: '作者',
                icon: Icons.people_alt_outlined,
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AuthorGridPage())),
              ),
              TopBarAction(
                id: 'rank',
                tooltip: '排行榜',
                icon: Icons.leaderboard_outlined,
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const RankPage())),
              ),
              TopBarAction(
                id: 'settings',
                tooltip: '设置',
                icon: Icons.settings,
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsHubPage())),
              ),
            ],
          ),
        ],
      ),
      body: LibraryPage(key: ValueKey('home-libs-$_libEpoch'), embedded: true),
    );
  }
}

/// 顶部任务栏「总刷新」的实际编排：连接探活 → 库列表 → 封面缓存 → 作者索引。
///
/// 只做编排，不做 UI；结果交给调用方决定怎么提示。
Future<TotalRefreshOutcome> performTotalRefresh() async {
  List<ServerConn> servers = const <ServerConn>[];
  try {
    final sp = await SharedPreferences.getInstance();
    servers = liveServers(migrateLegacy(
      servers: decodeServers(sp.getString('servers_v1')),
      base: sp.getString('base') ?? cfg.base,
      user: sp.getString('user') ?? cfg.user,
      pass: sp.getString('pass') ?? cfg.pass,
    ));
  } catch (_) {}

  Future<int> probe(ServerConn s) async {
    try {
      final r = await http.get(Uri.parse('${s.base}/api/auth'), headers: {
        'Authorization': basicAuthHeader(s.user, s.pass),
      }).timeout(const Duration(seconds: 6));
      return r.statusCode;
    } catch (_) {
      return 0;
    }
  }

  Future<int> countLibs(ServerConn s) async {
    final r = await http.get(
        Uri.parse(
            '${s.base}/api/libraries.json?t=${DateTime.now().millisecondsSinceEpoch}'),
        headers: {
          'Authorization': basicAuthHeader(s.user, s.pass),
        }).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) throw StateError(httpErrorText(r.statusCode));
    final j = jsonOf(r);
    if (j is! Map) return 0;
    return ((j['libraries'] as List?) ?? const []).length;
  }

  return runTotalRefresh(
    servers: servers,
    probe: probe,
    libraryCount: countLibs,
    // 封面：清磁盘缓存 + 内存图片缓存 + bump 版本，让可见卡片重新取图。
    clearCoverCache: () async {
      try {
        await DiziCache.manager.emptyCache();
      } catch (_) {}
      try {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      } catch (_) {}
      coverRevision.value++;
    },
    // 作者/头像：清「已加载」标记后再拉一次索引，并通知已渲染头像重建。
    reloadAuthors: () async {
      _authorAvatarLoaded = false;
      authorAvatarIndex.clear();
      await ensureAuthorAvatarsLoaded();
      authorAvatarRevision.value++;
    },
  );
}

/// 作者行的库归属（基础库/大库/单元库）：作者总览与排行榜共用。
///
/// 合并索引会给 `libs`（出处）或无头像作者只有 `_lib`，不能只看头像路径，
/// 否则筛选面板选了库之后会把没有头像的作者全部排除。
({String basic, String big, String unit}) authorRowIdsFor(Map e, LibMeta? m) {
  var basic = '${e['_bid'] ?? ''}';
  final libs = e['libs'];
  if (basic.isEmpty && libs is List) {
    for (final x in libs) {
      final id = '$x';
      if (m?.basicById(id) != null) {
        basic = id;
        break;
      }
    }
  }
  final av = '${e['avatar'] ?? ''}';
  if (basic.isEmpty) basic = m?.basicIdForPath(av) ?? '';
  if (basic.isEmpty) {
    final l = '${e['_lib'] ?? ''}';
    if (m?.basicById(l) != null) basic = l;
  }
  var unit =
      basic.isEmpty ? (m?.unitIdFor(av) ?? '') : (m?.basicToUnit[basic] ?? '');
  var big = m?.basicById(basic)?.bigId ?? '';
  if (big.isEmpty) big = m?.bigIdFor(av) ?? '';
  return (basic: basic, big: big, unit: unit);
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
  List rows = [];
  final Map<String, LibMeta> metas = {};
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    sel = widget.initialLib ?? 'all';
    loadLibs();
    load();
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
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      final j = jsonOf(r);
      final meta = await LibMeta.load(cfg.lib);
      if (!mounted) return;
      metas[cfg.lib] = meta;
      final list =
          (j is Map && j['authors'] is List) ? j['authors'] as List : [];
      setState(() {
        rows = list;
        loading = false;
      });
      _prefetchRankAvatars();
    } catch (e) {
      if (mounted) {
        setState(() {
          err = errorText(e);
          loading = false;
        });
      }
    }
  }

  int _n(dynamic v) => v is num ? v.toInt() : (int.tryParse('${v ?? ''}') ?? 0);

  /// 0.9.30：排行榜首屏头像预热。
  ///
  /// 榜单每行都是 `AuthorRankTile`（头像 42），头像本身已在服务端预热过缩图，
  /// 但客户端仍要逐行发请求才会出图。这里先把首屏可见行的头像按显示尺寸拉进
  /// 缓存，provider 与 [AuthorAvatar] 完全一致（同 URL + 同 `ResizeImage` 宽度
  /// + 同鉴权头），滚动到该行时直接命中。失败不重试，交给头像自己再取一次。
  void _prefetchRankAvatars() {
    if (!mounted) return;
    final visibleRows = _visibleRows;
    if (visibleRows.isEmpty) return;
    final mq = MediaQuery.of(context);
    final n = firstScreenRowCount(viewportHeight: mq.size.height);
    if (n <= 0) return;
    final px = avatarDecodeWidth(
      displaySize: AuthorAvatar.rankSize,
      devicePixelRatio: mq.devicePixelRatio,
    );
    final urls = <String>[];
    final headers = <String, Map<String, String>>{};
    for (final e in visibleRows.take(n)) {
      final av = '${e['avatar'] ?? ''}';
      if (av.isEmpty) continue;
      final lib = sel == 'all'
          ? '${e['lib'] ?? cfg.lib}'
          : (sel.isEmpty ? cfg.lib : sel);
      final u = withImageWidth(cfg.mediaUrl(av, lib: lib), kAvatarImageWidth);
      urls.add(u);
      headers[u] = cfg.headersFor(lib);
    }
    if (urls.isEmpty) return;
    ThumbPrefetch.instance.run(
      urls,
      limit: n,
      provider: (u) => thumbImageProvider(
        u,
        decodeWidth: px,
        headers: headers[u] ?? cfg.headers,
        cacheManager: DiziCache.manager,
      ),
    );
  }

  Map<String, dynamic> _rowMap(dynamic e) =>
      e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};

  LibMeta? _rowMeta(Map<String, dynamic> e) =>
      metas[cfg.lib] ?? (metas.isEmpty ? null : metas.values.first);

  List<Map<String, dynamic>> get _visibleRows => [
        for (final e in rows)
          if (sel == 'all' ||
              _rowMeta(_rowMap(e))?.bigIdFor('${_rowMap(e)['avatar'] ?? ''}') ==
                  sel)
            _rowMap(e)
      ];

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
        HorizontalChipBar(
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
        // owner 2026-11-19：去掉顶部筛选栏，榜单直接展示全部作者。
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : err != null
                  ? LoadErrorView(
                      message: '加载失败：$err',
                      onRetry: load)
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                              metric == 'drop'
                                  ? '本期还没有小水滴，去播放页送一颗吧'
                                  : '本期还没有播放记录',
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
                            // 0.9.15：排行榜每行都用有效 meta（缺行库时回退到当前库），
                            // 否则作者词条会退化成 SECRET/旧词条。
                            final meta = _rowMeta(_rowMap(e));
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
                              rankColor: rankColorFor(context, i),
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
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      final j = jsonMapOf(r);
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
          loaded[id] = statsAuthors(jsonOf(sr));
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
          err = errorText(e);
          loading = false;
        });
      }
    }
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
        HorizontalChipBar(
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
                  ? LoadErrorView(
                      message: '加载失败：$err',
                      onRetry: load)
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
                                        color: rankColorFor(context, i))),
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

  /// 排序方式持久化的键：进页面先恢复上次选择，不再每次都回到「播放量」。
  static const _sortPrefsKey = 'author_sort_v1';

  List<MapEntry<String, Map<String, dynamic>>> authors = [];
  Map<String, dynamic> stats = {};
  // 0.9.8：作者数据源改为全部基础库（`/api/authors.json?lib=all`）。
  final Map<String, List<String>> authorLibs = {};
  // J9：库 -> 基础库/统计映射，用于显示基础库来源词条
  final Map<String, LibMeta> metas = {};
  String sort = 'plays';

  Future<void> _loadSort() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getString(_sortPrefsKey);
      if (!mounted || v == null || !_sorts.containsKey(v) || v == sort) return;
      setState(() {
        sort = v;
        _applyOrder();
      });
    } catch (_) {}
  }

  Future<void> _saveSort(String value) => savePrefString(_sortPrefsKey, value);

  bool loading = true;
  String? err;
  bool syncing = false;
  // 当前库是否配置了爬虫脚本；没有脚本时禁用联网同步按钮。
  bool hasScripts = false;
  // G19：作者网格分页渲染：首屏一页，滚动到底再追加（与作品网格同一套纯逻辑）。
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

  @override
  void initState() {
    super.initState();
    PerfDiagnostics.instance.beginSpan('page:authors');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerfDiagnostics.instance.endSpan('page:authors');
    });
    loadLibs();
    LibraryBadge.load().then((_) {
      if (mounted) setState(() {});
    });
    AuthorGrade.load().then((_) {
      if (mounted) setState(() {});
    });
    _loadSort();
    load();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    _scroll.removeListener(_maybeLoadMore);
    _scroll.dispose();
    super.dispose();
  }

  /// 滚动接近底部时追加一页作者；不再一次构建上千张卡片。
  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_shown >= _ordered.length) return;
    final p = _scroll.position;
    if (shouldLoadNextPage(
        pixels: p.pixels,
        maxScrollExtent: p.maxScrollExtent,
        viewportDimension: p.viewportDimension)) {
      setState(() => _shown = nextGridCount(_shown, _ordered.length));
    }
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
      setState(() {
        metas[cfg.lib] = meta;
      });
      try {
        final cr = await http
            .get(Uri.parse(libApiUrl(cfg.base, '/api/crawler', cfg.lib)),
                headers: cfg.headers)
            .timeout(const Duration(seconds: 8));
        if (cr.statusCode == 200) {
          final cj = jsonOf(cr);
          final scripts = (cj is Map ? cj['scripts'] : null);
          if (mounted) {
            setState(() => hasScripts = scripts is List && scripts.isNotEmpty);
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
      if (ar.statusCode != 200) throw Exception(httpErrorText(ar.statusCode));
      // 作者索引可能上千作者：解析放 isolate。
      final m = await parseJsonMapAsync(ar.bodyBytes);
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
          sj = jsonOf(sr);
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
      _prefetchAvatars();
    } catch (e) {
      if (mounted) {
        // 静默刷新失败时保留现有列表，不打扰用户
        if (quiet) return;
        setState(() {
          err = errorText(e);
          loading = false;
        });
      }
    }
  }

  /// 仅用于判断「返回后数据是否真的变了」：作者数、头像、作品数与三项统计。
  String _dataSignature(List<MapEntry<String, Map<String, dynamic>>> entries,
      Map<String, dynamic> stMap) {
    final b = StringBuffer('all')
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
  ///
  /// owner 2026-11-19：作者总览不再做顶部筛选，始终展示全部作者；
  /// 分页只用 [_shown] 控制渲染条数，数据不动。
  void _applyOrder({bool resetShown = true}) {
    _ordered = sortAuthorEntries(authors,
        metric: _metric, works: (e) => _num(e.value['n']), name: (e) => e.key);
    if (resetShown) {
      _shown = _initialShown(_ordered.length);
    } else if (_shown > _ordered.length) {
      _shown = _ordered.length;
    }
  }

  /// 0.9.27：首屏作者头像预热。
  ///
  /// 列表数据一到就先按显示尺寸拉首屏可见头像，provider 与 [AuthorAvatar]
  /// 完全一致（同 URL + 同 `ResizeImage` 宽度），格子渲染时直接命中缓存，
  /// 不再先出首字母占位再逐张替换。只预热有 `av` 的作者，失败由卡片自己重试。
  void _prefetchAvatars() {
    if (!mounted || _ordered.isEmpty) return;
    final mq = MediaQuery.of(context);
    final n = firstScreenThumbCount(
      viewportWidth: mq.size.width,
      viewportHeight: mq.size.height,
      maxCrossAxisExtent: 150,
      aspectRatio: 150 / 170,
    );
    if (n <= 0) return;
    final px = avatarDecodeWidth(
      displaySize: AuthorAvatar.gridSize,
      devicePixelRatio: mq.devicePixelRatio,
    );
    final urls = <String>[];
    final headers = <String, Map<String, String>>{};
    for (final e in _ordered.take(n)) {
      final av = '${e.value['av'] ?? ''}';
      if (av.isEmpty) continue;
      final lib = '${e.value['_lib'] ?? cfg.lib}';
      final u = withImageWidth(cfg.mediaUrl(av, lib: lib), kAvatarImageWidth);
      urls.add(u);
      headers[u] = cfg.headersFor(lib);
    }
    if (urls.isEmpty) return;
    ThumbPrefetch.instance.run(
      urls,
      limit: n,
      provider: (u) => thumbImageProvider(
        u,
        decodeWidth: px,
        headers: headers[u] ?? cfg.headers,
        cacheManager: DiziCache.manager,
      ),
    );
  }

  String _fmtDate(int sec) {
    if (sec <= 0) return '未访问';
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000).toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  /// 首屏渲染条数：桌面端直接全量。
  ///
  /// 桌面端（Windows/Linux/macOS）的列表由鼠标滚轮驱动，滚动事件不保证
  /// 触发 `_maybeLoadMore`，分页会把作者卡在首屏 60 个——owner 反馈
  /// 「Windows 版只显示 60 个」就是这个。移动端仍按页追加。
  int _initialShown(int total) {
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    return desktop ? total : initialGridCount(total);
  }

  /// 当前分页实际渲染条数（夹紧到总数）。
  int get _shownLen =>
      _shown <= 0 ? 0 : (_shown > _ordered.length ? _ordered.length : _shown);

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
      final m = jsonOf(r);
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
    final lib = '${e.value['_lib'] ?? cfg.lib}';
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
            tooltip: syncing ? '同步中…' : (hasScripts ? '立即同步作者' : '当前库未配置爬虫脚本'),
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
              ? LoadErrorView(
                  message: '加载失败：$err',
                  onRetry: load)
              : Column(children: [
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
                                _saveSort(s.key);
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // owner 2026-11-19：去掉顶部筛选栏；页面只保留排序与分页。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 8, 6),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              '$_shownLen/${_ordered.length} 位作者 · 播放/访问/水滴为本机统计',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey))),
                    ]),
                  ),
                  Expanded(
                    child: _ordered.isEmpty
                        ? const Center(
                            child: Text('暂无作者数据',
                                style: TextStyle(color: Colors.grey)))
                        : Builder(builder: (context) {
                            // 分页渲染：首屏一页（60），滚动到底自动追加；
                            // 卡片固定高度，GridView 自身虚拟化。
                            return GridView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 150,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                mainAxisExtent: AuthorGridCard.extent,
                              ),
                              itemCount: _shownLen,
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

/// C：PageView 邻页（预载页）。独立 StatefulWidget，State 与已解码封面
/// 在父级 setState 时保留；封面未就绪时用纯黑占位，绝不黑屏闪烁。
class _NeighborPage extends StatefulWidget {
  const _NeighborPage({
    required this.index,
    required this.imageUrl,
    required this.headers,
    required this.memCacheWidth,
    this.onAspect,
  });

  final int index;
  final String imageUrl;
  final Map<String, String> headers;
  final int memCacheWidth;

  /// 封面解析出比例后回填给播放页缓存：滑到它之前比例就已就绪，
  /// 落页时不再有「先铺满、再留边」的重排。
  final ValueChanged<double>? onAspect;

  @override
  State<_NeighborPage> createState() => _NeighborPageState();
}

class _NeighborPageState extends State<_NeighborPage> {
  /// 封面像素宽/高。封面截自视频帧，比例与视频一致——用它来判定这一页
  /// 是铺满还是留边，保证和落页后的播放器矩形完全重合。
  double? _aspect;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void initState() {
    super.initState();
    // 轻量日志：验证拖动前邻页已挂载（tag=page:mount）。
    debugPrint('[page:mount] index=${widget.index}');
    _resolveAspect();
  }

  void _resolveAspect() {
    if (widget.imageUrl.isEmpty) return;
    try {
      final provider = CachedNetworkImageProvider(
        widget.imageUrl,
        headers: widget.headers,
        cacheManager: DiziCache.manager,
        maxWidth: widget.memCacheWidth,
      );
      final listener = ImageStreamListener((info, _) {
        final img = info.image;
        if (!mounted || img.height <= 0) return;
        final a = img.width / img.height;
        if (a <= 0) return;
        widget.onAspect?.call(a);
        if (_aspect != null && (_aspect! - a).abs() < 0.001) return;
        setState(() => _aspect = a);
      });
      _listener = listener;
      _stream = provider.resolve(const ImageConfiguration());
      _stream!.addListener(listener);
    } catch (_) {
      // 解析失败保持默认铺满，不影响滑动。
    }
  }

  @override
  void dispose() {
    final s = _stream;
    final l = _listener;
    if (s != null && l != null) s.removeListener(l);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const fallback = ColoredBox(color: Colors.black);
    if (widget.imageUrl.isEmpty) return fallback;
    // 与播放页同一套判定：竖屏铺满、横板留边；用户手动覆盖优先。
    // 留边时黑底属于本页，滑动中整页一起位移，接缝是黑接黑。
    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: LayoutBuilder(builder: (_, c) {
          final fill = videoFitFor(
                  aspect: _aspect,
                  mode: AppSettings.videoFitOverride,
                  containerAspect:
                      c.maxHeight > 0 ? c.maxWidth / c.maxHeight : null) ==
              VideoFit.fill;
          return CachedNetworkImage(
            cacheManager: DiziCache.manager,
            // 滑动中的相邻页只是占位：720px 缩图足够，按屏幕宽度解码。
            imageUrl: widget.imageUrl,
            httpHeaders: widget.headers,
            memCacheWidth: widget.memCacheWidth,
            alignment: fill ? Alignment.topCenter : Alignment.center,
            fit: fill ? BoxFit.cover : BoxFit.contain,
            fadeInDuration: Duration.zero,
            placeholder: (_, __) => fallback,
            errorWidget: (_, __, ___) => fallback,
          );
        }),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final List works;
  final int start;
  // 作品可能来自非当前库（按库筛选 / 全部库），lib 为列表默认所属库
  final String? lib;
  // A2：列表到底时向来源页请求续播（返回是否追加成功）。
  final Future<bool> Function()? onNeedMore;
  // owner 2026-11-22：按「进入来源」区分行为。true 表示从作者页点进来：
  // 禁用左滑进作者页，并把点头像/作者名改成返回上一页。
  final bool fromAuthor;
  // T3：不再携带旧「收藏夹」idx/名称，来源只由单元库体系表达
  const PlayerPage(
      {super.key,
      required this.works,
      required this.start,
      this.lib,
      this.onNeedMore,
      this.fromAuthor = false});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// G18：两个播放器槽位。A 播放当前作品，B 在后台静音预缓冲下一条；
/// 切条时交换槽位，预缓冲好的媒体无需重新打开即可起播。
/// 把 mpv 的解封装缓存落到磁盘（优先 SSD），减少「未命中预载池」时
/// 起始段仍要从机械盘随机读的等待。只影响播放器参数，不动任何媒体文件。
///
/// owner 2026-11-22：热媒体常驻不现实（每个库都可能访问），先做磁盘缓存。
Future<void> _setupMpvDiskCache(Player p) async {
  try {
    final np = p.platform;
    if (np is! NativePlayer) return;
    final dir = await getTemporaryDirectory();
    final cacheDir = '${dir.path}${Platform.pathSeparator}mpv-cache';
    try {
      await Directory(cacheDir).create(recursive: true);
    } catch (_) {}
    await np.setProperty('cache', 'yes');
    await np.setProperty('cache-on-disk', 'yes');
    // mpv 0.38 起 `cache-dir` 已改名为 `demuxer-cache-dir`，旧名只保留兼容
    // 并在每次创建播放器时抛一条 warn（0.9.197 设备日志里实测到这条）。
    // 继续用旧名意味着磁盘缓存目录随时可能失效，且日志里多一行噪音；
    // 这里直接用**新名**，失败时由外层 catch 兜住（不写第二套兜底属性）。
    await np.setProperty('demuxer-cache-dir', cacheDir);
    // 单条 64MB 头部缓存，回读 32MB；SSD 上这点写入可以忽略。
    await np.setProperty('demuxer-max-bytes', '67108864');
    await np.setProperty('demuxer-max-back-bytes', '33554432');
  } catch (_) {}
}

class _PlaybackSlot {
  final String tag;
  final int sid;

  /// 本槽位当前打开的媒体地址（只用于落盘「地址形状」诊断）。
  /// 保存它是为了在命中预载池的路径上也能拿到地址——那条路径不经过
  /// `open()` 的媒体拼接，否则「池命中后播放失败」就没有任何形状指标。
  String mediaUrl = '';

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
        // 只要 error/warn：诊断需要「哪一层失败」，不需要每帧时钟。
        // 默认也是 error，这里显式写出来，避免日后被改成 none 而丢掉诊断。
        logLevel: MPVLogLevel.warn,
      ),
    );
    // Windows：显式使用安全硬件解码，避免窗口缩放/最大化时纹理重建导致崩溃
    vc = VideoController(
      player,
      configuration: VideoControllerConfiguration(
          hwdec: hwdecFor(mode, androidCopy: Platform.isAndroid)),
    );
    PerfDiagnostics.instance.slotCreated();
    // 每个槽位创建后立刻配置磁盘缓存（异步，不阻塞起播）。
    unawaited(_setupMpvDiskCache(player));
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
  // owner 2026-11-18：Windows 上反复切全屏会触发原生崩溃，根因是硬解纹理
  // 跟着窗口反复重建。这里默认改软件解码（兼容性优先），其它平台不变。
  DecodeMode _decodeMode =
      Platform.isWindows ? DecodeMode.software : DecodeMode.hardware;
  bool _softwareDecodeRetried = false;
  // 槽位重建后强制重建 Video，避免沿用旧控制器的纹理
  int _videoGen = 0;
  // iOS「有声无画」看门狗：音频在走但视频轨始终没报出尺寸，说明纹理没出帧。
  // 先只重建一次纹理（不重开媒体、不换解码器），仍无画面才降级软解。
  double _videoDw = 0;

  /// 纹理首次就绪后是否已经重挂过 Video widget。
  ///
  /// owner 2026-11-20：现象是「第一次播放有声音但画面黑，切下一条再回来又正常」。
  /// 这是 Video 组件在纹理 id 就绪前挂载导致的：重建一次即可出画。
  bool _videoGenSynced = false;
  bool _blackRebuilt = false;

  /// 首帧是否真的出来了（位置开始走动）。出来之前一直用海报盖住视频层，
  /// 避免「黑屏一下 / 缓冲圈闪一下 / 比例跳一下」的起播观感。
  bool _firstFrameSeen = false;

  /// 本次 open() 下发时刻：首帧到达时用它算起播耗时（写入 pause.log）。
  DateTime? _openStartedAt;

  /// 最近一次播放器错误的原始文本（仅用于写脱敏诊断摘要，不展示给用户）。
  String? _lastPlayerError;

  /// mpv 内部日志的脱敏尾部（只留 error/warn/fatal 的最近几条）。
  /// 失败时整段落盘，这样「mpv 为什么打不开」不再只剩一句分类名。
  List<String> _mpvTail = const <String>[];

  /// 本次 open() 要打开的媒体地址（仅用于落盘「地址形状」，不写地址本身）。
  String _openMediaUrl = '';

  /// 本次 open() 是否命中预载池（仅用于起播耗时的分组统计）。
  bool _poolHit = false;
  Timer? _blackGuard;
  _PlaybackSlot get _active => _slots[_slotActive];
  // 对播放页其余代码保持原有 player / vc 接口，内部指向当前活动槽位
  Player get player => _active.player;
  VideoController get vc => _active.vc;
  // M6：预加载账本 + 运行状态
  final PreloadCache _preloadCache =
      PreloadCache(maxEntries: preloadMaxPerSide * 2);
  // 预载占用的槽位（按对象身份，避免 sid 复用后误判）。
  final Map<_PlaybackSlot, String> _preloadBusy = <_PlaybackSlot, String>{};
  Timer? _preloadTimer;
  int _preloadGen = 0;
  bool _preloadRunning = false;
  // 线③：相邻视频 HTTP Range 预取（只预热 NAS 页缓存，不占播放器槽位）
  final VideoPrefetcher _videoPrefetch = VideoPrefetcher();
  Timer? _videoPrefetchTimer;
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
  // A2：列表到底续播请求进行中，避免重复请求。
  bool _fetchingMore = false;
  Timer? _wheelUnlock;
  Timer? _wheelIdle;
  bool _fsBusy = false;
  int _navAt = 0;
  int _lastKeyNav = 0;
  int? _pendingPage;
  /// 用户暂停意图（唯一真源）。
  ///
  /// 相位机负责「实际有没有在播」，这里只记录「用户想不想播」。
  /// 0.9.189 起写入点全部收敛到这一个私有字段（15 处），外部只读；
  /// 之前它叫 `paused` 且被 15 个位置各自赋值，谁都能盖住状态，
  /// 这正是「暂停不灵敏」的结构性来源。`test/pause_intent_single_source_test.dart`
  /// 钉住：播放页里不得再出现对裸 `paused` 的赋值。
  bool _pausedIntent = false;

  /// 对外只读的暂停意图（沿用旧名字，调用点不必改语义）。
  bool get paused => _pausedIntent;
  // G16：是否因切后台而暂停（回前台时只恢复这种暂停）
  bool _pausedByBackground = false;
  // 「随机自动暂停」修复：区分「用户主动暂停」与「播放器/系统造成的停止」。
  // 只有用户操作、切后台、判失败才允许把 paused 置真；播放器自己报
  // playing=false（卡顿、解码器被回收、音频设备切换）走自救流程。
  bool _userPaused = false;
  bool _appForeground = true;
  int _stallAttempts = 0;
  static const int _stallMaxAttempts = 3;
  // 当前挂着的健康检查允许几次自救（起播确认 2 次、播放中掉线 3 次）。
  int _stallCheckMax = _stallMaxAttempts - 1;
  Timer? _stallTimer;
  /// 显式播放相位（`playback_state.dart`）。owner 2026-11-23：
  /// 播放页有 59 个布尔量、18 个定时器、102 处 setState 互相猜状态，
  /// 这是「暂停不灵敏 / 点击被吞 / 卡封面」的结构性来源。
  ///
  /// 接线分三步，本字段是第 1 步：相位与旧布尔量**并行**推进，
  /// 只在日志里比对，不改变任何显示。确认一致后第 2 步才切显示源。
  PlaybackPhase _phase = PlaybackPhase.idle;
  /// 最近一次相位不一致的比对结果（仅用于诊断日志，不参与显示）。
  String _phaseMismatch = '';

  /// 起播 loading：**唯一真源是相位**，不再单独维护布尔量。
  ///
  /// 以前 `loading` 在六处被各自赋值（open 命中/未命中、失败、不可播放、
  /// 重试、软解重建），与相位并行推进时只能靠 `_feed` 的比对去发现两套
  /// 说法不一致——那属于「用检测兜住结构问题」。现在直接派生自
  /// [PlaybackPhase.showsLoading]，写入点归零：相位前进，界面才前进。
  bool get loading => _phase.showsLoading;

  /// 界面是否要表现「暂停中」。
  ///
  /// 相位机第 3 步（owner 2026-11-23）：显示层不能再看用户意图 [paused]，
  /// 而要看**实际相位**。意图是「用户想不想播」，若播放器还在播（相位 playing），
  /// 界面却画暂停图标，就又是两套说法分叉。
  bool get _showsPaused => _phase.showsPaused;
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

  /// O4：当前视频宽高比（来自播放器 videoParams），用于把手机端任务栏
  /// 贴到画面下沿；拿不到时退回屏幕底部。
  double? _videoAspect;

  /// 播放器自己上报的比例，按作品缓存（键与点赞一致）。
  ///
  /// owner 2026-11-21：起播瞬间「诡异拉伸」的根因是**拿封面比例给视频纹理
  /// 排版**。封面比例来自缩略图像素（可能是裁切过的帧，也可能与带旋转信息
  /// 的视频轨不一致）；它往往比播放器先到，视频就被画进错误矩形的
  /// `BoxFit.fill`，等解码器报出真比例再跳回——那一下就是拉伸。
  /// 现在视频层只认播放器上报的比例；拿不到就先不挂视频层（海报继续盖着）。
  final Map<String, double> _playerAspectByWork = {};

  /// 封面 / 邻页占位图的比例：只服务封面显示，不能用于视频层布局。
  final Map<String, double> _coverAspectByWork = {};

  /// 视频层可用比例：只有播放器报过的才作数。
  double? _videoAspectFor(dynamic w) {
    final a = _playerAspectByWork[_workKeyFor(w)];
    return (a != null && a > 0) ? a : null;
  }

  /// 封面显示比例：封面 → 播放器 → 上次播放器上报值。
  double? _coverAspectFor(dynamic w) {
    final key = _workKeyFor(w);
    final cover = _coverAspectByWork[key];
    if (cover != null && cover > 0) return cover;
    final player = _playerAspectByWork[key];
    if (player != null && player > 0) return player;
    return _videoAspect;
  }

  /// 记住封面比例（邻近页封面解析时回填）；与已有值相差 <2% 时不覆盖。
  void _rememberCoverAspect(dynamic w, double a) {
    if (a <= 0 || !a.isFinite) return;
    final key = _workKeyFor(w);
    final old = _coverAspectByWork[key];
    if (old != null && old > 0 && (old - a).abs() / old < 0.02) return;
    _coverAspectByWork[key] = a;
  }

  /// 记住播放器比例；与已有值相差 <2% 时不覆盖，避免来回抖动。
  void _rememberPlayerAspect(dynamic w, double a) {
    if (a <= 0 || !a.isFinite) return;
    final key = _workKeyFor(w);
    final old = _playerAspectByWork[key];
    if (old != null && old > 0 && (old - a).abs() / old < 0.02) return;
    _playerAspectByWork[key] = a;
  }

  // A：底部任务栏改为不透明实底；视频视口按其高度内缩，避免遮住画面。
  // 栏高在布局完成后测量（简介展开/安全区都会影响）。
  final GlobalKey _taskbarKey = GlobalKey();
  double _taskbarH = 0;
  // 最近两次测量值，用于识别全屏切换期间的来回震荡。
  double _taskbarSwingA = 0;
  double _taskbarSwingB = 0;
  // Windows：窗口缩放/最大化期间先摘掉视频纹理，避免 media_kit 在尺寸
  // 变化中重排纹理导致原生崩溃；尺寸稳定后重建 Video 元素。
  bool _winResizing = false;
  Timer? _winResizeTimer;

  /// 切换期间用户又点了全屏：记录最后一次意图，结束后补执行。
  bool? _fsPending;

  bool _taskbarMeasureScheduled = false;
  // C：邻页 widget 复用缓存：同一实例返回给 PageView，setState 时不重建。
  final Map<String, Widget> _neighborPages = <String, Widget>{};

  /// O3：iOS 启动 1.5 秒内未真正播放时只重开一次，避免循环重开。
  /// 起播守卫采样基准：调度守卫时的播放位置。iOS 上 `state.playing`
  /// 在缓冲/首帧渲染期间会短暂为 false，仅凭它判断会误触发重开，
  /// 表现为「刚播一秒又停一下」。位置有前进就说明在播，不再重开。
  // I1：音量调节 UI 仅桌面端保留，移动端交给系统音量键。
  bool get _volumeUi => volumeUiEnabled(
      isDesktop: Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  // M1 仅移动端改变全屏单击语义；M3 要求 Windows 交互不变（仍单击暂停）。
  bool get _mobileStageTap => Platform.isAndroid || Platform.isIOS;
  bool ui = true;
  bool fs = false;
  // M5：非全屏上下拖拽切条期间，功能区整体淡化（松手恢复）。
  bool _pageSwiping = false;
  // P2 §12：非全屏沉浸（3 秒无操作淡出互动栏/信息区，进度条保留）。
  // 与全屏的 UiAutoHidePolicy 完全独立，全屏分支不读这里的任何状态。
  final ImmersiveCycle _imm = ImmersiveCycle();
  Timer? _immTimer;
  // 按下瞬间是否处于沉浸：抬起后单击只负责恢复，不再触发暂停/点赞。
  bool _immAtDown = false;
  // P2 §13：翻页成功轻震动去重（每次翻页只一次）。
  // J-A2：播放页统一顶部提示（不随功能区淡出，约 3 秒自动消失）。
  String? _noticeText;
  Timer? _noticeTimer;
  int _noticeSeq = 0;
  // J-A4：滑动切条——拖拽期间不暂停当前视频，松手落定后才真正切条。
  int? _swipePendingIndex;
  // M2：是否由播放页主动锁定过屏幕方向（退出时需恢复系统默认）。
  bool _orientationForced = false;
  bool dragging = false;
  // P2：位置/时长改为 ValueNotifier——播放中每次位置回调只重绘进度条，
  // 不再整页 setState（原来播放页整个视频树/信息区/任务栏都跟着重建）。
  final ValueNotifier<Duration> _posVN = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> _durVN = ValueNotifier<Duration>(Duration.zero);

  /// 播放进度 0..1：由位置/时长派生，只驱动进度条自身（拖动时改用 _scrubFracVN）。
  late final PlaybackFraction _progressVN =
      PlaybackFraction(position: _posVN, duration: _durVN);

  /// 旧的读写接口保持不变：读/写都落到 ValueNotifier。
  Duration get pos => _posVN.value;
  set pos(Duration v) => _posVN.value = v;

  Duration get dur => _durVN.value;
  set dur(Duration v) => _durVN.value = v;

  // owner 2026-11-18：呼出式进度条——常态不可见，触底才在指下放大。
  bool _scrubActive = false;
  // 桌面端鼠标悬停：细条放大成可拖状态（owner 2026-11-18）。
  bool _scrubHover = false;
  double? _scrubFrac;

  /// 拖动中的比例：只驱动进度条自身重绘，不触发整页 setState。
  final ValueNotifier<double> _scrubFracVN = ValueNotifier<double>(0);

  /// 图文拖动中的目标段：同样只驱动分段条自身重绘。
  final ValueNotifier<int?> _picDragVN = ValueNotifier<int?>(null);
  bool _scrubThin = false;
  Timer? _scrubThinTimer;
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

  /// 乱序播放：只打乱当前列表（同一基础库/同一来源）的顺序，不跨库。
  bool shuffle = false;
  List<int> _shuffleOrder = const <int>[];

  void toggleShuffle() {
    setState(() {
      shuffle = !shuffle;
      if (shuffle) {
        final rest = <int>[
          for (var i = 0; i < widget.works.length; i++)
            if (i != cur) i
        ]..shuffle(Random());
        _shuffleOrder = <int>[cur, ...rest];
      } else {
        _shuffleOrder = const <int>[];
      }
    });
    _persistPlaybackPrefs();
  }

  /// 乱序模式下的目标下标；按当前作品在乱序序列里的位置前后移动。
  int _shuffleTarget(int delta) {
    final n = widget.works.length;
    if (n <= 1) return -1;
    var order = _shuffleOrder;
    if (order.length != n) {
      final rest = <int>[
        for (var i = 0; i < n; i++)
          if (i != cur) i
      ]..shuffle(Random());
      order = <int>[cur, ...rest];
      _shuffleOrder = order;
    }
    var pos = order.indexOf(cur);
    if (pos < 0) pos = 0;
    for (var k = 0; k < order.length; k++) {
      pos = (pos + delta + order.length) % order.length;
      final idx = order[pos];
      if (workPlayable(_workAt(idx))) return idx;
    }
    return -1;
  }

  // 当前页面实际已载入的媒体所属 open token；图文无音频时为 -1。
  // 用于忽略 player.stop()/切条时上一段媒体迟到的 completed 事件，
  // 避免刚打开图文就被上一次播放的完成事件带去下一条。
  int _mediaToken = -1;
  // 切条（stop/open）进行中：此时播放器会发出 playing=false，
  // 不能据此改写 paused，否则下一条会停在首帧（F32）。
  bool _opening = false;
  // 连播兜底：视频已就绪但播放器未在播放时补一次 play。
  double? dragFrac;
  // 图文进度条拖动时当前指向的图片序号（null = 未在拖动）
  int? dragPic;
  bool resumeAfterDrag = false;
  bool dropBusy = false;
  int dropDayLeft = 1;
  int dropWeekLeft = 3;
  int dropTotal = 0;
  // M12b：全站水滴余额（服务端全局计数，默认每日 5 / 每周 15）。
  int gDropDayLeft = 5;
  int gDropWeekLeft = 15;
  int gDropDayLimit = 5;
  int gDropWeekLimit = 15;
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
  // 2026-11-23 owner：去掉双击点赞后，不再需要双击仲裁与红心动画。
  // 单击仍是唯一判定路径（呼出/收起功能区、非全屏暂停），双击就是两次单击。
  // P1b §8：长按菜单（不暂停）。500ms / 位移 ≤12px，只作用于非全屏视频舞台。
  final StageLongPressTracker _lpTracker = StageLongPressTracker();
  Timer? _lpTimer;
  bool _suppressStageTap = false;

  bool _menuVisible = false;
  late final AnimationController _menuAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kOverlayAnimMs),
      value: 1);
  // P1b §9：评论半屏面板（60% → 全屏 → 关闭）。打开时静音，关闭恢复。
  bool _commentVisible = false;
  bool _commentDragging = false;
  double _commentFraction = kCommentPanelClosedFraction;
  double _commentAnimFrom = 0;
  double _commentAnimTo = 0;
  late final AnimationController _commentAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: kOverlayAnimMs),
      value: 1);
  // 本机「不感兴趣」集合（写入 hidden_works_v1，刷新列表后不再出现）。
  final Set<String> _hiddenKeys = <String>{};
  // P0 §3：进度条是否处于「按住/拖动」态（与拖动 seek 合并为一次按下）。
  bool _seeking = false;
  double speed = 1.0;
  Timer? autoTimer;
  Timer? hideTimer;

  /// 0.9.72：功能区自动隐藏的截止时刻（见 [HideDeadline]）。
  final HideDeadline _hideDeadline = HideDeadline();
  // I3：起播静音淡入（定时器 + 代数，用户调音量/切条时立即作废）
  Timer? _fadeTimer;
  int _fadeGen = 0;
  // G12：加载超时 / 播放器报错提示与重试
  PlaybackFailure? _failure;
  Timer? _loadTimeout;
  /// 缓冲中：**唯一真源是相位**（[PlaybackPhase.buffering]）。
  ///
  /// 以前这里有 `_buffering` / `_slowBuffer` 两个 ValueNotifier（而且没有
  /// 任何 `ValueListenableBuilder` 消费，等于两个普通布尔量）外加 5 处写入。
  /// 相位里 `buffering` 事件早已就位，继续并行维护只会让两套说法分叉，
  /// 所以这里改为派生：相位进入 buffering 就是缓冲，离开就不是。
  bool get _buffering => _phase.showsBuffering;

  /// 弱网缓冲（缓冲超过 [slowBufferThreshold] 仍未恢复）。
  ///
  /// 这不是兜底定时器：它只做「同一个 buffering 相位持续了多久」的计时，
  /// 进入/离开缓冲都由相位驱动（见 [_feed]），计时本身不改变任何状态。
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
    PerfDiagnostics.instance.beginSpan('page:player');
    _fromAuthor = widget.fromAuthor;
    cur = widget.start;
    // owner 2026-11-24：沿用上次的播放设置（倍速/连播/循环/乱序）。
    // 先给默认值保证首帧可用，随后异步读回持久化覆盖。
    speed = AppSettings.defaultSpeed;
    unawaited(_restorePlaybackPrefs());
    _ensureMetaFor(_curLib);
    _bindPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus.requestFocus();
      PerfDiagnostics.instance.endSpan(
          'page:player', <String, Object?>{'works': widget.works.length});
      open(widget.start);
      // 预热作者头像索引：作品没带 av 时用作者级头像兜底。
      ensureAuthorAvatarsLoaded();
      // P2：进入非全屏播放页即开始沉浸计时。
      _scheduleImmersive();
    });
  }

  /// owner 2026-11-24：进播放页时读回上次的播放设置。
  ///
  /// 只覆盖用户可调的三个量（倍速/连播循环/乱序），不碰当前播放位置、
  /// 不解码任何媒体；读失败就保持默认值，不阻塞进页。
  ///
  /// 恢复后必须让预载与「连播是否开启」重新对齐：`open()` 是按当时的默认值
  /// 安排预载的，若上次记住的是「单条循环开（连播关）」，还留着预载就是白占
  /// 两个解码器槽位。反过来若回过连播开启，则要补一次预载。
  Future<void> _restorePlaybackPrefs() async {
    final p = await loadPlaybackPrefs();
    if (!mounted) return;
    setState(() {
      speed = p.speed;
      _link = p.link;
      shuffle = p.shuffle;
    });
    // 倍速要在播放器就绪后生效；未就绪时 open() 会带上当前 speed。
    try {
      player.setRate(speed);
    } catch (_) {}
    if (_link.nextEnabled) {
      _schedulePreload();
    } else {
      _cancelPreload();
    }
  }

  /// 把当前播放设置落盘（用户每次改动后调用）。
  void _persistPlaybackPrefs() {
    unawaited(savePlaybackPrefs(PlaybackPrefs(
      speed: speed,
      link: _link,
      shuffle: shuffle,
    )));
  }

  Future<void> _ensureMetaFor(String lib) async {
    if (lib.isEmpty || lib == _metaLib) return;
    _metaLib = lib;
    try {
      final m = await LibMeta.load(lib);
      if (mounted) setState(() => _meta = m);
    } catch (_) {}
  }

  // 作者 → 兜底头像缓存。此前每次 build 都全量扫作品列表，
  // 播放中位置每秒 setState 会把「作品数 × 4 次调用」重复扫一遍，
  // 上万条列表时会明显卡住主线程（iOS 上尤其明显）。
  final Map<String, String> _avatarFallbackCache = <String, String>{};
  Map<String, String>? _avatarFallbackIndex;
  // 0.9.77：索引对应的作品列表指纹（条数 + 首个作品 id）。
  // 只看条数会漏掉「同一位置换了一批作品」（切筛选/换排序），旧索引会张冠李戴。
  String _avatarFallbackKey = '';
  // 已建索引的作品条数：分页追加时只补新批次，避免每页都全量重扫。
  int _avatarFallbackBuilt = 0;

  /// 作品列表指纹：条数 + 首个作品 id（id 缺失时退回标题/类型）。
  String _worksFingerprint() {
    final n = widget.works.length;
    if (n == 0) return '0|';
    String keyOf(Map w) => '${w['id'] ?? w['i'] ?? w['t'] ?? ''}';
    return '$n|${keyOf(widget.works.first)}';
  }

  /// 指纹里「首个作品」的部分（去掉条数），用于判断是否为尾部追加。
  static String _fingerprintHead(String fp) {
    final i = fp.indexOf('|');
    return i < 0 ? '' : fp.substring(i + 1);
  }

  /// 播放页头像优先级（B3）：手动覆盖 > 作品自带 `av`/作者级头像 > 作品缩略图兜底。
  ///
  /// 兜底索引按「作者 → 首张可用图」预建一次，只在作品列表变化时重建/补新批次；
  /// 结果按作者名缓存，单次 build 内的多次调用都是 O(1)。
  /// 统一取作者名：作品字段缺失时（部分作品没有 `a`）从媒体路径里
  /// 的 `@作者` 段回退，避免「没头像、点头像也进不去作者页」。
  String authorNameOf(Map w) => authorNameFromWork(w);

  String avatarFor(Map w) {
    final name = authorNameOf(w);
    final av = '${w['av'] ?? ''}';
    // 作品没带作者名时无从查手动/作者级头像，只能用作品自带 `av`。
    if (name.isEmpty) return av;
    // 统一头像来源：与作者主页共用 AuthorAvatarStore（同一份作者头像）。
    // 只有作者确实没有头像时，才退到作品缩略图。
    final stored = AuthorAvatarStore.instance.pathFor(name);
    final manual = (stored != null && stored.isNotEmpty) ? stored : '';
    // B3：手动头像必须压过作品自带 `av`（爬虫结果），否则手动挑选会失效。
    if (manual.isNotEmpty) return manual;
    // 作者级头像（authors.json）：作品条目没带 av 时用它兜底。
    final byAuthor = authorAvatarIndex[name];
    final crawled = av.isNotEmpty
        ? av
        : ((byAuthor != null && byAuthor.isNotEmpty) ? byAuthor : '');
    // 有爬虫/作品自带头像就不用建兜底索引（避免为了兜底白扫一遍全部作品）。
    if (crawled.isNotEmpty) return crawled;
    // 先确保索引与当前作品列表一致，再查缓存：否则列表换了一批后
    // 旧缓存会先命中，索引永远不会被纠正（0.9.77 修复）。
    final fp = _worksFingerprint();
    if (_avatarFallbackIndex == null || _avatarFallbackKey != fp) {
      final n = widget.works.length;
      // 同一批作品只在尾部追加：保留旧索引，只补新作者，缓存也留着。
      final appended = _avatarFallbackIndex != null &&
          n > _avatarFallbackBuilt &&
          _fingerprintHead(fp) == _fingerprintHead(_avatarFallbackKey);
      if (appended) {
        addFirstThumbPerAuthor(
          _avatarFallbackIndex!,
          widget.works.skip(_avatarFallbackBuilt),
          thumbOf: workAvatarFallbackPath,
        );
      } else {
        _avatarFallbackIndex = authorFallbackThumbs(widget.works);
        // 整表重建：旧缓存里的作者可能已不在列表，清掉避免脏数据。
        _avatarFallbackCache.clear();
      }
      _avatarFallbackBuilt = n;
      _avatarFallbackKey = fp;
    }
    final cached = _avatarFallbackCache[name];
    var fb = (cached != null && cached.isNotEmpty) ? cached : '';
    if (fb.isEmpty) {
      fb = _avatarFallbackIndex![name] ?? '';
      if (fb.isNotEmpty) _avatarFallbackCache[name] = fb;
    }
    return resolveAuthorAvatarPath(fallback: fb);
  }

  /// 头像/兜底图归属的库：优先用媒体路径里的库 id，取不到再用当前库。
  String _avatarLibFor(String path) {
    final lib = libOfMediaPath(path);
    return lib.isEmpty ? _curLib : lib;
  }

  /// 把槽位上「已经发生过的」视频参数同步到页面状态。
  ///
  /// 预缓冲用 `open(play: false)`，首帧在切过去之前就解出来了：media_kit 的
  /// `videoParams` 事件不会重放，而页面是在 `_bindPlayer()` 之后才开始订阅。
  /// 不主动读一次的话 `_videoDw` 永远停在 0，海报层按「视频轨还没报尺寸」
  /// 一直盖着 —— 现象就是停在封面、音频在播、无任何报错。
  void _seedVideoParams(Player p) {
    try {
      final vp = p.state.videoParams;
      final info = parseVideoParams(
          dw: vp.dw, dh: vp.dh, aspect: vp.aspect, rotate: vp.rotate);
      if (info.displayWidth <= 1) return;
      _videoDw = info.displayWidth;
      // 尺寸已就绪，不需要再靠首帧事件重挂一次纹理。
      _videoGenSynced = true;
      final a = info.aspect;
      if (a == null || a <= 0) return;
      _videoAspect = a;
      _rememberPlayerAspect(_workAt(cur), a);
    } catch (_) {}
  }

  /// G18：监听当前活动槽位。切换预缓冲槽位时先解绑旧槽位，避免
  /// 旧播放器迟到的 completed/position 事件干扰新作品。
  void _bindPlayer({bool seedVideoParams = false}) {
    for (final s in _playerSubs) {
      s.cancel();
    }
    _playerSubs.clear();
    final p = player;
    p.setPlaylistMode(PlaylistMode.none);
    // 命中预缓冲槽位时，该媒体在 open(play:false) 阶段就已经解码出首帧，
    // videoParams 事件早在订阅之前发过了。只订阅「后续事件」会让
    // _videoDw 永远停在 0 → 海报层不撤 → 看着就是「卡在封面、音频在播」。
    if (seedVideoParams) _seedVideoParams(p);
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
      if (_workAt(cur)['t'] != 'v') return;
      if (v) {
        // 播放器报「在播」不等于画面在动：mpv 管线掉线时仍会报 playing=true。
        // 所以这里不再取消健康检查、也不清空自救计数——统一交给
        // _scheduleStartupCheck 用「位置是否前进」判定，进度确认后才清零。
        if (paused &&
            !_userPaused &&
            !_pausedByBackground &&
            _failure == null) {
          _feed(PlaybackEvent.play);
          setState(() => _pausedIntent = false);
        }
        return;
      }
      // 播放器报「不在播放」≠ 用户想暂停。只有用户/后台/失败意图才采信，
      // 其余（弱网卡顿、解码器被系统回收、音频设备切换）走自救流程，
      // 避免界面被静默改成暂停后卡死。
      if (shouldAdoptPlayerPause(
          userPaused: _userPaused,
          backgroundPaused: _pausedByBackground,
          failed: _failure != null,
          opening: _opening)) {
        _feed(PlaybackEvent.pause);
        if (!paused) setState(() => _pausedIntent = true);
        return;
      }
      PauseTrace.mark('stall:playing=false');
      _scheduleStallCheck();
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
      // 位置流每 100ms 左右触发一次。pos 走 ValueNotifier，进度条自己
      // 订阅重绘；不再 setState 重建整页（视频层/信息区/任务栏保持不动）。
      // owner 2026-11-20：若能遮住解码预热的黑帧，等 0.5 秒是可接受的。
      // 采用 500ms 位置门槛 + 短淡出，兼顾「不露黑」与「不拖沓」。
      if (!_firstFrameSeen && position.inMilliseconds >= 500) {
        _firstFrameSeen = true;
        _feed(PlaybackEvent.progress);
        final t0 = _openStartedAt;
        if (t0 != null) {
          _openStartedAt = null;
          // 起播耗时：open() 下发 → 位置确认前进 0.5s。命中池与全新 open
          // 都走这一条，`pool=1` 即池命中，下一轮直接用这个数验收。
          PauseTrace.mark('firstframe:ms=${DateTime.now().difference(t0).inMilliseconds}'
              ' pool=${_poolHit ? 1 : 0}');
        }
        if (mounted) setState(() {});
      }
      pos = position;
    });
    subDur = p.stream.duration.listen((d) {
      if (!identical(p, player)) return;
      if (d.inMilliseconds > 0) {
        _loadTimeout?.cancel();
        _loadTimeout = null;
      }
      // 时长同样只喂给进度条，不触发整页重建。
      dur = d;
    });
    if (subPos != null) _playerSubs.add(subPos!);
    if (subDur != null) _playerSubs.add(subDur!);
    // G12：播放器报错（解码失败/流打不开）直接给出可重试提示，
    // 不再无限转圈；错误可能来自上一条媒体，切条后自动清除。
    _playerSubs.add(p.stream.error.listen((msg) {
      if (!identical(p, player)) return;
      if (!mounted || _failure != null) return;
      // 留原始错误文本给 [_errorDigest]：分类只存名字没法定位，
      // 而原始文本又要剥掉 URL 才能进日志（隐私红线）。
      // `stream.error` 这里发的是纯字符串（后端已把 cause 折进文本），
      // 直接留原文即可；脱敏在 `_errorDigest` 里统一做。
      _lastPlayerError = '$msg';
      final failure = classifyPlaybackError(msg);
      // F34：模拟器/个别解码器上硬件解码失败时，先用软件解码重试一次
      if (_shouldSoftRetry(failure.kind)) {
        _retryWithSoftwareDecode();
        return;
      }
      _showFailure(failure);
    }));
    // mpv 内部日志：`stream.error` 只说「打不开」，说不出「为什么打不开」。
    // 订阅 log 流把 error/warn/fatal 的**措辞**留成脱敏尾部，失败时整段
    // 落盘（401/404/timeout/protocol/decoder 一眼可分）。只收这三档，
    // info/v 级会把每帧时钟都吐出来，落盘等于淹掉日志。
    _playerSubs.add(p.stream.log.listen((log) {
      if (!identical(p, player)) return;
      final line = mpvLogDigest(
          prefix: log.prefix, level: log.level, text: log.text);
      if (line == null) return;
      _mpvTail = pushMpvDigest(_mpvTail, line);
    }));
    // G12：弱网缓冲提示 —— 缓冲超过阈值才显示，避免正常起播闪一下
    _playerSubs.add(p.stream.buffering.listen((b) {
      if (!identical(p, player)) return;
      if (!mounted) return;
      // 缓冲起止只喂事件，缓冲态本身由相位表达（[_feed] 里统一处理
      // 弱网计时与复位），监听回调不再自己维护布尔量。
      _feed(b ? PlaybackEvent.bufferStart : PlaybackEvent.bufferEnd);
    }));
    // O4：跟踪视频显示宽高比，供手机端任务栏贴画面下沿。
    _playerSubs.add(p.stream.videoParams.listen((vp) {
      if (!identical(p, player)) return;
      if (!mounted) return;
      final info = parseVideoParams(
          dw: vp.dw, dh: vp.dh, aspect: vp.aspect, rotate: vp.rotate);
      _videoDw = info.displayWidth;
      // 纹理参数第一次到达 = 真正的输出尺寸有了；此时重挂一次 Video，
      // 让纹理挂到已就绪的控制器上（否则首播可能一直黑屏，重进才好）。
      if (_videoDw > 1 && !_videoGenSynced) {
        _videoGenSynced = true;
        setState(() => _videoGen++);
      }
      final a = info.aspect;
      if (a == null || a <= 0) return;
      final curWork = _workAt(cur);
      final before = _videoAspectFor(curWork);
      _rememberPlayerAspect(curWork, a);
      // 拉伸判据（非内容判据）：渲染框按源比例算，正常应为 0。
      // 一旦 >2%，说明有人把框的宽度/高度夹住了，画面必定变形。
      // 记一条可量化日志，验收不必看画面。
      final dist = videoDistortion(
          sourceAspect: a, base: videoBaseSize(aspect: a));
      if (dist > kStretchTolerance) {
        PauseTrace.mark('stretch:dist=${(dist * 100).toStringAsFixed(2)}%');
      }
      // 已是同一比例（或只在 2% 内摆动）就不重排，避免像素级跳动。
      if (before != null && (before - a).abs() / before < 0.02) return;
      setState(() => _videoAspect = a);
    }));
  }

  /// 当前条前后各 3 条的封面预取（只进图片缓存，不占解码器）。
  ///
  /// 抖音「连续秒切」的关键不是开了很多播放器，而是**任何一页都有封面兜着**；
  /// 解码器只有 3 个，但封面可以是任意多条。
  int _coverPrefetchFor = -1;

  void _prefetchNeighborCovers() {
    if (!mounted) return;
    if (_coverPrefetchFor == cur) return;
    _coverPrefetchFor = cur;
    final memW = _posterDecodeWidth(context);
    final previewW =
        workCardDecodeWidth(MediaQuery.devicePixelRatioOf(context));
    for (var d = -3; d <= 3; d++) {
      final i = cur + d;
      if (i < 0 || i >= widget.works.length) continue;
      final it = _workAt(i);
      final lib = _libFor(it);
      // 与网格/海报同一个解析入口（th → 图文首图 → 抽帧），否则缺 th 的
      // 视频在这里就被跳过，进页时底图照样是空的。
      final cover = _posterCoverUrl(it, lib: lib);
      if (cover.isEmpty) continue;
      if (d == 0) {
        // 当前条只要那张「网格尺寸」底图：它就是播放页海报的 placeholder，
        // 命中后首帧零等待；从作者页/深链直接进播放页时也能提前缓存。
        try {
          precacheImage(
            thumbImageProvider(
              withImageWidth(cover, kWorkImageWidth),
              decodeWidth: previewW,
              headers: cfg.headersFor(lib),
              cacheManager: DiziCache.manager,
            ),
            context,
            onError: (_, __) {},
          );
        } catch (_) {}
        continue;
      }
      try {
        precacheImage(
          CachedNetworkImageProvider(
            withImageWidth(cover, kPlayerImageWidth),
            headers: cfg.headersFor(lib),
            cacheManager: DiziCache.manager,
            maxWidth: memW,
          ),
          context,
          onError: (_, __) {},
        );
      } catch (_) {}
    }
  }

  /// 播放器报「不在播放」后，等一小段确认是真空转，再决定是否自救。
  ///
  /// 很多暂停是瞬时的（切清晰度、音频设备重连、NAS 一次读超时），
  /// 立刻重开会打断正在缓冲的播放器，所以先等 1.2s；期间恢复播放则取消。
  void _scheduleStallCheck() {
    _stallTimer?.cancel();
    // 本次检查允许的自救次数（起播确认与「播放中掉线」预算不同，
    // 补 play 后复查要沿用同一份预算，避免绕过上限）。
    _stallCheckMax = _stallMaxAttempts;
    final my = _openToken;
    // owner 2026-11-20：mpv 在缓冲/换码流期间会短暂报 playing=false，
    // 只看这个标志会把「正在播」误判成「卡死」，于是重开媒体 →
    // 用户看到的就是「明明放出来了又退回去转圈」。以位置是否前进为准。
    final baseMs = pos.inMilliseconds;
    _stallTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || my != _openToken) return;
      if (_opening || _failure != null) return;
      if (_workAt(cur)['t'] != 'v') return;
      if (_userPaused || _pausedByBackground || !_appForeground) return;
      var playing = false;
      var hasMedia = dur.inMilliseconds > 0 || pos.inMilliseconds > 0;
      try {
        playing = player.state.playing;
        hasMedia = hasMedia ||
            player.state.duration.inMilliseconds > 0 ||
            player.state.position.inMilliseconds > 0;
      } catch (_) {}
      var atMs = pos.inMilliseconds;
      try {
        final cur2 = player.state.position.inMilliseconds;
        if (cur2 > atMs) atMs = cur2;
      } catch (_) {}
      // 位置有前进 = 实际在播，不再动作
      if (atMs - baseMs >= 300) {
        _stallAttempts = 0;
        return;
      }
      if (playing) return;
      _applyStallRecovery(
        stallRecoveryAction(
          userPaused: _userPaused,
          backgroundPaused: _pausedByBackground,
          failed: _failure != null,
          opening: _opening,
          appForeground: _appForeground,
          playerPlaying: playing,
          hasMedia: hasMedia,
          attempts: _stallAttempts,
          maxAttempts: _stallMaxAttempts,
        ),
      );
    });
  }

  /// 起播确认：播放命令发出后，用「位置是否前进」确认真的放起来了。
  ///
  /// 与 [_scheduleStallCheck] 共用同一个 `_stallTimer`（不新增守卫/兜底定时器），
  /// 区别只在触发点：这里是 open 完成、play() 已返回，那里是播放器报
  /// playing=false。判据统一为「一个窗口内位置没前进 ≥300ms」。
  ///
  /// 为什么不能看 playing：mpv 在管线卡死时仍可能报 playing=true，旧逻辑
  /// 会因此直接 return，页面就永久停在封面、也没有任何提示。
  ///
  /// 自救上限取 2（补 play 两次），不做 reopen：起播阶段重开整条媒体在
  /// 机械盘上要重读一遍文件头，代价远大于收益，2 次仍不动就直接给
  /// 可见的失败态（可点重试）。
  void _scheduleStartupCheck(
      {int? limit,
      int bufferBase = -1,
      int fillWaits = 0,
      int warmWaits = 0}) {
    _stallTimer?.cancel();
    final max = limit ?? (_stallMaxAttempts - 1);
    _stallCheckMax = max;
    final my = _openToken;
    final baseMs = pos.inMilliseconds;
    _stallTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || my != _openToken) return;
      if (_failure != null) return;
      if (_workAt(cur)['t'] != 'v') return;
      if (_userPaused || _pausedByBackground || !_appForeground) return;
      // 打开/缓冲期间还不能判定「卡死」：大文件（如 3.3 GB / 25 Mbps）
      // 首帧要等 demuxer 缓存填满，这时位置本来就还没前进。旧逻辑在这两
      // 种状态下直接 return，等于把唯一的起播观察点扔掉了 —— 真卡住时
      // 反而没有任何复查，页面就停在封面。改成用同一个 _stallTimer 继续
      // 观察，不新增第二个守卫。
      if (_opening || _buffering) {
        _scheduleStartupCheck(
            limit: max,
            bufferBase: bufferBase,
            fillWaits: fillWaits,
            warmWaits: warmWaits);
        return;
      }
      var atMs = pos.inMilliseconds;
      var hasMedia = dur.inMilliseconds > 0 || pos.inMilliseconds > 0;
      var bufferMs = 0;
      var completed = false;
      try {
        completed = player.state.completed;
        final st = player.state.position.inMilliseconds;
        if (st > atMs) atMs = st;
        // 解封装缓存：大文件（3.3 GB / 25 Mbps）首帧前位置一直是 0，
        // 但 demuxer 缓存会持续增长。它增长说明文件在读、不是卡死。
        bufferMs = player.state.buffer.inMilliseconds;
        hasMedia =
            hasMedia || player.state.duration.inMilliseconds > 0 || st > 0;
      } catch (_) {}
      if (completed) return;
      // 位置没前进时分两种「还没起播」：数据没到位（缓存没覆盖当前位置、
      // 但仍在增长）→ filling；数据早已到位（缓存已覆盖当前位置，I/O 不是
      // 瓶颈）→ warming。旧判据只看缓存增量，整段已缓存的条目增量可能为 0，
      // 反而比冷文件更早被判成卡死。两条都继续用同一个 _stallTimer 观察，
      // 各自限额；只有数据侧完全无进展才判卡死。
      final bufBase = bufferBase < 0 ? 0 : bufferBase;
      final signal = startupSignal(
        positionMs: atMs,
        basePositionMs: baseMs,
        bufferMs: bufferMs,
        baseBufferMs: bufBase,
        fillWaits: fillWaits,
        warmWaits: warmWaits,
      );
      switch (signal) {
        case StartupSignal.advancing:
          // 位置在走 = 真的在播：恢复自救计数后收工。
          _stallAttempts = 0;
          return;
        case StartupSignal.warming:
          _stallAttempts = 0;
          PauseTrace.mark('startup:warm buffer=$bufferMs '
              'cover=${bufferMs - atMs} waits=$warmWaits');
          _scheduleStartupCheck(
              limit: max,
              bufferBase: bufferMs,
              fillWaits: fillWaits,
              warmWaits: warmWaits + 1);
          return;
        case StartupSignal.filling:
          _stallAttempts = 0;
          PauseTrace.mark('startup:filling buffer=$bufferMs waits=$fillWaits');
          _scheduleStartupCheck(
              limit: max,
              bufferBase: bufferMs,
              fillWaits: fillWaits + 1,
              warmWaits: warmWaits);
          return;
        case StartupSignal.stalled:
          break;
      }
      PauseTrace.mark('stuck:startup id=${_watchIdFor(_workAt(cur))} '
          'userPaused=$_userPaused hasMedia=$hasMedia buffer=$bufferMs '
          'cover=${bufferMs - atMs} fill=$fillWaits warm=$warmWaits '
          'attempts=$_stallAttempts');
      _applyStallRecovery(
        stallRecoveryAction(
          userPaused: _userPaused,
          backgroundPaused: _pausedByBackground,
          failed: _failure != null,
          opening: _opening,
          appForeground: _appForeground,
          playerPlaying: false,
          hasMedia: hasMedia,
          attempts: _stallAttempts,
          maxAttempts: max,
        ),
        maxAttempts: max,
      );
    });
  }

  /// 执行自救：先补 play，再重开当前媒体，最多 [_stallMaxAttempts] 次。
  Future<void> _applyStallRecovery(StallRecoveryAction action,
      {int maxAttempts = _stallMaxAttempts}) async {
    switch (action) {
      case StallRecoveryAction.none:
        if (_stallAttempts >= maxAttempts && !_userPaused) {
          // 自救用尽：不再静默停住，给出明确可重试的失败态。
          PauseTrace.mark('stall:giveup');
          _showFailure(unknownFailure);
        }
        return;
      case StallRecoveryAction.retryPlay:
        _stallAttempts++;
        PauseTrace.mark('stall:retryPlay#$_stallAttempts');
        _feed(PlaybackEvent.play);
        if (paused) setState(() => _pausedIntent = false);
        try {
          final at = pos.inMilliseconds > 800 ? pos : player.state.position;
          if (at.inMilliseconds > 800) await player.seek(at);
          await player.setRate(speed);
          await player.play();
        } catch (_) {}
        // 补 play 后复查：仍然不动就继续计数，直到给出失败态。
        if (mounted) _scheduleStartupCheck(limit: _stallCheckMax);
        return;
      case StallRecoveryAction.reopen:
        _stallAttempts++;
        PauseTrace.mark('stall:reopen#$_stallAttempts');
        if (_stallAttempts > _stallMaxAttempts) return;
        await open(cur, saveProgress: false);
        return;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!Platform.isWindows) return;
    if (!_winResizing) setState(() => _winResizing = true);
    _winResizeTimer?.cancel();
    _winResizeTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      // 只恢复视频层，不换 key、不重建 Video：重建会把纹理重新挂载一次，
      // 在切全屏/进新页面的瞬间最容易触发原生崩溃。纹理本身会跟随尺寸自适应。
      setState(() => _winResizing = false);
    });
  }

  void didChangeAppLifecycleState(AppLifecycleState state) {
    // G16：切后台/最小化时自动暂停（先落盘位置），回前台再恢复；
    // O3：移动端仅 paused 暂停——iOS 的 inactive 会被控制中心、通知横幅、
    // 本地网络授权弹窗瞬时触发，不再采信。
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (shouldPauseInBackground(state: state.name, isMobile: isMobile)) {
      _appForeground = false;
      _stallTimer?.cancel();
      _pauseForBackground(reason: state.name);
      // L13：退出/关闭进程时 pause 不一定来得及生效，直接停掉所有槽位避免尾音。
      if (state.name == 'detached') {
        for (final s in _slots) {
          try {
            s.player.stop();
          } catch (_) {}
        }
      }
      return;
    }
    if (state == AppLifecycleState.resumed && mounted) {
      _appForeground = true;
      _stallAttempts = 0;
      PauseTrace.mark('lifecycle:resumed');
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
  ///
  /// [reason] 为生命周期状态名，写进暂停轨迹便于区分「最小化」与「来电」。
  void _pauseForBackground({String reason = 'unknown'}) {
    // G10：切后台/最小化前落盘，避免异常退出丢进度
    _saveWatchProgress(force: true);
    if (widget.works.isEmpty || _failure != null) return;
    // 用户自己暂停的保持原状，回前台不自动播放
    if (paused) return;
    _pausedByBackground = true;
    _userPaused = false;
    pauseAuto();
    PauseTrace.mark('background:$reason');
    try {
      Breadcrumb.mark('player:pause', 'L7706');
      player.pause();
    } catch (_) {}
    _feed(PlaybackEvent.pause);
    if (mounted) setState(() => _pausedIntent = true);
  }

  /// G16：只恢复「因切后台暂停」的播放，并从记忆位置继续。
  void _resumeFromBackground() {
    _pausedByBackground = false;
    if (!mounted) return;
    PauseTrace.mark('background:resume');
    final isV = _workAt(cur)['t'] == 'v';
    _feed(PlaybackEvent.play);
    setState(() => _pausedIntent = false);
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

  /// 推进播放相位（第 1 步：与旧布尔量并行，只记录不显示）。
  ///
  /// owner 2026-11-23 要求停止「补丁堆叠」。这里的做法是把散落的
  /// `loading / paused / _buffering` 写入点收敛成一个事件入口，
  /// 相位由 [nextPhase] 纯函数推进，避免各处 `if` 各自拍脑袋。
  ///
  /// 起播 loading 已由 [loading] 派生自相位（单一真源）；[paused] 则相反，
  /// 它是**用户意图**（点暂停/切后台/失败），相位由意图与播放器事件共同
  /// 推出。这里只核对「真矛盾」：相位说暂停而意图是播放，或相位说在播
  /// 而意图是暂停——ready/opening 这些过渡相位不参与比对，避免把正常
  /// 过渡记成告警淹没真正的问题。
  void _feed(PlaybackEvent e) {
    final next = nextPhase(_phase, e);
    if (next == _phase) return;
    _phase = next;
    // 弱网计时跟着相位走：只在「刚进入缓冲」时起表，离开缓冲立刻复位。
    // 这样 `_slowBuffer` 不可能与相位分叉，也不需要各处手动清。
    // 它只作为「跳过预热」的判断输入（见 [_scheduleVideoPrefetch]），
    // 不参与任何渲染，所以这里不需要 setState。
    if (next == PlaybackPhase.buffering) {
      if (!_slowBuffer) {
        _slowBufferTimer?.cancel();
        _slowBufferTimer = Timer(slowBufferThreshold, () {
          if (!mounted) return;
          if (_phase != PlaybackPhase.buffering) return;
          _slowBuffer = true;
        });
      }
    } else {
      _slowBufferTimer?.cancel();
      _slowBufferTimer = null;
      _slowBuffer = false;
    }
    final wantsPause = next == PlaybackPhase.paused;
    final wantsPlay = next.isActivelyPlaying;
    final contradiction = (wantsPause && !paused) || (wantsPlay && paused);
    if (contradiction) {
      _phaseMismatch = 'phase=${next.name} paused=$paused';
      Breadcrumb.mark('phase:mismatch', _phaseMismatch);
    } else if (_phaseMismatch.isNotEmpty) {
      _phaseMismatch = '';
    }
  }

  // G12：展示失败提示并停止转圈；重试时整条媒体重新打开。
  void _showFailure(PlaybackFailure raw) {
    if (!mounted) return;
    _loadTimeout?.cancel();
    _loadTimeout = null;
    _cancelVideoPrefetch();
    // 唯一校正口：`stream.error` 只能说「打不开」，分类只能靠措辞猜；
    // 但 mpv 内部日志带着真实的 HTTP 状态（我们实测到这里是 404）。
    // 不校正的话：「服务器上没有这个文件」会被显示成「网络连接失败」，
    // 用户按提示查网络永远查不出来，而重试按钮也永远不会成功。
    final f = withTransportStatus(raw, httpStatusFromMpvTail(_mpvTail));
    // 分类结果要留，但只有 `failure:network` 这三个字无法定位问题：
    // 本轮就卡在这里——`pause.log` 只记了分类名，原始错误文本一个字没留，
    // 于是「到底是解码器不支持 x86、还是取流被拒」完全无从判断。
    // 记一条脱敏摘要（剥掉 URL/路径/文件名，只留错误措辞）。
    PauseTrace.mark(
        'failure:${f.kind.name} detail=${sanitizePlaybackErrorForLog(_lastPlayerError)}');
    // 地址形状：只记长度/非 ASCII 数/空格数/转义数/协议/端口，
    // **不记地址本身**。用来分辨「打不开」是否与地址形态相关（未转义空格、
    // 非 ASCII 字节、协议被拒），而这一判断不需要看到媒体路径。
    if (_openMediaUrl.isNotEmpty) {
      PauseTrace.mark('media:${describeUrlShape(urlShapeOf(_openMediaUrl))}');
    }
    // mpv 自己的报错尾部：`stream.error` 只说「Failed to open」，说不出
    // 是 401/404/超时/协议/解码。这几行直接把「哪一层失败」写进日志。
    final tail = _mpvTail.length > kMpvTailReportMax
        ? _mpvTail.sublist(_mpvTail.length - kMpvTailReportMax)
        : _mpvTail;
    for (final line in tail) {
      PauseTrace.mark('mpv: $line');
    }
    // 失败的槽位不能继续当作「已就绪」留在池里，否则切条会命中一个
    // 出不了画的槽位；重试走 open() 会重新登记。
    _preloadCache.removeSlot(_active.sid);
    try {
      Breadcrumb.mark('player:pause', 'L7783');
      player.pause();
    } catch (_) {}
    _feed(PlaybackEvent.error);
    setState(() {
      _failure = f;
      _pausedIntent = true;
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
    PauseTrace.mark('decode:rebuild-software');
    _softwareDecodeRetried = true;
    _decodeMode = DecodeMode.software;
    // 这里整体重建槽位，所有旧槽位随后统一 dispose；只作废预载计划，
    // 不走 _cancelPreload（否则非活动槽位会被释放两次）。
    _invalidatePreload();
    final old = List<_PlaybackSlot>.from(_slots);
    _cancelPreload();
    _preloadBusy.clear();
    _stallTimer?.cancel();
    _stallAttempts = 0;
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
    PerfDiagnostics.instance.slotsReleased(old.length);
    if (!mounted) return;
    // 软解重试＝重开一条媒体：相位回到 opening，由后续 mediaReady/play 推进。
    _feed(PlaybackEvent.open);
    setState(() {
      _failure = null;
      _pausedIntent = false;
    });
    await open(cur);
  }

  void _retryPlayback() {
    if (!mounted) return;
    _loadTimeout?.cancel();
    // 失败后重试同样是一次重开（相位随之离开 buffering，弱网态自动复位）。
    _feed(PlaybackEvent.open);
    setState(() {
      _failure = null;
    });
    open(cur);
  }

  /// M6：作废正在进行的预加载计划（保留已就绪缓存）。
  void _invalidatePreload() {
    _preloadTimer?.cancel();
    _preloadTimer = null;
    _preloadGen++;
  }

  /// 清空预加载缓存并释放所有非活动槽位（关闭连播/单条循环等场景）。
  ///
  /// 此前只 `stop()` 不释放：关闭连播后这些播放器仍常驻（最多 9 个、
  /// 每个带 32MB 缓冲与一个视频控制器），iOS 上内存/解码器压力很大。
  /// 现在直接 dispose 并从槽位表移除；下次需要预载时按需重建。
  /// 正在预载（[_preloadBusy]）的槽位不在这里动，交给任务自己收尾。
  void _cancelPreload({bool stopIdle = true}) {
    _invalidatePreload();
    if (!stopIdle) return;
    _releaseSlots((_) => true);
  }

  /// 把「某槽位现在装着哪一条」写入缓存账本。
  ///
  /// 池计划（[planPreloadPool]）只认账本判断条目是否常驻，所以活动槽位与
  /// 刚停靠的旧活动槽位都必须登记；否则池计划会把它们当空槽重新 open。
  /// 同一槽位只保留一条登记（先清后写），避免 sid 复用时出现两条记录。
  void _markSlotResident(int sid, int index, String key) {
    if (key.isEmpty || index < 0) return;
    _preloadCache.removeSlot(sid);
    _preloadCache.put(PreloadEntry(slot: sid, index: index, key: key));
  }

  /// 释放满足 [pick] 的非活动槽位：stop + dispose，并从槽位表移除。
  ///
  /// 这是槽位释放的唯一路径（[_cancelPreload] 与池计划释放共用）。
  /// 0.9.156 之前这里有两个缺陷：
  /// 1. `_preloadBusy` 是按 `_PlaybackSlot` 对象索引的，却用 `s.sid` 去查，
  ///    判断永远为 false → 正在预载的槽位会被 dispose（预载随即失败）；
  /// 2. `drop` 收集表从未写入，于是播放器被 dispose 了却仍留在 `_slots`，
  ///    变成「幽灵槽位」——后续 `_slotForPreload()` 会把它再分配出去，
  ///    预载在已释放的播放器上 open → 异常 → 缓存永远登记不上。
  /// 两者叠加的结果就是「池里看着有播放器、切条却一次都没命中」。
  int _releaseSlots(bool Function(_PlaybackSlot s) pick) {
    final activeSid = _active.sid;
    final drop = <_PlaybackSlot>[];
    for (final s in _slots) {
      // 用对象身份判断，避免 sid 复用（解码重建/槽位回收）时误停正在播放的槽位。
      if (identical(s, _active)) continue;
      // 正在预载的槽位交给预载流程自己收尾（按对象身份）。
      if (_preloadBusy.containsKey(s)) continue;
      if (!pick(s)) continue;
      drop.add(s);
    }
    if (drop.isEmpty) return 0;
    for (final s in drop) {
      _preloadCache.removeSlot(s.sid);
      PauseTrace.mark('preload:stop-idle(sid=${s.sid})');
      try {
        s.player.stop();
      } catch (_) {}
      try {
        s.player.dispose();
      } catch (_) {}
    }
    _slots.removeWhere(drop.contains);
    final idx = _slots.indexWhere((s) => s.sid == activeSid);
    _slotActive = idx < 0 ? 0 : idx;
    PerfDiagnostics.instance.slotsReleased(drop.length);
    return drop.length;
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
    if (AppSettings.preloadPerSide <= 0) {
      // 预加载已关闭：顺手释放之前常驻的空闲槽位。
      _cancelPreload();
      return;
    }
    if (widget.works.length <= 1) return;
    final gen = _preloadGen;
    // owner 2026-11-19：起播 300ms 后就开始预载相邻条（原 600ms），
    // 缩短 iOS 滑动时的黑屏窗口；预载仍是每侧 1 条，内存可控。
    // owner 2026-11-20：切条后立刻开始预载相邻条，不再等 300ms。
    // 留 120ms 只是让当前条的打开请求先拿到网络，不与它抢带宽。
    _preloadTimer = Timer(const Duration(milliseconds: preloadKickoffDelayMs), () {
      if (gen == _preloadGen) _runPreloads();
    });
  }

  /// 线③：起播稳定后，用 HTTP Range 轻量预热前后相邻视频（最多 2 条）。
  /// 不做解码、不开播放器；弱网/缓冲中直接跳过。
  void _scheduleVideoPrefetch() {
    _cancelVideoPrefetch();
    if (widget.works.length <= 1) return;
    final my = _openToken;
    _videoPrefetchTimer = Timer(videoPrefetchDelay, () {
      if (!mounted || my != _openToken) return;
      final w = _workAt(cur);
      if (!shouldRunVideoPrefetch(
        isVideo: w['t'] == 'v',
        buffering: _buffering,
        slowBuffer: _slowBuffer,
        loading: loading,
        enabled: true,
        count: widget.works.length,
      )) {
        return;
      }
      final targets = videoPrefetchTargets(
        index: cur,
        count: widget.works.length,
        isVideo: (i) => _workAt(i)['t'] == 'v',
        mediaPath: (i) => preloadMediaPath(_workAt(i)) ?? '',
        direction: _preloadDir,
      );
      if (targets.isEmpty) return;
      _videoPrefetch.start(targets.map((t) {
        final tw = _workAt(t.index);
        final lib = _libFor(tw);
        return VideoPrefetchTask(
          url: cfg.mediaUrl(t.path, lib: lib),
          headers: cfg.headersFor(lib),
          key: '$lib|${tw['id'] ?? ''}|${t.path}',
        );
      }));
    });
  }

  void _cancelVideoPrefetch() {
    _videoPrefetchTimer?.cancel();
    _videoPrefetchTimer = null;
    _videoPrefetch.cancel();
  }

  int get _preloadByteLimit => AppSettings.preloadMemoryMb * 1024 * 1024;

  /// 为预加载挑一个槽位，按「长池 → 复用空闲 → 淘汰池外条目」三级。
  ///
  /// 0.9.157 之前的顺序把「淘汰」放在第一步：预算还剩 3 个槽位时，第二条
  /// 预载也会先把刚就绪的最近邻淘汰掉再复用同一个槽位，于是池里永远只剩
  /// 「最后预载的那一条」。真机日志即为此：`ready(i=1)` → `stop-idle` →
  /// `ready(i=2)` 都在同一个 `sid=1` 上，滑到下一条时池必然不命中。
  ///
  /// [keepKeys] 是池计划声明要常驻的条目键：即便走到淘汰，也不能拿它们
  /// 当牺牲品（否则计划与分配各说一套）。
  _PlaybackSlot? _slotForPreload({Set<String> keepKeys = const <String>{}}) {
    final maxSlots = preloadSlotBudget(AppSettings.preloadMemoryMb);
    // 一、预算未满就长池：只要还能放得下一条，就不该为了省一个槽位去
    // 淘汰已经解码好的邻居。
    if (_slots.length < maxSlots &&
        _preloadCache.canFit(preloadEntryBytes, byteLimit: _preloadByteLimit)) {
      final sid = _slotSeq++;
      final s = _PlaybackSlot('s$sid', sid: sid, mode: _decodeMode);
      _slots.add(s);
      return s;
    }
    // 二、复用完全空闲的槽位（没有缓存条目的）。
    for (final s in _slots) {
      if (identical(s, _active)) continue;
      if (_preloadBusy.containsKey(s)) continue;
      if (_preloadCache.containsSlot(s.sid)) continue;
      return s;
    }
    // 三、池已满：淘汰最远、且不在池计划内的条目。
    final victim = _preloadCache.evictionSlot(
      current: cur,
      direction: _preloadDir,
      protectedSlots: <int>{_active.sid},
      protectedKeys: <String>{..._preloadBusy.values, ...keepKeys},
    );
    if (victim != null) {
      final slot = _slotBySid(victim);
      _preloadCache.removeSlot(victim);
      if (slot != null &&
          !identical(slot, _active) &&
          !_preloadBusy.containsKey(slot)) {
        return slot;
      }
    }
    // 四、最后兜底：任意非活动、非忙的槽位（缓存账本已不可信时用）。
    for (final s in _slots) {
      if (identical(s, _active)) continue;
      if (_preloadBusy.containsKey(s)) continue;
      _preloadCache.removeSlot(s.sid);
      return s;
    }
    return null;
  }

  /// 在槽位中静音打开目标媒体，等到解封装/首帧就绪后登记缓存。
  /// 安全约束：预载绝不能动正在播放的槽位（按对象身份判断）；每个 await
  /// 之后都复查 generation/epoch/活动槽位，迟到的预载任务直接放弃。
  Future<bool> _preloadInto(
      _PlaybackSlot slot, int idx, String key, int gen, String path) async {
    final lib = _libFor(_workAt(idx));
    if (identical(slot, _active)) {
      PauseTrace.mark('preload:skip-active');
      return false;
    }
    _preloadBusy[slot] = key;
    final epoch = ++slot.epoch;
    try {
      PauseTrace.mark('preload:stop-idle(sid=${slot.sid})');
      await slot.player.stop();
      if (!mounted ||
          gen != _preloadGen ||
          slot.epoch != epoch ||
          identical(slot, _active)) {
        return false;
      }
      await slot.player.setVolume(0);
      slot.mediaUrl = cfg.mediaUrl(path, lib: lib);
      await slot.player.open(
        Media(slot.mediaUrl, httpHeaders: cfg.headersFor(lib)),
        play: false,
      );
      if (!mounted ||
          gen != _preloadGen ||
          slot.epoch != epoch ||
          identical(slot, _active)) {
        return false;
      }
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
      if (!ready) {
        // 解封装迟迟没给出时长：登记不上缓存 → 切条时必然重新 open。
        // 这条标记是真机判断「池为什么没命中」的第一手证据。
        PauseTrace.mark('preload:not-ready(sid=${slot.sid},i=$idx)');
        return false;
      }
      // 再给解码器一点时间铺好首帧，命中时直接出画面。
      await Future<void>.delayed(preloadFirstFrameDelay);
      if (!mounted ||
          gen != _preloadGen ||
          slot.epoch != epoch ||
          identical(slot, _active)) {
        return false;
      }
      _preloadCache.put(PreloadEntry(slot: slot.sid, index: idx, key: key));
      PauseTrace.mark('preload:ready(sid=${slot.sid},i=$idx)');
      return true;
    } catch (_) {
      try {
        await slot.player.stop();
      } catch (_) {}
      return false;
    } finally {
      _preloadBusy.remove(slot);
    }
  }

  Future<void> _runPreloads() async {
    if (!mounted || _preloadRunning) return;
    if (AppSettings.preloadPerSide <= 0) return;
    _preloadRunning = true;
    final gen = ++_preloadGen;
    try {
      // P3：池决策只走 `preload_pool.dart`（常驻哪几条 / 还缺哪几条），
      // 播放页只负责把计划落到槽位。槽位身份用「忙键 → 缓存键」两级，
      // 保证正在预载的条目不会被重复排队。
      String keyOf(int i) => preloadKeyFor(_workAt(i), _libFor(_workAt(i)));
      final plan = planPreloadPool(
        current: cur,
        count: widget.works.length,
        direction: _preloadDir,
        maxSlots: preloadSlotBudget(AppSettings.preloadMemoryMb),
        perSide: AppSettings.preloadPerSide,
        slots: <PoolSlotState>[
          for (final s in _slots)
            PoolSlotState(
              sid: s.sid,
              index: _preloadCache.entryOfSlot(s.sid)?.index ?? -1,
              key: _preloadBusy[s] ?? _preloadCache.keyOfSlot(s.sid) ?? '',
              busy: _preloadBusy.containsKey(s),
              active: identical(s, _active),
            ),
        ],
        keyOf: keyOf,
        hasMedia: (i) =>
            workPlayable(_workAt(i)) && preloadMediaPath(_workAt(i)) != null,
      );
      // 池计划是槽位生命周期的唯一决策源：池外空闲槽位立即释放，
      // 不再靠 `_slotForPreload()` 的「预算满就复用」隐式回收
      // （那条路径会留下仍在 `_slots` 里、却已被 stop 的槽位）。
      if (plan.release.isNotEmpty) {
        _releaseSlots((s) => plan.release.contains(s.sid));
      }
      // 池计划要常驻的条目是分配时的硬约束：走到淘汰也不能拿它们开刀。
      final keepKeys = <String>{for (final i in plan.hold) keyOf(i)};
      for (final idx in plan.preload) {
        if (!mounted || gen != _preloadGen) return;
        if (idx == cur || idx < 0 || idx >= widget.works.length) continue;
        final w = _workAt(idx);
        if (!workPlayable(w)) continue;
        final path = preloadMediaPath(w);
        if (path == null) continue;
        final key = preloadKeyFor(w, _libFor(w));
        if (_preloadCache.containsKey(key)) continue;
        if (_preloadBusy.containsValue(key)) continue;
        final slot = _slotForPreload(keepKeys: keepKeys);
        if (slot == null) return;
        await _preloadInto(slot, idx, key, gen, path);
      }
    } finally {
      _preloadRunning = false;
    }
  }

  Future<void> open(int i, {bool saveProgress = true}) async {
    if (widget.works.isEmpty || i < 0 || i >= widget.works.length) return;
    // 切条前的条目身份：旧活动槽位要被「停靠」进池，登记时用它的序号与键。
    final fromIndex = cur;
    final fromKey = preloadKeyFor(_workAt(cur), _libFor(_workAt(cur)));
    // 非用户暂停自救：正常切条/重开时重置计数；自救触发的 reopen 保留计数，
    // 否则「重开 → 又停 → 再重开」会无限循环。
    final switching = i != cur;
    _stallTimer?.cancel();
    _blackGuard?.cancel();
    if (switching) _resetOverlaysOnSwitch();
    if (switching) {
      _stallAttempts = 0;
      _videoAspect = null;
    }
    _userPaused = false;
    // 切条前先把上一条的进度落盘
    if (saveProgress) _saveWatchProgress(force: true);
    // 线③：切条/重开时立刻取消上一轮的相邻视频预取
    _cancelVideoPrefetch();
    // J5：切到其他作品时回到第一集
    if (i != cur) _chapter = 0;
    final w = _workAt(i);
    final wl = _libFor(w);
    _ensureMetaFor(wl);
    // G20：单条作品数据异常时不再调用播放器（避免未捕获异常卡死整页），
    // 只切到该条并展示占位，PageView 仍可继续上下滑。
    if (!workPlayable(w)) {
      _cancelPreload();
      _cancelVideoPrefetch();
      autoTimer?.cancel();
      _loadTimeout?.cancel();
      _slowBufferTimer?.cancel();
      _preloadTimer?.cancel();
      _preloadTimer = null;
      ++_openToken;
      _opening = false;
      _pendingPage = null;
      _mediaToken = -1;
      _pausedByBackground = false;
      PauseTrace.mark('open:stop-current(broken)');
      _preloadCache.removeSlot(_active.sid);
      try {
        await player.stop();
      } catch (_) {}
      if (!mounted) return;
      // 不可播放条目：没有媒体、也没有等待中的起播，相位必须明确落到
      // 「暂停」，不能留着上一条的 playing/opening。
      _feed(PlaybackEvent.open);
      _feed(PlaybackEvent.pause);
      setState(() {
        cur = i;
        _setPicIndex(0);
        captionOpen = false;
        _pausedIntent = true;
        _failure = null;
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
    // 换条时作废尚未执行的播放/暂停意图，避免上一条的暂停落到新视频上
    _playCmdDesired = null;
    _pausedByBackground = false;
    autoTimer?.cancel();
    _loadTimeout?.cancel();
    _preloadTimer?.cancel();
    _preloadTimer = null;
    manualPic = false;
    _pendingPage = null;
    _mediaToken = -1;
    _blackGuard?.cancel();
    _blackRebuilt = false;
    _videoDw = 0;
    _videoGenSynced = false;
    _firstFrameSeen = false;
    _opening = true;
    _openStartedAt = DateTime.now();
    // 换条后诊断摘要必须归零，否则新条目的失败会带上一条的错误文本。
    _lastPlayerError = null;
    // mpv 日志尾部同样归零：上一条的 401/404 不能算到下一条头上。
    _mpvTail = const <String>[];
    _openMediaUrl = '';
    _poolHit = canUsePreload;
    if (canUsePreload) _openMediaUrl = cachedSlot.mediaUrl;
    // 预载命中：媒体早已在解码器里解出首帧，open 只是换槽位，不存在
    // 「等待起播」阶段。若仍按 open 推进，相位停在 opening，与
    // `loading = !canUsePreload`（命中时为 false）长期冲突，自检会被这条
    // 假告警持续污染，之后真正的暂停/起播异常就淹没了。
    _feed(canUsePreload ? PlaybackEvent.mediaReady : PlaybackEvent.open);
    setState(() {
      cur = i;
      _setPicIndex(0);
      captionOpen = false;
      // 缓存命中 → mediaReady → 相位 ready，不再转圈；未命中 → opening 仍在转圈。
      _pausedIntent = false;
      // P2 §11：新页进度归零，绝不用上一条的进度渲染进度条。
      pos = Duration.zero;
      dur = Duration.zero;
      _failure = null;
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
      // 活动条也登记进账本：池计划只看账本判断常驻，活动槽位不入账就会
      // 被当成空槽，预载可能往它上面 open（或把它算成不存在）。
      _markSlotResident(target.sid, i, key);
      // 预缓冲槽位已解出首帧：把已有的视频参数同步过来（见 _seedVideoParams）。
      _bindPlayer(seedVideoParams: true);
      // 旧活动槽位不再 stop()：stop 会卸载媒体，它立刻变成池外空槽，下一轮
      // 预载又得为同一条重新 open（每次切条多一个解码器 + 一次 open，回滑的
      // 「秒开」只能等下一次预载）。改为停靠：暂停 + 静音，媒体留在解码器里，
      // 账本按它自己的序号/键登记，回滑直接命中。释放仍走 _releaseSlots()。
      if (!identical(old, target)) {
        _markSlotResident(old.sid, fromIndex, fromKey);
        PauseTrace.mark('open:park-old(sid=${old.sid},i=$fromIndex)');
        try {
          await old.player.pause();
          await old.player.setVolume(0);
        } catch (_) {}
      }
      _mediaToken = my;
      setState(() {
        pos = Duration.zero;
        final d0 = player.state.duration;
        dur = d0.inMilliseconds > 0 ? d0 : Duration.zero;
      });
    } else {
      PauseTrace.mark('open:stop-current');
      try {
        await player.stop();
      } catch (_) {}
    }
    if (my != _openToken) return;
    _refreshDrop('${w['id'] ?? ''}', my, wl);
    postStat('play', '${w['a'] ?? ''}', lib: wl);
    // L5-C：本机播放量（基础库自动封面取播放量最高的作品），顺手记住缩略图
    WorkPlaysStore.bump(
      wl,
      _watchIdFor(w),
      thumb: '${w['th'] ?? ''}'.trim(),
      kind: '${w['t'] ?? ''}'.trim(),
      at: DateTime.tryParse('${w['d'] ?? ''}')?.millisecondsSinceEpoch ?? 0,
    );
    if (!canUsePreload) {
      try {
        if (w['t'] == 'v') {
          _openMediaUrl = cfg.mediaUrl(workMediaPaths(w).first, lib: wl);
          await player.open(Media(_openMediaUrl, httpHeaders: cfg.headersFor(wl)));
        } else if ((w['au'] ?? '').toString().isNotEmpty) {
          _openMediaUrl = cfg.mediaUrl(w['au'].toString(), lib: wl);
          await player.open(Media(_openMediaUrl, httpHeaders: cfg.headersFor(wl)));
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
    if (!canUsePreload) {
      // 新开媒体（非池命中）：这一槽位的旧登记已随 stop() 失效，先作废；
      // 视频按实际条目重新登记，图文不占池位。
      _preloadCache.removeSlot(_active.sid);
      if (w['t'] == 'v') _markSlotResident(_active.sid, i, key);
    }
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

      // iOS：音频在走、视频轨却始终没有尺寸（黑屏有声）。先重建纹理，
      // 仍不出画面才降级软解；不主动强制软解。
      _blackGuard?.cancel();
      // owner 2026-11-22：Android 也会出现「有声音、画面卡在封面」——视频轨
      // 始终没报尺寸。看门狗原先只挂 iOS，现在两端都挂：先重建一次纹理，
      // 仍无画面才降级软解（真坏了才降级，不主动强制）。
      if ((Platform.isIOS || Platform.isAndroid) && w['t'] == 'v') {
        void check() {
          if (!mounted || my != _openToken || _failure != null) return;
          if (paused || loading || _videoDw > 1) return;
          var at = Duration.zero;
          try {
            at = player.state.position;
          } catch (_) {}
          if (at.inMilliseconds < 400) return;
          if (!_blackRebuilt) {
            _blackRebuilt = true;
            PauseTrace.mark('video:rebuild-texture');
            setState(() => _videoGen++);
            _blackGuard =
                Timer(const Duration(milliseconds: 2600), () => check());
            return;
          }
          PauseTrace.mark('video:soft-decode');
          _retryWithSoftwareDecode();
        }

        _blackGuard = Timer(const Duration(milliseconds: 2600), () => check());
      }
    }
    // 起播确认：play() 已返回不代表画面在动（个别作品 mpv 会一直报
    // playing=true 却不推进位置）。用同一个 _stallTimer 按位置复查，
    // 3 秒内起不来就给可见失败态，不再无限停在封面。
    if (w['t'] == 'v' && my == _openToken && _failure == null) {
      _scheduleStartupCheck();
    }
    if (mounted && my == _openToken && _failure == null) {
      _feed(PlaybackEvent.mediaReady);
      // 只有真要起播时才推进到 playing。后台打开的作品按设计要求保持
      // 暂停等回前台，此时喂 play 会让相位说「正在播放」而界面停在暂停，
      // 自检随即报假告警。
      final keepsPaused = paused && (w['t'] == 'v' || _pausedByBackground);
      _feed(keepsPaused ? PlaybackEvent.pause : PlaybackEvent.play);
      setState(() {
        // 若打开过程中被切到后台，保持暂停，等回前台再恢复
        if (w['t'] != 'v' && !_pausedByBackground) _pausedIntent = false;
      });
    }
    // 后台打开的作品不启动图文轮播，等回前台再按用户状态恢复
    if (w['t'] != 'v' && !paused) startAuto();
    // G18：起播稳定后再预缓冲下一条，避免和当前条抢带宽
    _schedulePreload();
    // 线③：同时轻量预热相邻视频头部（HTTP Range，不占播放器）
    _scheduleVideoPrefetch();
    // owner 2026-11-20：连续快滑时，解码器来不及准备下下条，但封面可以。
    // 前后各预取 3 条封面（纯图片，几百 KB），保证每次落页都有画面可看，
    // 不会出现「滑过去是黑的，等解码器」。
    _prefetchNeighborCovers();
  }

  Future<void> _refreshDrop(String id, int token, String lib) async {
    if (id.isEmpty) return;
    final r = await fetchDropStatus(id, lib: lib);
    if (!mounted || token != _openToken || r == null) return;
    setState(() {
      dropDayLeft = _intOf(r['dayLeft'], 1);
      dropWeekLeft = _intOf(r['weekLeft'], 3);
      dropTotal = _intOf(r['total'], 0);
      gDropDayLeft = _intOf(r['gDayLeft'], gDropDayLeft);
      gDropWeekLeft = _intOf(r['gWeekLeft'], gDropWeekLeft);
      gDropDayLimit = _intOf(r['gDayLimit'], 5);
      gDropWeekLimit = _intOf(r['gWeekLimit'], 15);
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
    if (gDropDayLeft <= 0) {
      _toast('今日全站小水滴已送完（$gDropDayLimit/$gDropDayLimit）');
      return;
    }
    if (gDropWeekLeft <= 0) {
      _toast('本周全站小水滴已送完（$gDropWeekLimit/$gDropWeekLimit）');
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
        gDropDayLeft = _intOf(r['gDayLeft'], gDropDayLeft);
        gDropWeekLeft = _intOf(r['gWeekLeft'], gDropWeekLeft);
        gDropDayLimit = _intOf(r['gDayLimit'], gDropDayLimit);
        gDropWeekLimit = _intOf(r['gWeekLimit'], gDropWeekLimit);
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

  // J-A2：所有播放页提示统一走顶部胶囊，不再用底部 SnackBar。
  void _toast(String msg) => _showTopNotice(msg);

  void _showTopNotice(String msg) {
    if (!mounted) return;
    final seq = ++_noticeSeq;
    setState(() => _noticeText = msg);
    _noticeTimer?.cancel();
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || seq != _noticeSeq) return;
      setState(() => _noticeText = null);
    });
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
          index: img,
          count: n,
          loopOne: loopOne,
          hasAudio: hasAudio,
          autoplay: autoplay)) {
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
        case SlideshowAction.stop:
          pauseAuto();
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
    // 乱序模式：按随机序列前后走；否则按原顺序并跳过数据异常的作品。
    final target = (shuffle && base == cur)
        ? _shuffleTarget(delta)
        : nextPlayableIndex(
            current: base,
            count: widget.works.length,
            step: delta,
            playable: (i) => workPlayable(_workAt(i)));
    if (target < 0 || target == base) {
      // A2：最后一条再往后走时向来源页续拉新一批，成功后重试一次。
      if (delta > 0 &&
          !_fetchingMore &&
          widget.onNeedMore != null &&
          base >= widget.works.length - 1) {
        _fetchingMore = true;
        widget.onNeedMore!().then((ok) {
          _fetchingMore = false;
          if (!mounted) return;
          if (ok && widget.works.length > base) {
            setState(() {});
            _step(delta, instant: instant);
          }
        }).catchError((_) {
          _fetchingMore = false;
        });
      }
      return;
    }
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

  /// 作品唯一键（库/作品 id），只服务本机比例与隐藏集合等内存映射。
  String _workKeyFor(dynamic w) =>
      workKey(lib: _libFor(w), id: '${(w is Map ? w['id'] : null) ?? ''}');

  // P1：非全屏互动栏的收藏标记（本机内存态，暂不写服务端）。

  /// P1 §2：文案优先用作品简介，没有简介用标题；都为空则不显示。
  String _infoCaptionFor(dynamic w) {
    final desc = '${w['desc'] ?? ''}'.trim();
    if (desc.isNotEmpty) return desc;
    return '${w['ti'] ?? ''}'.trim();
  }

  // P1b §8：非全屏舞台长按菜单（500ms、位移 ≤12px、不暂停）。
  // 全屏分支不进入以下逻辑。
  // ---------------------------------------------------------------------

  void _stageLongPressDown(PointerDownEvent e) {
    if (fs || _menuVisible || _commentVisible) return;
    final w = _workAt(cur);
    if (w['t'] != 'v') return; // 图文沿用 G11/G14 的既有长按菜单
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    if (!stageLongPressAllowed(
      position: e.localPosition,
      stageSize: size,
      topInset: pad.top,
      bottomInset: pad.bottom + 88,
      rightInset: kRailReservedWidth,
      fullscreen: fs,
    )) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    _lpTracker.begin(nowMs: now, pos: e.localPosition);
    _lpTimer?.cancel();
    _lpTimer =
        Timer(const Duration(milliseconds: kStageLongPressMs), _fireLongPress);
  }

  void _stageLongPressMove(PointerMoveEvent e) {
    if (!_lpTracker.tracking) return;
    if (!_lpTracker.update(e.localPosition)) _lpTimer?.cancel();
  }

  void _stageLongPressUp() {
    final fired = _lpTracker.fired;
    _lpTracker.cancel();
    _lpTimer?.cancel();
    // 长按已弹菜单：这次抬起不再当作单击（否则会误暂停）。
    if (fired) _suppressStageTap = true;
  }

  void _fireLongPress() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!mounted || !_lpTracker.shouldFire(now)) return;
    _lpTracker.fire();
    // 长按期间与菜单打开后都不暂停（抬起不再当作单击）。
    _suppressStageTap = true;
    hapticTap();
    _openStageMenu();
  }

  void _openStageMenu() {
    if (fs) return;
    _menuAnim.forward(from: 0);
    setState(() => _menuVisible = true);
    // P2：菜单打开期间不进入沉浸。
    _scheduleImmersive();
  }

  void _closeStageMenu() {
    if (!_menuVisible) return;
    _menuAnim.reverse().whenComplete(() {
      if (mounted && _menuAnim.value == 0) {
        setState(() => _menuVisible = false);
        _scheduleImmersive();
      }
    });
  }

  /// §8 菜单项：只在本地生效，不上传任何数据。
  Future<void> _onStageMenuAction(String label) async {
    _closeStageMenu();
    final w = _workAt(cur);
    switch (label) {
      case '不感兴趣':
        await _hideCurrentWork(w);
        break;
      case '保存到本机':
        await _saveCurrentMedia(w);
        break;
      case '复制文案':
        final text = _infoCaptionFor(w);
        if (text.isEmpty) {
          _toast('当前作品没有文案');
          break;
        }
        await Clipboard.setData(ClipboardData(text: text));
        _toast('文案已复制');
        break;
      case '举报':
        // 举报只做本地记录，不联网、不上报服务端。
        debugPrint('[report] local-only work=${_workKeyFor(w)}');
        _toast('已记录举报（仅本地，未联网）');
        break;
    }
  }

  /// 不感兴趣：写入本机集合 `hidden_works_v1`，刷新列表后生效；
  /// 当前会话内直接跳到下一条，抖音同款手感。
  Future<void> _hideCurrentWork(dynamic w) async {
    final key = _workKeyFor(w);
    if (key.isEmpty) {
      _toast('缺少作品标识，无法隐藏');
      return;
    }
    setState(() => _hiddenKeys.add(key));
    _toast('已隐藏该作品');
    try {
      final sp = await SharedPreferences.getInstance();
      final list = <String>{...sp.getStringList('hidden_works_v1') ?? const []}
        ..add(key);
      await sp.setStringList('hidden_works_v1', list.toList());
    } catch (_) {}
    if (mounted && cur < widget.works.length - 1) _step(1);
  }

  /// 保存到本机：桌面端把当前媒体原文件落到系统下载目录（不写 NAS）；
  /// Android/iOS 暂无下载目录权限，提示暂不可用。
  Future<void> _saveCurrentMedia(dynamic w) async {
    if (!mediaDownloadSupported(
        android: Platform.isAndroid, ios: Platform.isIOS)) {
      _toast('移动端暂不支持保存到本机');
      return;
    }
    final m = w['m'];
    final first = (m is List && m.isNotEmpty) ? '${m.first}' : '';
    if (first.isEmpty) {
      _toast('暂无可保存的媒体');
      return;
    }
    final isVideo = w['t'] == 'v';
    final url = cfg.mediaUrl(first, lib: _libFor(w));
    if (url.isEmpty) {
      _toast('暂无可保存的媒体');
      return;
    }
    if (url.toLowerCase().contains('.m3u8')) {
      _toast('流媒体暂不支持保存');
      return;
    }
    _toast('正在保存…');
    try {
      final dir = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final base = '${w['ti'] ?? ''}'.trim().isEmpty
          ? '${w['id'] ?? 'dizi'}'
          : '${w['ti']}';
      final name = mediaSaveFileName(base: base, url: url, video: isVideo);
      final file = File('${dir.path}${Platform.pathSeparator}$name');
      final resp =
          await http.get(Uri.parse(url), headers: cfg.headersFor(_libFor(w)));
      if (resp.statusCode != 200) {
        _toast('保存失败：${httpErrorText(resp.statusCode)}');
        return;
      }
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      _toast('已保存到 ${file.path}');
    } catch (e) {
      _toast('保存失败：${errorText(e)}');
    }
  }

  // ---------------------------------------------------------------------
  // P1b §9：评论半屏面板。打开 = 60% 屏高并静音；再次上滑 = 全屏；
  // 下滑 = 关闭并恢复原音量。面板在顶层手势域，不影响 PageView 翻页。
  // ---------------------------------------------------------------------

  double get _commentFractionNow {
    if (_commentDragging || !_commentAnim.isAnimating) return _commentFraction;
    final t = Curves.easeOut.transform(_commentAnim.value);
    return _commentAnimFrom + (_commentAnimTo - _commentAnimFrom) * t;
  }

  void _animateCommentTo(double target) {
    _commentAnimFrom = _commentFractionNow;
    _commentAnimTo = target;
    _commentAnim.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _commentFraction = target;
        if (target <= 0) _commentVisible = false;
      });
      if (target <= 0) {
        try {
          player.setVolume(volume);
        } catch (_) {}
      }
      // P2：评论面板收起后重新开始沉浸计时。
      _scheduleImmersive();
    });
  }

  void _commentDragUpdate(DragUpdateDetails d, double screenH) {
    if (screenH <= 0) return;
    _commentDragging = true;
    _commentAnim.stop();
    setState(() {
      _commentFraction =
          (_commentFractionNow - d.delta.dy / screenH).clamp(0.0, 1.0);
    });
  }

  void _commentDragEnd(DragEndDetails d, double screenH) {
    _commentDragging = false;
    final target = commentPanelSnap(
      fraction: _commentFraction,
      velocity: d.primaryVelocity ?? 0,
    );
    _animateCommentTo(target);
  }

  /// 切条时收起评论面板/长按菜单，避免带到下一条。
  void _resetOverlaysOnSwitch() {
    if (_commentVisible) {
      _commentVisible = false;
      _commentFraction = kCommentPanelClosedFraction;
      try {
        player.setVolume(volume);
      } catch (_) {}
    }
    // P2：即使面板正在上滑动画中也立即收起，不带进下一条。
    _commentAnim.stop();
    _commentAnim.value = 0;
    _commentDragging = false;
    if (_menuVisible) {
      _menuVisible = false;
      _menuAnim.stop();
      _menuAnim.value = 0;
    }
    // §11：长按/点击抑制状态不带进下一条（点赞与双击仲裁已移除）。
    _suppressStageTap = false;
    _lpTimer?.cancel();
    _lpTracker.cancel();
    // P2 §12：新页从可见功能区开始，重新计时。
    _imm.cancel();
    _scheduleImmersive();
  }

  /// §8 底部菜单弹层：半透明黑底 + 取消钮，200ms easeOut 上滑，
  /// 背景遮罩黑 40%。只在非全屏舞台最上层渲染。
  Widget _stageMenuOverlay() {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _menuAnim,
        builder: (_, __) {
          final t = Curves.easeOut.transform(_menuAnim.value.clamp(0.0, 1.0));
          return Stack(fit: StackFit.expand, children: [
            GestureDetector(
              key: const Key('stage-menu-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: _closeStageMenu,
              child: ColoredBox(
                  color: kStageScrimColor.withValues(alpha: 0.4 * t)),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 320),
                child: GestureDetector(
                  // 吞掉面板内空白处点击，避免误关
                  onTap: () {},
                  child: Container(
                    key: const Key('stage-menu'),
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: kStageMenuBackground,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(top: 8, bottom: 4),
                          decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2)),
                        ),
                        for (final label in kStageMenuLabels)
                          ListTile(
                            key: Key('stage-menu-$label'),
                            dense: true,
                            title: Text(label,
                                style: const TextStyle(
                                    fontSize: 15, color: Colors.white)),
                            onTap: () => _onStageMenuAction(label),
                          ),
                        const Divider(height: 1, color: Colors.white12),
                        ListTile(
                          key: const Key('stage-menu-cancel'),
                          dense: true,
                          title: const Center(
                            child: Text('取消',
                                style: TextStyle(
                                    fontSize: 15, color: Colors.white70)),
                          ),
                          onTap: _closeStageMenu,
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  /// §9 评论半屏面板：高度 = 屏高 × 当前比例（0.6 / 1.0），
  /// 打开动画 200ms easeOut；拖动时跟手，松手按速度 snap。
  Widget _commentPanelOverlay(Size viewSize) {
    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _commentAnim,
        builder: (_, __) {
          final frac = _commentFractionNow;
          final h =
              commentPanelHeight(fraction: frac, screenHeight: viewSize.height);
          if (h <= 0.5) return const SizedBox.shrink();
          final scrim = (frac / kCommentPanelInitialFraction).clamp(0.0, 1.0);
          return Stack(fit: StackFit.expand, children: [
            GestureDetector(
              key: const Key('comment-scrim'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _animateCommentTo(kCommentPanelClosedFraction),
              child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.4 * scrim)),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: h,
              child: GestureDetector(
                key: const Key('comment-panel'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => _commentDragging = true,
                onVerticalDragUpdate: (d) =>
                    _commentDragUpdate(d, viewSize.height),
                onVerticalDragEnd: (d) => _commentDragEnd(d, viewSize.height),
                onVerticalDragCancel: () =>
                    _animateCommentTo(kCommentPanelInitialFraction),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1C1C1E),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 6),
                      decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 8, 6),
                      child: Row(children: [
                        const Text('评论 0',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                        const Spacer(),
                        IconButton(
                          key: const Key('comment-close'),
                          tooltip: '关闭评论',
                          onPressed: () =>
                              _animateCommentTo(kCommentPanelClosedFraction),
                          icon: const Icon(Icons.close,
                              size: 22, color: Colors.white70),
                        ),
                      ]),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    const Expanded(
                      child: Center(
                        child: Text('评论功能待接入',
                            style:
                                TextStyle(fontSize: 13, color: Colors.white38)),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  // 全屏且功能隐藏时，第一次点击只呼出功能区，第二次才暂停；
  // 320ms 内在相近位置再次点击视为双击：点赞并恢复到点击前的播放状态。
  void onStageTap([Offset? pos]) {
    // 取证：舞台收到点击时记下当时的可见态。信息层同时有 pointer-down 日志，
    // 两者对不上就说明点击被进度条热区/其它层吞掉后穿到了舞台。
    CrashLog.instance.record(
      'stage-tap ui=$ui fs=$fs paused=$paused swipe=$_pageSwiping '
      'pos=${pos == null ? 'null' : '${pos.dx.toStringAsFixed(0)},${pos.dy.toStringAsFixed(0)}'}',
      kind: 'author',
    );
    // owner 2026-11-21：呼出的进度条要能被单击收回。
    // 进度条本身只认拖动（点按已不 seek），所以单击落到舞台时统一收起。
    if (_scrubActive || _scrubHover) {
      _scrubThinTimer?.cancel();
      setState(() {
        _scrubActive = false;
        _scrubHover = false;
      });
    }
    // 2026-11-23：双击点赞已移除。舞台点击只有一条路径——
    // 非全屏走 _onStageTapNonFullscreen（沉浸/长按抑制/缩放复位/单击暂停），
    // 全屏只切换功能区显隐。双击 = 两次单击，不出现「暂停又播放」的抖动，
    // 因为每次单击都独立走 _singleStageTap。
    if (!fs) {
      // P2：沉浸态下第一次点按只恢复功能区，不暂停。
      final fromImmersive = _immAtDown;
      _immAtDown = false;
      if (fromImmersive) {
        _immersiveTouch();
        showUi();
        return;
      }
      _immersiveTouch();
      _onStageTapNonFullscreen(pos);
      return;
    }
    focus.requestFocus();
    // M1：全屏单击只切换功能区显隐，不暂停（保留 G14 缩放复位）。
    switch (stageTapAction(
      uiVisible: ui,
      // owner 2026-11-21：全屏下舞台任意位置（含视频矩形外的黑边/留白）
      // 都只切换功能区显隐，桌面端不再「单击暂停」，与移动端一致。
      fullscreen: fs,
      zoomed: _picZoom.isZoomed,
      doubleTap: false,
    )) {
      case StageTapAction.resetZoom:
        _resetPicZoom();
        return;
      case StageTapAction.hideUi:
        hideUiNow();
        return;
      // 下面两个分支在全屏 + 无双击时不可达；保留穷尽分支，避免将来
      // 语义变更时静默漏处理。
      case StageTapAction.showUi:
        showUi();
        return;
      case StageTapAction.togglePause:
        hapticTap();
        togglePause();
        showUi();
        return;
      case StageTapAction.like:
        // 双击点赞已移除：这里不再有点赞动作，只保证功能区可见。
        showUi();
        return;
    }
  }

  /// 非全屏单击：沉浸恢复 / 长按抑制 / 图片缩放复位 / 暂停继续。
  ///
  /// 2026-11-23：原本这里还有 250ms 双击仲裁（双击点赞）。点赞删除后，
  /// 仲裁窗口没有第二个用途，直接取消——单击立即生效，不再有 250ms 延迟。
  void _onStageTapNonFullscreen(Offset? pos) {
    focus.requestFocus();
    // P1b：长按已弹菜单/评论面板时，抬起不当作单击（不暂停）。
    if (_suppressStageTap) {
      _suppressStageTap = false;
      return;
    }
    // G14：图片放大时单击只恢复原始大小
    if (_picZoom.isZoomed) {
      _resetPicZoom();
      return;
    }
    _singleStageTap();
  }

  /// 非全屏单击：功能区隐藏时先呼出；否则暂停/继续。
  /// 暂停时中央只显示播放图标（无大按钮），0.8s 后 easeOut 淡出。
  void _singleStageTap() {
    if (!ui) {
      showUi();
      return;
    }
    // owner 2026-11-22：移动端暂停不再震动（手感差），去掉触感反馈。
    togglePause();
    showUi();
  }

  /// M1：立即收起功能区（取消自动隐藏计时器，避免残留定时器再触发）。
  void hideUiNow() {
    // 与进度条同步收起：清掉拖动/悬停状态，避免残留让进度条“粘”在屏幕上
    _scrubActive = false;
    _scrubHover = false;
    _scrubThinTimer?.cancel();
    hideTimer?.cancel();
    hideTimer = null;
    _hideDeadline.clear();
    if (!mounted) return;
    setState(() => ui = false);
  }

  // M9：作者页跟手拖拽。拖动开始时透明路由即入栈（进度 0），位移由手指驱动。
  AuthorDragController? _authorDrag;
  double _authorDragDx = 0;
  bool _authorDragResume = false;
  bool _authorDragClosing = false;

  /// 触发「左滑进入作者主页」的右侧边缘宽度。
  /// owner 2026-11-20：只在右侧边缘起手，避免在画面中间滑动误开作者页。
  static const double kAuthorDragEdge = 48;

  /// owner 2026-11-22：从作者页点进来的作品，左滑进作者页与点头像都要关掉
  /// （否则原地绕回同一个作者）。来源在 initState 里定格。
  late bool _fromAuthor;

  void _authorDragStart(double startDx, double width, {double startDy = -1}) {
    // 起手判定集中在 authorDragAllowed（来源 + 边缘 + 任务栏排除），
    // 不在这里另写一套条件。判定通过才取消单击判定，避免吞掉正常点击。
    final pad = MediaQuery.paddingOf(context);
    final allowed = authorDragAllowed(
      fromAuthor: _fromAuthor,
      fullscreen: fs,
      startDx: startDx,
      startDy: startDy,
      width: width,
      screenHeight: MediaQuery.sizeOf(context).height,
      taskbarHeight: _liveTaskbarHeight(pad),
      taskbarVisible: ui,
      edgeWidth: kAuthorDragEdge,
    );
    if (!allowed) return;
    // 左滑起手后指针位移已超过单击阈值，不会再落到单击路径。
    if (_authorDrag != null) return;
    final name = '${_workAt(cur)['a'] ?? ''}';
    if (name.isEmpty) return;
    _authorDragDx = 0;
    _authorDragClosing = false;
    _authorDragResume = !paused;
    _userPaused = true;
    PauseTrace.mark('user:author-drag');
    try {
      Breadcrumb.mark('player:pause', 'L9245');
      player.pause();
    } catch (_) {}
    final c = AuthorDragController();
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
        _userPaused = false;
        _stallAttempts = 0;
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

  /// 作者点击链路取证（0.9.144）。
  ///
  /// owner 2026-11-21 复现：点头像「什么都没发生」，点作者名却落回舞台暂停。
  /// 三种可能必须分清，否则只能继续在手势参数上试：
  ///   a) 指针根本没到信息层（上层有别的层挡住）；
  ///   b) 到了信息层但抬手被别的手势抢走；
  ///   c) onTap 进了却在中途抛异常（界面无变化、日志也没有）。
  /// 指针级日志 + onTap 首行 + 异常记录，一次即可区分。
  ///
  /// 2026-11-22：`pointer-down/up` 只说明指针进了信息层，**不代表点击**。
  /// 一次竖向上滑曾留下两行 `author-tap[...]` 被读成「点了没反应」，
  /// 所以抬手时补一个明确的 `gesture=tap|swipe|hold` 判定。
  Offset? _diagPointer;
  Offset? _diagDownPoint;
  DateTime? _diagDownAt;

  void _authorTapDiag(String stage, {Object? error}) {
    try {
      final p = _diagPointer;
      final down = _diagDownPoint;
      final at = _diagDownAt;
      var gesture = '';
      if (stage == 'pointer-up' && p != null && down != null && at != null) {
        final v = gestureVerdict(
          down: down,
          up: p,
          held: DateTime.now().difference(at),
        );
        gesture =
            ' gesture=${gestureVerdictName(v)} dx=${(p.dx - down.dx).toStringAsFixed(0)} dy=${(p.dy - down.dy).toStringAsFixed(0)}';
      }
      CrashLog.instance.record(
        'author-tap[$stage] pos=${p == null ? 'null' : '${p.dx.toStringAsFixed(0)},${p.dy.toStringAsFixed(0)}'} '
        'ui=$ui fs=$fs paused=$paused$gesture'
        '${error == null ? '' : ' err=$error'}',
        kind: 'author',
      );
    } catch (_) {}
  }

  /// 头像 / 作者名 / 占位图三处热区的**同一个**点击处理。
  ///
  /// 原来这三处各自内联了一份 `_authorTapDiag('tap') → try openAuthor() →
  /// catch(_authorTapDiag('tap-error'))`：改一处忘两处就会出现「头像是好的、
  /// 名字点了没日志」这种查不出来的现象。热区行为（opaque）仍由各自的
  /// GestureDetector 保留，这里只管点击之后做什么。
  void _authorTapOpen() {
    _authorTapDiag('tap');
    try {
      openAuthor();
    } catch (e) {
      _authorTapDiag('tap-error', error: e);
    }
  }

  // 打开当前作品作者主页：先暂停，返回后按原状态恢复
  Future<void> openAuthor() async {
    _authorTapDiag('openAuthor');
    // owner 2026-11-22：从作者页进来的作品，点头像/作者名 = 返回作者页。
    if (_fromAuthor) {
      _authorTapDiag('pop-to-author');
      try {
        Navigator.of(context).maybePop();
      } catch (_) {}
      return;
    }
    final name = authorNameOf(_workAt(cur));
    CrashLog.instance.record(
      'author-tap raw=${_workAt(cur)['a'] ?? ''} resolved=${name.isEmpty ? 'EMPTY' : 'ok'}',
      kind: 'author',
    );
    if (name.isEmpty) return;
    final resume = !paused;
    _userPaused = true;
    PauseTrace.mark('user:open-author');
    try {
      Breadcrumb.mark('player:pause', 'L9308');
      player.pause();
    } catch (_) {}
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AuthorPage(name: name, libs: [_curLib])));
    if (resume && mounted && !fs) {
      _userPaused = false;
      _stallAttempts = 0;
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

  /// 播放/暂停命令串行化：连点只保证最后一次意图落地。
  ///
  /// 原来每次点击都直接调 `player.play()/pause()`；快速连点会让多个调用
  /// 同时在 media_kit 原生层执行，Android/iOS 解码器不可重入 → 闪退。
  /// 改成「写期望状态 + 单线程消费」，原生层永远只有一次调用在跑。
  bool _playCmdBusy = false;
  bool? _playCmdDesired;

  /// 交命令时所属的 open 周期：换条后旧命令必须作废，
  /// 否则「上一条的暂停」会在新视频起播后落地，表现就是起播即停。
  int _playCmdToken = -1;

  void _requestPlayState({required bool playing}) {
    _playCmdDesired = playing;
    _playCmdToken = _openToken;
    if (_playCmdBusy) return;
    _playCmdBusy = true;
    Future<void>(() async {
      try {
        while (mounted) {
          final want = _playCmdDesired;
          if (want == null) break;
          _playCmdDesired = null;
          // 换过条：这条命令属于上一条，丢弃
          if (_playCmdToken != _openToken) continue;
          try {
            if (want) {
              await player.setRate(speed);
              await player.play();
            } else {
              await player.pause();
            }
          } catch (_) {}
        }
      } finally {
        _playCmdBusy = false;
      }
    });
  }

  void togglePause() {
    final isV = _workAt(cur)['t'] == 'v';
    // 用户手动操作后不再视为后台暂停，避免回前台被自动恢复
    _pausedByBackground = false;
    _stallTimer?.cancel();
    _stallAttempts = 0;
    if (!isV) {
      final willPause = !paused;
      _userPaused = willPause;
      _feed(willPause ? PlaybackEvent.pause : PlaybackEvent.play);
      setState(() => _pausedIntent = willPause);
      if (willPause) {
        pauseAuto();
        PauseTrace.mark('user:toggle');
        Breadcrumb.mark('player:pause', 'L9345');
        _requestPlayState(playing: false);
      } else {
        if (!manualPic) startAuto();
        _requestPlayState(playing: true);
      }
      return;
    }
    // 先更新 UI（点击立刻有反馈），再排队执行原生调用。
    if (paused) {
      _userPaused = false;
      _feed(PlaybackEvent.play);
      setState(() => _pausedIntent = false);
      _requestPlayState(playing: true);
    } else {
      _userPaused = true;
      PauseTrace.mark('user:toggle');
      Breadcrumb.mark('player:pause', 'L9362');
      _feed(PlaybackEvent.pause);
      setState(() => _pausedIntent = true);
      _requestPlayState(playing: false);
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
    if (_commentVisible) return; // P1b：评论面板打开时保持静音
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
    // P1b：评论面板打开期间保持静音，关闭时由面板逻辑恢复。
    player.setVolume(_commentVisible ? 0 : nv);
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

  void toggleLoop() {
    // L6：打开循环时自动关闭连播并记住原状态；关闭循环时恢复到打开前的连播。
    // 不使用 media_kit 原生 PlaylistMode.single（原生 loop-file 会吞掉
    // completed 事件），统一由 completed 回调在 Dart 层重播。
    setState(() => _link = _link.toggleLoop());
    _persistPlaybackPrefs();
    if (_link.nextEnabled) {
      _schedulePreload();
    } else {
      _cancelPreload();
    }
  }

  void toggleAutoplay() {
    // L6：循环开启期间也允许手动切连播，但退出循环仍回到记忆值。
    setState(() => _link = _link.toggleAutoplay());
    _persistPlaybackPrefs();
    if (_link.nextEnabled) {
      _schedulePreload();
    } else {
      _cancelPreload();
    }
  }

  /// 设定倍速（播放设置菜单与键盘循环共用唯一入口）。
  void setSpeed(double value) {
    final next = value.clamp(0.5, 3.0).toDouble();
    setState(() => speed = next);
    player.setRate(next);
    _persistPlaybackPrefs();
  }

  /// owner 2026-11-23：播放设置——倍速/自动连播/单条循环/乱序合并到一个菜单，
  /// 任务栏只留一个入口（按钮显示当前倍速），原有操作一个不少。
  void _showPlaybackSettings() {
    hapticTap();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setSheet) {
          void apply(VoidCallback fn) {
            fn();
            setSheet(() {});
          }

          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  const Icon(Icons.tune, size: 18),
                  const SizedBox(width: 8),
                  const Text('播放设置',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('1.0x 表示原速',
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  const Text('倍速', style: TextStyle(fontSize: 13)),
                  const Spacer(),
                  for (final v in const [0.75, 1.0, 1.25, 1.5, 2.0])
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(
                        key: ValueKey('speed-$v'),
                        label: Text(speedLabel(v),
                            style: const TextStyle(fontSize: 11)),
                        selected: (speed - v).abs() < 0.001,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => apply(() => setSpeed(v)),
                      ),
                    ),
                ]),
              ),
              SwitchListTile(
                key: const ValueKey('setting-autoplay'),
                dense: true,
                title: const Text('自动连播'),
                subtitle: loopOne ? const Text('单条循环开启时自动连播不可用') : null,
                value: autoplay,
                onChanged: loopOne ? null : (_) => apply(toggleAutoplay),
              ),
              SwitchListTile(
                key: const ValueKey('setting-loop'),
                dense: true,
                title: const Text('单条循环'),
                value: loopOne,
                onChanged: (_) => apply(toggleLoop),
              ),
              SwitchListTile(
                key: const ValueKey('setting-shuffle'),
                dense: true,
                title: const Text('乱序播放'),
                subtitle: const Text('当前库内随机'),
                value: shuffle,
                onChanged: (_) => apply(toggleShuffle),
              ),
              const SizedBox(height: 8),
            ]),
          );
        });
      },
    );
  }

  Future<void> toggleFs() async {
    final next = !fs;
    // 快速连点：记住最后一次意图，等本次切换结束再执行。直接丢弃会让
    // 界面状态与真实窗口状态错位，下一次切换就更容易触发原生崩溃。
    if (_fsBusy) {
      _fsPending = next;
      return;
    }
    if (Platform.isWindows && _winResizing) return;
    _fsBusy = true;
    Breadcrumb.mark('fs:toggle', next ? 'enter' : 'exit');
    try {
      // 先刷新界面：按钮立即响应，不再等窗口管理器回来才变。
      if (mounted) setState(() => fs = next);
      if (fs) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        showUi();
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        hideTimer?.cancel();
        hideTimer = null;
        _hideDeadline.clear();
        if (mounted) setState(() => ui = true);
        _scheduleImmersive();
      }
      if (Platform.isWindows) {
        try {
          await windowManager
              .setFullScreen(next)
              .timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
    } finally {
      // Windows 窗口切换更慢，留足时间再接受下一次切换。
      await Future<void>.delayed(
          Duration(milliseconds: Platform.isWindows ? 800 : 220));
      _fsBusy = false;
      final pending = _fsPending;
      _fsPending = null;
      if (mounted && pending != null && pending != fs) {
        scheduleMicrotask(toggleFs);
      }
    }
  }

  void showUi() {
    if (!mounted) return;
    // 0.9.72：桌面端每个 pointer move 都会调用这里（见 MouseRegion.onHover）。
    // 旧实现无条件 setState，鼠标划过播放页时整页（视频舞台 + 功能区子树）
    // 每秒重建上百次，是 owner 反馈「电脑卡顿」的一处直接来源。功能区已
    // 可见时不再重建，只顺延自动隐藏的截止时刻。
    if (!ui) setState(() => ui = true);
    // P2：任何呼出功能区都重置非全屏沉浸计时（全屏内部会取消）。
    _scheduleImmersive();
    if (!UiAutoHidePolicy.shouldSchedule(fullscreen: fs, uiVisible: ui)) {
      hideTimer?.cancel();
      hideTimer = null;
      _hideDeadline.clear();
      return;
    }
    _hideDeadline.extend(DateTime.now(), AppSettings.hideUiSec);
    _armHideTimer();
  }

  /// 只保留一个待触发的隐藏计时器；期间再次 [showUi] 仅推进截止时刻，
  /// 到点后按剩余时间重排，避免鼠标移动时高频 cancel/新建 Timer。
  void _armHideTimer() {
    if (hideTimer != null) return;

    void fire() {
      hideTimer = null;
      if (!mounted) return;
      final left = _hideDeadline.remaining(DateTime.now());
      if (left > Duration.zero) {
        hideTimer = Timer(left, fire);
        return;
      }
      _hideDeadline.clear();
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
    }

    final left = _hideDeadline.remaining(DateTime.now());
    hideTimer = Timer(
        left > Duration.zero ? left : Duration(seconds: AppSettings.hideUiSec),
        fire);
  }

  /// P2 §12：当前是否允许进入沉浸——全屏、翻页、面板、拖动、
  /// 拖进度条任一成立时都不允许。
  bool _immersiveEligible() {
    // owner 2026-11-18：非全屏的头像/简介必须常驻，不允许过几秒自动淡出。
    if (!fs) return false;
    return ImmersivePolicy.eligible(
      fullscreen: fs,
      uiVisible: ui,
      pageSwiping: _pageSwiping,
      overlayOpen: _commentVisible || _menuVisible,
      dragging: dragging,
      seeking: _seeking,
    );
  }

  /// P2 §12：重新排定 3 秒无操作计时；不允许时立即退出沉浸。
  void _scheduleImmersive() {
    _immTimer?.cancel();
    _immTimer = null;
    if (!mounted) return;
    if (!_immersiveEligible()) {
      if (_imm.immersive) {
        setState(_imm.cancel);
      } else {
        _imm.cancel();
      }
      return;
    }
    _imm.schedule(DateTime.now().millisecondsSinceEpoch);
    _immTimer = Timer(kImmersiveIdle, () {
      _immTimer = null;
      if (!mounted) return;
      if (_imm.tick(DateTime.now().millisecondsSinceEpoch,
          eligible: _immersiveEligible())) {
        setState(() {});
      }
    });
  }

  /// P2 §12：点击/滑动/按键都立即退出沉浸并重新计时。
  void _immersiveTouch() {
    if (!mounted) return;
    final was = _imm.immersive;
    _imm.touch();
    if (was) setState(() {});
    _scheduleImmersive();
  }

  /// M5：只在状态真正变化时重建，避免滚动通知每帧触发 setState。
  void _setPageSwiping(bool value) {
    // P2：翻页中立即退出沉浸，松手后重新计时。
    if (value) {
      _immTimer?.cancel();
      _immTimer = null;
      if (_imm.immersive) {
        _imm.touch();
      }
    }
    if (!mounted || _pageSwiping == value) return;
    setState(() => _pageSwiping = value);
    if (!value) _scheduleImmersive();
  }

  void onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final dy = e.scrollDelta.dy;
    if (dy == 0) return;
    // P2：滚轮/触控板滚动静默视为操作，恢复非全屏沉浸。
    if (!fs) _immersiveTouch();
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
    // P2：任何按键都先恢复非全屏沉浸（全屏逻辑不动）。
    if (down && !fs) _immersiveTouch();
    // 自定义键位只在按下时触发一次，长按重复不再连发。
    // 组合键按「修饰键 + 主键」精确匹配：Ctrl+J 不会触发绑定在单键 J 上的动作。
    if (down) {
      final bound =
          AppSettings.actionForCombo(k.keyId, AppSettings.currentMods());
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
    PauseTrace.mark('page:dispose');
    _stallTimer?.cancel();
    // G10：退出播放页前落盘当前进度
    _saveWatchProgress(force: true);
    WatchProgressStore.flush();
    _dropAnim.dispose();
    _menuAnim.dispose();
    _commentAnim.dispose();
    _lpTimer?.cancel();
    autoTimer?.cancel();
    hideTimer?.cancel();
    _immTimer?.cancel();
    _loadTimeout?.cancel();
    _slowBufferTimer?.cancel();
    _wheelUnlock?.cancel();
    _wheelIdle?.cancel();
    _volHintTimer?.cancel();
    _noticeTimer?.cancel();
    _fadeTimer?.cancel();
    _blackGuard?.cancel();
    _fadeGen++;
    _preloadTimer?.cancel();
    _preloadGen++;
    _cancelVideoPrefetch();
    _videoPrefetch.dispose();
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
    for (final s in _playerSubs) {
      s.cancel();
    }
    _playerSubs.clear();
    for (final s in _slots) {
      // L13：dispose 只是释放原生资源，先显式 stop 确保退出播放页立刻静音。
      try {
        s.player.stop();
      } catch (_) {}
      s.player.dispose();
    }
    PerfDiagnostics.instance.slotsReleased(_slots.length);
    _preloadCache.clear();
    pc.dispose();
    focus.dispose();
    _scrubThinTimer?.cancel();
    _winResizeTimer?.cancel();
    _scrubFracVN.dispose();
    _picDragVN.dispose();
    // 先断开派生进度对位置/时长的监听，再释放底层 notifier。
    _progressVN.dispose();
    _posVN.dispose();
    _durVN.dispose();
    super.dispose();
  }

  // 视频层：窗口最小化/缩放时约束可能瞬间为 0，直接挂载纹理会让
  // Windows 上的 libmpv 重建输出并崩溃；尺寸过小时用纯黑占位。
  // 0.9.25：播放页海报按屏幕宽度解码（原图常见 2400×3600，整张进内存
  // 约 30MB，滑动时会明显卡顿甚至闪退）。
  int _posterDecodeWidth(BuildContext c) {
    final size = MediaQuery.sizeOf(c);
    final dpr = MediaQuery.devicePixelRatioOf(c);
    return (size.width * dpr).round().clamp(360, 2160);
  }

  /// 播放页封面地址：与网格卡片**同一个解析入口**。
  ///
  /// 根因（2026-11-21 复测 0.9.146 后定位）：网格卡片走 `workCoverUrl`
  /// （`th` → 图文首图 → `/api/thumb` 抽帧），播放页却只读 `it['th']`。
  /// 视频作品大量没有 `th`，于是网格里明明有图、播放页的底图 URL 却是空
  /// 串——占位永远不可能命中，黑窗照旧。解析入口收敛到一处后，两边 URL
  /// 与解码宽度都一致，缓存键才对得上。
  String _posterCoverUrl(dynamic it, {String? lib}) {
    if (it is! Map) return '';
    final l = lib ?? _libFor(it);
    return workCoverUrl(
      it,
      lib: l,
      urls: WorkCoverUrls.standard(
        mediaUrl: (path) => cfg.mediaUrl(path, lib: l),
        rawUrl: (path) => cfg.u(path, lib: l).toString(),
      ),
    );
  }

  /// 播放页海报的「零等待底图」。
  ///
  /// 根因（2026-11-21 真机取证）：网格卡片按 `kWorkImageWidth` +
  /// `workCardDecodeWidth` 缓存缩略图，播放页海报按 `kPlayerImageWidth` +
  /// `_posterDecodeWidth` 请求——URL 与解码宽度都不同 → 图片缓存键不同 →
  /// 进播放页必须重新下载/解码，期间海报是空的，露出底层黑色 → 就是
  /// 「有声音、黑屏 ~300ms」。
  ///
  /// 这里不再加任何计时/兜底，只把渲染拆成两级（抖音做法）：先铺那张
  /// **已在缓存里的网格缩略图**，高清图解码完成后由 `CachedNetworkImage`
  /// 自然淡入覆盖。底图 provider 与 `WorkCard` 完全一致（同 URL + 同
  /// `ResizeImage` 宽度），命中即同步出图、无额外请求。
  Widget _posterPreview(dynamic it, {required BoxFit fit}) {
    final cover = _posterCoverUrl(it);
    if (cover.isEmpty) return const SizedBox.expand();
    final lib = _libFor(it);
    final align = fit == BoxFit.cover ? Alignment.topCenter : Alignment.center;
    return Image(
      image: thumbImageProvider(
        withImageWidth(cover, kWorkImageWidth),
        decodeWidth:
            workCardDecodeWidth(MediaQuery.devicePixelRatioOf(context)),
        headers: cfg.headersFor(lib),
        cacheManager: DiziCache.manager,
      ),
      fit: fit,
      alignment: align,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.expand(),
    );
  }

  /// 是否已为某条作品建过邻页（决定图文落页时该用哪张「已解码」的底图）。
  bool _neighborPageBuilt(int i) => _neighborPages.keys.any((k) {
        final bar = k.indexOf('|');
        return bar > 0 && k.substring(0, bar) == '$i';
      });

  /// 图文/单图作品落页的「零等待底图」。
  ///
  /// 根因（owner 2026-11-21 反馈「图已经显示过，落页还要黑一下」）：
  /// 邻页铺的是封面（`w=1080` + 屏幕解码宽度），落页后当前页却换成原图
  /// 地址 + 另一解码宽度 → 图片缓存键不同 → 必须重下一次；期间
  /// `CachedNetworkImage` 的 placeholder 是空的，舞台底色就是纯黑。
  ///
  /// 这里不新增任何定时器/兜底，只补一层**已经解码过**的同图底图：
  ///  - 从网格点开：作品卡的 440px 版本已在 ImageCache；
  ///  - 上下滑入：邻页的 1080px 版本刚刚显示过。
  /// 原图解码完成后由 CachedNetworkImage 自然覆盖（与视频海报同一套两级渲染）。
  Widget _picPreview(dynamic it, String path, {String? lib}) {
    final cover = _posterCoverUrl(it);
    if (cover.isEmpty) return const SizedBox.shrink();
    // 只有「底图就是当前这张」才铺，多图作品翻到第二张以后不能拿首图冒充。
    final pageUrl = cfg.mediaUrl(path, lib: lib);
    if (withImageWidth(cover, kPlayerImageWidth) !=
        withImageWidth(pageUrl, kPlayerImageWidth)) {
      return const SizedBox.shrink();
    }
    final ImageProvider provider = _neighborPageBuilt(cur)
        ? thumbImageProvider(
            withImageWidth(cover, kPlayerImageWidth),
            decodeWidth: _posterDecodeWidth(context),
            headers: cfg.headersFor(lib),
            cacheManager: DiziCache.manager,
          )
        : thumbImageProvider(
            withImageWidth(cover, kWorkImageWidth),
            decodeWidth:
                workCardDecodeWidth(MediaQuery.devicePixelRatioOf(context)),
            headers: cfg.headersFor(lib),
            cacheManager: DiziCache.manager,
          );
    return Image(
      image: provider,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }

  /// 页内浮层：作者头像/文案/音乐 + 右侧互动栏（含全屏旧信息行）。
  ///
  /// 放进每一页自己的 Stack，滑动时随视频整页位移——抖音的文案是跟着
  /// 视频一起滑的，钉在外层就会「画面滑走、文字不动」。
  /// [bottom] 用页内坐标（不含 stageInset），避免重复扣一次任务栏高度。
  List<Widget> _stageOverlayChildren({
    required dynamic w,
    required bool fs,
    required bool broken,
    required EdgeInsets pad,
    required double bottom,
    required Size viewSize,
    required double chromeOpacity,
    required int chromeMs,
    required double infoOpacity,
    required bool immersiveFade,
    required double railOpacity,
    required int railMs,
  }) {
    // 全屏时任务栏是半透明浮层（占 _taskbarH），信息必须整段让开，
    // 否则会与任务栏重叠。
    final overlayBottom = fs ? _liveTaskbarHeight(pad) + 12 : bottom;
    // 作品缺 `a` 时统一从媒体路径 `%40作者` 回退；UI 与跳转必须用同一个名字，
    // 否则会出现「点头像能进、作者名显示空」的不一致。
    final authorName = authorNameOf(w);
    final authorLabel = authorName.startsWith('@')
        ? authorName.substring(1).trim()
        : authorName;
    return [
      // P1 §2：非全屏左侧信息区走独立的抖音式面板；全屏保留旧信息行。
      if (!broken)
        Positioned(
          left: pad.left + 14,
          right: pad.right + 80,
          bottom: overlayBottom,
          child: IgnorePointer(
            ignoring: !ui,
            // 指针级取证：只要指针进到信息层就会留下 down/up，用来区分
            // 「没进来」和「进来了但被抢」。translucent 不拦兄弟层。
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (e) {
                _diagPointer = e.localPosition;
                _diagDownPoint = e.localPosition;
                _diagDownAt = DateTime.now();
                _authorTapDiag('pointer-down');
              },
              onPointerUp: (e) {
                _diagPointer = e.localPosition;
                _authorTapDiag('pointer-up');
              },
              child: AnimatedOpacity(
                opacity: infoOpacity,
                duration: Duration(milliseconds: chromeMs),
                curve: Curves.easeOut,
                child: GestureDetector(
                  // owner 2026-11-18：只有头像和作者名可进作者页；简介区域与
                  // 进度条上方空白不再误触发跳转。
                  onLongPress: _showWorkMenu,
                  child: Row(children: [
                    // B2：作者级头像索引异步到位后要重新解析，否则会一直显示人形占位。
                    ValueListenableBuilder<int>(
                      valueListenable: authorAvatarRevision,
                      builder: (context, _, __) => avatarFor(w).isNotEmpty
                          ? GestureDetector(
                              // owner 2026-11-21：头像/作者名的点击必须由「显式热区」
                              // 保证。默认 deferToChild 依赖子组件自己命中，图片还在
                              // 加载（占位为空）或加载失败时中心像素没有可命中对象，
                              // 点击会穿透到舞台被当成暂停——表现就是「点头像没反应」。
                              behavior: HitTestBehavior.opaque,
                              onTap: _authorTapOpen,
                              child: ClipOval(
                                  child: CachedNetworkImage(
                                      cacheManager: DiziCache.manager,
                                      // 播放页头像 38dp：取 200px 缩图即可。
                                      // 兜底图可能来自作者所在的基础库，按图片自身
                                      // 的库路由与鉴权，避免跨库 401 一直显示默认头像。
                                      imageUrl: withImageWidth(
                                          cfg.mediaUrl(avatarFor(w),
                                              lib: _avatarLibFor(avatarFor(w))),
                                          kAvatarImageWidth),
                                      httpHeaders: cfg.headersFor(
                                          _avatarLibFor(avatarFor(w))),
                                      width: 38,
                                      height: 38,
                                      memCacheWidth: (38 *
                                              MediaQuery.devicePixelRatioOf(
                                                  context))
                                          .round(),
                                      fadeInDuration: Duration.zero,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          const CircleAvatar(
                                              radius: 19,
                                              child: Icon(Icons.person)))))
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _authorTapOpen,
                              child: const CircleAvatar(
                                  radius: 19, child: Icon(Icons.person))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Flexible(
                              child: GestureDetector(
                                // 同上：文字区域也按整块热区命中，不依赖字形像素。
                                behavior: HitTestBehavior.opaque,
                                onTap: _authorTapOpen,
                                child: Text(
                                    authorLabel.isEmpty
                                        ? '@未知作者'
                                        : '@$authorLabel',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                            ),
                            if (('${w['d'] ?? ''}').isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text('${w['d']}',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white54)),
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
                                  name: authorName,
                                  mediaPath: avatarFor(w),
                                  // 作品条目自带基础库 id 时直接用它归属单元库
                                  basicId: '${w['_bid'] ?? w['basicId'] ?? ''}',
                                  fallbackId: _curLib,
                                  // 0.9.6：不再回退库名文案，无归属显示 SECRET
                                  fallbackName: '',
                                  works: widget.works
                                      .where((e) =>
                                          e is Map &&
                                          authorNameOf(e) == authorName)
                                      .length,
                                ),
                              ),
                            ),
                          // 作品/合集文件夹里的 txt 简介（服务端下发 desc）
                          if ('${w['desc'] ?? ''}'.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text('${w['desc']}'.trim(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white70)),
                            ),
                          // T：集数标签已移入页内舞台底部的进度层（随页位移），
                          // 信息行不再重复展示。
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
                                    locale:
                                        Localizations.maybeLocaleOf(context));
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
                                          maxHeight: MediaQuery.sizeOf(context)
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
                                            alignment: Alignment.centerRight,
                                            child: GestureDetector(
                                              onTap: toggleCaption,
                                              child: const Padding(
                                                padding: EdgeInsets.only(
                                                    left: 6, top: 4, bottom: 2),
                                                child: Icon(Icons.unfold_less,
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
                                            size: 16, color: Colors.white54),
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
        ),
    ];
  }

  Widget videoView() {
    // B：按源比例自适应；比例差超过 8% 一律适应，保原比例不裁切。
    return LayoutBuilder(builder: (_, c) {
      if (c.maxWidth < 2 || c.maxHeight < 2) {
        return const ColoredBox(color: Colors.black);
      }
      // owner 2026-11-19：比例未知时先不挂视频层（下层海报继续显示），
      // 避免先按错误比例画一帧、再跳成正确比例的「抽搐」。
      final aspectNow = _videoAspectFor(_workAt(cur));
      if (aspectNow == null || aspectNow <= 0) {
        return const SizedBox.shrink();
      }
      final fit = videoFitFor(
                  aspect: aspectNow,
                  mode: AppSettings.videoFitOverride,
                  containerAspect: c.maxWidth / c.maxHeight) ==
              VideoFit.fill
          ? BoxFit.cover
          : BoxFit.contain;
      // 关键：纹理按「视频自身比例」的固定基准尺寸渲染，窗口缩放/最大化/
      // 切全屏时由合成器缩放这张已渲染的画面，而不是让 media_kit 重建纹理。
      // 基准框按视频比例算，避免换比例视频时被拉伸；只在比例变化时重建一次。
      // 宽度不再 clamp（那会改变宽高比、把极端比例画面拉变形），只等比缩放。
      final base = videoBaseSize(aspect: aspectNow);
      // 竖屏铺满时把画面锚到顶部：与状态栏/灵动岛融合，且多余部分只从底部裁。
      final topAnchored = videoTopAnchored(
          aspect: aspectNow,
          fit: fit == BoxFit.cover ? VideoFit.fill : VideoFit.contain);
      return ClipRect(
        child: FittedBox(
          fit: fit,
          alignment: topAnchored ? Alignment.topCenter : Alignment.center,
          child: SizedBox(
            width: base.width,
            height: base.height,
            child: RepaintBoundary(
              // key 随槽位变化：预缓冲切换后必须重建 Video，才能挂到新控制器
              child: Video(
                  key: ValueKey('video-${_active.tag}-$_videoGen'),
                  controller: vc,
                  fit: BoxFit.fill,
                  controls: NoVideoControls),
            ),
          ),
        ),
      );
    });
  }

  /// 布局完成后测量底部任务栏真实高度（随简介展开/安全区变化）。
  /// 任务栏高度的唯一取值口：实测值优先，首帧实测前用与任务栏
  /// SizedBox 同源的估算（kTaskbarHeight + 底部安全区）。舞台 inset、
  /// 全屏进度条/信息区避让都走这里，避免两套回退常量各差 1dp。
  double _liveTaskbarHeight(EdgeInsets pad) => _taskbarH > 0
      ? _taskbarH
      : taskbarReservedHeight(
          contentHeight: kTaskbarHeight, safeBottom: pad.bottom);

  void _scheduleTaskbarMeasure() {
    if (_taskbarMeasureScheduled) return;
    _taskbarMeasureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _taskbarMeasureScheduled = false;
      if (!mounted) return;
      final h = _taskbarKey.currentContext?.size?.height ?? 0;
      if (h <= 0) return;
      // 防震荡：全屏切换时布局会抖动，如果高度在两值之间来回跳，
      // 每帧 setState 会让窗口线程卡死。连续两次回到同一值就锁定。
      if ((h - _taskbarH).abs() <= 0.5) {
        _taskbarSwingA = _taskbarSwingB;
        _taskbarSwingB = h;
        return;
      }
      final oscillating = (_taskbarSwingB - h).abs() < 0.5 &&
          (_taskbarSwingA - h).abs() < 0.5 &&
          _taskbarSwingA > 0;
      if (oscillating) {
        debugPrint('[taskbar] measure oscillation ignored: $h');
        return;
      }
      _taskbarSwingA = _taskbarSwingB;
      _taskbarSwingB = _taskbarH;
      setState(() => _taskbarH = h);
    });
  }

  /// C：邻页封面页。按 index/封面/解码宽度缓存 widget 实例，
  /// 播放页 setState 时返回同一实例，Element 直接跳过重建。
  Widget _neighborPageFor(int i) {
    final it = _workAt(i);
    final lib = _libFor(it);
    final cover = _posterCoverUrl(it, lib: lib);
    final memW = _posterDecodeWidth(context);
    // 预载页与正式海报必须用同一个 URL/宽度，否则切到这一页时又要重下。
    final key = '$i|${it['id'] ?? ''}|$lib|$cover|$memW';
    return _neighborPages.putIfAbsent(key, () {
      return _NeighborPage(
        index: i,
        imageUrl: cover.isEmpty ? '' : withImageWidth(cover, kPlayerImageWidth),
        headers: cfg.headersFor(lib),
        memCacheWidth: memW,
        onAspect: (a) => _rememberCoverAspect(it, a),
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
    final it = _workAt(cur);
    // 原图可能几千像素宽，按屏幕宽度解码，避免大图整张进内存导致卡顿/闪退。
    final screenW = MediaQuery.sizeOf(context).width;
    final decodeW = (screenW * MediaQuery.devicePixelRatioOf(context)).round();
    // G12：图片加载失败（弱网/文件损坏）给出重试，而不是空白
    Widget retryBox() => _MediaRetryBox(
          message: '图片加载失败',
          onRetry: () async {
            try {
              await DiziCache.manager.removeFile(url);
            } catch (_) {}
            if (mounted) setState(() => _imgReload++);
          },
        );
    if (isGifPath(path)) {
      return Image.network(url,
          key: ValueKey('gif-$cur-$img-$_imgReload'),
          headers: cfg.headers,
          // 动图同样按屏幕宽度解码；解码尺寸不影响帧动画播放。
          cacheWidth: decodeW,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          loadingBuilder: (c, child, p) => p == null
              ? child
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white38)),
          errorBuilder: (_, __, ___) => retryBox());
    }
    return CachedNetworkImage(
        cacheManager: DiziCache.manager,
        key: ValueKey('pic-$cur-$img-$_imgReload'),
        imageUrl: url,
        httpHeaders: cfg.headers,
        memCacheWidth: decodeW,
        fit: BoxFit.contain,
        // owner 2026-11-21：图片不再显示中央缓冲圈；但也不能留空——空的
        // placeholder 会露出舞台黑底，就是「图已经出现过、落页又黑一下」。
        // 这里铺一张已在缓存里的同图底图（与视频海报同一套两级渲染）。
        placeholder: (_, __) => _picPreview(it, path, lib: lib),
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
        _feed(PlaybackEvent.play);
        setState(() => _pausedIntent = false);
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

  /// 封面请求：视频带当前播放位置（秒）由服务端截帧；图文/单图带当前图序号。
  CoverRequest _coverRequestFor(Map<String, dynamic> w, CoverScope scope) {
    final isv = w['t'] == 'v';
    return CoverRequest.set(
      lib: _libFor(w),
      work: '${w['id'] ?? ''}',
      scope: scope,
      at: isv ? pos.inMilliseconds / 1000.0 : null,
      index: isv ? null : img,
    );
  }

  /// 打开固定比例截取框，确认后按选框提交封面（owner 2026-11-21 要求）。
  ///
  /// 预览图就是「即将被截取的那一帧」——视频取播放器当前帧
  /// （`player.screenshot`），图文取当前这张图；都拿不到时退回海报封面
  /// （与视频同帧比例）。拿不到任何预览就直接按整帧提交（旧行为）。
  /// 比例常量与库卡片共用 [kLibraryCoverAspect]，入库后 `BoxFit.cover`
  /// 刚好铺满，不会再被裁一次。
  Future<void> _cropAndApplyCover(dynamic w0, CoverScope scope) async {
    final w = w0 as Map<String, dynamic>;
    // `at` / `index` 在打开截取框这一刻定格，选框期间播放位置前进也不影响。
    final base = _coverRequestFor(w, scope);
    final lib = _libFor(w);
    final isv = w['t'] == 'v';
    ImageProvider? preview;
    if (isv) {
      try {
        final bytes = await player.screenshot();
        if (bytes != null && bytes.isNotEmpty) preview = MemoryImage(bytes);
      } catch (_) {}
    } else {
      final paths = workMediaPaths(w);
      if (img >= 0 && img < paths.length && paths[img].isNotEmpty) {
        preview = CachedNetworkImageProvider(
          cfg.mediaUrl(paths[img], lib: lib),
          headers: cfg.headersFor(lib),
          cacheManager: DiziCache.manager,
        );
      }
    }
    final cover = _posterCoverUrl(w);
    preview ??= cover.isEmpty
        ? null
        : thumbImageProvider(
            withImageWidth(cover, kPlayerImageWidth),
            decodeWidth: _posterDecodeWidth(context),
            headers: cfg.headersFor(lib),
            cacheManager: DiziCache.manager,
          );
    if (!mounted) return;
    if (preview == null) {
      await _applyCover(base);
      return;
    }
    final res = await Navigator.of(context).push<CoverCropResult>(
      MaterialPageRoute(builder: (_) => CoverCropPage(image: preview!)),
    );
    if (res == null || !mounted) return;
    await _applyCover(CoverRequest.set(
      lib: base.lib,
      work: base.work,
      scope: base.scope,
      at: base.at,
      index: base.index,
      rect: res.rect,
    ));
  }

  /// 可见的封面入口：**全 App 唯一的封面菜单**（基础库 / 单元库四项）。
  ///
  /// 0.9.191（owner 2026-11-24）：以前长按信息区菜单里另有两条封面项
  /// （设/清基础库封面），与封面按钮里的面板说法不一、重叠两套；
  /// 现在长按菜单只留一个「封面…」入口，四项全部收起在
  /// [ _openCoverSheet ] 里，任何入口弹出的都是同一份菜单。
  void _openCoverSheet() {
    final w = _workAt(cur);
    final lib = _libFor(w);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_size_select_actual_outlined),
            title: const Text('设为该库封面'),
            subtitle: const Text('用当前画面框选作为基础库封面，不影响原文件'),
            onTap: () {
              Navigator.of(ctx).pop();
              _cropAndApplyCover(w, CoverScope.basic);
            },
          ),
          ListTile(
            leading: const Icon(Icons.hide_image_outlined),
            title: const Text('清除自定义封面'),
            subtitle: const Text('恢复自动封面（爬虫封面 → 最高播放作品）'),
            onTap: () {
              Navigator.of(ctx).pop();
              _confirmClearCover(lib);
            },
          ),
          ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: const Text('设为该单元库封面'),
            subtitle: const Text('用当前画面框选作为所属单元库封面，不动作品原图'),
            onTap: () {
              Navigator.of(ctx).pop();
              _cropAndApplyCover(w, CoverScope.unit);
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_off_outlined),
            title: const Text('清除单元库封面'),
            subtitle: const Text('恢复该单元库的自动封面'),
            onTap: () {
              Navigator.of(ctx).pop();
              _confirmClearCover(lib, scope: CoverScope.unit);
            },
          ),
          const SizedBox(height: 4),
        ]),
      ),
    );
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
            // 0.9.191：封面统一入口——四项全收进同一个面板，不再两套说法。
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('封面…'),
              subtitle: const Text('基础库 / 单元库：选画面、恢复自动、清除'),
              onTap: () {
                Navigator.of(ctx).pop();
                _openCoverSheet();
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

  // 0.9.29：清除自定义封面前先确认（服务端只删指针，封面文件保留可回滚）。
  Future<void> _confirmClearCover(String lib,
      {CoverScope scope = CoverScope.basic}) async {
    final unit = scope == CoverScope.unit;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(unit ? '清除单元库封面？' : '清除自定义封面？'),
        content: Text(unit
            ? '该单元库会恢复自动封面（子树最高播放基础库 → 第一个有封面的基础库）。'
                '作品原图不受影响。'
            : '会恢复该库的自动封面（爬虫封面 → 最高播放作品）。'
                '已生成的封面图片仍保留在库里，之后再设回来不会丢。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('清除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _applyCover(CoverRequest.clear(lib: lib, scope: scope));
  }

  // 0.9.19/0.9.29/0.9.35：自定义封面设置与清除（服务端只新增文件、改指针，
  // 单元库封面只改 unit-covers.json：都不动作品原图）。
  Future<void> _applyCover(CoverRequest req) async {
    if (!req.valid) {
      _toast('${req.failText}：缺少库或作品标识');
      return;
    }
    final lib = req.lib;
    try {
      final r = await http.post(
        cfg.u(req.scope.path, lib: lib),
        headers: {...cfg.headersFor(lib), 'Content-Type': 'application/json'},
        body: jsonEncode(req.toBody()),
      );
      if (r.statusCode != 200) {
        _toast('${req.failText}：${coverErrorText(r.statusCode)}');
        return;
      }
      _toast(req.doneText);
      // 封面已写入服务端：通知主页/库页重新拉取封面索引，立即显示新封面。
      coverRevision.value++;
    } catch (e) {
      _toast('${req.failText}：$e');
    }
  }

  // G11：跳到记录位置（「继续观看」）
  void _resumePlayback(int at) {
    try {
      player.seek(Duration(milliseconds: at));
    } catch (_) {}
    setState(() => pos = Duration(milliseconds: at));
    if (paused) {
      _feed(PlaybackEvent.play);
      setState(() => _pausedIntent = false);
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

  /// 任务栏槽位 → 控件。只做映射，不参与排布决策（排布在 [taskbarPlan]）。
  Widget _taskbarSlotWidget({
    required TaskbarSlot slot,
    required bool fs,
    required double tbBtnW,
    required TaskbarPolicy taskbar,
    required int chapterCount,
    required bool paused,
    required double speed,
    required bool muted,
    required double volume,
    required VoidCallback toggleFs,
    required VoidCallback toggleOrientation,
  }) {
    switch (slot) {
      case TaskbarSlot.play:
        // M3/O2：桌面端播放/暂停常驻任务栏主位；手机端由画面中央大圆钮承担。
        return TaskbarPlayButton(paused: _showsPaused, onPressed: togglePause);
      case TaskbarSlot.episodes:
        // J5：视频合集章节——`1/12` 单入口，点击弹出集数列表。
        return TaskbarEpisodeButton(
          current: _chapter + 1,
          total: chapterCount,
          width: fs ? 46 : tbBtnW,
          onPressed: _showChapters,
        );
      case TaskbarSlot.settings:
        // owner 2026-11-24：只保留一个集成设置入口。自动连播/单条循环/乱序
        // 都在这个菜单里，任务栏不再重复摆按钮（重复入口只增加误触）。
        return TaskbarSettingsButton(
          speed: speed,
          width: fs ? 46 : tbBtnW,
          onPressed: _showPlaybackSettings,
        );
      case TaskbarSlot.sound:
        // H14：点击=静音切换；长按/左右拖动调音量（不弹模块）。
        return TaskbarSoundButton(
          muted: muted,
          volume: volume,
          width: fs ? 48 : tbBtnW,
          onTap: toggleMute,
          onLongPressStart: _volLongPressStart,
          onLongPressMoveUpdate: _volLongPressMove,
          onLongPressEnd: (_) => _volDragEnd(),
          onHorizontalDragStart: _volDragStart,
          onHorizontalDragUpdate: _volDragUpdate,
          onHorizontalDragEnd: _volDragEnd,
        );
      case TaskbarSlot.volume:
        // L6：桌面端音量模块常驻任务栏（声音按钮右侧）。
        return _taskbarVolumeModule();
      case TaskbarSlot.drop:
        return _taskbarDropButton(fs: fs, tbBtnW: tbBtnW);
      case TaskbarSlot.display:
        // owner 2026-11-23：移动端点按=全屏、长按=横竖屏；桌面端独立全屏按钮。
        return taskbar.showRotate
            ? TaskbarDisplayButton(
                fullscreen: fs,
                mobile: true,
                width: fs ? 46 : tbBtnW,
                onPressed: toggleFs,
                onLongPress: toggleOrientation,
              )
            : TaskbarDisplayButton(
                fullscreen: fs,
                mobile: false,
                onPressed: toggleFs,
              );
    }
  }

  /// 桌面端常驻音量滑杆（104dp）。
  Widget _taskbarVolumeModule() => SizedBox(
        key: const ValueKey('volume-module'),
        width: 104,
        height: 48,
        child: Row(children: [
          Expanded(
            child: SliderTheme(
              data: const SliderThemeData(
                trackHeight: 2.5,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.white70,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
              ),
              child: Slider(
                value: (muted ? 0.0 : volume).clamp(0.0, 100.0),
                max: 100,
                onChanged: _setVolume,
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text('${volume.round()}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ),
        ]),
      );

  /// J-A1：播放页不再展示水滴数量/余额，只保留赠送动作。
  Widget _taskbarDropButton({required bool fs, required double tbBtnW}) => Tooltip(
        message: '送一颗小水滴',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (dropBusy || dropDayLeft <= 0 || dropWeekLeft <= 0)
              ? null
              : _sendDrop,
          child: SizedBox(
            width: fs ? 48 : tbBtnW,
            height: 48,
            child: ScaleTransition(
              scale: _dropScale,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (dropBusy)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white54))
                  else
                    Icon(Icons.water_drop,
                        size: fs ? 20 : kTaskbarIconSize,
                        color: _dropIconColor(fs: fs)),
                ],
              ),
            ),
          ),
        ),
      );

  /// 水滴图标配色：全屏沿用旧的 70%/24% 白，非全屏用纯白/未激活色。
  Color _dropIconColor({required bool fs}) {
    if (dropGlow && dropDayLeft >= 0) return Colors.lightBlueAccent;
    final active = dropDayLeft > 0 && dropWeekLeft > 0;
    if (fs) return active ? Colors.white70 : Colors.white24;
    return active ? Colors.white : kTaskbarInactiveColor;
  }

  /// 「更多」菜单里的文案。
  String _taskbarSlotLabel(TaskbarSlot s) => switch (s) {
        TaskbarSlot.play => '播放/暂停',
        TaskbarSlot.episodes => '选集',
        TaskbarSlot.settings => '播放设置 ${speedLabel(speed)}',
        TaskbarSlot.sound => '声音',
        TaskbarSlot.volume => '音量',
        TaskbarSlot.drop => '送一颗小水滴',
        TaskbarSlot.display => '显示 / 全屏',
      };

  /// 「更多」菜单选中后的动作：与可见按钮走同一批处理函数，不复制逻辑。
  void _taskbarSlotAction(TaskbarSlot s) {
    switch (s) {
      case TaskbarSlot.play:
        togglePause();
      case TaskbarSlot.episodes:
        _showChapters();
      case TaskbarSlot.settings:
        _showPlaybackSettings();
      case TaskbarSlot.sound:
        toggleMute();
      case TaskbarSlot.volume:
        // 音量模块无法塞进菜单（滑杆需要连续拖动），菜单项改为静音切换入口。
        toggleMute();
      case TaskbarSlot.drop:
        if (!dropBusy && dropDayLeft > 0 && dropWeekLeft > 0) _sendDrop();
      case TaskbarSlot.display:
        toggleFs();
    }
  }

  String fmt(Duration d) {
    return formatClock(d);
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
                : f.kind == PlaybackFailureKind.missing
                    ? Icons.file_present_outlined
                    : f.kind == PlaybackFailureKind.denied
                        ? Icons.lock_outline
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
              // 文件不存在/被拒绝：重试永远同一个结果，直接给「下一条」；
              // 已经是最后一条时给「返回」，不让用户卡在一个无按钮的弹层里。
              else if (cur < widget.works.length - 1)
                FilledButton.icon(
                  onPressed: next,
                  icon: const Icon(Icons.keyboard_arrow_up, size: 18),
                  label: const Text('下一条'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(120, 38)),
                )
              else
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('返回'),
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

  /// T：本页舞台底部的进度层（进度条 / 图文分段 / 集数标签）。
  ///
  /// 放在 PageView 子页的 Stack 内、贴舞台底边，随页面一起上下位移；
  /// 页面级只留不透明任务栏自身控件。进度条的操作仍是全局控制当前视频，
  /// 这里只改变视觉归属。
  Widget _stageProgressOverlay({
    required dynamic w,
    required bool isV,
    required List<String> pics,
    required int idx,
    required double progress,
  }) {
    // owner 2026-11-18：只有「单张图的图文」整层隐藏（计数也不显示）；
    // 多图图文仍要分段进度条。视频不受影响。
    if (!isV && pics.length <= 1) return const SizedBox.shrink();
    if (!isV) {
      // owner 2026-11-18：图文的分段进度条也紧贴任务栏上缘（通栏细条）。
      return _picProgressFlush(
          pics: pics,
          idx: idx,
          lift: fs ? _liveTaskbarHeight(MediaQuery.paddingOf(context)) : 0.0);
    }
    // 非全屏视频：呼出式进度条（贴任务栏上缘、极细、不操作时不可见）。
    // 全屏保留旧进度条，避免破坏沉浸态已有的呼出/隐藏逻辑。
    if (isV) {
      // 全屏时任务栏是浮层，进度条贴它的上缘，而不是屏幕最底。
      return _scrubOverlay(progress: progress, lift: fs ? _taskbarH : 0.0);
    }
    final pad = MediaQuery.paddingOf(context);
    final opacity = ChromeFade.opacity(
        uiVisible: ui, fullscreen: fs, swiping: _pageSwiping);
    final ms = ChromeFade.durationMs(swiping: _pageSwiping);
    final chapters = workChapterCount(w);
    // P0 §3：非全屏进度条距任务栏 8dp（全屏保持旧值 10dp）。
    final bottom = stageProgressBottomOffset(
        safeBottom: fs ? pad.bottom : 0, padding: fs ? 10 : kProgressBottomGap);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !ui,
        child: AnimatedOpacity(
          opacity: opacity,
          duration: Duration(milliseconds: ms),
          curve: Curves.easeOut,
          child: Padding(
            padding: EdgeInsets.only(
                left: pad.left + kProgressSideMargin,
                right: pad.right + kProgressSideMargin,
                bottom: bottom),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // 集数标签（视频合集）：随页移动，不再固定在页面级底栏。
              if (chapters > 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                      '第 ${_chapter.clamp(0, chapters - 1) + 1}/$chapters 集 · '
                      '${chapterLabel(workChapters(w)[_chapter.clamp(0, chapters - 1)], _chapter)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5, color: Colors.lightBlueAccent)),
                ),
              Row(children: [
                Text(
                    isV
                        ? '${fmt(pos)} / ${fmt(dur)}'
                        // 单图没有“第几张/共几张”，不显示计数
                        : (pics.length > 1
                            ? '${(dragging && dragPic != null ? dragPic! : idx) + 1}/${pics.length}'
                            : ''),
                    // P0 §3：非全屏时间 11px tabular / 白 90%。
                    style: fs
                        ? const TextStyle(fontSize: 10, color: Colors.white60)
                        : kProgressTimeStyle),
                const SizedBox(width: 8),
                Expanded(
                  child: LayoutBuilder(builder: (ctx, cons) {
                    if (!isV && pics.length <= 1) {
                      return const SizedBox.shrink();
                    }
                    if (!isV) {
                      return _picProgressBar(
                          pics: pics, idx: idx, width: cons.maxWidth);
                    }
                    return _videoProgressBar(
                        progress: progress,
                        width: cons.maxWidth,
                        // P0 §3 只改非全屏的进度条视觉与按下/拖动交互。
                        spec: !fs);
                  }),
                ),
                const SizedBox(width: 8),
                Text('${cur + 1} / ${widget.works.length}',
                    style: fs
                        ? const TextStyle(fontSize: 10, color: Colors.white54)
                        : const TextStyle(
                            fontSize: kProgressTimeFontSize,
                            color: Color(0xB3FFFFFF),
                            fontFeatures: [FontFeature.tabularFigures()])),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  /// 视频进度条：点击跳转、横向拖动预览；按下暂停、松手才 seek 并恢复。
  /// J4 语义不变：拖动期间当前视频不切条，松手才落定。
  /// P0 §3：非全屏（[spec]）按下即暂停；常态 2dp/白 60%/圆角 1dp，
  /// 按住或拖动 4dp/全白/圆角 2dp；拖动显示 mm:ss 气泡；松手恢复（仅原本在播）。
  /// 全屏（spec=false）保持旧视觉与旧拖动语义。
  /// 呼出式进度条浮层：底部 28dp 热区，整条宽度可拖。
  Widget _scrubOverlay({required double progress, double lift = 0}) {
    // owner 2026-11-22：全屏下进度条完全跟随功能区——功能区隐藏时，
    // 进度条与拖动热区都要一起消失，热区也不能再把进度条「呼出」回来。
    if (fs && !ui) return const SizedBox.shrink();
    final desktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    // 全屏时进度条要跟功能区一起随时间隐藏；非全屏桌面端才常驻细条。
    // owner 2026-11-21：全屏下进度条不能常驻——呼出后单击就该收起。
    // 桌面端常驻只在非全屏保留（那时它是视频与任务栏的分界线）。
    // owner 2026-11-22：全屏不再用「呼出式」——进度条跟任务栏一起常驻，
    // 随功能区一起显示、一起在自动隐藏时间到后消失；非全屏保持原样。
    final persistent = ui && (desktop || fs);
    final active = _scrubActive || (_scrubHover && (!fs || ui));
    // owner 2026-11-22：进度条属于「信息层」，非全屏滑动时与信息区一起淡化；
    // 全屏走原有的显示/隐藏，不叠加第二套透明度。
    final fade = ChromeFade.infoOpacity(
        uiVisible: ui, fullscreen: fs, swiping: _pageSwiping);
    final fadeMs = ChromeFade.durationMs(swiping: _pageSwiping);
    final layer = LayoutBuilder(builder: (_, c) {
        final width = c.maxWidth;
        return Stack(children: [
          // 绘制层：轨道与气泡。气泡预留的 34dp 是**视觉空间**，必须不可
          // 命中——整块 62dp 都当热区时，它会盖住上方信息区，头像/作者名
          // 的点击被这里吞掉（无指针事件、无日志）。
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ScrubBar(
                  // P2：不拖动时直接订阅播放进度（ValueListenable），
                  // 播放中不再需要整页 setState 才能让进度条动。
                  fraction: _scrubActive ? _scrubFracVN : _progressVN,
                  active: active,
                  visible: active || _scrubThin || persistent,
                  labelFor: (f) => dur.inMilliseconds > 0
                      ? '${fmt(dur * f)} / ${fmt(dur)}'
                      : '',
                ),
              ),
            ),
          ),
          // 命中层：只有贴底的 kScrubHotZoneHeight 条带响应拖动/悬停。
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: kScrubHotZoneHeight,
            child: MouseRegion(
              // 桌面端：指针进入条带即放大成可拖状态，移出恢复细条。
              onEnter: (_) {
                if (_scrubHover) return;
                if (fs && !ui) return; // 全屏清屏状态下不因悬停把进度条叫出来
                setState(() => _scrubHover = true);
              },
              onExit: (_) {
                if (!_scrubHover) return;
                setState(() => _scrubHover = false);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 内层手势优先：底部横向拖动归进度条，不再触发“左拖进作者页”。
                // owner 2026-11-20：进度条只认「横向拖动」，不再响应点按。
                onHorizontalDragStart: (d) =>
                    _scrubStart(d.localPosition, width),
                onHorizontalDragUpdate: (d) =>
                    _scrubMove(d.localPosition, width),
                onHorizontalDragEnd: (_) => _scrubEnd(),
                onHorizontalDragCancel: () => _scrubEnd(),
              ),
            ),
          ),
        ]);
      });
    if (fade >= 1) {
      return Positioned(
        left: 0,
        right: 0,
        bottom: lift,
        height: kScrubHotZoneHeight + kScrubBubbleSpace,
        child: layer,
      );
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: lift,
      height: kScrubHotZoneHeight + kScrubBubbleSpace,
      child: AnimatedOpacity(
        opacity: fade,
        duration: Duration(milliseconds: fadeMs),
        curve: Curves.easeOut,
        child: layer,
      ),
    );
  }

  void _scrubStart(Offset p, double width) {
    if (!mounted || width <= 0) return;
    _scrubThinTimer?.cancel();
    final f = (p.dx / width).clamp(0.0, 1.0);
    _scrubFrac = f;
    _scrubFracVN.value = f;
    setState(() => _scrubActive = true);
  }

  void _scrubMove(Offset p, double width) {
    if (!mounted || !_scrubActive || width <= 0) return;
    final next = (p.dx / width).clamp(0.0, 1.0);
    final prev = _scrubFrac;
    if (prev != null && (prev - next).abs() < 0.002) return;
    _scrubFrac = next;
    // 只让进度条重绘；整页 setState 会让播放器/视频树跟着重建，拖动时容易崩。
    _scrubFracVN.value = next;
  }

  /// 松手才跳转：拖动过程不暂停、不 seek，避免解码器被反复拖动。
  void _scrubEnd() {
    if (!mounted || !_scrubActive) return;
    final f = _scrubFrac;
    if (f != null && dur.inMilliseconds > 0) {
      // 页面可能正在切走，播放器已释放；seek 失败不能让整个 App 崩。
      try {
        player.seek(dur * f);
      } catch (e) {
        debugPrint('[scrub] seek failed: $e');
      }
    }
    setState(() {
      _scrubActive = false;
      _scrubFrac = null;
      _scrubThin = true;
    });
    _scrubThinTimer?.cancel();
    _scrubThinTimer = Timer(const Duration(milliseconds: kScrubThinHoldMs), () {
      if (!mounted) return;
      setState(() => _scrubThin = false);
    });
  }

  Widget _videoProgressBar({
    required double progress,
    required double width,
    bool spec = false,
  }) {
    void seekAt(Offset p) {
      if (dur.inMilliseconds == 0) return;
      final f = (p.dx / width).clamp(0.0, 1.0);
      player.seek(dur * f);
    }

    // 按下即进入「按住」态并暂停；只在原本播放时记录松手恢复。
    void beginSeek(Offset p) {
      if (_seeking) return;
      _seeking = true;
      resumeAfterDrag = !paused;
      if (!paused) {
        _userPaused = true;
        PauseTrace.mark('user:seek-press');
        Breadcrumb.mark('player:pause', 'L11202');
        player.pause();
      }
      setState(() {
        dragging = true;
        dragFrac = (p.dx / width).clamp(0.0, 1.0);
      });
    }

    // 松手：spec 模式里 commit=true 时 seek 并（仅原本在播）恢复播放。
    void endSeek({bool commit = true}) {
      if (!_seeking) return;
      _seeking = false;
      final f = dragFrac ?? progress;
      if (commit && dur.inMilliseconds > 0) {
        player.seek(dur * f);
        if (resumeAfterDrag) {
          _userPaused = false;
          _stallAttempts = 0;
          player.play();
        }
      } else if (resumeAfterDrag) {
        _userPaused = false;
        _stallAttempts = 0;
        player.play();
      }
      setState(() {
        dragging = false;
        dragFrac = null;
      });
    }

    final pressed = spec && (dragging || _seeking);
    final metrics = stageProgressMetrics(pressed: pressed);
    final idleH =
        spec ? kProgressIdleHeight : ((dragging || barHover) ? 7.0 : 3.0);
    final h = spec ? metrics.height : idleH;
    final trackColor = spec ? metrics.trackColor : Colors.white24;
    final playedColor =
        spec ? metrics.playedColor : (dragging ? Colors.white : Colors.white70);
    final radius =
        spec ? BorderRadius.circular(metrics.radius) : BorderRadius.circular(0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: spec ? (d) => beginSeek(d.localPosition) : null,
      onTapUp: spec
          ? (d) {
              seekAt(d.localPosition);
              endSeek(commit: false);
            }
          : (d) => seekAt(d.localPosition),
      onTapCancel: spec ? () => endSeek(commit: false) : null,
      onHorizontalDragStart: (d) {
        if (spec) {
          beginSeek(d.localPosition);
          return;
        }
        resumeAfterDrag = !paused;
        if (!paused) {
          _userPaused = true;
          PauseTrace.mark('user:seek-drag');
          Breadcrumb.mark('player:pause', 'L11265');
          player.pause();
        }
        setState(() {
          dragging = true;
          dragFrac = progress;
        });
      },
      onHorizontalDragUpdate: (d) {
        final f = (d.localPosition.dx / width).clamp(0.0, 1.0);
        setState(() => dragFrac = f);
      },
      onHorizontalDragEnd: spec
          ? (_) => endSeek()
          : (_) {
              final f = dragFrac ?? progress;
              if (dur.inMilliseconds > 0) {
                player.seek(dur * f);
                if (resumeAfterDrag) {
                  _userPaused = false;
                  _stallAttempts = 0;
                  player.play();
                }
              }
              setState(() {
                dragging = false;
                dragFrac = null;
              });
            },
      onHorizontalDragCancel: spec ? () => endSeek(commit: false) : null,
      child: MouseRegion(
        onEnter: (_) => setState(() => barHover = true),
        onExit: (_) => setState(() => barHover = false),
        child: SizedBox(
          height: 30,
          child: Stack(
            // P0：拖动气泡画在轨道上方，不能裁掉。
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                  height: h,
                  decoration:
                      BoxDecoration(color: trackColor, borderRadius: radius)),
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: dragFrac ?? progress,
                child: Container(
                    height: h,
                    decoration: BoxDecoration(
                        color: playedColor, borderRadius: radius)),
              ),
              // P0 §3：拖动气泡（12px / #CC000000 / 圆角 6dp / mm:ss）。
              if (spec && dragging && dragFrac != null)
                Positioned(
                  left: ((dragFrac! * width) - 24)
                      .clamp(0.0, (width - 48).clamp(0.0, width)),
                  top: -28,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        color: kSeekBubbleColor,
                        borderRadius: BorderRadius.circular(kSeekBubbleRadius)),
                    child: Text(fmt(dur * (dragFrac ?? 0)),
                        style: kSeekBubbleTextStyle),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 图文分段进度：按图片数量分段，当前张高亮；拖动不震动，松手才切图。
  /// 图文分段进度条（贴任务栏上缘、通栏、细条）。
  ///
  /// 与视频的呼出式进度条同一位置基准：常态 2.5dp，手指按住放大到 6dp，
  /// 左右拖动切图，松手落定。
  Widget _picProgressFlush({
    required List<String> pics,
    required int idx,
    double lift = 0,
  }) {
    int picAt(Offset p, double width) =>
        picIndexAtFraction(width <= 0 ? 0 : p.dx / width, pics.length);
    // owner 2026-11-22：图文分段条与视频进度条同一口径——非全屏滑动时淡化，
    // 全屏仍按功能区显示/隐藏（拖动中不淡化，否则拖一半看不清目标段）。
    final fade = ChromeFade.infoOpacity(
        uiVisible: true, fullscreen: fs, swiping: _pageSwiping);
    return Positioned(
      left: 0,
      right: 0,
      bottom: lift,
      height: kScrubHotZoneHeight,
      child: LayoutBuilder(builder: (_, c) {
        final width = c.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            stopAuto();
            setState(() => _setPicIndex(picAt(d.localPosition, width)));
            hapticTap();
          },
          onHorizontalDragStart: (d) {
            stopAuto();
            _picDragVN.value = picAt(d.localPosition, width);
          },
          onHorizontalDragUpdate: (d) {
            final k = picAt(d.localPosition, width);
            // 只让分段条重绘；整页 setState 会在拖动中重建播放器树，
            // 是图文拖动闪退的直接原因。
            _picDragVN.value = k;
          },
          onHorizontalDragEnd: (_) {
            final k = _picDragVN.value;
            _picDragVN.value = null;
            setState(() {
              if (k != null) _setPicIndex(k);
            });
          },
          onHorizontalDragCancel: () {
            _picDragVN.value = null;
          },
          // owner 2026-11-18：全屏清屏时图文/图片合集的进度条必须跟任务栏
          // 一起消失；非全屏与拖动中保持可见。
          child: ValueListenableBuilder<int?>(
            valueListenable: _picDragVN,
            builder: (_, drag, __) {
              final draggingNow = drag != null;
              return IgnorePointer(
                ignoring: fs && !ui && !draggingNow,
                child: AnimatedOpacity(
                  opacity: (!fs || ui || draggingNow)
                      ? (draggingNow ? 1.0 : fade)
                      : 0,
                  duration: const Duration(milliseconds: kScrubFadeMs),
                  curve: Curves.easeOut,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(pics.length, (k) {
                        final selected = k == (drag ?? idx);
                        final active = k <= (drag ?? idx);
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            height: draggingNow
                                ? (selected ? 6 : 3)
                                : kScrubThinHeight,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: active
                                  ? (selected ? Colors.white : Colors.white70)
                                  : Colors.white24,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      }),
    );
  }

  Widget _picProgressBar({
    required List<String> pics,
    required int idx,
    required double width,
  }) {
    // H1：按下即进入拖动，松手才切换图片（owner 2026-11-21：去掉滑动震动）；
    // 拖动中的目标段放大到与视频进度条一致（7px）。
    int picAt(Offset p) => picIndexAtFraction(p.dx / width, pics.length);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        stopAuto();
        setState(() => _setPicIndex(picAt(d.localPosition)));
        hapticTap();
      },
      onHorizontalDragStart: (d) {
        stopAuto();
        final k = picAt(d.localPosition);
        setState(() {
          dragging = true;
          dragPic = k;
          dragFrac = ((k + 0.5) / pics.length).clamp(0.0, 1.0);
        });
      },
      onHorizontalDragUpdate: (d) {
        final f = (d.localPosition.dx / width).clamp(0.0, 1.0);
        final k = picIndexAtFraction(f, pics.length);
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
          children: List.generate(pics.length, (k) {
            final selected = k == (dragging ? dragPic : idx);
            final active = k <= (dragging ? (dragPic ?? idx) : idx);
            return Expanded(
              child: Container(
                height: 30,
                alignment: Alignment.center,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: dragging ? (selected ? 7 : 3) : (selected ? 6 : 3),
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: active
                        ? (selected ? Colors.white : Colors.white70)
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
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
    // owner 2026-11-22：信息区（头像/作者名/简介）与进度条单独淡化——
    // 顶部返回/封面按钮、底部任务栏保持不淡化，所以这里是第二套透明度。
    final infoOpacity = ChromeFade.infoOpacity(
        uiVisible: ui, fullscreen: fs, swiping: _pageSwiping);
    // P2 §12：非全屏沉浸只淡出右侧互动栏与左侧信息区（200ms easeOut），
    // 页内进度条不参与；全屏不受影响。
    final immersiveFade = !fs && _imm.immersive;
    final railOpacity = chromeOpacity *
        ImmersivePolicy.opacity(uiVisible: ui, immersive: immersiveFade);
    final railMs = ImmersivePolicy.durationMs(
        immersive: immersiveFade, fallbackMs: chromeMs);
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
    final viewSize = MediaQuery.sizeOf(context);
    // P1 §4：非全屏任务栏控件间距（320dp 窄屏压到 20dp）；全屏保持旧值不动。
    final tbSpacing = taskbarSpacingFor(viewSize.width);
    final tbBtnW = kTaskbarIconSize + tbSpacing;
    // owner 2026-11-22：任务栏按「取舍」排布，不再用 FittedBox 整体缩放。
    // 缩放会把 44dp 触达区悄悄压到 30dp 以下（点不中），改为把低优先级
    // 槽位收进「更多」菜单，任何按钮都保持原尺寸。
    final tbSlots = <TaskbarSlot>[
      if (taskbar.showPlayPause) TaskbarSlot.play,
      if (workChapterCount(w) > 1) TaskbarSlot.episodes,
      // owner 2026-11-24：只保留一个集成设置入口。自动连播/单条循环/乱序
      // 都在这个菜单里，不重复摆到任务栏上——重复入口只增加误触。
      TaskbarSlot.settings,
      if (_volumeUi) TaskbarSlot.sound,
      if (_volumeUi) TaskbarSlot.volume,
      TaskbarSlot.drop,
      TaskbarSlot.display,
    ];
    final tbWidthOf = <TaskbarSlot, double>{
      TaskbarSlot.play: 48,
      TaskbarSlot.episodes: fs ? 46.0 : tbBtnW,
      TaskbarSlot.settings: fs ? 46.0 : tbBtnW,
      TaskbarSlot.sound: fs ? 48.0 : tbBtnW,
      // 桌面端音量模块固定 104dp，明显比其他按钮宽，必须按真实宽度算。
      TaskbarSlot.volume: 104,
      TaskbarSlot.drop: fs ? 48.0 : tbBtnW,
      TaskbarSlot.display: taskbar.showRotate ? (fs ? 46.0 : tbBtnW) : 48,
    };
    // 桌面端允许全部可见；移动端按宽度取舍。
    // owner 2026-11-24：加入自动连播/单条循环/乱序三个开关后，旧的「最多
    // 5 个」会把常用按钮挤进「更多」菜单。上限放宽到 8，真正的约束交给
    // 宽度（放不下才进菜单），但全屏键无论如何都保留。
    final tbPlan = taskbarPlan(
      items: tbSlots,
      availableWidth: viewSize.width -
          pad.left -
          pad.right -
          (fs ? 24 : kTaskbarSidePadding * 2),
      widthOf: (s) => tbWidthOf[s] ?? tbBtnW,
      maxVisible: taskbar.showRotate ? 8 : 99,
    );
    // A/T：任务栏实底后，视频舞台内缩到栏上方（首帧栏高未知，测量后校正）；
    // 移动端全屏为沉浸式，任务栏隐藏、舞台铺满屏幕。
    // 全屏：保留旧的「单击呼出/隐藏」逻辑——任务栏始终渲染为半透明浮层，
    // 显隐由 ui（及 chromeOpacity）控制；舞台仍铺满整屏不占位。
    final hideTaskbar = false;
    // owner 2026-11-19：任务栏「跟随视频」暂时关闭。
    // 它在留边视频上导致画面/信息区被任务栏盖住（多处反馈），
    // 先回到稳定布局：任务栏恒贴屏幕底，舞台恒让出栏高。
    final _taskbarHNow = _taskbarH > 0
        ? _taskbarH
        : taskbarReservedHeight(
            contentHeight: kTaskbarHeight, safeBottom: pad.bottom);
    final stageInset = broken
        ? 0.0
        : stageBottomInset(
            screenHeight: viewSize.height,
            taskbarHeight: _taskbarHNow,
            fullscreen: fs,
          );
    // T：进度层贴在本页舞台底边（PageView 子页 Stack 内）；作者/标题信息行
    // 在进度层上方避让，避免压住进度条。
    final progressBottom =
        stageProgressBottomOffset(safeBottom: fs ? pad.bottom : 0);
    final chapterCount = workChapterCount(w);
    // 页内浮层坐标：舞台已让掉任务栏（stageInset），这里不能再加一次。
    // 单图图文没有进度层，信息区直接贴到舞台底部上方 10dp，不留空位。
    final noProgressLayer = !isV && pics.length <= 1;
    // 非全屏进度条真正可命中的是贴底 kScrubHotZoneHeight 的条带（气泡预留
    // 区只做绘制，见 _scrubOverlay）。信息区必须让开「条带」而不是 2.5dp
    // 细线，否则头像下半截落在热区里，点击被整块吞掉（0.9.144 实测：
    // 头像位置完全没有指针事件）。
    final infoBottomInPage = stageInfoBottom(
      fullscreen: fs,
      hasProgressLayer: !noProgressLayer,
      hasChapter: chapterCount > 1,
      progressBottom: progressBottom,
      hitStripHeight: kScrubHotZoneHeight,
    );
    if (!broken) _scheduleTaskbarMeasure();
    // 邻页缓存只保留当前 ±2，避免滑动久后持有过多封面。
    _neighborPages.removeWhere((k, _) {
      final bar = k.indexOf('|');
      final idx = bar < 0 ? -1 : (int.tryParse(k.substring(0, bar)) ?? -1);
      return idx < cur - 2 || idx > cur + 2;
    });
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
            // P2：记下按下瞬间的沉浸态；暂停计时，抬起后统一恢复。
            if (!fs) {
              _immAtDown = _imm.immersive;
              _immTimer?.cancel();
              _immTimer = null;
            }
            // P1b：非全屏视频舞台长按（500ms / 位移 ≤12px）候选起点。
            if (pointers == 0) {
              _suppressStageTap = false;
              _stageLongPressDown(e);
            }
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
            _stageLongPressMove(e);
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
            _stageLongPressUp();
            _stagePointers.remove(e.pointer);
            // P2：任何一次抬手都恢复互动栏/信息区并重新计时。
            if (!fs) {
              if (_imm.immersive) {
                _imm.touch();
                if (mounted) setState(() {});
              }
              _scheduleImmersive();
            }
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
                  hideTimer = null;
                  _hideDeadline.clear();
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
            _lpTracker.cancel();
            _lpTimer?.cancel();
            _stagePointers.remove(e.pointer);
            if (!fs) {
              _immAtDown = false;
              _scheduleImmersive();
            }
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
              // A：播放视口不含底部实底任务栏。
              Padding(
                padding: EdgeInsets.only(bottom: stageInset),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (n) {
                    if (n.depth != 0) return false;
                    if (n is ScrollStartNotification && n.dragDetails != null) {
                      _setPageSwiping(true);
                    } else if (n is ScrollEndNotification) {
                      _setPageSwiping(false);
                      // J-A4：拖动/回弹结束后才切条，拖拽过程中旧视频继续播放。
                      final pending = _swipePendingIndex;
                      _swipePendingIndex = null;
                      if (pending != null && pending != cur) open(pending);
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
                        : DiziPageScrollPhysics(
                            parent: const ClampingScrollPhysics(),
                            fromPage: cur.toDouble()),
                    // I2：移动端抖音式手感——越界阻尼 + 松手快速吸附（三端一致无回弹）
                    dragStartBehavior: DragStartBehavior.down,
                    scrollDirection: Axis.vertical,
                    // C：预载相邻页并参与 render，拖动时邻页已挂载。
                    // 稳定性优先：不提前挂载邻页，避免同时存在多个解码器导致 OOM 闪退。
                    allowImplicitScrolling: false,
                    itemCount: widget.works.length,
                    onPageChanged: (i) {
                      // J-A4：手势滑动中只记下标，等 ScrollEnd 确认后再切；
                      // 键盘/按钮的程序化翻页（不在滑动中）保持立即切换。
                      if (_pageSwiping) {
                        _swipePendingIndex = i;
                      } else {
                        open(i);
                      }
                    },
                    itemBuilder: (_, i) {
                      final it = _workAt(i);
                      if (!workPlayable(it)) return _brokenWorkView(it);
                      if (i != cur) {
                        // C：邻页拆成独立子组件并复用实例；预载页先铺封面，
                        // setState 时 Element 不重建，拖动进页不黑屏。
                        final page = _neighborPageFor(i);
                        // 拖动时把信息层也挂到邻页上：头像/文案跟画面一起滑进来，
                        // 落页后不再「凭空冒出一段文字」。不拖动时不建，省开销。
                        if (!_pageSwiping) return page;
                        return Stack(fit: StackFit.expand, children: [
                          page,
                          ..._stageOverlayChildren(
                            w: it,
                            fs: fs,
                            broken: false,
                            pad: pad,
                            bottom: infoBottomInPage,
                            viewSize: viewSize,
                            chromeOpacity: chromeOpacity,
                            chromeMs: chromeMs,
                            infoOpacity: infoOpacity,
                            immersiveFade: immersiveFade,
                            railOpacity: railOpacity,
                            railMs: railMs,
                          ),
                        ]);
                      }
                      if (it['t'] == 'v') {
                        // 海报底图与卡片同一个解析入口（th → 图文首图 →
                        // /api/thumb 抽帧）。
                        //
                        // 根因（0.9.148 复测后定位）：下面这层海报的显示条件还
                        // 停留在旧口径 `it['th']`，而视频作品大量没有 `th`
                        // （封面走 `/api/thumb` 抽帧）。于是作者/单元库网格里
                        // 卡片明明有封面，播放页却**整层海报都不建**，首帧之前
                        // 只有黑色 → 「有声黑屏」在这条入口必然复现、在基础库
                        // 网格（作品都有 th）不复现。条件收敛到封面地址后，
                        // 有封面就一定先铺海报。
                        final posterCover = _posterCoverUrl(it);
                        return GestureDetector(
                          // 默认 deferToChild：只有子组件画到的像素才响应。
                          // 视频 contain 铺在中间时，四周黑边点下去没有任何
                          // handler，点击被直接吞掉。opaque 让整块舞台都算命中。
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (d) => onStageTap(d.localPosition),
                          // M9：抖音式跟手拖拽——向左拖作者页随手指从右侧滑入，
                          // 松手 ≥30% 屏宽或左向速度足够则进入，否则回弹。
                          onHorizontalDragStart: (d) => _authorDragStart(
                              d.globalPosition.dx,
                              MediaQuery.sizeOf(context).width,
                              startDy: d.globalPosition.dy),
                          onHorizontalDragUpdate: (d) => _authorDragUpdate(
                              d.delta.dx, MediaQuery.sizeOf(context).width),
                          onHorizontalDragEnd: (d) =>
                              _authorDragEnd(d.primaryVelocity ?? 0),
                          onHorizontalDragCancel: _authorDragCancel,
                          // G2：2 倍速只在全屏保留；非全屏长按改为 §8 菜单
                          // （500ms / 位移 ≤12px，由舞台 Listener 统一判定，不暂停）。
                          onLongPressStart:
                              fs ? (_) => player.setRate(2.0) : null,
                          onLongPressEnd:
                              fs ? (_) => player.setRate(speed) : null,
                          child: Stack(fit: StackFit.expand, children: [
                            // P2：视频层自成一画层——上层进度条/提示的局部重绘
                            // 不再把原生视频纹理拖进同一 layer 重绘。
                            RepaintBoundary(child: videoView()),
                            // 首帧没出来之前用海报盖住视频层：既挡掉起播黑屏，
                            // 也避免纹理先按错误比例画一帧再跳。
                            // owner 2026-11-22：海报层只服务视频起播遮黑。
                            // 图文作品的位置永远不前进，`_firstFrameSeen` 一直为
                            // false → 海报永远盖在真实图片上，看起来就是「开始
                            // 时变暗一下」。图文不再挂海报层。
                            if (it['t'] == 'v' &&
                                posterLayerVisible(posterCover))
                              IgnorePointer(
                                // 只有「首帧出来」+「视频轨报了尺寸」+
                                // 「播放器比例已知」才让位：比例没到就淡出，
                                // 视频层还没挂载，会露黑屏。
                                // 有声无画时 _videoDw 一直是 0，海报继续盖着，
                                // 用户看到的是封面而不是黑屏。
                                ignoring: _firstFrameSeen &&
                                    _videoDw > 1 &&
                                    _videoAspectFor(it) != null,
                                child: AnimatedOpacity(
                                  opacity: _firstFrameSeen &&
                                          _videoDw > 1 &&
                                          _videoAspectFor(it) != null
                                      ? 0
                                      : 1,
                                  // 短淡出：不拖沓，也不至于生硬跳变
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOut,
                                  child: LayoutBuilder(builder: (_, pc) {
                                    final fit = videoFitFor(
                                                aspect: _coverAspectFor(it),
                                                mode: AppSettings
                                                    .videoFitOverride,
                                                containerAspect: pc.maxHeight >
                                                        0
                                                    ? pc.maxWidth / pc.maxHeight
                                                    : null) ==
                                            VideoFit.fill
                                        ? BoxFit.cover
                                        : BoxFit.contain;
                                    // 与网格卡片同一解析入口：视频缺 `th` 时走
                                    // `/api/thumb` 抽帧，URL 与卡片逐字符相同。
                                    return CachedNetworkImage(
                                        cacheManager: DiziCache.manager,
                                        // 底图：与作品卡同一张 provider。进播放页
                                        // 时它通常已在 ImageCache 里，直接同步命中，
                                        // 海报第一帧不空 → 起播不再露黑。
                                        placeholder: (_, __) =>
                                            _posterPreview(it, fit: fit),
                                        imageUrl: withImageWidth(
                                            posterCover, kPlayerImageWidth),
                                        httpHeaders:
                                            cfg.headersFor(_libFor(it)),
                                        memCacheWidth:
                                            _posterDecodeWidth(context),
                                        alignment: fit == BoxFit.cover
                                            ? Alignment.topCenter
                                            : Alignment.center,
                                        fit: fit);
                                  }),
                                ),
                              ),
                            // owner 2026-11-20：舞台上不再有任何加载圈，
                            // 起播阶段由封面兜住。
                            ..._stageOverlayChildren(
                              w: it,
                              fs: fs,
                              broken: false,
                              pad: pad,
                              bottom: infoBottomInPage,
                              viewSize: viewSize,
                              chromeOpacity: chromeOpacity,
                              chromeMs: chromeMs,
                              infoOpacity: infoOpacity,
                              immersiveFade: immersiveFade,
                              railOpacity: railOpacity,
                              railMs: railMs,
                            ),
                            // T：进度条/集数标签贴本页舞台底边，随 PageView 位移。
                            _stageProgressOverlay(
                              w: it,
                              isV: true,
                              pics: const <String>[],
                              idx: 0,
                              progress: progress,
                            ),
                          ]),
                        );
                      }
                      return GestureDetector(
                        // 与视频分支同理：deferToChild 时 contain 留出的
                        // 上下黑边不参与命中，点上去被直接吞掉。
                        behavior: HitTestBehavior.opaque,
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
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 1.5),
                                              decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: k == idx
                                                      ? Colors.white
                                                      : Colors.white24),
                                            ))),
                              ),
                            ),
                          // T：图文分段进度 + 计数贴本页舞台底边，随页位移。
                          if (pics.length > 1)
                            _stageProgressOverlay(
                              w: it,
                              isV: false,
                              pics: pics,
                              idx: idx,
                              progress: progress,
                            ),
                          ..._stageOverlayChildren(
                            w: it,
                            fs: fs,
                            broken: false,
                            pad: pad,
                            bottom: infoBottomInPage,
                            viewSize: viewSize,
                            chromeOpacity: chromeOpacity,
                            chromeMs: chromeMs,
                            infoOpacity: infoOpacity,
                            immersiveFade: immersiveFade,
                            railOpacity: railOpacity,
                            railMs: railMs,
                          ),
                        ]),
                      );
                    },
                  ),
                ),
              ),
              // owner 2026-11-20：去掉中央「网络较慢，正在缓冲…」提示，
              // 缓冲态只在诊断里记录，不再占用画面中心。
              // G12：加载超时/解码失败/网络失败 —— 给出重试入口
              if (_failure != null) _failureOverlay(),
              Positioned(
                // P0 §6：非全屏左边距 12dp（全屏保持旧值 8dp）。
                left: pad.left + (fs ? 8 : 12),
                top: pad.top + 8,
                child: IgnorePointer(
                  ignoring: !ui,
                  child: AnimatedOpacity(
                    opacity: chromeOpacity,
                    duration: Duration(milliseconds: chromeMs),
                    curve: Curves.easeOut,
                    // P0 §6：非全屏改用 24dp/间距 12dp/无圆底的抖音式图标按钮；
                    // 全屏保留原 IconButton 组合，行为与视觉均不变。
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: fs
                            ? [
                                IconButton(
                                    onPressed: () =>
                                        Navigator.of(context).maybePop(),
                                    icon: const Icon(Icons.arrow_back,
                                        color: Colors.white70),
                                    style: IconButton.styleFrom(
                                        overlayColor: Colors.white24)),
                                // 深页面统一「返回主页」：从作者页/搜索进播放页也能一步回主页。
                                const HomeOverlayButton(),
                                // 封面入口做成可见按钮（长按信息区同样可用）
                                IconButton(
                                    tooltip: '设置封面',
                                    onPressed: _openCoverSheet,
                                    icon: const Icon(Icons.image_outlined,
                                        color: Colors.white70),
                                    style: IconButton.styleFrom(
                                        overlayColor: Colors.white24)),
                              ]
                            : [
                                StageIconButton(
                                    tooltip: '返回',
                                    icon: Icons.arrow_back,
                                    onPressed: () =>
                                        Navigator.of(context).maybePop()),
                                const SizedBox(width: kStageIconSpacing),
                                StageIconButton(
                                    tooltip: '返回主页',
                                    icon: Icons.home_outlined,
                                    onPressed: () => Navigator.of(context)
                                        .popUntil((r) => r.isFirst)),
                                const SizedBox(width: kStageIconSpacing),
                                StageIconButton(
                                    tooltip: '设置封面',
                                    icon: Icons.image_outlined,
                                    onPressed: _openCoverSheet),
                              ]),
                  ),
                ),
              ),
              // P0：常驻大播放图标只在全屏保留；非全屏改为 0.8s 淡出提示。
              // owner 2026-11-22：全屏暂停键与这枚白色三角重叠，删掉三角。
              // H14：不再弹独立音量模块，仅保留一个轻量读数提示（松手后自动消失）
              // O2：手机端中央大号播放/暂停圆钮，随控制层淡入淡出。
              // P0：中央大圆钮只在全屏出现；非全屏暂停只显示 0.8s 播放图标。
              if (fs && _mobileStageTap && isV && !broken)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !ui,
                    child: AnimatedOpacity(
                      opacity: chromeOpacity,
                      duration: Duration(milliseconds: chromeMs),
                      curve: Curves.easeOut,
                      child: Center(
                        child: GestureDetector(
                          key: const Key('center-pause'),
                          behavior: HitTestBehavior.opaque,
                          onTap: togglePause,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.black.withValues(alpha: 0.45)),
                            child: Icon(_showsPaused ? Icons.play_arrow : Icons.pause,
                                size: 44, color: Colors.white70),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              // P0 §5：非全屏暂停提示——无背景大按钮，只一个播放图标，
              // 0.8s / Curves.easeOut 淡出（每次暂停重新计时）。
              // owner 2026-11-22：非全屏暂停时要能看到半透明播放标（原来只在
              // 0.8s 提示动画期间出现，之后就没有了），改为暂停期间常显。
              if (!fs && !broken && _showsPaused)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Icon(Icons.play_arrow_rounded,
                          size: 64, color: Colors.white38),
                    ),
                  ),
                ),
              if (_volumeUi && _volHintVisible && ui)
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
                            volumeIconData(
                                volumeIconFor(volume, muted: muted)),
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
              // T：任务栏只放自身控件并固定屏幕最底；移动端全屏时隐藏，
              // 舞台铺满（进度条仍在页内舞台底部随页滑动）。
              if (!broken && !hideTaskbar)
                Positioned(
                  left: 0,
                  right: 0,
                  // A：实底任务栏贴屏幕底；视频舞台已按其高度内缩。
                  bottom: 0,
                  // P2：任务栏自成一画层，视频层/进度条的局部重绘不波及它。
                  child: RepaintBoundary(
                    child: IgnorePointer(
                      ignoring: !ui,
                      child: AnimatedOpacity(
                        opacity: chromeOpacity,
                        duration: Duration(milliseconds: chromeMs),
                        curve: Curves.easeOut,
                        child: Container(
                          key: _taskbarKey,
                          // P1 §4：非全屏 56dp 纯黑 + 1px #1AFFFFFF 顶部分割线；
                          // 全屏保留旧的 10/6 内边距与无分割线外观。
                          decoration: BoxDecoration(
                            // 全屏：半透明浮层（保留旧观感）；非全屏：不透明实底。
                            color: fs
                                ? Colors.black.withValues(alpha: 0.35)
                                : kTaskbarColor,
                            border: fs
                                ? null
                                : const Border(
                                    top: BorderSide(
                                        color: kTaskbarDividerColor, width: 1)),
                          ),
                          padding: EdgeInsets.only(
                              left: pad.left + (fs ? 12 : kTaskbarSidePadding),
                              right:
                                  pad.right + (fs ? 12 : kTaskbarSidePadding),
                              top: fs ? 10 : 0,
                              bottom: fs ? 6 + pad.bottom : pad.bottom),
                          child: SizedBox(
                            height: fs ? null : kTaskbarContentHeight,
                            child: Column(
                                mainAxisSize:
                                    fs ? MainAxisSize.min : MainAxisSize.max,
                                mainAxisAlignment: fs
                                    ? MainAxisAlignment.start
                                    : MainAxisAlignment.center,
                                children: [
                                  Row(children: [
                                    // owner 2026-11-22：任务栏按 [TaskbarPlan] 取舍渲染。
                                    // 不再用 FittedBox(scaleDown) 整体缩放——那会把 44dp
                                    // 触达区压到 30dp 以下；放不下的槽位改收进「更多」菜单，
                                    // 每个按钮都保持原尺寸与触达区。
                                    Expanded(
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            for (final slot in tbPlan.visible)
                                              if (slot != TaskbarSlot.display)
                                                _taskbarSlotWidget(
                                                  slot: slot,
                                                  fs: fs,
                                                  tbBtnW: tbBtnW,
                                                  taskbar: taskbar,
                                                  chapterCount: chapterCount,
                                                  paused: _showsPaused,
                                                  speed: speed,
                                                  muted: muted,
                                                  volume: volume,
                                                  toggleFs: toggleFs,
                                                  toggleOrientation:
                                                      toggleOrientation,
                                                ),
                                            if (tbPlan.hasOverflow)
                                              TaskbarMoreButton(
                                                key: const ValueKey(
                                                    'taskbar-more'),
                                                items: tbPlan.overflow,
                                                labelOf: _taskbarSlotLabel,
                                                onSelected: (s) =>
                                                    _taskbarSlotAction(s),
                                              ),
                                            // owner 2026-11-24：全屏键固定最右侧。
                                            // 原来它排在传入顺序末尾、又紧贴左边，
                                            // 窄屏取舍后跑到左端，手很难按到。
                                            const Spacer(),
                                            if (tbPlan.visible
                                                .contains(TaskbarSlot.display))
                                              _taskbarSlotWidget(
                                                slot: TaskbarSlot.display,
                                                fs: fs,
                                                tbBtnW: tbBtnW,
                                                taskbar: taskbar,
                                                chapterCount: chapterCount,
                                                paused: _showsPaused,
                                                speed: speed,
                                                muted: muted,
                                                volume: volume,
                                                toggleFs: toggleFs,
                                                toggleOrientation:
                                                    toggleOrientation,
                                              ),
                                          ]),
                                    ),
                                  ]),
                                ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // owner 2026-11-20：进度条呼出/拖动热区向下跨过分界线，
              // 视频区与任务栏各占一半；靠近分界线横向拖动也能拖进度条。
              if (!broken &&
                  !hideTaskbar &&
                  ui &&
                  !fs &&
                  _workAt(cur)['t'] == 'v')
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: (_taskbarH > 0 ? _taskbarH : kTaskbarHeight) - 8,
                  height: 18,
                  child: LayoutBuilder(builder: (_, cc) {
                    Offset at(double dx) => Offset(dx, kScrubBubbleSpace);
                    return GestureDetector(
                      // translucent：拖动归进度条，单击仍能落到任务栏按钮上
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (d) =>
                          _scrubStart(at(d.globalPosition.dx), cc.maxWidth),
                      onHorizontalDragUpdate: (d) =>
                          _scrubMove(at(d.globalPosition.dx), cc.maxWidth),
                      onHorizontalDragEnd: (_) => _scrubEnd(),
                      onHorizontalDragCancel: _scrubEnd,
                    );
                  }),
                ),
              // J-A2：顶部固定半透明胶囊（位于顶部工具按钮下沿，
              // 不随功能区淡出，也绝不进入底部任务栏区域）。
              if (_noticeText != null)
                _PlayerTopNotice(text: _noticeText!, pad: pad),
              // P1b：评论半屏面板与长按菜单在舞台最顶层（覆盖任务栏），
              // 自带手势域，不与 PageView 竖向翻页抢手势。
              if (_commentVisible) _commentPanelOverlay(viewSize),
              if (_menuVisible) _stageMenuOverlay(),
            ]),
          ),
        ),
      ),
    );
  }
}

/// J-A2：播放页统一提示条——贴 SafeArea 顶部、水平居中、半透明胶囊。
class _PlayerTopNotice extends StatelessWidget {
  final String text;
  final EdgeInsets pad;
  const _PlayerTopNotice({required this.text, required this.pad});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      // 顶部工具按钮行高 48；下移一行避免遮挡返回/主页/封面按钮。
      top: pad.top + 58,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(anim),
                child: child,
              ),
            ),
            child: Container(
              key: ValueKey<String>(text),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
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
  // A2：无限续播状态。失败静默；空结果/连续重复则停止继续请求。
  bool _loadingMore = false;
  bool _moreExhausted = false;
  int _moreSeq = 0;
  bool _showAll = false;
  final Set<int> _usedSeeds = {};
  // J11：推荐页支持作者筛选（与总览/排行/搜索共享状态）
  LibMeta? meta;
  Map<String, Set<String>> authorTypes = {};
  bool typesLoading = false;
  final Map<String, int> _authorCount = {};

  @override
  void initState() {
    super.initState();
    authorFilter.addListener(_onSharedFilter);
    PerfDiagnostics.instance.beginSpan('page:recommend');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerfDiagnostics.instance.endSpan('page:recommend');
    });
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
    _moreExhausted = false;
    _moreSeq = 0;
    _showAll = false;
    _usedSeeds
      ..clear()
      ..add(seed);
    try {
      // 推荐改为跨全部已注册库：每个库取一批，按库轮转合并，
      // 避免默认库（抖音收藏）独占整个页面。
      if (libs.isEmpty) {
        try {
          final lr = await http
              .get(cfg.u('/api/libraries'), headers: cfg.headers)
              .timeout(const Duration(seconds: 8));
          if (lr.statusCode == 200) {
            final lj = jsonOf(lr);
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
      // 有范围筛选时先多取（筛完仍要够数量），无筛选按设置数量取。
      final merged = await _fetchPage(seed, _fetchCount);
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
          err = errorText(e);
          loading = false;
        });
      }
    }
  }

  /// 本次请求数量：筛选时多取（筛完仍要够数），否则用设置值（0/空 = 40）。
  int get _fetchCount =>
      authorFilter.value.isActive ? 600 : RecommendCountSettings.value;

  Future<List<Map<String, dynamic>>> _fetchPage(int seed, int n) async {
    final r = await http.get(
        cfg.u('/api/recommend?n=$n&seed=$seed', lib: 'all'),
        headers: cfg.headers);
    if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
    final j = jsonOf(r);
    final out = <Map<String, dynamic>>[];
    for (final w
        in (j is Map && j['works'] is List) ? (j['works'] as List) : const []) {
      if (w is! Map) continue;
      final m = Map<String, dynamic>.from(w);
      out.add({...m, '_lib': '${m['_lib'] ?? cfg.lib}'});
      if (out.length >= n) break;
    }
    return out;
  }

  /// A2：列表到底后换新 seed 拉一批并追加（按 id 去重，保持原顺序）。
  ///
  /// [target] 是播放器手里的列表实例（可能不是 [works]），追加后播放器
  /// 可以直接继续连播。失败静默返回 false，不打断播放。
  Future<bool> _loadMore({List? target}) async {
    if (_loadingMore || _moreExhausted || !mounted) return false;
    _loadingMore = true;
    try {
      final n = _fetchCount;
      for (var attempt = 0; attempt < 3; attempt++) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final seed = nextRecommendSeed(
            nowSeconds: now, seq: ++_moreSeq, used: _usedSeeds);
        _usedSeeds.add(seed);
        List<Map<String, dynamic>> page;
        try {
          page = await _fetchPage(seed, n);
        } catch (_) {
          return false; // 失败静默：保留现有列表，下次滚动可再试
        }
        if (page.isEmpty) {
          _moreExhausted = true;
          return false;
        }
        final merged = mergeRecommendPages(works, page);
        if (merged.length == works.length) continue; // 整批重复，换 seed 重试
        final appended = merged.sublist(works.length);
        if (!mounted) return false;
        setState(() {
          works = merged;
          _authorCount.clear();
          for (final w in works) {
            if (w is! Map) continue;
            final a = '${w['a'] ?? ''}';
            if (a.isEmpty) continue;
            _authorCount[a] = (_authorCount[a] ?? 0) + 1;
          }
        });
        if (target != null && !identical(target, works)) {
          try {
            target.addAll(appended);
          } catch (_) {
            // 目标列表不可变时忽略：播放器下次 next() 会再请求。
          }
        }
        _showAll = true;
        return appended.isNotEmpty;
      }
      _moreExhausted = true;
      return false;
    } finally {
      _loadingMore = false;
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
    for (final b in meta?.filterBasics ?? const <BasicLibRef>[]) {
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

  /// P3：顶级节点（＝媒体库根）作一级筛选项。
  List<AuthorLibNode> get _filterTops {
    final out = <AuthorLibNode>[];
    final seen = <String>{};
    for (final t in meta?.tops ?? const <UnitLibrary>[]) {
      if (t.id.isEmpty || !seen.add(t.id)) continue;
      out.add(AuthorLibNode(id: t.id, name: t.name));
    }
    return authorLibNodes(out);
  }

  Map<String, String> get _filterTopNames =>
      {for (final t in _filterTops) t.id: t.name};

  bool _matches(dynamic raw, AuthorFilterState f) {
    if (raw is! Map) return false;
    final w = Map<String, dynamic>.from(raw);
    final av = '${w['av'] ?? ''}';
    final a = '${w['a'] ?? ''}';
    final type = workFilterType(w);
    final types =
        authorTypes[a] ?? (type == 'other' ? const <String>{} : <String>{type});
    // 作品条目直接带 `_bid`（基础库 id）时优先用它，否则按路径反查；
    // 再不行用条目自带的 `_lib`（基础库页/单库数据源）。
    var basic = '${w['_bid'] ?? ''}';
    final libId = '${w['_lib'] ?? ''}';
    if (basic.isEmpty) basic = meta?.basicIdForPath(av) ?? '';
    if (basic.isEmpty && meta?.basicById(libId) != null) basic = libId;
    final unit = basic.isEmpty
        ? (meta?.unitIdFor(av) ?? '')
        : (meta?.basicToUnit[basic] ?? '');
    return f.matches(
      basicId: basic,
      bigId: meta?.bigIdFor(av) ?? '',
      unitId: unit,
      topId: unit.isEmpty ? '' : (meta?.topIdFor(unit) ?? ''),
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
      tops: _filterTops,
      grades: const ['S', 'A', 'B', 'C', 'D'],
      count: (f) => works.where((w) => _matches(w, f)).length,
    );
    if (res == null || !mounted) return;
    authorFilter.apply(res);
  }

  /// 首屏展示数量：默认铺满一屏；设置更大时按设置；续播过则全部展示。
  List _displayWorks(List visible, Size size) {
    if (_showAll) return visible;
    final fill = recommendVisibleCount(size);
    final want = RecommendCountSettings.value;
    final cap = want > fill ? want : fill;
    if (visible.length <= cap) return visible;
    // 续播时要往播放器手里的同一列表追加，必须是可变列表。
    return visible.take(cap).toList();
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
              ? LoadErrorView(
                  message: '加载失败：$err',
                  onRetry: () => load(refresh: false))
              : Column(children: [
                  // J11：推荐与总览/排行/搜索共用同一套作者筛选与状态
                  AuthorFilterBar(
                    filter: authorFilter.value,
                    loading: typesLoading,
                    onOpen: _openFilter,
                    onClear: authorFilter.clearAll,
                    summary: authorFilter.value.isActive
                        ? '${authorFilter.value.summary(basicNames: _filterLibNames, bigNames: _filterBigNames, unitNames: _filterUnitNames, topNames: _filterTopNames)} · 命中 ${visible.length}/${works.length}'
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
                                // 与作者页/基础库页/搜索页共用同一个作品卡组件；
                                // 首屏数量：默认铺满一屏（最少 40），设置更大时按设置；
                                // 滚到末尾后自动换 seed 续一批（A2 无限续播）。
                                child: WorkGrid(
                                  works: _displayWorks(
                                      visible, MediaQuery.sizeOf(context)),
                                  lib: cfg.lib,
                                  onEndReached: () => _loadMore(),
                                  onNeedMoreWorks: (list) =>
                                      _loadMore(target: list),
                                ),
                              ),
                  ),
                ]),
    );
  }
}

/// 搜索页待扫的基础库（0.9.23：并发拉取用）。
class _BasicJob {
  final String lib;
  final String basicId;
  final String rel;
  final String name;

  const _BasicJob({
    required this.lib,
    required this.basicId,
    required this.rel,
    required this.name,
  });
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
  // 0.9.23：并行拉取进度（已载入 / 共几个基础库）
  int _loadedBasics = 0;
  int _totalBasics = 0;
  // J11：搜索页同样支持作者筛选（与总览/排行/推荐共享同一份状态）
  Map<String, Set<String>> authorTypes = {};
  bool typesLoading = false;
  String _typesForSel = '';

  @override
  void initState() {
    super.initState();
    authorFilter.addListener(_onSharedFilter);
    sel = cfg.lib;
    PerfDiagnostics.instance.beginSpan('page:search');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerfDiagnostics.instance.endSpan('page:search');
    });
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
      final j = jsonMapOf(r);
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

  void _select(String id) {
    if (sel == id) return;
    setState(() {
      sel = id;
      loading = true;
      all = [];
      _loadedBasics = 0;
      _totalBasics = 0;
    });
    loadAll();
  }

  Future<void> loadAll() async {
    final token = ++_loadToken;
    // 0.9.9：默认搜索全部基础库（39 个），不再只扫注册库目录；
    // 选定某个注册库时仍只扫该库目录。
    final targets = [sel.isEmpty ? cfg.lib : (sel == 'all' ? cfg.lib : sel)];
    final out = <Map<String, dynamic>>[];
    // 0.9.23：先收集要扫的 (库, 基础库) 列表，再按 6 路并发拉 works.json；
    // 原来是逐个 `await`，39 个库串行要好几个往返。
    final jobs = <_BasicJob>[];
    try {
      for (final lib in targets) {
        try {
          metas[lib] = await LibMeta.load(lib);
        } catch (_) {}
        // T3：作品来源改为基础库 `works.json`（旧 `/api/c/` 收藏夹通道已移除）
        final basics = (sel == 'all' || sel.isEmpty)
            ? (metas[lib]?.filterBasics ?? const <BasicLibRef>[])
            : (metas[lib]?.basics ?? const <BasicLibRef>[]);
        for (final b in basics) {
          jobs.add(
              _BasicJob(lib: lib, basicId: b.id, rel: b.rel, name: b.name));
        }
      }
      if (mounted) {
        setState(() {
          _loadedBasics = 0;
          _totalBasics = jobs.length;
        });
      }
      final pages = await mapConcurrent<_BasicJob, List<dynamic>>(
        jobs,
        6,
        (j) async {
          List<dynamic> ws;
          try {
            ws = await _libWorks(j.lib, j.basicId);
          } catch (_) {
            ws = const <dynamic>[];
          }
          if (mounted && token == _loadToken) {
            setState(() => _loadedBasics++);
          }
          return ws;
        },
      );
      for (var k = 0; k < jobs.length; k++) {
        final j = jobs[k];
        final ws = pages[k];
        for (var i = 0; i < ws.length; i++) {
          out.add({
            'w': ws[i],
            'works': ws,
            'i': i,
            '_lib': j.lib,
            '_bid': j.basicId,
            '_rel': j.rel,
          });
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
      _loadedBasics = _totalBasics;
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
        final j = jsonOf(r);
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
      for (final b in m.filterBasics) {
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

  /// P3：顶级节点（＝媒体库根）作一级筛选项（多库口径）。
  List<AuthorLibNode> get _filterTops {
    final out = <AuthorLibNode>[];
    final seen = <String>{};
    for (final m in metas.values) {
      for (final t in m.tops) {
        if (t.id.isEmpty || !seen.add(t.id)) continue;
        out.add(AuthorLibNode(id: t.id, name: t.name));
      }
    }
    return authorLibNodes(out);
  }

  Map<String, String> get _filterTopNames =>
      {for (final t in _filterTops) t.id: t.name};

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
    final unitId = bid.isNotEmpty
        ? (meta?.basicToUnit[bid] ?? '')
        : (meta?.unitIdFor(av) ?? '');
    return f.matches(
      basicId: known?.id ?? (meta?.idFor(av) ?? ''),
      bigId: known != null && known.bigId.isNotEmpty
          ? known.bigId
          : (meta?.bigIdFor(av) ?? ''),
      unitId: unitId,
      // P3：顶级节点按「基础库 → 单元库 → 顶级节点」链，不另算一份归属。
      topId: bid.isNotEmpty
          ? (meta?.topIdForBasic(bid) ?? '')
          : (unitId.isEmpty ? '' : (meta?.topIdFor(unitId) ?? '')),
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
      tops: _filterTops,
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
              ? '${authorFilter.value.summary(basicNames: _filterLibNames, bigNames: _filterBigNames, unitNames: _filterUnitNames, topNames: _filterTopNames)} · 命中 ${res.length}/${all.length}'
              : null,
        ),
        if (loading)
          Column(mainAxisSize: MainAxisSize.min, children: [
            const LinearProgressIndicator(),
            if (_totalBasics > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '已载入 $_loadedBasics/$_totalBasics 个基础库',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
          ]),
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
                  : WorkGrid(
                      works: [
                        for (final e in res)
                          {
                            ...Map<String, dynamic>.from(e['w'] as Map),
                            '_lib': '${e['_lib']}',
                            '_bid': '${e['_bid'] ?? ''}',
                          }
                      ],
                      lib: sel.isEmpty ? cfg.lib : sel,
                      // 搜索结果在卡片上保留作者，双击即从结果列表起播
                      subtitleOf: (w) =>
                          '@${authorDisplayNameFromWork(w)} · ${workTypeLabel(w)}',
                    ),
        ),
      ]),
    );
  }
}

// ───────────────────────── J12b：头像裁切 ─────────────────────────
//
// 视窗固定正方形；图像先按 cover 铺满视窗，再乘 zoom 放大。平移量以视窗
// 中心为原点夹紧，保证任何缩放级别都不会露出黑边。这里只放纯几何，便于单测。

const double kAvatarCropMinZoom = 1.0;
const double kAvatarCropMaxZoom = 4.0;

/// 输出头像的最小像素边（服务端仍会统一裁成 512×512）。
const int kAvatarCropMinPixels = 512;

/// zoom 夹紧到 [1,4]；非有限值按 1 处理。
double avatarCropClampZoom(double zoom) {
  if (!zoom.isFinite) return kAvatarCropMinZoom;
  return zoom.clamp(kAvatarCropMinZoom, kAvatarCropMaxZoom).toDouble();
}

/// cover 之后乘 zoom 的显示尺寸；参数非法时返回 [Size.zero]。
Size avatarCropDisplaySize(Size image, double viewSide, double zoom) {
  if (image.width <= 0 || image.height <= 0 || viewSide <= 0) {
    return Size.zero;
  }
  final z = avatarCropClampZoom(zoom);
  final scale = max(viewSide / image.width, viewSide / image.height) * z;
  return Size(image.width * scale, image.height * scale);
}

/// 平移夹紧：显示尺寸超出视窗的一半即上限，另一方向不许移动。
Offset avatarCropClampOffset(Offset offset, Size display, double viewSide) {
  final mx = max(0.0, (display.width - viewSide) / 2);
  final my = max(0.0, (display.height - viewSide) / 2);
  final dx = offset.dx.isFinite ? offset.dx : 0.0;
  final dy = offset.dy.isFinite ? offset.dy : 0.0;
  return Offset(dx.clamp(-mx, mx).toDouble(), dy.clamp(-my, my).toDouble());
}

/// 渲染像素比：保证输出短边 ≥512，上限 6（避免超大内存）。
double avatarCropPixelRatio(double viewSide) {
  if (!viewSide.isFinite || viewSide <= 0) return 1;
  return (kAvatarCropMinPixels / viewSide).clamp(1.0, 6.0).toDouble();
}

/// J13：简介按 Unicode 码点计数（中文/emoji 各算 1）。
int authorBioLength(String text) => text.runes.length;

const int kAuthorBioMaxChars = 500;

/// 与服务端一致：去 `\r`、去首尾空白；清空 = 空串。
String normalizeAuthorBio(String raw) => raw.replaceAll('\r', '').trim();

/// 不合法时返回提示；空串合法（表示清空）。
String? validateAuthorBio(String raw) {
  if (authorBioLength(normalizeAuthorBio(raw)) > kAuthorBioMaxChars) {
    return '简介最多 $kAuthorBioMaxChars 字';
  }
  return null;
}

/// 服务端 bioAt（秒）→ 本地时间；0/负数返回空串。
String formatAuthorBioAt(int ts) {
  if (ts <= 0) return '';
  return yearMonthDayTimeOfSec(ts);
}

/// J12b/J13：作者头像/简介写入结果。
class AuthorEditResult {
  final bool ok;
  final String message;

  /// 头像：服务端返回的媒体路径；简介：服务端回写的正文。
  final String path;

  const AuthorEditResult(this.ok, this.message, {this.path = ''});
}

/// P6：从服务端拉作者等级配置（`GET /api/author-grade.json`）。
///
/// 成功时套用到 [AuthorGrade] 并写一份本机只读缓存供下次首帧使用；
/// 失败不抛异常，保持上次值（绝不因服务端离线把等级改回默认）。
Future<bool> syncAuthorGradeFromServer({String? lib}) async {
  if (cfg.base.isEmpty) return false;
  http.Response r;
  try {
    r = await http.get(cfg.u('/api/author-grade.json', lib: lib),
        headers: cfg.headersFor(lib));
  } catch (_) {
    return false;
  }
  if (r.statusCode != 200) return false;
  final j = jsonObjectOrEmpty(r);
  if (j.isEmpty) return false;
  final ok = AuthorGrade.applyRemote(j);
  if (ok) await AuthorGrade.cacheLocal();
  return ok;
}

/// 把裁切好的 PNG 字节 POST 到 `/api/author/avatar`。
Future<AuthorEditResult> uploadAuthorAvatarBytes({
  required String libId,
  required String author,
  required List<int> pngBytes,
}) async {
  http.Response r;
  try {
    r = await http.post(
      cfg.u('/api/author/avatar', lib: libId),
      headers: {...cfg.headersFor(libId), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'lib': libId,
        'author': author,
        'data': base64Encode(pngBytes),
      }),
    );
  } catch (e) {
    return AuthorEditResult(false, '上传失败：$e');
  }
  final j = jsonObjectOrEmpty(r);
  final bad = apiFailureText(r.statusCode, j);
  if (bad != null) return AuthorEditResult(false, '头像上传失败：$bad');
  return AuthorEditResult(true, '头像已更新', path: '${j['u'] ?? ''}');
}

/// J13：把简介写回 `/api/author/bio`（空串表示清空）。
Future<AuthorEditResult> uploadAuthorBio({
  required String libId,
  required String author,
  required String bio,
}) async {
  final bad = validateAuthorBio(bio);
  if (bad != null) return AuthorEditResult(false, bad);
  final clean = normalizeAuthorBio(bio);
  http.Response r;
  try {
    r = await http.post(
      cfg.u('/api/author/bio', lib: libId),
      headers: {...cfg.headersFor(libId), 'Content-Type': 'application/json'},
      body: jsonEncode({'lib': libId, 'author': author, 'bio': clean}),
    );
  } catch (e) {
    return AuthorEditResult(false, '保存失败：${errorText(e)}');
  }
  final j = jsonObjectOrEmpty(r);
  final fail = apiFailureText(r.statusCode, j);
  if (fail != null) return AuthorEditResult(false, '保存失败：$fail');
  final saved = j['bio'] is String ? j['bio'] as String : clean;
  return AuthorEditResult(true, '简介已更新', path: saved);
}

/// 批 A（2026-11-23）：把库内 `<lib>/.avatars/<file>` 注册为该作者头像。
///
/// 服务端写入 `LIBDIR/manual_avatars.json` 并清缓存，作者页/作者索引
/// 立即改用该文件（跨设备生效）。成功时回传媒体地址 `u`。
Future<AuthorEditResult> setAuthorAvatarFile({
  required String libId,
  required String author,
  required String file,
}) async {
  if (libId.trim().isEmpty || author.trim().isEmpty) {
    return const AuthorEditResult(false, '缺少库或作者');
  }
  if (!isServerAvatarFileName(file)) {
    return const AuthorEditResult(false, '头像文件名不合法（只支持 JPG/PNG/WebP）');
  }
  http.Response r;
  try {
    r = await http.post(
      cfg.u(kAuthorAvatarSetPath, lib: libId),
      headers: {...cfg.headersFor(libId), 'Content-Type': 'application/json'},
      body: jsonEncode(authorAvatarSetBody(
          lib: libId, author: author, file: file)),
    );
  } catch (e) {
    return AuthorEditResult(false, '设置头像失败：$e');
  }
  final j = jsonObjectOrEmpty(r);
  final bad = apiFailureText(r.statusCode, j,
      statusText: authorAvatarApiErrorText);
  if (bad != null) return AuthorEditResult(false, '设置头像失败：$bad');
  return AuthorEditResult(true, '已设为该作者头像', path: '${j['u'] ?? ''}');
}

/// 2026-11-22 / 批 A（2026-11-23）：清除服务端自定义头像（恢复「爬虫 → 自动」）。
///
/// 走 `POST /api/avatar/set {clear:true}`：删注册项并清缓存，作者索引重新生成；
/// 没有覆盖时同样返回 ok（幂等），客户端可无条件调用。
/// 文件本身保留（可回滚），不再像旧接口那样删除 `@manual-avatar/<作者>` 目录。
Future<AuthorEditResult> clearAuthorAvatar({
  required String libId,
  required String author,
}) async {
  http.Response r;
  try {
    r = await http.post(
      cfg.u(kAuthorAvatarSetPath, lib: libId),
      headers: {...cfg.headersFor(libId), 'Content-Type': 'application/json'},
      body: jsonEncode(authorAvatarClearBody(lib: libId, author: author)),
    );
  } catch (e) {
    return AuthorEditResult(false, '清除头像失败：$e');
  }
  final j = jsonObjectOrEmpty(r);
  final bad = apiFailureText(r.statusCode, j,
      statusText: authorAvatarApiErrorText);
  if (bad != null) return AuthorEditResult(false, '清除头像失败：$bad');
  return const AuthorEditResult(true, '已恢复自动头像');
}

/// J12b：方形裁切页。确定后返回 PNG 字节（短边 ≥512）。
class AvatarCropPage extends StatefulWidget {
  final List<int> bytes;
  const AvatarCropPage({super.key, required this.bytes});

  @override
  State<AvatarCropPage> createState() => _AvatarCropPageState();
}

class _AvatarCropPageState extends State<AvatarCropPage> {
  final GlobalKey _viewKey = GlobalKey();
  ui.Image? _image;
  String? _error;
  double _zoom = kAvatarCropMinZoom;
  Offset _offset = Offset.zero;
  double _startZoom = kAvatarCropMinZoom;
  double _viewSide = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    try {
      final codec =
          await ui.instantiateImageCodec(Uint8List.fromList(widget.bytes));
      final frame = await codec.getNextFrame();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (e) {
      if (mounted) setState(() => _error = '图片解码失败：$e');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Size _displayFor(double zoom) {
    final img = _image;
    if (img == null) return Size.zero;
    return avatarCropDisplaySize(
        Size(img.width.toDouble(), img.height.toDouble()), _viewSide, zoom);
  }

  void _setZoom(double z) {
    final next = avatarCropClampZoom(z);
    setState(() {
      _zoom = next;
      _offset = avatarCropClampOffset(_offset, _displayFor(next), _viewSide);
    });
  }

  Widget _cropView(ui.Image img, double side) {
    final display = avatarCropDisplaySize(
        Size(img.width.toDouble(), img.height.toDouble()), side, _zoom);
    final offset = avatarCropClampOffset(_offset, display, side);
    return GestureDetector(
      onScaleStart: (_) => _startZoom = _zoom,
      onScaleUpdate: (d) {
        final z = avatarCropClampZoom(_startZoom * d.scale);
        final nextDisplay = avatarCropDisplaySize(
            Size(img.width.toDouble(), img.height.toDouble()), side, z);
        setState(() {
          _zoom = z;
          _offset = avatarCropClampOffset(
              _offset + d.focalPointDelta, nextDisplay, side);
        });
      },
      child: SizedBox(
        width: side,
        height: side,
        child: Stack(fit: StackFit.expand, children: [
          RepaintBoundary(
            key: _viewKey,
            child: ClipRect(
              child: Stack(children: [
                const Positioned.fill(child: ColoredBox(color: Colors.black)),
                Center(
                  child: Transform.translate(
                    offset: offset,
                    child: SizedBox(
                      width: display.width,
                      height: display.height,
                      child: RawImage(
                        image: img,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          IgnorePointer(
              child: CustomPaint(painter: const _AvatarCropGridPainter())),
        ]),
      ),
    );
  }

  Future<void> _confirm() async {
    final ro = _viewKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return;
    setState(() => _busy = true);
    try {
      final shot =
          await ro.toImage(pixelRatio: avatarCropPixelRatio(_viewSide));
      final data = await shot.toByteData(format: ui.ImageByteFormat.png);
      shot.dispose();
      if (data == null) throw 'PNG 编码失败';
      if (!mounted) return;
      Navigator.of(context).pop(
          Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('生成头像失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('裁剪头像'),
      ),
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('拖动调整位置，双指或滑杆缩放；确定后上传为 512×512 头像',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ),
          Expanded(
            child: Center(
              child: LayoutBuilder(builder: (context, cons) {
                if (img == null) {
                  return _error != null
                      ? Text(_error!,
                          style: const TextStyle(color: Colors.white70))
                      : const CircularProgressIndicator();
                }
                final side = max(80.0, min(cons.maxWidth, cons.maxHeight) - 16);
                _viewSide = side;
                return _cropView(img, side);
              }),
            ),
          ),
          Slider(
            value: _zoom,
            min: kAvatarCropMinZoom,
            max: kAvatarCropMaxZoom,
            onChanged: img == null ? null : _setZoom,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (_busy || img == null) ? null : _confirm,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('确定'),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _AvatarCropGridPainter extends CustomPainter {
  const _AvatarCropGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white54;
    for (var i = 1; i < 3; i++) {
      final d = size.width * i / 3;
      canvas.drawLine(Offset(d, 0), Offset(d, size.height), paint);
      canvas.drawLine(Offset(0, d), Offset(size.width, d), paint);
    }
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_AvatarCropGridPainter oldDelegate) => false;
}

/// 作者页头像下方的小按钮（owner 2026-11-22）：与库封面入口一致的低调样式。
class _AvatarAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AvatarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10.5, color: color, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
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

  /// J13：本机最近一次简介写入时间（服务端 authors.json 的 bioAt 未下发）。
  int bioAt = 0;
  String av = '';
  // J12：没有现成头像时，从作品图里自动挑一张兜底（中心裁剪）。
  String fallbackAv = '';
  List works = [];
  // J6：按作品类型筛选（可多选，空集合=全部）
  final Set<String> typeFilter = <String>{};
  /// 跨库同名作者合并：按来源基础库筛选（空 = 全部）。
  String libFilter = '';
  /// owner 2026-11-24：顶级单元库（＝媒体库根）作为一级筛选维度。
  /// 只有该作者的作品跨越多于一个顶级单元库时才出现这一行。
  String topFilter = '';
  List filteredWorks = [];
  Map<String, int> typeCounts = {};
  String primaryLib = '';
  bool loading = true;
  LibMeta? meta;
  // J-A3：作者主页头部上滑自动收起为紧凑条（头像 + 名字 + 等级）。
  // 0.9.153：状态改成 ValueNotifier，滚动回调只重建信息栏，不再整页 setState。
  final ValueNotifier<bool> _headerCollapsed = ValueNotifier<bool>(false);
  // P 修复：外部滚动控制器，收起后能读到实时的 maxScrollExtent。
  final ScrollController _authorScroll = ScrollController();
  // 0.9.153：量出展开/收起两态的真实高度。收起会让 maxScrollExtent 等量变小，
  // 判定必须预留这份余量，否则「收起→到底→展开」会逐帧自激（边缘闪烁）。
  double _headerExpandedH = 0;
  double _headerCollapsedH = 0;
  double get _headerExtent {
    final d = _headerExpandedH - _headerCollapsedH;
    return d > 0 ? d : 0;
  }

  // K2：多选模式与已选作品；K3：手动名单（作品 id）。
  bool selectingWorks = false;
  Set<String> selectedWorks = <String>{};
  Set<String> manualWorkIds = <String>{};
  bool _batchBusy = false;

  List<String> get _libs =>
      (widget.libs == null || widget.libs!.isEmpty) ? [cfg.lib] : widget.libs!;

  String get displayAv => av.isNotEmpty ? av : fallbackAv;

  /// 0.9.41：本机手动头像（作者主页长按头像设置）。
  String get manualAv => AuthorAvatarStore.instance.pathFor(widget.name) ?? '';

  /// 服务端自定义头像（上传后注册，跨设备生效）。
  bool get serverManualAv => isManualAvatarPath(av);

  /// 是否有任何手动来源需要「恢复自动」——本机覆盖或服务端注册。
  bool get canRestoreAvatar => manualAv.isNotEmpty || serverManualAv;

  /// 爬虫/自动头像（load() 后的原始 av）；上传/恢复时用来回滚显示。
  String _crawledAv = '';

  /// 真正用于展示/放大的头像：手动 > 爬虫 av > 自动兜底。
  String get effectiveAv => manualAv.isNotEmpty ? manualAv : displayAv;

  Future<void> _showAvatarMenu(BuildContext context) async {
    final has = canRestoreAvatar;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.crop_square),
            title: const Text('更换头像（裁切上传）'),
            subtitle: const Text('裁切为 512×512 写回 NAS，旧图保留',
                style: TextStyle(fontSize: 11)),
            onTap: () => Navigator.of(ctx).pop('upload'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从作品里挑一张作头像'),
            subtitle: const Text('库内 .avatars 头像可跨设备；普通作品图只存本机',
                style: TextStyle(fontSize: 11)),
            onTap: () => Navigator.of(ctx).pop('pick'),
          ),
          if (has)
            ListTile(
              leading: const Icon(Icons.restart_alt),
              title: const Text('清除自定义头像（回到自动）'),
              onTap: () => Navigator.of(ctx).pop('clear'),
            ),
        ]),
      ),
    );
    if (!mounted) return;
    if (choice == 'clear') {
      await _restoreAutoAvatar();
    } else if (choice == 'pick') {
      _pickAvatarImage(context);
    } else if (choice == 'upload') {
      _pickCropUploadAvatar();
    }
  }

  void _pickAvatarImage(BuildContext context) {
    final cands = <String>[];
    for (final c in avatarCandidatesFromWorks(works.whereType<Map>())) {
      if (!c.valid) continue;
      if (cands.contains(c.path)) continue;
      cands.add(c.path);
      if (cands.length >= 36) break;
    }
    if (cands.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('该作者还没有可用作品图')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选一张作头像'),
        content: SizedBox(
          width: 420,
          height: 420,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
            itemCount: cands.length,
            itemBuilder: (_, i) {
              final p = cands[i];
              final l = libOfMediaPath(p).isEmpty
                  ? (primaryLib.isEmpty ? null : primaryLib)
                  : libOfMediaPath(p);
              return InkWell(
                onTap: () async {
                  // 批 A：`.avatars` 里的头像文件直接注册到服务端（跨设备）；
                  // 普通作品图仍只存本机，不传媒体文件。
                  final srv = serverAvatarFileFromPath(p);
                  if (srv != null) {
                    final r = await setAuthorAvatarFile(
                        libId: srv.lib, author: widget.name, file: srv.file);
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    if (!mounted) return;
                    if (!r.ok) {
                      _toast(r.message);
                      return;
                    }
                    // 服务端已生效：清掉同作者的本机覆盖，避免旧图压住新图。
                    await AuthorAvatarStore.instance.clear(widget.name);
                    if (!mounted) return;
                    setState(() {
                      if (r.path.isNotEmpty) av = r.path;
                    });
                    authorAvatarRevision.value++;
                    _toast(r.message);
                    return;
                  }
                  final ok =
                      await AuthorAvatarStore.instance.setPath(widget.name, p);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  if (!mounted) return;
                  authorAvatarRevision.value++;
                  setState(() {});
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                        SnackBar(content: Text(ok ? '已设为该作者头像' : '这张图不能作头像')));
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    cacheManager: DiziCache.manager,
                    imageUrl: withImageWidth(
                        cfg.mediaUrl(p, lib: l), kAvatarImageWidth),
                    httpHeaders: cfg.headersFor(l),
                    fit: BoxFit.cover,
                    fadeInDuration: Duration.zero,
                    memCacheWidth: avatarDecodeWidth(
                        displaySize: 96,
                        devicePixelRatio:
                            MediaQuery.devicePixelRatioOf(context)),
                    errorWidget: (_, __, ___) => const ColoredBox(
                        color: Colors.black26,
                        child: Icon(Icons.broken_image_outlined,
                            color: Colors.white38, size: 18)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// J12b：本地选图 → 方形裁切 → PNG 直传 `/api/author/avatar`。
  Future<void> _pickCropUploadAvatar() async {
    final lib = primaryLib.isEmpty ? cfg.lib : primaryLib;
    if (lib.isEmpty) {
      _toast('请先选择库');
      return;
    }
    XFile? picked;
    try {
      picked = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: '图片', extensions: ['jpg', 'jpeg', 'png', 'webp']),
      ]);
    } catch (e) {
      _toast('打开文件选择器失败：$e');
      return;
    }
    if (picked == null) return;
    List<int> bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (e) {
      _toast('读取图片失败：$e');
      return;
    }
    if (bytes.isEmpty) {
      _toast('图片为空');
      return;
    }
    if (bytes.length > kCoverUploadMaxBytes) {
      _toast('图片超过 12MB，请先压缩');
      return;
    }
    if (!isSupportedCoverBytes(bytes)) {
      _toast('只支持 JPG/PNG/WebP 图片');
      return;
    }
    if (!mounted) return;
    final png = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => AvatarCropPage(bytes: bytes)));
    if (png == null || png.isEmpty || !mounted) return;
    final r = await uploadAuthorAvatarBytes(
        libId: lib, author: widget.name, pngBytes: png);
    if (!mounted) return;
    if (!r.ok) {
      _toast(r.message);
      return;
    }
    // 清掉本机覆盖，避免旧的手动头像继续遮住服务端新图。
    await AuthorAvatarStore.instance.clear(widget.name);
    if (!mounted) return;
    authorAvatarRevision.value++;
    setState(() {
      if (r.path.isNotEmpty) av = r.path;
    });
    _toast(r.message);
  }

  /// owner 2026-11-22：「恢复自动」——清掉本机手动头像**与服务端注册**，
  /// 回落到爬虫/自动生成。服务端没有覆盖时接口幂等返回 ok。
  ///
  /// 清完立刻涨一次 [authorAvatarRevision]，作者页、播放页信息区与作品卡片
  /// 三处同时换回自动头像；本机与服务端都没有覆盖时按钮不显示。
  Future<void> _restoreAutoAvatar() async {
    // 手动头像可能来自别的基础库（`.avatars` 跨设备注册），清除时必须
    // 用头像路径里的库 id，否则会清错库、旧图依旧盖住自动结果。
    final avLib = isManualAvatarPath(av) ? libOfMediaPath(av) : '';
    final lib = avLib.isNotEmpty
        ? avLib
        : (primaryLib.isEmpty ? cfg.lib : primaryLib);
    if (lib.isNotEmpty) {
      final r = await clearAuthorAvatar(libId: lib, author: widget.name);
      if (!r.ok) {
        if (mounted) _toast(r.message);
        return;
      }
    }
    await AuthorAvatarStore.instance.clear(widget.name);
    if (!mounted) return;
    setState(() => av = _crawledAv);
    authorAvatarRevision.value++;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已恢复自动头像')));
  }

  /// J13：编辑简介（0–500 字，留空=清空），写回 authors.json。
  Future<void> _editBio() async {
    final ctrl = TextEditingController(text: bio);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          void save() {
            final bad = validateAuthorBio(ctrl.text);
            if (bad != null) {
              setD(() => error = bad);
              return;
            }
            Navigator.of(ctx).pop(normalizeAuthorBio(ctrl.text));
          }

          return AlertDialog(
            title: const Text('编辑作者简介'),
            content: SizedBox(
              width: 460,
              child: TextField(
                controller: ctrl,
                autofocus: true,
                minLines: 4,
                maxLines: 8,
                maxLength: kAuthorBioMaxChars,
                decoration: InputDecoration(
                  hintText: '留空表示清空简介',
                  errorText: error,
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消')),
              FilledButton(onPressed: save, child: const Text('保存')),
            ],
          );
        },
      ),
    );
    ctrl.dispose();
    if (result == null || !mounted) return;
    final lib = primaryLib.isEmpty ? cfg.lib : primaryLib;
    final r =
        await uploadAuthorBio(libId: lib, author: widget.name, bio: result);
    if (!mounted) return;
    if (!r.ok) {
      _toast(r.message);
      return;
    }
    setState(() {
      bio = r.path;
      bioAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    });
    _toast(r.message);
  }

  /// 简介只保留正文：去掉与作者名重复的行、以及单独一行的日期。
  String get _bioText {
    final text = bio.trim();
    if (text.isEmpty) return '（暂无简介）';
    final name = widget.name.trim();
    final out = <String>[];
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line == name ||
          line == '@$name' ||
          line == name.replaceAll('@', '')) {
        continue;
      }
      if (RegExp(r'^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}$').hasMatch(line)) continue;
      out.add(line);
    }
    return out.isEmpty ? '（暂无简介）' : out.join('\n');
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _headerCollapsed.dispose();
    _authorScroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    works = [];
    bio = '';
    bioAt = 0;
    av = '';
    fallbackAv = '';
    primaryLib = '';
    // 重新拉取时来源筛选归零：库可能增减，旧选择不一定还成立。
    libFilter = '';
    topFilter = '';
    // 各库作品先分别收齐，再统一交给 mergeAuthorWorks 合并。
    //
    // 之前这里是「边拉边用 seen 集合去重」——与 author_merge.dart 里那份
    // 带单测的合并规则是同一件事的第二份实现。两份实现的好处是零，代价是
    // 改规则时必然漏一处：这里改了就与单测脱节，单测绿着、真实路径却是另一套。
    // 现在只保留一份：按 _libs 顺序传入，先到先得 = 主库优先，语义不变。
    final perLib = <List<Map<String, dynamic>>>[];
    for (final lib in _libs) {
      try {
        final r = await http.get(cfg.u('/api/authors.json', lib: lib),
            headers: cfg.headers);
        if (r.statusCode != 200) continue;
        final idx = jsonMapOf(r);
        // 服务端作者索引存在 `作者` / `@作者` 两种键；名字可能来自作品 `a`
        // 或媒体路径里的 `%40作者`。统一按裸名匹配，避免「进页后空白」。
        final info = authorInfoFromIndex(idx, widget.name);
        if (info == null) continue;
        final d = await http.get(cfg.u('/api/a/${info['i']}.json', lib: lib),
            headers: cfg.headers);
        if (d.statusCode != 200) continue;
        final m = jsonOf(d);
        if (bio.isEmpty) bio = (m['bio'] ?? '').toString();
        if (av.isEmpty) av = (m['av'] ?? '').toString();
        if (primaryLib.isEmpty) primaryLib = lib;
        // 本库作品打上 `_lib` 后整批交给合并器；去重与顺序由它保证。
        perLib.add([
          for (final w in ((m['works'] as List?) ?? const []))
            if (w is Map)
              {...Map<String, dynamic>.from(w), '_lib': lib},
        ]);
        postStat('visit', widget.name, lib: lib);
      } catch (_) {}
    }
    works = mergeAuthorWorks(perLib);
    // 记下爬虫/自动头像，上传自定义后仍保留，供「恢复自动」回滚显示。
    if (!isManualAvatarPath(av)) _crawledAv = av;
    if (primaryLib.isNotEmpty) {
      try {
        meta = await LibMeta.load(primaryLib);
      } catch (_) {}
    }
    fallbackAv =
        pickFallbackAvatar(avatarCandidatesFromWorks(works.whereType<Map>())) ??
            '';
    // K3：手动名单按库拉取并缓存，刷新后重取。
    final manual = <String>{};
    final manualLibs = _libs.toSet();
    for (final lib in manualLibs) {
      manual.addAll(await fetchManualWorkIds(lib));
    }
    manualWorkIds = manual;
    if (mounted) {
      setState(() {
        loading = false;
        // 作品被删/移动后，已不存在的选择一并清掉。
        final ids = works
            .whereType<Map>()
            .map((w) => '${w['id'] ?? ''}')
            .where((e) => e.isNotEmpty)
            .toSet();
        selectedWorks = selectedWorks.where(ids.contains).toSet();
        if (selectedWorks.isEmpty) selectingWorks = false;
        _refreshFilter();
      });
    }
  }

  // ---------------- K2：多选与批量操作 ----------------

  List<String> get _visibleIds => filteredWorks
      .whereType<Map>()
      .map((w) => '${w['id'] ?? ''}')
      .where((e) => e.isNotEmpty)
      .toList();

  String _libOfWork(dynamic w) =>
      '${(w is Map ? w['_lib'] : null) ?? primaryLib}';

  Map<String, dynamic>? _workById(String id) {
    for (final w in works) {
      if (w is Map<String, dynamic> && '${w['id'] ?? ''}' == id) return w;
      if (w is Map && '${w['id'] ?? ''}' == id) {
        return Map<String, dynamic>.from(w);
      }
    }
    return null;
  }

  void _enterSelect(String id) {
    setState(() {
      selectingWorks = true;
      selectedWorks = toggleWorkSelection(selectedWorks, id);
    });
  }

  void _exitSelect() {
    setState(() {
      selectingWorks = false;
      selectedWorks = <String>{};
    });
  }

  void _toggleSelect(String id) {
    setState(() => selectedWorks = toggleWorkSelection(selectedWorks, id));
  }

  void _toggleSelectAll() {
    setState(() {
      selectedWorks = toggleSelectAllWorks(selectedWorks, _visibleIds);
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 把选中作品按库分组（删除时逐库逐作品调用）。
  Map<String, List<String>> _selectedByLib() {
    final out = <String, List<String>>{};
    for (final id in selectedWorks) {
      final w = _workById(id);
      if (w == null) continue;
      out.putIfAbsent(_libOfWork(w), () => <String>[]).add(id);
    }
    return out;
  }

  /// 批量删除的单条失败原因。`postWorkDelete` 的返回体里状态码在 `status`
  /// 字段（不是 HTTP 层），所以要显式传进去；两处调用共用一个出口，
  /// 避免同一个内部错误码在两段循环里出现两种说法。
  String _deleteFailureText(Map<String, dynamic> j) {
    // `postWorkDelete` 把状态码塞在返回体的 `status` 字段（内部码，不是 HTTP 层）。
    // 返回 null 表示「按读接口口径这不叫失败」（200 且没有显式 ok:false），
    // 此时只能说「服务端未确认」——不能说「HTTP 200」，那是自相矛盾的文案。
    final st = (j['status'] as num?)?.toInt() ?? 0;
    return apiFailureText(st, j, requireOk: false) ?? '服务端未确认';
  }

  Future<void> _batchDelete() async {
    if (_batchBusy || !canBatchDelete(selectedWorks)) return;
    setState(() => _batchBusy = true);
    try {
      final groups = _selectedByLib();
      var files = 0;
      final errors = <String>[];
      for (final e in groups.entries) {
        for (final id in e.value) {
          final j = await postWorkDelete(e.key, id);
          if (j == null) {
            errors.add('网络错误');
            continue;
          }
          if (j['ok'] != true) {
            errors.add(_deleteFailureText(j));
            continue;
          }
          files += (j['count'] is num) ? (j['count'] as num).toInt() : 0;
        }
      }
      if (errors.isNotEmpty) {
        _toast('预检失败：${errors.first}');
        return;
      }
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('批量删除'),
          content: Text(batchDeleteConfirmText(selectedWorks.length, files)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('确认删除')),
          ],
        ),
      );
      if (ok != true) return;
      var done = 0;
      for (final e in groups.entries) {
        for (final id in e.value) {
          final j = await postWorkDelete(e.key, id, confirm: true);
          if (j != null && j['ok'] == true) {
            done++;
          } else if (j != null) {
            errors.add(_deleteFailureText(j));
          } else {
            errors.add('网络错误');
          }
        }
      }
      _exitSelect();
      await load();
      _toast(errors.isEmpty
          ? '已删除 $done 个作品（可在内容维护里撤销）'
          : '已删除 $done 个，失败：${errors.first}');
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  Future<String?> _pickMoveTarget(String lib) async {
    try {
      final r = await http
          .get(cfg.u('/api/cat/tree', lib: lib), headers: cfg.headersFor(lib))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) {
        _toast('读取目录失败：${httpErrorText(r.statusCode)}');
        return null;
      }
      dynamic tree = jsonOf(r);
      // 用选中作品第一条媒体路径推断作者前缀，只列出该作者下的目录。
      String prefix = '';
      for (final id in selectedWorks) {
        final w = _workById(id);
        final m = (w == null) ? null : w['m'];
        final media = (m is List && m.isNotEmpty) ? '${m.first}' : '';
        if (media.startsWith('/media/')) {
          prefix = authorPrefixOfMedia(media);
          break;
        }
      }
      final cands = moveTargetCandidates(tree, prefix);
      if (cands.isEmpty) {
        _toast('没有可用的目标文件夹（需同作者同单元库）');
        return null;
      }
      if (!mounted) return null;
      return showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('移动到文件夹'),
          content: SizedBox(
            width: 420,
            height: 420,
            child: cands.length > 400
                ? ListView.builder(
                    itemCount: 400,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text(cands[i],
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(ctx).pop(cands[i]),
                    ),
                  )
                : ListView(
                    children: [
                      for (final c in cands)
                        ListTile(
                          dense: true,
                          title: Text(c,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => Navigator.of(ctx).pop(c),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消')),
          ],
        ),
      );
    } catch (e) {
      _toast('读取目录失败：$e');
      return null;
    }
  }

  Future<void> _batchMove() async {
    if (_batchBusy || !canBatchDelete(selectedWorks)) return;
    final groups = _selectedByLib();
    if (groups.length != 1) {
      _toast('批量移动一次只能处理同一基础库的作品');
      return;
    }
    final lib = groups.keys.first;
    final ids = groups[lib]!;
    setState(() => _batchBusy = true);
    try {
      final target = await _pickMoveTarget(lib);
      if (target == null || !canBatchMove(selectedWorks, target)) return;
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('批量移动'),
          content: Text(batchMoveConfirmText(ids.length, target)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('确认移动')),
          ],
        ),
      );
      if (ok != true) return;
      var done = 0;
      final errors = <String>[];
      for (final id in ids) {
        // 先 dry 预检（服务端校验同作者/同单元库），再确认执行。
        final dry = await postWorkMove(lib, id, target);
        if (dry == null || dry['ok'] != true) {
          errors.add('${dry?['error'] ?? '网络错误'}');
          continue;
        }
        final j = await postWorkMove(lib, id, target, confirm: true);
        if (j != null && j['ok'] == true) {
          done++;
        } else {
          errors.add('${j?['error'] ?? '网络错误'}');
        }
      }
      _exitSelect();
      await load();
      _toast(errors.isEmpty
          ? '已移动 $done 个作品到「$target」'
          : '已移动 $done 个，失败：${errors.first}');
    } finally {
      if (mounted) setState(() => _batchBusy = false);
    }
  }

  // K2 第3项：服务端暂未提供"手动新增作品"接口，入口保留但置灰。
  void _manualAddUnavailable() {
    _toast('服务端未提供新增作品接口');
  }

  // 仅在数据加载/筛选变化时重算，避免观看进度刷新时反复重建列表
  void _refreshFilter() {
    // 顺序：顶级单元库 → 来源基础库 → 作品类型。
    var scoped = works.whereType<Map>().toList();
    if (topFilter.isNotEmpty) {
      scoped = [
        for (final w in scoped)
          if (_topOfWork(w) == topFilter) Map<String, dynamic>.from(w)
      ];
    }
    // 再按来源库（跨库同名作者合并后的筛选）。
    final byLib = filterWorksByLib(
      scoped,
      lib: libFilter,
      fallbackLib: primaryLib,
    );
    filteredWorks = filterWorksByType(byLib, typeFilter);
    typeCounts = workTypeCounts(works);
  }

  /// 作品 → 所属顶级单元库 id；拿不到返回空串（不猜）。
  String _topOfWork(dynamic raw) {
    if (raw is! Map) return '';
    final m = meta;
    if (m == null) return '';
    var basic = '${raw['_bid'] ?? ''}'.trim();
    if (basic.isEmpty) {
      final libId = '${raw['_lib'] ?? ''}'.trim();
      if (libId.isNotEmpty && m.basicById(libId) != null) basic = libId;
    }
    final av = '${raw['av'] ?? ''}'.trim();
    if (basic.isEmpty && av.isNotEmpty) basic = m.basicIdForPath(av);
    if (basic.isEmpty) return '';
    return m.topIdForBasic(basic);
  }

  /// 作品里实际出现的顶级单元库（按首次出现顺序）；只有 >1 个才显示筛选条。
  List<MapEntry<String, int>> get _topFilterOptions {
    final counts = <String, int>{};
    final order = <String>[];
    for (final w in works.whereType<Map>()) {
      final t = _topOfWork(w);
      if (t.isEmpty) continue;
      if (!counts.containsKey(t)) order.add(t);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return [for (final k in order) MapEntry(k, counts[k] ?? 0)];
  }

  /// 顶级单元库的显示名（取树里的名字，拿不到就用 id）。
  String _topLabel(String id) {
    for (final t in meta?.tops ?? const <UnitLibrary>[]) {
      if (t.id == id) return t.name.isEmpty ? id : t.name;
    }
    return id;
  }

  /// 切换顶级单元库筛选项（空串 = 全部）。
  void _setTopFilter(String top) {
    if (topFilter == top) return;
    setState(() {
      topFilter = top;
      // 换顶级后原来的来源库选择可能不再成立，一并归零。
      libFilter = '';
      _refreshFilter();
    });
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

  /// 来源库筛选（跨库同名作者合并）：空串 = 全部。
  void _setLibFilter(String lib) {
    if (libFilter == lib) return;
    setState(() {
      libFilter = lib;
      _refreshFilter();
    });
  }

  /// 基础库展示名：优先当前库元数据里的名称，其次 id 本身。
  ///
  /// 只在多库合并时用（单库不显示筛选条），所以查不到名称时直接给 id 也能读。
  String libLabel(String id) {
    for (final b in (meta?.allBasics ?? const <BasicLibRef>[])) {
      if (b.id == id) {
        return displayLibraryName(b.id, b.name);
      }
    }
    for (final b in (meta?.basics ?? const <BasicLibRef>[])) {
      if (b.id == id) return displayLibraryName(b.id, b.name);
    }
    return displayLibraryName(id, id);
  }

  // 点击头像放大查看（可双指缩放，点任意处关闭）；长按设置/清除手动头像。
  void _showAvatar(BuildContext context) {
    final src = effectiveAv;
    if (src.isEmpty) return;
    final srcLib =
        libOfMediaPath(src).isEmpty ? primaryLib : libOfMediaPath(src);
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
              cacheManager: DiziCache.manager,
              imageUrl: cfg.mediaUrl(src, lib: srcLib.isEmpty ? null : srcLib),
              httpHeaders: cfg.headersFor(srcLib.isEmpty ? null : srcLib),
              fit: BoxFit.contain,
              // owner 2026-11-21：同上，去掉图片中央缓冲圈
              placeholder: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  // J-A3：作者信息头——展开为完整资料，收起为紧凑条（头像 + 名字 + 等级）。
  Widget _authorHeader(BuildContext context) {
    final grade =
        AuthorGrade.fromStats(meta?.stats[widget.name], works: works.length);
    if (_headerCollapsed.value) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        child: Row(children: [
          GestureDetector(
            onTap: () => _showAvatar(context),
            onLongPress: () => _showAvatarMenu(context),
            child: AuthorAvatar(
              name: widget.name,
              mediaPath: displayAv,
              lib: primaryLib.isEmpty ? null : primaryLib,
              size: 26,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text('@${widget.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Color(AuthorGrade.colorForGrade(grade))
                  .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(grade,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(AuthorGrade.colorForGrade(grade)))),
          ),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: () => _showAvatar(context),
                onLongPress: () => _showAvatarMenu(context),
                child: AuthorAvatar(
                  name: widget.name,
                  mediaPath: displayAv,
                  lib: primaryLib.isEmpty ? null : primaryLib,
                  size: AuthorAvatar.headerSize,
                ),
              ),
              const SizedBox(height: 4),
              // owner 2026-11-22：头像旁固定入口，与库封面入口同风格。
              _AvatarAction(
                icon: Icons.add_photo_alternate_outlined,
                label: '设置头像',
                onTap: () => _showAvatarMenu(context),
              ),
              if (canRestoreAvatar)
                _AvatarAction(
                  icon: Icons.restart_alt,
                  label: '恢复自动',
                  onTap: _restoreAutoAvatar,
                ),
            ]),
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
                    fallbackId: primaryLib.isEmpty ? cfg.lib : primaryLib,
                    // 0.9.6：不再回退库名文案，无归属显示 SECRET
                    fallbackName: '',
                    works: works.length,
                  ),
                  // 跨库同名作者合并：多库时才提示「来自 N 个库」。
                  if (authorSourceSummary(_libs).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${authorSourceSummary(_libs)}'
                        ' · 同名作者已合并 · 可按库里作品分开看',
                        key: const ValueKey('author-merge-hint'),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Text('作者简介',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: _editBio,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.edit_outlined,
                              size: 13, color: Colors.grey),
                          SizedBox(width: 2),
                          Text('编辑',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey)),
                        ]),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(_bioText,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13)),
                  if (bioAt > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('简介更新于 ${formatAuthorBioAt(bioAt)}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey)),
                    ),
                ])),
          ]),
          // L2：作者页不再提供「全量同步」入口，同步统一收到单元库级配置。
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.name}'), actions: [
        const HomeAction(),
        if (loading)
          const SizedBox.shrink()
        else if (selectingWorks) ...[
          IconButton(
              tooltip:
                  allWorksSelected(selectedWorks, _visibleIds) ? '取消全选' : '全选',
              onPressed: _visibleIds.isEmpty ? null : _toggleSelectAll,
              icon: Icon(allWorksSelected(selectedWorks, _visibleIds)
                  ? Icons.deselect
                  : Icons.select_all)),
          IconButton(
              tooltip: '退出多选',
              onPressed: _exitSelect,
              icon: const Icon(Icons.close)),
        ] else ...[
          IconButton(
              tooltip: '手动新增作品（服务端未提供）',
              onPressed: _manualAddUnavailable,
              icon: const Icon(Icons.add_box_outlined, color: Colors.grey)),
          IconButton(
              tooltip: '多选作品',
              onPressed: works.isEmpty
                  ? null
                  : () => setState(() => selectingWorks = true),
              icon: const Icon(Icons.checklist)),
        ],
      ]),
      body: loading
          ? const _AuthorPageSkeleton()
          : Column(children: [
              // J-A3：可滚动收起的作者信息头（高度动画，不回弹抖动）。
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                // 0.9.153：只重建信息栏本身（滚动回调不再 setState 整页）。
                child: ValueListenableBuilder<bool>(
                  valueListenable: _headerCollapsed,
                  builder: (_, __, ___) => _MeasuredSize(
                    onSize: (s) {
                      // 布局阶段只记数值，不写状态；下一帧滚动判定读它。
                      if (_headerCollapsed.value) {
                        _headerCollapsedH = s.height;
                      } else {
                        _headerExpandedH = s.height;
                      }
                    },
                    child: _authorHeader(context),
                  ),
                ),
              ),
              const Divider(height: 1),
              // owner 2026-11-24：顶级单元库作为一级筛选维度。
              // 只有该作者的作品跨越多于一个顶级单元库（媒体库）时才出现，
              // 单库作者（常态）不多占一行。
              if (_topFilterOptions.length > 1)
                HorizontalChipBar(
                  key: const ValueKey('author-top-filter'),
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Center(
                      child: FilterChip(
                          label: Text('全部媒体库 ${works.length}',
                              style: const TextStyle(fontSize: 12)),
                          selected: topFilter.isEmpty,
                          showCheckmark: false,
                          onSelected: (_) => _setTopFilter('')),
                    ),
                    for (final o in _topFilterOptions)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Center(
                          child: FilterChip(
                              key: ValueKey('author-top-${o.key}'),
                              label: Text(
                                  '${LibraryBadge.stripIndex(_topLabel(o.key))} ${o.value}',
                                  style: const TextStyle(fontSize: 12)),
                              selected: topFilter == o.key,
                              showCheckmark: false,
                              onSelected: (_) => _setTopFilter(o.key)),
                        ),
                      ),
                  ],
                ),
              // 跨库同名作者合并：只在作者确实来自多个基础库时出现来源筛选，
              // 单库作者（常态）不额外占一行。
              if (libFilterOptions(works, fallbackLib: primaryLib).length > 1)
                HorizontalChipBar(
                  key: const ValueKey('author-lib-filter'),
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Center(
                      child: FilterChip(
                          label: Text('全部库 ${works.length}',
                              style: const TextStyle(fontSize: 12)),
                          selected: libFilter.isEmpty,
                          showCheckmark: false,
                          onSelected: (_) => _setLibFilter('')),
                    ),
                    for (final o
                        in libFilterOptions(works, fallbackLib: primaryLib))
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Center(
                          child: FilterChip(
                              key: ValueKey('author-lib-${o.key}'),
                              label: Text('${libLabel(o.key)} ${o.value}',
                                  style: const TextStyle(fontSize: 12)),
                              selected: libFilter == o.key,
                              showCheckmark: false,
                              onSelected: (_) => _setLibFilter(o.key)),
                        ),
                      ),
                  ],
                ),
              if (works.isNotEmpty)
                HorizontalChipBar(
                  height: 46,
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
              // K2：批量操作条（多选时显示）。
              if (selectingWorks)
                Material(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      child: Row(children: [
                        Text('已选 ${selectedWorks.length}',
                            style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _visibleIds.isEmpty
                                ? ''
                                : '共 ${_visibleIds.length} 个',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ),
                        TextButton.icon(
                            onPressed:
                                _visibleIds.isEmpty ? null : _toggleSelectAll,
                            icon: const Icon(Icons.select_all, size: 16),
                            label: Text(
                                allWorksSelected(selectedWorks, _visibleIds)
                                    ? '取消全选'
                                    : '全选',
                                style: const TextStyle(fontSize: 12))),
                        TextButton.icon(
                            onPressed: (_batchBusy ||
                                    !canBatchMove(selectedWorks, 'x'))
                                ? null
                                : _batchMove,
                            icon: const Icon(Icons.drive_file_move_outline,
                                size: 16),
                            label: const Text('移动',
                                style: TextStyle(fontSize: 12))),
                        TextButton.icon(
                            onPressed:
                                (_batchBusy || !canBatchDelete(selectedWorks))
                                    ? null
                                    : _batchDelete,
                            icon: const Icon(Icons.delete_outline,
                                size: 16, color: Colors.redAccent),
                            label: const Text('删除',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.redAccent))),
                      ]),
                    ),
                  ),
                ),
              Expanded(
                  child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.depth != 0) return false;
                  if (n is ScrollUpdateNotification ||
                      n is OverscrollNotification) {
                    final m = n.metrics;
                    final action = headerActionFor(
                      collapsed: _headerCollapsed.value,
                      pixels: m.pixels,
                      maxScrollExtent: m.maxScrollExtent,
                      delta: n is ScrollUpdateNotification
                          ? (n.scrollDelta ?? 0)
                          : 0,
                      // 边缘 overscroll 不分方向：已到端点即稳定态，收起态需要展开。
                      overscroll: n is OverscrollNotification,
                      headerExtent: _headerExtent,
                    );
                    if (action == HeaderAction.collapse &&
                        !_headerCollapsed.value) {
                      _headerCollapsed.value = true;
                    } else if (action == HeaderAction.expand &&
                        _headerCollapsed.value) {
                      _headerCollapsed.value = false;
                    }
                  }
                  return false;
                },
                child: WorkGrid(
                    controller: _authorScroll,
                    works: filteredWorks,
                    lib: primaryLib.isEmpty ? null : primaryLib,
                    selecting: selectingWorks,
                    selectedIds: selectedWorks,
                    onToggleSelect: _toggleSelect,
                    onEnterSelect: _enterSelect,
                    // owner 2026-11-24：只有从作者主页进播放页时，
                    // 点头像才返回作者页（不叠新页）。
                    fromAuthor: true,
                    manualIds: manualWorkIds),
              )),
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

  /// 卡片第二行文字；默认「作品类型」，搜索结果可传「@作者 · 类型」。
  final String Function(dynamic work)? subtitleOf;

  /// 已展示到列表末尾时回调（推荐页用它续拉下一批）。
  final VoidCallback? onEndReached;

  /// 播放器走到末尾需要更多作品时的回调，返回是否追加成功。
  final Future<bool> Function(List works)? onNeedMoreWorks;

  /// K2：多选模式（卡片显示勾选圈，点击改为切换选择）。
  final bool selecting;

  /// K2：当前已选作品 id。
  final Set<String> selectedIds;

  /// K2：切换某个作品的选择状态。
  final ValueChanged<String>? onToggleSelect;

  /// K2：长按卡片进入多选模式（携带被长按的作品 id）。
  final ValueChanged<String>? onEnterSelect;

  /// K3：手动名单（作品 id），卡片左上角显示「手」角标。
  final Set<String> manualIds;

  /// P 修复：外部可传入滚动控制器（作者页头部收起需要读实时滚动范围）。
  /// 为空时沿用内部控制器。
  final ScrollController? controller;

  /// owner 2026-11-24：是否从**作者主页**进入播放页。
  ///
  /// 只有作者页传 true。此前这里写死 `fromAuthor: true`，导致推荐页/搜索页
  /// 进播放页后点头像会执行 `maybePop()` 返回上一页（回到推荐页），
  /// 而不是打开作者主页。
  final bool fromAuthor;

  // T3：已移除旧「收藏夹」idx/名称传参链
  const WorkGrid({
    super.key,
    required this.works,
    this.lib,
    this.subtitleOf,
    this.onEndReached,
    this.onNeedMoreWorks,
    this.selecting = false,
    this.selectedIds = const <String>{},
    this.onToggleSelect,
    this.onEnterSelect,
    this.manualIds = const <String>{},
    this.controller,
    this.fromAuthor = false,
  });

  @override
  State<WorkGrid> createState() => _WorkGridState();
}

class _WorkGridState extends State<WorkGrid> {
  late final bool _ownsScroll = widget.controller == null;
  late final ScrollController _scroll = widget.controller ?? ScrollController();
  int _shown = 0;

  /// 已经为哪一份作品列表预热过首屏封面（按列表实例判定，避免每帧重复发起）。
  List<dynamic>? _prefetchedFor;
  @override
  void initState() {
    super.initState();
    _shown = initialGridCount(widget.works.length);
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePrefetch();
  }

  @override
  void didUpdateWidget(covariant WorkGrid old) {
    super.didUpdateWidget(old);
    if (!identical(old.works, widget.works) ||
        old.works.length != widget.works.length) {
      // 推荐页续播是「尾部追加」：保留已渲染进度，新条目随滚动出现。
      final appended = widget.onEndReached != null &&
          widget.works.length > old.works.length &&
          _shown >= old.works.length;
      if (appended) {
        _shown = widget.works.length;
      } else {
        // 重新加载/筛选后回到首屏分页，避免沿用上一个列表的滚动位置
        _shown = initialGridCount(widget.works.length);
      }
    }
    if (_shown > widget.works.length) _shown = widget.works.length;
    _schedulePrefetch();
  }

  /// 首屏缩略图预热（0.9.68）：作者主页/收藏夹/搜索/推荐共用这个网格，
  /// 此前只有基础库页和单元库页会预热，这几页首屏仍会先空白再逐张请求。
  /// 放到帧后执行，不阻塞首帧；provider 与 `WorkCard` 完全一致
  /// （同 `withImageWidth` URL + 同 `ResizeImage` 宽度），缓存键一致才命中。
  void _schedulePrefetch() {
    if (!mounted) return;
    final works = widget.works;
    if (works.isEmpty || identical(_prefetchedFor, works)) return;
    _prefetchedFor = works;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchFirstScreen();
    });
  }

  void _prefetchFirstScreen() {
    final works = widget.works;
    if (works.isEmpty) return;
    final mq = MediaQuery.of(context);
    final n = firstScreenThumbCount(
      viewportWidth: mq.size.width,
      viewportHeight: mq.size.height,
      maxCrossAxisExtent: 180,
      padding: 0,
      crossSpacing: 2,
      mainSpacing: 2,
      aspectRatio: WorkCard.aspect,
    );
    if (n <= 0) return;
    final px = workCardDecodeWidth(mq.devicePixelRatio);
    // 网格可能跨库（收藏夹/搜索/推荐），headers 按作品各自的库取，
    // 与 `WorkCard.headers` 一致，缓存键才对得上。
    final headersOfUrl = <String, Map<String, String>>{};
    for (final w in works.take(n)) {
      final lib = _libFor(w);
      final cover = workCoverUrl(
        w,
        lib: lib,
        urls: WorkCoverUrls.standard(
          mediaUrl: (path) => cfg.mediaUrl(path, lib: lib),
          rawUrl: (path) => cfg.u(path, lib: lib).toString(),
        ),
      );
      if (cover.isEmpty) continue;
      headersOfUrl.putIfAbsent(
          withImageWidth(cover, kWorkImageWidth), () => cfg.headersFor(lib));
    }
    if (headersOfUrl.isEmpty) return;
    ThumbPrefetch.instance.runWith(
      headersOfUrl.keys,
      limit: n,
      fetch: (u) => loadImage(thumbImageProvider(
        u,
        decodeWidth: px,
        headers: headersOfUrl[u] ?? const <String, String>{},
        cacheManager: DiziCache.manager,
      )),
    );
  }

  @override
  void dispose() {
    if (_ownsScroll) _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    if (_shown >= widget.works.length) {
      widget.onEndReached?.call();
      return;
    }
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
    // G10：观看记录由每张卡片的 `_WatchProgressLayer` 局部监听（work_card.dart），
    // 进度 tick 不再重建整个网格与全部卡片。
    return _buildGrid(context);
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
        final lib = _libFor(w);
        // 封面统一走 work_cover：th → 图文首图 → 视频抽帧（带版本参数避开旧缓存）
        final cover = workCoverUrl(
          w,
          lib: lib,
          urls: WorkCoverUrls.standard(
            mediaUrl: (path) => cfg.mediaUrl(path, lib: lib),
            rawUrl: (path) => cfg.u(path, lib: lib).toString(),
          ),
        );
        // G13：视频右下角显示时长，图文显示图片张数
        final wid = '${(w is Map ? w['id'] : null) ?? ''}';
        final selected = widget.selecting && widget.selectedIds.contains(wid);
        final manual = widget.manualIds.contains(wid);
        Widget card = WorkCard(
          title: '${w['ti'] ?? ''}',
          typeLabel: widget.subtitleOf?.call(w) ?? workTypeLabel(w),
          coverUrl: cover,
          headers: cfg.headersFor(_libFor(w)),
          badge: workCoverBadge(w),
          watchLib: lib,
          watchId: wid,
          onTap: () {
            // K2：多选模式下点击只切换选择，不进播放器。
            if (widget.selecting) {
              widget.onToggleSelect?.call(wid);
              return;
            }
            // 播放器需要可变列表：续播时直接追加到它自己手里这份。
            final playerWorks = List.of(works, growable: true);
            // owner 2026-11-22：标明来源，播放页据此禁用左滑并把头像改成返回。
            // owner 2026-11-24：改为跟随组件参数，只有作者页进来才是 true；
            // 推荐页/搜索页进播放页时点头像必须打开作者主页，不能弹回上一页。
            Navigator.of(context).push(instantRoute((_) => PlayerPage(
                works: playerWorks,
                start: i,
                lib: _libFor(w),
                fromAuthor: widget.fromAuthor,
                onNeedMore: widget.onNeedMoreWorks == null
                    ? null
                    : () => widget.onNeedMoreWorks!(playerWorks))));
          },
        );
        // K2：选择圈与选中描边（画在卡片外层，不改 WorkCard 本身）。
        card = Stack(fit: StackFit.expand, children: [
          card,
          if (widget.selecting)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.black45,
                  border: Border.all(color: Colors.white70, width: 1.5),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 15, color: Colors.white)
                    : null,
              ),
            ),
          if (selected)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(WorkCard.radius),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
                ),
              ),
            ),
        ]);
        // K3：手动作品角标（手动 > 爬虫，与 J19 一致）。
        if (manual) {
          card = Stack(fit: StackFit.expand, children: [
            card,
            Positioned(
              top: 6,
              left: 6,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(workSourceLabel(manual: true),
                      style:
                          const TextStyle(fontSize: 9, color: Colors.white70)),
                ),
              ),
            ),
          ]);
        }
        if (widget.onEnterSelect != null && !widget.selecting) {
          card = GestureDetector(
            onLongPress: () => widget.onEnterSelect!(wid),
            child: card,
          );
        }
        return card;
      },
    );
  }
}

/// 0.9.153：量出头部两态的真实高度。
///
/// 为何需要：`AnimatedSize` 动画的是外层高度，子节点始终按最终尺寸布局，
/// 所以这里读到的是稳定值而不是动画中间值。布局阶段只回调数值、不触发重建。
class _MeasuredSize extends SingleChildRenderObjectWidget {
  const _MeasuredSize({required this.onSize, required Widget child})
      : super(child: child);
  final ValueChanged<Size> onSize;
  @override
  _RenderMeasuredSize createRenderObject(BuildContext context) =>
      _RenderMeasuredSize(onSize);
  @override
  void updateRenderObject(
      BuildContext context, _RenderMeasuredSize renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderMeasuredSize extends RenderProxyBox {
  _RenderMeasuredSize(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;
  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      onSize(size);
    }
  }
}
