import 'dart:async';
import 'json_num.dart';
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
import 'card_metrics.dart';
import 'author_index.dart' show kAuthorGridPagePadding;
import 'grid_spec.dart';
import 'work_card_prefetch.dart';
import 'work_cover.dart';
import 'work_lib.dart';
import 'media_path.dart';
import 'media_resize.dart';
import 'player_image.dart';
import 'rel_path.dart';
import 'recommend_grid.dart';
import 'horizontal_chip_bar.dart';
import 'cache_settings.dart';
import 'app_settings.dart';
import 'app_theme.dart';
import 'author_filter.dart';
import 'author_filter_options.dart';
import 'author_drag.dart';
import 'author_merge.dart';
import 'author_mount_sheet.dart';
import 'author_dir_filter.dart';
import 'author_avatar.dart';
import 'author_avatar_store.dart';
import 'author_avatar_view.dart';
import 'author_badge_row.dart';
import 'author_filter_bar.dart';
import 'author_filter_ui.dart';
import 'author_grid.dart';
import 'author_grade.dart';
import 'basic_lib_page.dart';
import 'folder_structure_page.dart';
import 'text_fold.dart';
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
import 'rank_filter.dart';
import 'rank_metric.dart';
import 'lib_cover.dart';
import 'loop_link.dart';
import 'playback_prefs.dart';
import 'json_isolate.dart';
import 'library_tree.dart';
import 'unit_crawler.dart';
import 'crawler_sections.dart';
import 'unit_crawler_page.dart';
import 'unit_author_mount_page.dart';
import 'unit_author_groups.dart'
    show authorDirForName, authorDirError, unitAuthorCreateUrl;
import 'stable_order.dart';
import 'unit_library.dart';
import 'unit_library_view.dart';
import 'header_collapse.dart';
import 'work_card.dart';
import 'work_key.dart';
import 'multi_server.dart';
import 'meta_source.dart';
import 'node_key.dart';
import 'server_origin.dart';
import 'playback_flow.dart';
import 'playback_state.dart';
import 'pic_zoom.dart';
import 'playback_error.dart';
import 'mpv_log_digest.dart';
import 'perf_diagnostics.dart';
import 'text_fit.dart';
import 'esc_back.dart';
import 'top_node.dart';
import 'avatar_prefetch.dart';
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
import 'unit_fraction.dart';

/// `encodeMediaPath` 的唯一实现在 `media_path.dart`；main.dart 继续转发，
/// 免得既有 import 点（含测试）全部改路径。
export 'media_path.dart'
    show
        encodeMediaPath,
        isApiMediaPath,
        isAbsoluteMediaUrl,
        isProtocolRelativeUrl,
        resolveProtocolRelative;

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
//
// 规则本身收口到 `media_path.isGifMediaPath`（与 `isCoverImagePath` /
// `isVideoMediaPath` 同一条后缀剥除）：旧写法 `endsWith('.gif') ||
// contains('.gif?')` 只认查询串，`/m/a.gif#poster` 判成**不是动图**，
// 那张动图在网格里只播第一帧。这里只保留函数名（调用点与测试在用）。
bool isGifPath(String path) => isGifMediaPath(path);

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

  /// 跨库聚合请求（`lib=all`）的**地址与鉴权一起**取。
  ///
  /// `lib=all` 在绑定表里没有对应条目，地址因此回落 `base`——即**激活
  /// 连接**；而 `headers` 是 `headersFor(lib)`，即**当前库**那条连接。
  /// 用户切过连接但没切库时（`active_server_v1` 已指向 B，`cfg.lib` 仍是
  /// A 的库），这两个值分属两台机器：拿 A 的密码去问 B 的 `/api/authors`
  /// → 401，或两台恰好同账号时静默读到另一台的作者/推荐/排行。
  ///
  /// 返回 record 而不是「地址 getter + 头 getter」两个独立口子：调用方
  /// 拿不到只取一半的组合，这类「地址 A、账号 B」的缺陷也就无处可写。
  /// 鉴权用 `user`/`pass`——它们由 `_boot` / `_persist` 与 `base` 一起从
  /// 激活连接写入，天然与地址同源。
  ({Uri uri, Map<String, String> headers}) aggregate(String path) => (
        uri: u(path, lib: 'all'),
        headers: {'Authorization': basicAuthHeader(user, pass)},
      );

  // 媒体路径统一带库前缀：/media/<lib>/<相对路径>
  String media(String p, {String? lib}) {
    final l = lib ?? this.lib;
    final path = p.trim();
    if (path.isEmpty) return path;
    // 网络地址（带协议的绝对地址 / 协议相对的 `//cdn/x.jpg`）都不补库前缀。
    // 协议相对地址在这里就按当前库的服务器协议补全：`mediaUrl` 会再前置
    // `baseFor`，不补就会拼出 `http://nas:8090//cdn/x.jpg`。
    if (isProtocolRelativeUrl(path)) {
      return resolveProtocolRelative(baseFor(l), path);
    }
    if (isAbsoluteMediaUrl(path)) return path;
    // 服务端接口地址（`/api/thumb/<lib>/<id>` 等）不是媒体文件：
    // 扫描器会把这类地址直接写进作品的 `th`，若再套 `/media/<lib>/` 就变成
    // `/media/<lib>/api/thumb/...` —— 服务端把 `api` 当库内子目录 → 必然 404。
    // 实测 2026-11-23：2288 条图文作品是这种 `th`，对应「comics / AI 单图无封面」。
    if (isApiMediaPath(path)) return path;
    if (l.isEmpty) return path;
    // 相对路径（如手动封面 `_cover/v1.jpg`）必须补成 /media/<lib>/...，
    // 否则会被直接拼到域名后面变成 `http://ip:8090_cover/...`，永远加载不出来。
    // 前缀拼装只有 `media_path.libMediaPrefix` 一处（库段编码也在那里）。
    if (!isMediaPath(path)) return libMediaPrefix(l, path);
    // `/media/` 尾部走 `mediaLibSplitOrNull`（前缀判定、切片、库段解码与
    // `lib_cover.libOfMediaPath` / `authorPrefixOfMedia` 同一个出口）；未知
    // 首段要连带它自己一起重新前缀，所以这里还需要原始 rest 拼回去。
    final rest = mediaRelOrNull(path)!;
    final headId = mediaLibSplitOrNull(path)!.lib;
    if (headId.isNotEmpty &&
        (_bindings.containsKey(headId) || headId == l)) {
      return path;
    }
    return libMediaPrefix(l, rest);
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

/// 全局作者头像索引：作者名 → `av` 路径（来自 `/api/authors.json`）。
///
/// 作品的 `av` 只有部分条目带；没有时 `avatarFor` 之前会直接落到默认头像。
/// 作者级头像在 authors.json 里是全的，这里补一层兜底。
///
/// 这张表属于**某一条连接**：`authors.json` 按 `lib=all` 读激活连接，索引里
/// 记的是那台服务器的作者头像。此前「已加载」是一个进程级布尔值，切过激活
/// 连接后仍然为 true：新连接的作者全部停在首字占位/旧服务器的头像上，直到
/// 重启 App（或手动「刷新作者」）。现在加载标记记录**来源作用域**，连接一变
/// 就当作没加载过。
final Map<String, String> authorAvatarIndex = <String, String>{};
bool _authorAvatarLoading = false;

/// 索引来源（`<base>␁<user>`）：空串＝尚未加载。
String _authorAvatarScope = '';

/// 当前激活连接的索引作用域。用户与地址一起算：只换密码不必重拉，
/// 换地址/账号就是换了一台机器或另一份作者表。
///
/// 分隔符不在这里手写：`node_key.scopedKey` 是作用域键的唯一拼装口
/// （0.9.334 把五份 `\u0001` 字面量收成一处之后，再写一份就又回到
/// 「某处被改成 `\u0001 `」时只有一处读不出来）。
String get authorAvatarScopeKey => scopedKey(cfg.base, cfg.user);

bool get _authorAvatarLoaded =>
    _authorAvatarScope.isNotEmpty && _authorAvatarScope == authorAvatarScopeKey;

/// B2：作者头像索引是异步补进来的，索引到位后通知已渲染的头像/播放页重建。
///
/// 之前的实现只在启动时 fire-and-forget 拉一次，网络慢于首帧时，
/// 卡片和播放页会一直停在默认人形占位，直到别的状态变化才刷新。
final ValueNotifier<int> authorAvatarRevision = ValueNotifier<int>(0);

Future<void> ensureAuthorAvatarsLoaded() async {
  if (_authorAvatarLoaded || _authorAvatarLoading) return;
  _authorAvatarLoading = true;
  // 连接已变：旧索引属于另一台服务器，留着就是串头像（同名作者带上别人
  // 机器上的图，或本机有、对方没有的条目永远不消失）。
  if (_authorAvatarScope.isNotEmpty) authorAvatarIndex.clear();
  final scopeKey = authorAvatarScopeKey;
  try {
    // 头像索引属于**激活连接**：地址与鉴权必须同源（`cfg.aggregate`）。
    final scope = cfg.aggregate('/api/authors.json');
    final r = await http
        .get(scope.uri, headers: scope.headers)
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
        // 作用域取**发请求时**那一份：请求途中用户可能又切了连接，
        // 直接把当前值写进去等于把旧服务器的索引记成新连接的。
        _authorAvatarScope = scopeKey;
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
  final List<BasicLib> basics;

  /// 0.9.9：库根坐标系下的**全部**基础库（含其它单元库下的）。
  /// `basics` 只覆盖当前注册库目录，作者总览/排行榜/推荐/搜索的筛选与词条
  /// 需要跨全部基础库，否则非当前库的作者会落到 SECRET 或无法被筛到。
  final List<BasicLib> allBasics;
  final Map<String, dynamic> stats;

  /// J10：大库 id → 名称，用于作者筛选里的「大库」多选。
  final Map<String, String> bigNames;

  /// L5：单元库树（作者筛选与词条来源）。为空表示服务端未提供节点信息。
  final UnitLibrary? unitTree;

  /// 含基础库的单元库（深度优先，SECRET 最后）。
  final List<UnitLibrary> units;

  /// 基础库 id → 所属单元库 id。
  final Map<String, String> basicToUnit;

  /// 顶级节点（媒体库根）的显示名：**这台服务器自己的库根目录名**。
  ///
  /// 此前 `unitNameOf('secret')` 一律读进程级 `TopNodeName.current`，而那是
  /// 一个全局单值：设置页逐台加载元数据时，第二台的库根名会把第一台的名字
  /// 直接改掉（`LibMeta.load` 里无条件 `TopNodeName.setFromRoot(root)`）。
  /// 首页两张媒体库卡片于是同名——都是最后加载那台的根目录名，而各自的
  /// 基础库/封面仍然来自不同机器，用户看到的是「两个不一样的库叫同一个名字」。
  ///
  /// 名字是这份元数据的属性（它读的就是这台服务器的 `root`），所以存在这里；
  /// 全局 `TopNodeName` 只服务「手里没有 meta」的旧页面（文件结构页）。
  final String topName;

  const LibMeta({
    required this.basics,
    required this.stats,
    this.allBasics = const [],
    this.bigNames = const {},
    this.unitTree,
    this.units = const [],
    this.basicToUnit = const {},
    this.topName = '',
  });

  /// 跨库口径的基础库列表（全量优先，缺失时回落到当前库）。
  List<BasicLib> get filterBasics =>
      allBasics.isNotEmpty ? allBasics : basics;

  /// P3：顶级节点列表（＝每个连接的媒体库根，即单元库树的直接子节点）。
  ///
  /// 只由结构算出（根的直接子节点），不看任何目录名文本。
  List<UnitLibrary> get tops => [
        for (final c in (unitTree?.children ?? const <UnitLibrary>[]))
          if (!c.isEmpty) c,
      ];

  /// P3：单元库 → 所属顶级节点 id。顶级节点自身返回自己。
  ///
  /// 查询顺序（0.9.347 收口）：
  ///  1. **本份元数据自己的树**（`mediaRootOfUnit`）——多连接时它与
  ///     `LibraryBadge.topOfUnit` 可能给出两个答案；
  ///  2. 树里没有「媒体库」这一层（单连接旧形态）时，才读全局结构表；
  ///  3. 最后只接受「本身就是顶级」的精确命中，不猜。
  ///
  /// 为什么第 1 步必须在前面：`LibraryBadge.topOfUnit` 是**进程级**、由最后
  /// 一次 `UnitMetaReg.setFrom` 覆盖。两台服务器存在同名 rel 时（`A/MID`
  /// 两边都有），A 服务器的作者会被贴上 B 服务器的媒体库 id：筛选面板点
  /// 「媒体库 B」能看到 A 的作者，点 A 反而看不到。`mediaIdFor` 已在 0.9.324
  /// 改成只读本树并写了注释，而这条链路（筛选/删除监测/作者页顶部筛选）
  /// 还停在全局表上——同一个问题只修了半边。
  String topIdFor(String unitId) {
    if (unitId.isEmpty) return '';
    final tree = unitTree;
    if (tree != null && tree.children.any((c) => c.isMediaRoot)) {
      final own = mediaRootOfUnit(tree, unitId);
      if (own != null) return own.id;
    }
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

  /// 单元库 → 所属**媒体库** id（用于给作者卡贴媒体库词条）。
  ///
  /// 只用**本份元数据自己的树**反查，不走全局 `LibraryBadge.topOfUnit`：
  /// 那张表是进程级、由最后一次 `setFrom` 覆盖，两台服务器有同名 rel 时
  /// A 库的作者会贴上 B 服务器的媒体库名（与 0.9.324「两张媒体库卡片同名」
  /// 同一族）。结构表在这里只能作为「自己这棵树」的查询，不能跨连接共用。
  ///
  /// 单连接/旧形态下树里没有媒体库这一层（根的直接子节点就是单元库，且
  /// 它们本来就以 `LibEntryKind.top` 外观渲染），此时不存在可以额外贴的
  /// 一级——返回空串，调用方不贴。不拿库根容器冒充一级。
  String mediaIdFor(String unitId) {
    if (unitId.isEmpty) return '';
    final tree = unitTree;
    if (tree == null) return '';
    if (!tree.children.any((c) => c.isMediaRoot)) return '';
    final media = mediaRootOfUnit(tree, unitId);
    return media?.id ?? '';
  }

  static final Map<String, LibMeta> cache = <String, LibMeta>{};
  static final Map<String, Future<LibMeta>> _loading =
      <String, Future<LibMeta>>{};
  static final Map<String, DateTime> _cachedAt = <String, DateTime>{};

  /// 缓存有效期：服务端改了单元库名/节点后最多 5 分钟生效，无需重启 App。
  static const Duration cacheTtl = Duration(minutes: 5);

  /// 作废某库的元数据缓存（`lib` 省略＝全部）。
  ///
  /// 与 `clearAuthorTypeCache` 同一个理由：卡片「快速刷新」重建索引后，
  /// `libraries.json`/`nodes` 都可能已变（单元库新目录、封面指针），
  /// 而这张表只有 TTL、没有主动失效入口，5 分钟内看到的仍是旧树。
  /// **不是**给「猜状态」用的保险，只由明确的写入动作调用。
  static void invalidate([String? lib]) {
    if (lib == null || lib.isEmpty) {
      cache.clear();
      _cachedAt.clear();
      _loading.clear();
      return;
    }
    // 键可能带来源连接（同一库在两台服务器各有一份元数据），
    // 「作废这个库」必须清掉**全部连接**的副本，不能只清默认那一份。
    cache.removeWhere((k, _) => metaKeyIsFor(k, lib));
    _loading.removeWhere((k, _) => metaKeyIsFor(k, lib));
    _cachedAt.removeWhere((k, _) => metaKeyIsFor(k, lib));
  }

  /// 读取某库的元数据。
  ///
  /// [source] 是**这条记录属于哪台服务器**。不传（旧行为）时按 `cfg` 绑定表
  /// 路由——那条路只在首页聚合过库列表后才成立：从设置页直接进入时表是空的，
  /// 第二台服务端的库 id 会被拿去请求默认服务器（404 → 叶节点全落 SECRET，
  /// 或恰好同名时读到另一台服务器的整棵树）。调用方知道自己读的是哪台
  /// 服务器时必须传进来。
  ///
  /// 缓存键同时带连接（`meta_source.metaCacheKey`）：两台服务端各有一个
  /// `lib-1` 时只按 `lib` 做键，后到的一份会把先到的一份顶掉。
  static Future<LibMeta> load(String lib,
      {bool force = false, MetaSource source = MetaSource.none}) {
    final key = metaCacheKey(lib, source);
    final hit = cache[key];
    final at = _cachedAt[key];
    if (!force &&
        hit != null &&
        at != null &&
        DateTime.now().difference(at) < cacheTtl) {
      return Future.value(hit);
    }
    return _loading.putIfAbsent(key, () async {
      var basics = const <BasicLib>[];
      var allBasics = const <BasicLib>[];
      var stats = <String, dynamic>{};
      var bigNames = <String, String>{};
      UnitLibrary? unitTree;
      var units = const <UnitLibrary>[];
      var basicToUnit = const <String, String>{};
      var topName = '';
      try {
        // 地址与鉴权同源：有显式来源就用它，否则按 `lib` 走绑定表。
        // 旧写法两处都是 `cfg.*`，绑定表为空（设置页直入）或库里没有这条
        // 绑定时，第二台服务端的请求会打到默认服务器。
        final hdr = source.headers();
        Uri u(String path) => source.isScoped
            ? Uri.parse(libApiUrl(source.base, path, lib))
            : cfg.u(path, lib: lib);
        Map<String, String> h() => hdr ?? cfg.headersFor(lib);
        final rs = await Future.wait([
          http.get(
              u('/api/libraries.json?t=${DateTime.now().millisecondsSinceEpoch}'),
              // 地址按 `lib` 路由，鉴权头也必须按 `lib`（`cfg.headers` 是
              // **当前库**那条连接的账号）：从另一个服务端的库进来时，两者
              // 不同源就是拿 A 的密码去敲 B 的门（401），整棵库树退回空。
              headers: h()),
          http.get(u('/api/libraries'), headers: h()),
          http.get(u('/api/author_stats.json'),
              headers: h()),
          http.get(u('/api/nodes'), headers: h()),
        ]).timeout(const Duration(seconds: 10));
        if (rs[0].statusCode == 200 && rs[1].statusCode == 200) {
          final lj = jsonOf(rs[0]);
          final reg = jsonOf(rs[1]);
          var base = '';
          if (reg is Map) {
            for (final e in listOf(reg['libraries'])) {
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
              //
              // 0.9.324：这里原来只写全局 `TopNodeName`——设置页逐台加载时，
              // 后一台的库根名会把前一台覆盖掉（两张媒体库卡片同名）。名字是
              // **这份元数据**的属性，本地留一份；全局值只留给没有 meta 的
              // 旧页面（文件结构页）。
              final ownTopName = TopNodeName.nameFromRoot(root);
              if (ownTopName.isNotEmpty) topName = ownTopName;
              TopNodeName.setFromRoot(root);
              // 0.9.284：`basicsUnderBase` 直接返回 `BasicLib`，不再有
              // 「ref → 模型」的转换点（那里就是丢 cover/cv 的地方）。
              var unitBasics = basics;
              var rootBasics = const <BasicLib>[];
              if (root.isNotEmpty) {
                // 以库根为坐标系取**全部**基础库（39 个），既给单元库归属，
                // 也给作者筛选/词条用。
                rootBasics = basicsUnderBase(ljm, root);
                if (rootBasics.isNotEmpty) unitBasics = rootBasics;
              }
              allBasics = rootBasics.isNotEmpty ? rootBasics : basics;
              // 单元库＝owner 在「文件结构」里勾选的节点文件夹（/api/nodes），
              // 与主页使用同一份来源；只有节点为空时才退回 v2 分组。
              // 解析与归一化只在 [parseNodesPayload] 一处（与主页同一个入口）。
              var markRels = const <String>[];
              var markCovers = const <String, String>{};
              if (rs[3].statusCode == 200) {
                final p = parseNodesPayload(jsonOf(rs[3]));
                markRels = p.rels;
                markCovers = p.covers;
              }
              // 0.9.327：封面指针与首页同一条链（`unitCoverTable`）。
              // 此前这里只把 `/api/nodes` 的 `covers` 交给 `nodesFromMarks`，
              // 而那个表只有被标记为节点的 rel 才带指针（实测 31 条里 4 条）：
              // 从设置页进单元库页时，owner 在 `libraries.json` 里设过的
              // 整树封面读不到，卡片回落到自动封面——首页却是对的。
              //
              // 作用域仍是**本函数正在读的那条连接**：这四条请求已经按 `lib`
              // 路由，节点却写当前库的 base/id 时，跨连接下单元库卡片的封面
              // 与挂载请求会打到另一台服务器。
              final treeCovers = <String, String>{};
              collectUnitCovers(ljm, treeCovers,
                  source.isScoped ? source.serverId : cfg.serverIdFor(lib));
              final nodes = markRels.isEmpty
                  ? nodesFromV2(ljm, root: base)
                  : nodesFromMarks(markRels,
                      covers: unitCoverTable(
                        serverId: source.isScoped
                            ? source.serverId
                            : cfg.serverIdFor(lib),
                        rels: markRels,
                        treeCovers: treeCovers,
                        nodesCovers: markCovers,
                      ),
                      // 节点归属也按来源：`cfg.baseFor(lib)` 在绑定表为空时
                      // 回落到默认服务器，单元库卡片的封面与挂载请求就会
                      // 打到另一台机器（同族缺陷的「归属」那一份）。
                      serverBase: source.isScoped
                          ? source.base
                          : cfg.baseFor(lib),
                      serverId: source.isScoped
                          ? source.serverId
                          : cfg.serverIdFor(lib),
                      serverLabel: source.isScoped
                          ? ''
                          : cfg.serverLabelFor(lib));
              final ownName =
                  ownTopName.isEmpty ? TopNodeName.current : ownTopName;
              final tree = buildUnitTree(
                  nodes: nodes,
                  basics: unitBasics,
                  topName: ownName,
                  // 这台服务器的根名就是它自己的：节点归属连接只有它一个。
                  topNameOf: (_) => ownName);
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
          final auth = mapOrNull(sj is Map ? sj['authors'] : null);
          if (auth != null) stats = auth;
        }
      } catch (_) {}
      final meta = LibMeta(
          basics: basics,
          allBasics: allBasics,
          stats: stats,
          bigNames: bigNames,
          unitTree: unitTree,
          units: units,
          basicToUnit: basicToUnit,
          topName: topName);
      cache[key] = meta;
      _cachedAt[key] = DateTime.now();
      _loading.remove(key);
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
  BasicLib? basicById(String id) {
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
    if (id == 'secret') {
      final own = topName.trim();
      return own.isNotEmpty ? own : TopNodeName.current;
    }
    for (final u in units) {
      if (u.id == id) return u.name;
    }
    // 媒体库根不在 `units` 里（那是容器，不带基础库），只按 id 回落会把
    // `media:s1` 这种内部键直接写到界面上。先查一次顶层名字。
    final t = tops.where((u) => u.id == id).toList();
    if (t.isNotEmpty) {
      final n = t.first.name.trim();
      if (n.isNotEmpty) return n;
    }
    return id;
  }

  /// 顶级节点（＝媒体库根）的显示名：**只认这份元数据**。
  ///
  /// 顶级节点在 `units` 里没有条目（`flattenUnits` 只收带基础库的层，
  /// 媒体库根是容器），所以 [unitNameOf] 拿它只能回落 id——卡片上就会出现
  /// `media:s1` 这种东西。名字优先取树里那一层的 `name`，其次本份元数据的
  /// 库根名（[topName]），最后才回落 id；不读进程级 `TopNodeName`（两台
  /// 服务器会串名）。
  String topNameOf(String topId) {
    if (topId.isEmpty) return '';
    final t = tops.where((u) => u.id == topId).toList();
    if (t.isNotEmpty && t.first.name.trim().isNotEmpty) return t.first.name;
    final own = topName.trim();
    if (own.isNotEmpty) return own;
    return topId;
  }

  /// 筛选条上那一枚媒体库词条的名字：**树里的名字，拿不到就用 id**。
  ///
  /// 与 [topNameOf] 的区别是有意的：`topName` 是本份元数据**库根目录**的名字，
  /// 多连接时每个媒体库根的目录名全都一样（都叫 SECRET 或同一个根名），
  /// 拿它当兜底会让筛选条上出现两三个同名词条 —— 用户无法区分点哪个。
  /// 所以这里回落 id（`media:s1`），至少能看出是两张不同的卡片。
  ///
  /// 0.9.347：这段「遍历 tops 找同 id、名字空就回落 id」此前在删除监测页与
  /// 作者页的 `_topLabel` 里各写一份，**函数体逐字相同**；两处词条文案必须
  /// 一致（同一个媒体库在两个页面不能显示两个名字），所以只能有一处实现。
  String topLabelFor(String topId) {
    if (topId.isEmpty) return '';
    for (final t in tops) {
      if (t.id == topId) return t.name.trim().isEmpty ? topId : t.name;
    }
    return topId;
  }

  /// 单元库配色顺序（不含顶级 SECRET）。
  List<String> get unitOrder => [
        for (final u in units)
          if (u.id != 'secret') u.id
      ];

  Map<String, String> get unitNames =>
      {for (final u in units) u.id: unitNameOf(u.id)};

  /// 作者所属历史分组（服务端 `big_id`）；无法匹配基础库时为空。
  ///
  /// 基础库反查只走 [basicIdForPath] 一条链（`basics` + `allBasics`）。
  /// 此前这里自己调 `basicLibForMedia(basics, …)`，只查当前注册库那一份：
  /// 作者挂在别的单元库的基础库里时（`allBasics` 里才有），同一份数据
  /// 「基础库/单元库归属算得出来、历史分组归属永远空」——筛选面板选了
  /// 单元库能命中、选了分组却一条不中，两边都自称按同一份 meta 算的。
  String bigIdFor(String mediaPath) =>
      basicById(basicIdForPath(mediaPath))?.bigId ?? '';

  List<String> get order => filterBasics.map((e) => e.id).toList();

  Map<String, String> get names => {
        for (final b in filterBasics) b.id: basicLibLabel(b, b.name),
      };

  String gradeFor(String author, int works) =>
      AuthorGrade.fromStats(stats[author], works: works);
}

/// 多份 [LibMeta] → 筛选面板选项（**唯一同包装**）。
///
/// 0.9.334：`_optionsOf` 与 `_unitNameIn` 这两个静态函数在推荐页与搜索页
/// 各写了一份，**字节完全相同**。四张表的合并规则（`bigNames` 同名取谁、
/// 单元库名先问哪份 meta）只该有一条：改一处而漏另一处时，两个页面的
/// 筛选面板就会对同一份数据给出不同名字，而两边各自都「汇总成功」。
AuthorFilterOptions authorFilterOptionsOfMetas(List<LibMeta> ms) =>
    authorFilterOptionsFrom(
      basics: [for (final m in ms) ...m.filterBasics],
      units: [for (final m in ms) ...m.units],
      tops: [for (final m in ms) ...m.tops],
      bigNames: {for (final m in ms) ...m.bigNames},
      unitNameOf: (id) => unitNameInMetas(ms, id),
    );

/// 单元库名称：先问定义了它的那份 meta。
///
/// `secret`（＝媒体库根）这层的名字来自 `TopNodeName`，不是节点自身字段，
/// 所以不能直接读 `u.name`。
String unitNameInMetas(List<LibMeta> ms, String id) {
  for (final m in ms) {
    if (m.units.any((u) => u.id == id)) return m.unitNameOf(id);
  }
  return '';
}

/// J10：作者作品类型索引。T3 起只走基础库索引
/// `/api/lib/<id>/index.json` 的 kinds（覆盖库内全部作品，无需逐作者请求）；
/// 旧「收藏夹」`/api/c/<idx>.json` 通道已移除。按注册库缓存，失败不阻断筛选。
///
/// 0.9.325：**失败不进缓存**。这张表是进程级的，没有 TTL；此前一次超时/401
/// 也被当成「这个库的作者都没有类型」永久写进表里，于是「按类型筛选」直到
/// 重启 App 或手动快速刷新之前都是空结果，而索引其实好好的。现在只缓存
/// **读成功**的结果（含「服务器上确实没有基础库」这种真答案）；读失败当场
/// 把条目摘掉，下一次进筛选面板重新请求一次。
///
/// 0.9.331：缓存键**必须带连接**。此前只按 `lib` 做键，而 `lib` 这个字符串不是
/// 全局唯一的：`mergeRegisteredLibraries` 按库 id 去重，于是「同一条库 id 昨天
/// 属于 A 机、今天属于 B 机」（A 机删库/断连，B 机注册了同名 id）之后，键仍是
/// 同一个 `lib-1`——B 机的「按类型筛选」拿到的是 A 机那份 kinds，页面上一片
/// 「没有这段类型的作品」，而索引其实好好的，且没有任何入口能发现。
/// 键带连接后，绑定一变就是新键，旧条目自然不会被误用。
/// 与 `LibMeta` 的 `metaCacheKey` / `unitCoverKey` 同一条规则。
final Map<String, Future<Map<String, Set<String>>>> _authorTypeCache = {};

/// 类型索引的缓存键：`<lib>` 或 `<lib>\u0001<连接>`。
///
/// 未指定来源时退化为裸库 id（旧键）：调用方不知道自己在哪台服务器上，
/// 硬编一个作用域只会把同一份数据拆成两份缓存。
/// 分隔符取自 `node_key.kNodeKeySep`，与节点/封面/元数据缓存同一套。
String authorTypeCacheKey(String lib, String serverId) {
  final l = lib.trim();
  final sid = serverId.trim();
  return sid.isEmpty ? l : '$l$kNodeKeySep$sid';
}

Future<Map<String, Set<String>>> _authorTypesForLib(String lib,
    {String serverId = ''}) {
  final key = authorTypeCacheKey(lib, serverId);
  return _authorTypeCache.putIfAbsent(key, () async {
    try {
      final reg = await http
          .get(cfg.u('/api/libraries', lib: lib), headers: cfg.headersFor(lib))
          .timeout(const Duration(seconds: 12));
      if (reg.statusCode != 200) return _typesFailed(key);
      final lj = await http
          .get(
              cfg.u(
                  '/api/libraries.json?t=${DateTime.now().millisecondsSinceEpoch}',
                  lib: lib),
              headers: cfg.headersFor(lib))
          .timeout(const Duration(seconds: 12));
      if (lj.statusCode != 200) return _typesFailed(key);
      final regJson = jsonOf(reg);
      var base = '';
      if (regJson is Map) {
        for (final e in listOf(regJson['libraries'])) {
          if (e is Map && '${e['id']}' == lib) {
            base = '${e['base'] ?? ''}';
            break;
          }
        }
      }
      final libJson = jsonOf(lj);
      if (base.isEmpty || libJson is! Map) return _typesFailed(key);
      final basics = basicsUnderBase(Map<String, dynamic>.from(libJson), base);
      // 每个基础库各读一份 `index.json`。此前是 `Future.wait` 全量并发：
      // 39 个基础库会在同一瞬间发出 39 条请求（各 12s 上限），把刚起来的
      // 连接池和 NAS 一起打满——与搜索页/爬虫页的「有界并发」口径相反。
      // 这里同样走 6 路（`mapConcurrent`），结果保持输入顺序，
      // `mergeAuthorTypes` 不关心顺序。
      final parts = await mapConcurrent<BasicLib, Map<String, Set<String>>>(
          basics, 6, (b) => _typesFromLibIndex(lib, b.id));
      return mergeAuthorTypes(parts);
    } catch (_) {
      return _typesFailed(key);
    }
  });
}

/// 读失败：把这条缓存摘掉再返回空表。
///
/// 不做「先缓存、失败后再删」的两段式：`putIfAbsent` 已经把这枚 Future 放
/// 进表里，删除必须发生在**同一次**调用内，否则下一次调用拿到的是那个
/// 已经失败的 Future（Future 不会重跑）。
Map<String, Set<String>> _typesFailed(String cacheKey) {
  _authorTypeCache.remove(cacheKey);
  return <String, Set<String>>{};
}

Future<Map<String, Set<String>>> _typesFromLibIndex(
    String lib, String basicId) async {
  try {
    final r = await http
        .get(cfg.u('/api/lib/$basicId/index.json', lib: lib),
            headers: cfg.headersFor(lib))
        .timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return <String, Set<String>>{};
    return authorTypesFromIndex(jsonOf(r));
  } catch (_) {
    return <String, Set<String>>{};
  }
}

/// 汇总多个注册库的作者类型。
/// 清掉某库的类型索引缓存（该库索引被重建后必须清）。
///
/// 此前这张表只有 `putIfAbsent`、**没有任何失效入口**：卡片「快速刷新」重建
/// 了 `lib/<id>/index.json`，类型筛选（kinds）却一直用进程启动时那份结果，
/// 新加的作品在下一次重启前永远不会出现在「按类型筛选」里——刷新按钮
/// 看起来成功了，筛选结果却是旧的。
/// 键带连接（`authorTypeCacheKey`），所以「作废这个库」必须清掉**全部连接**
/// 的副本——只清裸库 id 会留下另一台服务器那份旧 kinds，与
/// `LibMeta.invalidate` 同一个口径（`metaKeyIsFor`）。
void clearAuthorTypeCache(String lib, {String serverId = ''}) {
  final l = lib.trim();
  if (l.isEmpty) {
    _authorTypeCache.clear();
    return;
  }
  if (serverId.trim().isNotEmpty) {
    _authorTypeCache.remove(authorTypeCacheKey(l, serverId));
    return;
  }
  _authorTypeCache.removeWhere((k, _) => authorTypeCacheKeyIsFor(k, l));
}

/// [key] 是否属于库 [lib]（不带连接的旧键与任何作用域键都算）。
///
/// 判定只有一处（`node_key.scopedKeyIsFor`）：与 `metaKeyIsFor` 用的是**同
/// 一个函数体**，两处各写一份时总有一处忘记 `lib-1` / `lib-10` 的前缀关系，
/// 表现是「刷新了库 1，库 10 的旧 kinds 留到重启」。
bool authorTypeCacheKeyIsFor(String key, String lib) =>
    scopedKeyIsFor(key, lib);

/// [libs] 的每一条各自属于哪台连接：[lib] → 连接 id。
///
/// 调用方从库列表/绑定表能读到来源时用它，读不到就留空（旧行为：裸库 id 做键）。
typedef AuthorTypeScope = String Function(String lib);

Future<Map<String, Set<String>>> loadAuthorTypes(Iterable<String> libs,
    {AuthorTypeScope? serverIdOf}) async {
  final parts = await Future.wait([
    for (final l in libs.toSet())
      _authorTypesForLib(l, serverId: serverIdOf?.call(l) ?? '')
  ]);
  return mergeAuthorTypes(parts);
}

// 作者统计上报（播放/访问），失败静默，不影响播放
//
// 0.9.331：带上上限。`.ignore()` 只是不关心结果，**不是**不限时：断网/掉包时
// 这条请求会在连接池里挂到 OS 超时，长时间占用一个连接名额（而它是每次进
// 作者页都会发的一条）。8s 与其它读请求同一口径。
void postStat(String type, String author, {String? lib}) {
  if (cfg.base.isEmpty || author.isEmpty) return;
  try {
    http
        .post(cfg.u('/api/stats', lib: lib),
            headers: {...cfg.headersFor(lib), 'Content-Type': 'application/json'},
            body: jsonEncode({'type': type, 'author': author}))
        .timeout(const Duration(seconds: 8))
        .ignore();
  } catch (_) {}
}

// 小水滴：每个作品每日 1 颗、每周 3 颗，服务端按作者累计
Future<Map<String, dynamic>?> fetchDropStatus(String id, {String? lib}) async {
  if (cfg.base.isEmpty || id.isEmpty) return null;
  try {
    final r = await http
        .get(cfg.u('/api/drops?id=${Uri.encodeQueryComponent(id)}', lib: lib),
            headers: cfg.headersFor(lib))
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
            // 地址按 `lib` 路由，鉴权头也必须按 `lib`：`cfg.headers` 是**当前库**
            // 那条连接的账号，从另一个服务端的库发起同步就是拿 A 的密码敲 B 的
            // 门（401），页面显示「同步失败」而其实是打错了服务器。
            headers: {...cfg.headersFor(lib), 'Content-Type': 'application/json'},
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
  if (j == null || !serviceSaidOk(j)) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('同步启动失败：${serverErrorText(j) ?? '网络错误'}')));
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
    if (boolOf(s['running'])) return;
    _finish(intOf(s['exit'], -1));
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
            // 同上：小水滴统计要记在作品所属那台服务器上。
            headers: {...cfg.headersFor(lib), 'Content-Type': 'application/json'},
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
  // 去 `/media/<lib>/` 前缀走 `media_path.mediaLibSplitOrNull`（唯一实现，
  // 连百分号解码一起做完）；本文件不手写 `substring(7)` + `indexOf('/')`。
  var p = path.trim();
  final split = mediaLibSplitOrNull(p);
  if (split != null && split.rel.isNotEmpty) p = split.rel;
  // 拆分走 `rel_path.dart` 唯一实现：`A\\B` 与 `A/B` 必须是同一组段，
  // 否则「移动到文件夹」的作者前缀算不出候选，跟同一作者在别的库里的
  // 表现对不上。
  final segs = relSegments(p);
  final i = segs
      .indexWhere((s) => s == 'VID' || s == 'PIC' || s == 'vid' || s == 'pic');
  if (i > 0) return relJoin(segs.sublist(0, i));
  return segs.length > 1 ? relJoin(segs.sublist(0, segs.length - 1)) : '';
}

/// K2：目标文件夹候选列表（`/api/cat/tree` 的 dirs 拍平），
/// 只保留与作者前缀一致的目录，避免把作品移到别的作者下。
List<String> moveTargetCandidates(dynamic catTree, String authorPrefix) {
  final out = <String>[];
  final prefix = authorPrefix.trim();
  void walk(List dirs) {
    for (final d in dirs) {
      if (d is! Map) continue;
      // rel 先归一：服务端下发的 `A\\B` 与这里缓存的 `A/B` 是同一目录，
      // 不归一就会漏掉整棵子树（目录在对话框里少一层，用户以为不能移）。
      final rel = normalizeRelPath('${d['rel'] ?? ''}');
      if (rel.isEmpty) continue;
      if (prefix.isEmpty || rel == prefix || rel.startsWith('$prefix/')) {
        out.add(rel);
      }
      final kids = d['dirs'];
      if (kids is List) walk(kids);
    }
  }

  if (catTree is Map) walk(listOf(catTree['dirs']));
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
    // P1：词条配色与三层级外观必须在首帧前就位，否则首屏卡片会先闪默认色。
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
      final cols = listLengthOf(jsonOf(rs[0])['collections']);
      var basics = 0;
      if (rs[1].statusCode == 200) {
        final j = mapOrNull(jsonOf(rs[1]));
        basics = listLengthOf(j?['basicLibraries']);
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
          testMsg[s.id] = '连接失败：${errorText(e)}';
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
                // owner 2026-11-27：「主页多库并列，没有『当前』」——
                // 这里指服务端注册表里的默认库，措辞统一为「默认」。
                child: Text('默认',
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
                  child: Text(isActive ? '默认连接' : '设为默认')),
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

/// A2（0.9.315 删除）：这里曾有一个「仅本层」标记，用来提示「设了色但不下发」。
///
/// owner 2026-11-27 把规则改成「从直接上级逐级上行，第一个设过色的层即分发源」
/// 之后，任何单元库设的色都会下发，标记本身成了错误信息。按「同一个问题
/// 不允许两个兜底」的规矩整个删掉，而不是留一个永远不亮的组件。

class LibraryBadgeColorsPage extends StatefulWidget {
  const LibraryBadgeColorsPage({super.key});
  @override
  State<LibraryBadgeColorsPage> createState() => _LibraryBadgeColorsPageState();
}

class _LibraryBadgeColorsPageState extends State<LibraryBadgeColorsPage> {
  /// 0.9.9：词条配色按**单元库**（作者来源词条）配置，不再按旧注册库。
  List<UnitLibrary> units = const [];

  /// P1：媒体库与基础库各一组，配合向下继承。
  List<UnitLibrary> tops = const [];
  List<BasicLib> basics = const [];

  /// P2：按顶级单元库分组——每个顶级单元库下的单元库与基础库，
  /// 只按树结构归组，不看任何目录名文本。
  final Map<String, List<UnitLibrary>> unitsByTop = <String, List<UnitLibrary>>{};
  final Map<String, List<BasicLib>> basicsByTop = <String, List<BasicLib>>{};
  List<UnitLibrary> otherUnits = const [];

  /// owner 2026-11-26：「防止页面显示条目过多……默认将媒体库下所有词条
  /// 自定义设置条目隐藏，点击展开后再进行分别设置」。
  ///
  /// 默认空集合＝全部折叠。键用顶级单元库 id 而不是名字：名字会变，
  /// 带序号时同一个库还可能有两种写法，用名字做键会出现「展开又自己收起来」。
  final Set<String> expandedTopSections = <String>{};
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
        // 不属于任何媒体库的单元库归入「其它」。
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
                        '词条按四类组织：媒体库设色后向下继承给其下所有'
                        '单元库/基础库；单元库可各自覆盖；基础库自己的颜色优先级最高；'
                        '作者一档管作者卡上那枚等级词条。'
                        '分发规则：任何单元库设的色都会向下分发给它的基础库/作品/作者，'
                        '更近的一层设过色时以更近的那层为准。'
                        '四种词条形状与尺寸一致，只用边框/底纹区分。',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  const _SectionHeader('词条外观（四类边框 / 底纹）'),
                  _entryStyleSection(),
                  const SizedBox(height: 8),
                  const _SectionHeader('按媒体库设置词条色'),
                  // P2：按媒体库分类——每个媒体库根一节，展开就是它的
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
                    const _SectionHeader('其它（不属于任何媒体库）'),
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
      LibEntryKind.top: '媒体库',
      LibEntryKind.unit: '单元库',
      LibEntryKind.basic: '基础库',
      LibEntryKind.author: '作者',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
              '四种词条（媒体库 / 单元库 / 基础库 / 作者）的圆角、内边距、字号'
              '固定一致，只能调边框粗细、边框颜色、边框深浅与底纹浓度'
              '（词条底色仍在下方按库设置）。作者那一档指作者卡上的等级词条。'
              '边框加粗只改视觉、不改变词条占位。调完即时生效，也可单层级恢复默认。',
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

  /// 边宽 / 边框颜色 / 边框透明 / 底纹；圆角与尺寸没有入口（形状固定）。
  ///
  /// owner 2026-11-26：「边框颜色调不了」——此前边框色写死在代码里
  /// （顶级白、其余黑），只能调粗细和透明度。现在可选颜色。
  Future<EntryStyle?> _showEntryStyleDialog(
      LibEntryKind kind, String label, EntryStyle initial) async {
    var w = initial.borderWidth;
    var ba = initial.borderAlpha;
    var fa = initial.fillAlpha;
    var bc = initial.borderColor ??
        (kDefaultEntryStyle[kind]?.borderColor ?? 0xFFFFFFFF);
    return showDialog<EntryStyle>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('$label · 词条外观'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _sliderRow('边框粗细', w, 0, 3, 31, (v) => setDlg(() => w = v),
                '${w.toStringAsFixed(1)}dp'),
            // 边框颜色：与词条底色用的同一套色板，点一下即预览。
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Text('边框颜色',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ),
            ),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in LibraryBadge.palette)
                GestureDetector(
                  onTap: () => setDlg(() => bc = c),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Color(c),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: bc == c ? Colors.lightBlueAccent : Colors.black26,
                        width: bc == c ? 2.5 : 1,
                      ),
                    ),
                    child: bc == c
                        ? const Icon(Icons.check,
                            size: 15, color: Colors.white)
                        : null,
                  ),
                ),
            ]),
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
                    borderWidth: w,
                    borderAlpha: ba,
                    fillAlpha: fa,
                    borderColor: bc)),
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
    final expanded = expandedTopSections.contains(top.id);
    // 折叠时也要能看出「这个媒体库设过什么」：按本组内已自定义的条目数
    // 给一句摘要，不展开也能判断要不要进去改。
    //
    // 判定必须走 `hasOwnColor` / `hasOwnBasicColor`，不能直接查色表：
    // 来源选了「自动分配」的条目表里可能还留着旧色（手工改过的配置、
    // 或从别的入口写过），那张色并不生效。旧写法按色表计数，于是一个
    // 全部选自动的媒体库会显示「已自定义 5 项」，进去一看每一行都写着
    // 「自动分配」——摘要与列表两个说法。
    final customized = <String>[
      if (LibraryBadge.hasOwnColor(top.id)) '本库',
      for (final u in subUnits)
        if (LibraryBadge.hasOwnColor(u.id)) u.name,
      for (final b in subBasics)
        if (LibraryBadge.hasOwnBasicColor(b.id)) b.name,
    ];
    final emojiCount = <String>[
      if (LibraryBadge.ownEmoji(top.id).isNotEmpty) top.id,
      for (final u in subUnits)
        if (LibraryBadge.ownEmoji(u.id).isNotEmpty) u.id,
      for (final b in subBasics)
        if (LibraryBadge.ownEmoji(b.id).isNotEmpty) b.id,
    ].length;
    final summary = customized.isEmpty && emojiCount == 0
        ? '未自定义 · 点开设置'
        : '已自定义 ${customized.length} 项'
            '${emojiCount > 0 ? ' · 后缀 $emojiCount' : ''}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 组头本身就是展开开关：整行可点，右侧箭头指示状态。
        InkWell(
          key: ValueKey('badge-section-toggle-${top.id}'),
          onTap: () => setState(() {
            if (!expandedTopSections.remove(top.id)) {
              expandedTopSections.add(top.id);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('媒体库 · ${LibraryBadge.stripIndex(name)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              Icon(expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: Colors.grey),
            ]),
          ),
        ),
        if (expanded) ...[
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
              child: Text('基础库（优先级最高）',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey)),
            ),
          for (final b in subBasics) _basicTile(b, indent: true),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _libTile(UnitLibrary u, {bool isTop = false, bool indent = false}) {
    final id = u.id;
    final name = u.name.isEmpty ? id : u.name;
    // D1：自定义色可能以 rel / node:rel 任一形式落盘，统一走归一化查询。
    // 顶级与下级各写一遍 `topColorFor(...) ?? …` 是两处口径：顶级换了来源
    // 之后其中一处必然漏（实测顶级选「自动分配」仍显示旧自定义色）。
    // 现在一律由 colorForUnit 给出**实际生效**的颜色。
    final color = LibraryBadge.colorForUnit(id, order: _order);
    final emoji = LibraryBadge.ownEmoji(id);
    // 文案与颜色同源：本层有没有生效中的自定义色 / 是否正在继承顶级。
    final ownColor = LibraryBadge.hasOwnColor(id);
    // 继承来源直接从分发链读（不再看 `topOfUnit` 那一跳）：颜色可以由
    // 中间层单元库分发，「我现在的色从哪来」必须与着色链是同一个答案。
    final inheritedFrom = LibraryBadge.inheritedColorFrom(id);
    final sourceLabel = LibraryBadge.sourceLabelOf(
      LibraryBadge.sourceFor(id),
      hasOwn: ownColor,
      inherits: inheritedFrom.isNotEmpty,
      sourceName: inheritedFrom.isEmpty
          ? ''
          : LibraryBadge.stripIndex(meta?.unitNameOf(inheritedFrom) ?? ''),
    );
    // 分发语义只有一条（owner 2026-11-27）：从直接上级逐级上行，第一个设过色
    // 的那层就是分发源。因此任何单元库设的色都能被下级拿到，不再区分
    // 「末梢 / 非末梢」——此前那行 `非末梢 · 仅本层` 是旧规则的遗留说法，
    // 界面上写着一个与真实行为相反的结论。
    final distributeNote = isTop ? '向下继承' : '可分发给下级';
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
      ]),
      subtitle: Text(
          '${u.basicCount} 个基础库 · $distributeNote'
          '${emoji.isEmpty ? '' : ' · 后缀 $emoji'}',
          style: const TextStyle(fontSize: 11)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (emoji.isNotEmpty)
            Text(emoji, style: const TextStyle(fontSize: 16, height: 1.1)),
          Text(
            sourceLabel,
            style: TextStyle(
                fontSize: 12,
                color: ownColor
                    ? Colors.lightBlueAccent
                    : (inheritedFrom.isNotEmpty
                        ? Colors.amber
                        : Colors.grey)),
          ),
        ],
      ),
      onTap: () async {
        final chosen = await _showBadgeDialog(name, id, color,
            kind: isTop ? LibEntryKind.top : LibEntryKind.unit,
            note: isTop
                ? '该色会向下继承给整个媒体库（单元库/基础库/作者）。'
                : '该色会向下分发给它的基础库/作品/作者；'
                    '更近的一层（自己或上级）设过色时，以更近的那层为准。');
        if (chosen == null) return;
        // 先写来源：setSource 在非「自定义」时会清掉本层自定义色，
        // 顺序反了会把刚设的色删掉。
        await LibraryBadge.setSource(id, chosen.source);
        if (chosen.source == BadgeColorSource.fixedCustom) {
          if (isTop) {
            await LibraryBadge.setTopColor(id, chosen.color);
          } else {
            await LibraryBadge.setColor(id, chosen.color);
          }
        } else {
          if (isTop) {
            await LibraryBadge.setTopColor(id, null);
          } else {
            await LibraryBadge.setColor(id, null);
          }
        }
        await LibraryBadge.setEmoji(id, chosen.reset ? null : chosen.emoji);
        if (mounted) setState(() {});
      },
    );
  }

  /// P1：基础库词条——自己设色优先，否则继承单元库/媒体库。
  Widget _basicTile(BasicLib b, {bool indent = false}) {
    final unitId = meta?.basicToUnit[b.id] ?? '';
    final color = LibraryBadge.basicColorFor(b.id, unitId, order: _order);
    // 文案与颜色同源：以前这行写 `own ? '自定义' : '继承'`，
    // 于是「来源=自动分配」被显示成「继承」，改了来源看不出变化。
    final own = LibraryBadge.hasOwnBasicColor(b.id);
    // 基础库的继承源从「所属单元库本层」开始逐级上行——中间层单元库设的色
    // 会先于媒体库根被拿到的。旧写法只看 `inheritsTopColor(unitId)`（只到
    // 媒体库根那一跳），于是「这张卡的色是从中间层单元库来的」在设置页
    // 显示成「继承上级」但说不出来源，与卡片实际颜色对不上。
    final inheritedFrom =
        LibraryBadge.inheritedColorFromBasic(b.id, unitId);
    final sourceLabel = LibraryBadge.sourceLabelOf(
      LibraryBadge.sourceForBasic(b.id),
      hasOwn: own,
      inherits: inheritedFrom.isNotEmpty,
      sourceName: inheritedFrom.isEmpty
          ? ''
          : LibraryBadge.stripIndex(meta?.unitNameOf(inheritedFrom) ?? ''),
    );
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
      subtitle: Text(
          '${formatCount(b.authors)} 作者 · ${formatCount(b.works)} 作品',
          style: const TextStyle(fontSize: 11)),
      trailing: Text(sourceLabel,
          style: TextStyle(
              fontSize: 12,
              color: own ? Colors.lightBlueAccent : Colors.grey)),
      onTap: () async {
        final chosen = await _showBadgeDialog(name, b.id, color,
            kind: LibEntryKind.basic, topLevelOnly: true);
        if (chosen == null) return;
        await LibraryBadge.setSource(b.id, chosen.source, basic: true);
        await LibraryBadge.setBasicColor(
            b.id,
            chosen.source == BadgeColorSource.fixedCustom && !chosen.reset
                ? chosen.color
                : null);
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
    // 初始色直接用调用方算好的**生效色**：再查一次 `customColorFor(id)`
    // 是第三处读法——基础库的色存在 `basicCustom`、顶级存在 `topCustom`，
    // 这里都查不到，于是弹窗预览与背后卡片不同色（`?? autoColor` 恰好盖住
    // 了后者，前者要靠调用方另写一遍才不露）。
    var current = autoColor;
    var hsv = HSVColor.fromColor(Color(current));
    // 本层设置值，**不是**含继承的 `emojiFor`：用后者当初值，一个「本层没设、
    // 从上级继承到某后缀」的库只要在这里改个颜色再保存，继承来的后缀就被
    // 写成本层值——用户没碰过后缀，继承关系却断了（0.9.347）。
    var currentEmoji = LibraryBadge.emojiForEdit(id);
    // D1：点「恢复自动」后必须真的清掉自定义色，而不是把当前自动色存成自定义。
    var reset = false;
    // owner 2026-11-25：颜色来源可选，不再把「继承顶级」写死成唯一出路。
    var source = topLevelOnly
        ? LibraryBadge.sourceForBasic(id)
        : (LibraryBadge.sourceFor(id));
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
                    // 后缀只在**这一层真正设过**时才回传自己：`emojiFor` 会
                    // 把上级继承来的后缀一起返回，拿去当 `unitId` 的短路值
                    // 等于把「继承来的」写死在本层预览里。上级后缀仍由绘制层
                    // 按同一链拿到，预览不会因此丢后缀。
                    unitId: currentEmoji.isEmpty ? '' : id,
                    emoji: LibraryBadge.ownEmoji(id),
                    kind: kind),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(note,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('颜色来源',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
                const SizedBox(height: 6),
                SegmentedButton<BadgeColorSource>(
                  segments: const [
                    ButtonSegment(
                        value: BadgeColorSource.inheritTop,
                        label: Text('继承上级', style: TextStyle(fontSize: 11))),
                    ButtonSegment(
                        value: BadgeColorSource.autoAssign,
                        label: Text('自动分配', style: TextStyle(fontSize: 11))),
                    ButtonSegment(
                        value: BadgeColorSource.fixedCustom,
                        label: Text('自定义', style: TextStyle(fontSize: 11))),
                  ],
                  selected: <BadgeColorSource>{source},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setLocal(() {
                    source = v.first;
                    // 选「自定义」才用当前色；选自动则预览立刻换成本库自动色。
                    if (source == BadgeColorSource.fixedCustom) {
                      current = Color(current).toARGB32();
                    } else {
                      reset = false;
                    }
                  }),
                ),
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
                        source = BadgeColorSource.fixedCustom;
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
                      source = BadgeColorSource.inheritTop;
                      reset = true;
                    }),
                    // owner 2026-11-26：统一说法「恢复默认」。
                    // 语义固定为：来源回「继承顶级」+ 清掉本层自定义色
                    // + 清掉 emoji 后缀。不再用「恢复继承/自动」这种
                    // 把两种来源混在一个词里的写法。
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('恢复默认'),
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
                    color: current,
                    emoji: currentEmoji,
                    reset: reset,
                    source: source)),
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

  /// 保存时写入的颜色来源（继承顶级 / 自动分配 / 自定义）。
  final BadgeColorSource source;
  const _BadgeDraft(
      {required this.color,
      required this.emoji,
      this.reset = false,
      this.source = BadgeColorSource.inheritTop});
}

class LibBadges extends StatelessWidget {
  final List<String> libIds;
  final List<String> order;
  final Map<String, String> names;

  /// 固定使用灰色的词条 id（顶级 SECRET / 无归属库名）。
  final Set<String> grayIds;
  // 等级词条（D–S），空串表示不显示
  final String grade;

  /// 基础库词条（owner 2026-11-26）。
  ///
  /// 「基础库词条的出现是配合文件夹挂载机制的」——它回答的是「这个作者在这几个
  /// 基础库里有目录」。层级上它是最末一级，只用于区分「同一作者分布在哪」，
  /// 不参与单元库归属判定（那个仍由**最下级单元库**生成，旧规则不变）。
  ///
  /// 常态折叠：标记为 [LibEntryKind.basic] 的词条默认收进末尾的展开键里，
  /// 避免播放页作者卡被撑长。
  final List<BadgeChipSpec> basicChips;

  /// 单条词条最大宽度（透传给词条行）。
  final double chipMaxWidth;

  const LibBadges({
    super.key,
    required this.libIds,
    this.order = const [],
    this.names = const {},
    this.grayIds = const {},
    this.grade = '',
    this.basicChips = const <BadgeChipSpec>[],
    this.chipMaxWidth = kBadgeChipMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    // owner 2026-11-27：媒体库词条也要贴到卡片上（`UnitBadges` 会把媒体库 id
    // 排在 `libIds` 最前）。上限从 2 提到 3 是**同一件事的后果**，不是放宽：
    // 保留 2 的话媒体库词条会占掉两个单元库名额中的一个，作者挂两个单元库时
    // 第二个直接变成 `+1`——「更上级的词条把下级挤掉」正好反了。
    final labels = LibraryBadge.labels(libIds, max: 3, names: names);
    // 基础库词条（owner 2026-11-26 新增）也必须参与「有没有词条」的判定：
    // 只判 labels/grade 时，一个「单元库归属算不出来（labels 空）+ 没有等级」
    // 却挂了多个基础库的作者，基础库词条会被这条早退整个丢掉——而那正是
    // 基础库词条要回答的问题（他挂在哪几个基础库）。
    if (labels.isEmpty && grade.isEmpty && basicChips.isEmpty) {
      return const SizedBox.shrink();
    }
    // 与 [LibraryBadge.labels] **同一去重口径**：它按「非空 + 首次出现」去重，
    // 这里只过滤空串而不去重的话，`['a','a','b']` 会让第二个词条用 `a`
    // 的颜色/层级（label 是 `b`）——颜色与文字对不上。
    final shown = <String>[];
    final seenIds = <String>{};
    for (final id in libIds) {
      if (id.isEmpty || !seenIds.add(id)) continue;
      shown.add(id);
    }
    // 配色顺序：全局单元库顺序优先（与基础库卡同源），没有时才用调用方的。
    final colorOrder = UnitBadgeRegistry.orderOr(order);
    // 0.9.291：绘制只有 `author_badge_row` 一处（`BadgeChipWrap`）；这里只把
    // 「去重后的 id」翻译成 `BadgeChipSpec`（颜色/层级/`+N`）——先前本处的
    // `Wrap` 与作者卡那组词条的 `Wrap` 是两份同写。
    return CollapsibleBadgeWrap(
      chipMaxWidth: chipMaxWidth,
      chips: [
        for (var i = 0; i < labels.length; i++)
          // `+N` 那一条不对应任何库：`labels` 比 `shown` 多出一项（末尾的
          // 折叠计数）。此前仍拿 `shown[i]` 取 id/层级，于是「+2」这个词条会
          // 用第 4 个库的真实层级外观（比如媒体库粗边框）看起来像一级词条，
          // 颜色又因为 `startsWith('+')` 被强行改灰——同一个词条两处口径相反。
          if (labels[i].startsWith('+'))
            BadgeChipSpec(
                label: labels[i], color: LibraryBadge.gray)
          else
            BadgeChipSpec(
              label: labels[i],
              unitId: i < shown.length ? shown[i] : '',
              kind: i < shown.length
                  ? LibraryBadge.entryKindOfUnit(shown[i])
                  : LibEntryKind.unit,
              color: (i < shown.length && grayIds.contains(shown[i]))
                  ? LibraryBadge.gray
                  : LibraryBadge.colorForUnit(i < shown.length ? shown[i] : '',
                      order: colorOrder),
            ),
        if (grade.isNotEmpty)
          BadgeChipSpec(
            label: grade,
            color: AuthorGrade.colorForGrade(grade),
            kind: LibEntryKind.author,
          ),
        ...basicChips,
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

  /// owner 2026-11-26：「分发词条你倒是贴到相应位置去啊，多挂载作者挂几个
  /// 文件夹就贴几个到主页和卡片，像现在的单元库词条一样」。
  ///
  /// 同一作者分布在多个基础库时，说明他挂载了几处；词条就该一一列出，
  /// 而不是只贴主库那一个。为空时退回 `basicId`（单来源）。
  final List<String> basicIds;

  /// 等级词条（D–S），空串表示不显示。
  ///
  /// 0.9.317：`fallbackId` / `fallbackName` 两个参数在这里**零读取方**——
  /// 「没有单元库归属时显示的库名」这条规则早就换成了「无归属一律 SECRET」
  /// （owner 2026-11-27：不给作者编一个看着像库名的假归属）。参数留着
  /// 只会让调用方以为它还在起作用，所以整组删掉。
  final String grade;

  /// T5：词条唯一来源。调用方传入与基础库卡片同一份映射
  /// （[unitLabelByBasic] / [unitKeyByBasic]）；为空时用全局
  /// [UnitBadgeRegistry]（主页加载单元库时写入），再退回 [meta]。
  final Map<String, String> unitLabels;
  final Map<String, String> unitKeys;

  /// 单条词条最大宽度（透传给 [LibBadges]）。固定尺寸卡片传更小的值。
  final double chipMaxWidth;

  const UnitBadges({
    super.key,
    required this.meta,
    required this.mediaPath,
    this.basicId = '',
    this.basicIds = const <String>[],
    this.grade = '',
    this.unitLabels = const {},
    this.unitKeys = const {},
    this.chipMaxWidth = kBadgeChipMaxWidth,
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
    // owner 2026-11-26：按**全部来源基础库**贴词条，而不是只贴主库。
    // 多挂几个文件夹就有几条来源，词条一一列出（与单元库词条同一形态）。
    final sources = <String>[
      for (final b in basicIds)
        if (b.trim().isNotEmpty) b.trim(),
    ];
    if (sources.isEmpty && basicId.isNotEmpty) sources.add(basicId);

    final ids = <String>[];
    final names = <String, String>{...?meta?.unitNames};
    final gray = <String>{};
    void addUnit(String unitId, String basic) {
      // 同一个单元库只在词条里出现一次：多来源可能同属一个单元库。
      if (unitId.isEmpty) return;
      if (ids.contains(unitId)) return;
      ids.add(unitId);
      if (unitId == 'secret') {
        // 进程级 `TopNodeName` 是「最后加载那台服务器」的根名：两台服务器
        // 同时在线时，无名作者会贴上另一台的库根名。手里有 meta 就用它自己
        // 的库根名（`LibMeta.topName`），没有 meta 才回落全局值。
        final own = meta?.topName.trim() ?? '';
        names[unitId] = own.isNotEmpty ? own : TopNodeName.current;
        gray.add(unitId);
        return;
      }
      final label = _unitNameOf(basic, unitId);
      if (label.isNotEmpty) names[unitId] = label;
    }

    if (sources.isEmpty) {
      // 没有来源基础库：按路径解析，仍不行就落到媒体库根词条。
      var unitId = meta?.unitIdFor(mediaPath) ?? '';
      if (unitId.isEmpty) unitId = 'secret';
      addUnit(unitId, '');
    } else {
      for (final basic in sources) {
        addUnit(_unitKeyOf(basic), basic);
      }
      if (ids.isEmpty) addUnit('secret', '');
    }

    // 2026-11-27 事故复盘：这里曾按「每个来源基础库各贴一条」生成
    // `basicChips`，再叠加 emoji 分发 —— 一个跨 3 个基础库的作者会在播放页
    // 出现 3 条长词条、把信息区顶满。owner 只要「媒体库 / 单元库 / 基础库
    // 三个种类」，不是「每个来源各一条」。已撤掉，只保留单元库这一级。
    //
    // 2026-11-27 补：撤过头了。`CollapsibleBadgeWrap` 本来就是为「基础库
    // 词条常态折叠、点展开才显示」写的（owner 原话：「平日里可把基础库等
    // 词条隐藏起来…留一个小展开显示按键」），但它一直没有收到任何
    // `basicChips` —— `LibBadges.basicChips` 在全库零调用点。于是「基础库
    // 词条」这个种类在界面上根本不存在，owner 说「词条还是没下发」指的就是它。
    // 现在按来源基础库各生成一条（`LibEntryKind.basic`），交给折叠组件收纳：
    // 常态只显示媒体库/单元库，末尾一个 `▾N`，点它或点媒体库词条才展开。
    final basicChips = <BadgeChipSpec>[];
    for (final basic in sources) {
      if (basic.isEmpty) continue;
      final label = (meta?.basicById(basic)?.name ?? '').trim();
      if (label.isEmpty) continue;
      // 同一基础库只贴一条（多来源可能重复传入同一个库）。
      if (basicChips.any((c) => c.unitId == basic)) continue;
      basicChips.add(BadgeChipSpec(
        label: label,
        unitId: basic,
        kind: LibEntryKind.basic,
        // 后缀与颜色同一条链：基础库自己的后缀 → 所属单元库 → 逐级上行。
        // 不传的话绘制层会把基础库 id 当单元库 id 去查，继承段永远落空。
        emoji: LibraryBadge.basicEmojiFor(basic, _unitKeyOf(basic)),
        // 配色顺序与同一排里的单元库词条同源：`UnitBadges` 上方给单元库词条
        // 走的是注册表（`LibBadges` 里 `orderOr`），这里若直读 `meta.unitOrder`，
        // 退化 meta（没有单元库树）时同一个作者的两条词条会用两套顺序取色。
        color: LibraryBadge.basicColorFor(
          basic,
          _unitKeyOf(basic),
          order: UnitBadgeRegistry.orderOr(meta?.unitOrder ?? const []),
        ),
      ));
    }

    // owner 2026-11-27（第四次提同一件事）：
    // > 「词条还是没下发，还是没粘贴！！！媒体库词条啊！！！基础库词条啊！！！」
    //
    // 单元库词条一直都在，媒体库词条却只有首页卡片有。作者卡/播放页/排行榜
    // 都只贴到最末一级，于是「这个作者属于哪个媒体库」任何卡片上都看不出来。
    // 这里按结构补一级：单元库 → 所属媒体库根（`topOfUnit` 结构表），
    // 拿不到就不贴（不编一个假的一级，也不读目录名）。单连接旧形态下
    // 单元库自己就是一级，`topIdFor` 返回它自己，于是自然不重复贴。
    // 逐个单元库取所属媒体库，**不是只看第一个**。
    //
    // 同名作者可能同时挂在两台服务器（两个媒体库）下——挂载不跨单元库，
    // 但作者身份是按平台 uid 认的，于是 `ids` 里会有属于 A 库与 B 库的两个
    // 单元库。此前只对 `ids.first` 求一次媒体库，作者卡上永远只有先出现的
    // 那一个媒体库词条，另一个库的归属在界面上不存在——而 owner 的原话是
    // 「多挂载作者挂几个文件夹就贴几个」。
    final mediaIds = <String>[];
    final namesWithTop = <String, String>{...names};
    for (final unitId in ids) {
      final topId = meta?.mediaIdFor(unitId) ?? '';
      if (topId.isEmpty || ids.contains(topId) || mediaIds.contains(topId)) {
        continue;
      }
      final label = meta?.topNameOf(topId) ?? '';
      if (label.isEmpty) continue;
      mediaIds.add(topId);
      namesWithTop[topId] = label;
      // 媒体库词条是继承源，不是「无归属」：不能被灰。
      gray.remove(topId);
    }
    // 媒体库词条排在最前（层级从高到低），后面才是单元库与折叠的基础库。
    final shownIds = <String>[...mediaIds, ...ids];
    return LibBadges(
      libIds: shownIds,
      order: meta?.unitOrder ?? const [],
      names: namesWithTop,
      grayIds: gray,
      grade: grade,
      basicChips: basicChips,
      chipMaxWidth: chipMaxWidth,
    );
  }
}

/// 作者头像：作者总览、排行榜、作者主页共用一套尺寸/解码/占位规则。
class AuthorAvatar extends StatelessWidget {
  // 0.9.288：三个边长收到 `card_metrics`（尺寸表），本类只转发。
  static const double gridSize = kAvatarGridSize;
  static const double rankSize = kAvatarRankSize;
  static const double headerSize = kAvatarHeaderSize;

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
    // owner 2026-11-18：作者主页/作者总览也要吃「作者级头像」兜底——
    // 卡片上能显示的头像，播放页与主页必须一致，不再只依赖调用方传入。
    final authorAv = override.isEmpty && mediaPath.isEmpty
        ? (authorAvatarIndex[name] ?? '')
        : '';
    // 0.9.290：优先级合成与绘制都只有一处（`author_avatar_view`）。
    // 与基础库页作者 tab 共用同一个组件——此前那页自己画一遍，于是不监听
    // `AuthorAvatarStore`（手动头像在那页不生效）而且占位样式也不同。
    final picked = resolveAvatarSource(
      manual: override,
      fallback: mediaPath.isNotEmpty ? mediaPath : authorAv,
      fallbackLib: lib,
    );
    return AuthorAvatarView(
      name: name,
      mediaPath: picked.path,
      lib: picked.lib,
      size: size,
      urlOf: (path, {String? lib}) => cfg.mediaUrl(path, lib: lib),
      headersOf: ([String? lib]) => cfg.headersFor(lib),
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

  /// owner 2026-11-26：作者分布在多个基础库（挂了几个文件夹）时，
  /// 词条按**每个来源**各贴一条，而不是只贴主库那一个。
  final List<String> basicIds;

  /// 已知基础库 id（基础库页/基础库作者页直接给 id 时用）。
  ///
  /// 0.9.317：`fallbackName` 一并删掉——它只被转发给 `UnitBadges` 的一个
  /// 零读取方参数，界面上从来没有「回退显示库名」这条路（无归属一律 SECRET）。
  final String fallbackId;
  final int works;

  /// 显式指定的作者统计（含 `p`/`dr`）；null 表示从 [meta] 取。
  final Map<String, dynamic>? stats;

  /// T5：与基础库卡片同一份「基础库 → 单元库」映射（词条同源）。
  final Map<String, String> unitLabels;
  final Map<String, String> unitKeys;

  /// 单条词条最大宽度（透传给词条行）。固定尺寸的小卡片必须传更小的值。
  final double chipMaxWidth;

  const AuthorBadges({
    super.key,
    required this.meta,
    required this.name,
    required this.mediaPath,
    required this.fallbackId,
    this.basicId = '',
    this.basicIds = const <String>[],
    this.works = 0,
    this.stats,
    this.unitLabels = const {},
    this.unitKeys = const {},
    this.chipMaxWidth = kBadgeChipMaxWidth,
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
      chipMaxWidth: chipMaxWidth,
      basicId: _basicId,
      // 多来源：显式传入优先；否则至少带主库，保持旧行为。
      basicIds: basicIds.isNotEmpty
          ? basicIds
          : (_basicId.isEmpty ? const <String>[] : <String>[_basicId]),
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
                        color: AuthorGrade.colors[i],
                        kind: LibEntryKind.author),
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
  /// owner 2026-11-27：「删除监控页塞到对应单元库的爬虫配置页面下去」。
  ///
  /// 传了单元库就只展示该单元库的记录（服务端 `lib` 是单元库目录名）。
  /// 不传时保持原来的「聚合所有单元库」，供总览入口沿用。
  final String unitRel;
  final String unitName;

  /// 该单元库所属连接的地址与凭据（跨连接场景不能错配）。
  final String base;
  final Map<String, String> headers;

  /// 该单元库的第一个基础库 id；服务端按 `lib` 过滤记录时用它。
  final String libId;

  const DeletedMonitorPage({
    super.key,
    this.unitRel = '',
    this.unitName = '',
    this.base = '',
    this.headers = const {},
    this.libId = '',
  });
  @override
  State<DeletedMonitorPage> createState() => _DeletedMonitorPageState();
}

class _DeletedMonitorPageState extends State<DeletedMonitorPage> {
  DeletedReport report = DeletedReport.empty;
  bool loading = true;
  String? err;

  /// 作用域：空串＝不按单元库过滤。
  String get _scopeName => widget.unitName.trim().isEmpty
      ? _basename(widget.unitRel)
      : widget.unitName.trim();

  static String _basename(String path) {
    final s = path.replaceAll('\\', '/');
    final i = s.lastIndexOf('/');
    return (i >= 0 ? s.substring(i + 1) : s).trim();
  }

  String get _base => widget.base.isEmpty ? cfg.base : widget.base;

  Map<String, String> get _headers =>
      widget.headers.isEmpty ? cfg.headers : widget.headers;

  /// 按记录所属基础库取鉴权头（0.9.312）。
  ///
  /// 从单元库进来时（[widget.headers] 非空）必须**固定用该单元库所属连接**：
  /// 同一台 NAS 上多个服务端各有一套账号，删除记录只属于当前单元库，
  /// 按 `cfg.headersFor(lib)` 走会落到「默认注册库」那条连接上——密码不同
  /// 就是 401，密码相同也只是运气好。只有总览入口（无作用域）才按库路由。
  Map<String, String> _headersFor(String libId) {
    if (widget.headers.isNotEmpty) return widget.headers;
    return cfg.headersFor(libId);
  }

  /// 作用域内要读的元数据库 id：单元库自己的第一个基础库。
  ///
  /// 0.9.312：`LibMeta.load(cfg.lib)` 在多服务端下读的是**默认注册库**那棵树
  /// ——从另一个服务端的单元库进来时，它给不出这台服务端的基础库→单元库映射，
  /// 「当前媒体库」词条于是整排消失（记录明明都带 libId）。
  String get _metaLib =>
      widget.libId.trim().isNotEmpty ? widget.libId.trim() : cfg.lib;

  /// 作者头像索引（`/api/authors.json`）。删除记录的本地媒体通常已被清理，
  /// 服务端下发的记录里就没有 `th`/`cv`；此时按 `deleted_cover.dart` 的规则
  /// 退回作者头像，列表才不会整列「图片不可用」。
  Map<String, dynamic> _authorIdx = const {};

  bool checking = false;

  /// owner 2026-11-27：「删除监测条目分页显示，防止积攒过多页面过长」。
  ///
  /// 每组（每次同步）默认只显示前 N 条，其余折叠为「再显示 N 条」。
  /// 不用 PageView：这些条目是按同步批次分组的，跨组翻页会打断「同一次同步」
  /// 的阅读顺序；折叠更符合这里的结构。
  static const int kDeletedPageSize = 20;
  /// 键是 [DeletedSyncGroup.key]（UTC 分钟键），不是 `label`（展示文本）：
  /// 两个不同批次落在同一分钟、或时区切换导致标签相同，用展示文本会让
  /// 「再显示」按钮展开的是别人那一组。
  final Map<String, int> _shownPerGroup = <String, int>{};

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
    if (_base.isEmpty || _metaLib.isEmpty) return;
    try {
      // 记录带着所属连接的地址与鉴权头（从单元库页进来时一定非空）。
      // 只传库 id 会让 `LibMeta.load` 去查绑定表——那页的绑定表里只有默认
      // 注册库那几条，跨服务端时元数据整棵取自另一台机器。
      final m = await LibMeta.load(_metaLib,
          source: MetaSource.ofBase(_base, _headers));
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
    // 只在**当前作用域内的记录**里统计媒体库：从单元库页进来时，
    // 记录已经只剩该单元库，顶部再出现别的媒体库词条就是坏导航。
    final scope = _scopeName;
    for (final e in report.items) {
      if (scope.isNotEmpty && e.libName.trim() != scope) continue;
      final t = _topOf(e);
      if (t.isEmpty) continue;
      if (!counts.containsKey(t)) order.add(t);
      counts[t] = (counts[t] ?? 0) + 1;
    }
    return [for (final k in order) MapEntry(k, counts[k] ?? 0)];
  }

  String _topLabel(String id) => _meta?.topLabelFor(id) ?? id;

  void _setTopFilter(String t) {
    if (topFilter == t) return;
    setState(() => topFilter = t);
  }

  /// 当前筛选下要显示的记录。
  ///
  /// 两级：① 从单元库页进来时只看该单元库（服务端 `lib` 是单元库目录名）；
  /// ② 再从顶部媒体库词条里收敛。第二级在单单元库作用域下通常没有选项。
  List<DeletedEntry> get _visibleItems {
    final scope = _scopeName;
    return [
      for (final e in report.items)
        if ((scope.isEmpty || e.libName.trim() == scope) &&
            (topFilter.isEmpty || _topOf(e) == topFilter))
          e
    ];
  }

  /// 拉一次作者索引供预览图兜底；失败不影响列表（只是回落到占位图标）。
  Future<void> _loadAuthorIdx() async {
    if (_base.isEmpty) return;
    try {
      final r = await http
          .get(Uri.parse(joinApiUrl(_base, '/api/authors.json')),
              headers: _headers)
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
          .post(Uri.parse(joinApiUrl(_base, '/api/deleted/check')),
              headers: _headers)
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
          .showSnackBar(SnackBar(content: Text('检测启动失败：${errorText(e)}')));
    } finally {
      if (mounted) setState(() => checking = false);
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
    });
    // 读取链路：带库参数的正式地址 → 不带库参数 → 该连接上的首个库。
    // 旧记录为空时先确认是「服务端确实没有」还是「请求落到了别的库」，
    // 不再把空列表直接当成「暂无删除记录」。
    final attempts = <Uri>[];
    void addAttempt(Uri u) {
      if (!attempts.any((e) => e.toString() == u.toString())) attempts.add(u);
    }

    if (_base.isNotEmpty) {
      if (widget.libId.isNotEmpty) {
        addAttempt(Uri.parse(joinApiUrl(_base, '/api/deleted.json',
            query: {'lib': widget.libId})));
      }
      addAttempt(Uri.parse(joinApiUrl(_base, '/api/deleted.json')));
      // 第三条「该连接上的首个库」只在它**确实属于这台服务器**时才试。
      //
      // 旧写法无条件加一条 `?lib=${cfg.lib}`：`cfg.lib` 是默认注册库，可能
      // 属于另一台服务器，拿它去问这一台只会 404/空列表——而空列表会与
      // 「服务端真的没有记录」写得一模一样，排查时看不出是请求本身发错了。
      // 地址比对走 `sameBase`（协议/主机大小写/尾斜杠都归一）。
      if (cfg.lib.isNotEmpty &&
          cfg.lib != widget.libId &&
          sameBase(cfg.baseFor(cfg.lib), _base)) {
        addAttempt(Uri.parse(joinApiUrl(_base, '/api/deleted.json',
            query: {'lib': cfg.lib})));
      }
    }
    DeletedReport best = DeletedReport.empty;
    Object? lastErr;
    var anyOk = false;
    for (final uri in attempts) {
      try {
        final r = await http
            .get(uri, headers: _headers)
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
    final lib = libFromMediaPath(path, fallbackLib: cfg.lib);
    // 0.9.292：边长与解码宽度同源（原先 56 写三遍 + `memCacheWidth: 160` 内联）。
    final ql = squareThumbDecodeWidth(
        kDeletedThumbSize, MediaQuery.devicePixelRatioOf(context));
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        cacheManager: DiziCache.manager,
        imageUrl: cfg.mediaUrl(path, lib: lib),
        httpHeaders: cfg.headersFor(lib),
        width: kDeletedThumbSize,
        height: kDeletedThumbSize,
        fit: BoxFit.cover,
        memCacheWidth: ql,
        fadeInDuration: Duration.zero,
        errorWidget: (_, __, ___) => Container(
          width: kDeletedThumbSize,
          height: kDeletedThumbSize,
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
    // 0.9.312：地址必须走该记录所属连接。此前用全局 `cfg.base`——从另一个
    // 服务端的单元库进来时，请求打到了默认注册库那台机器上，作品明明在本地
    // 也只会得到 404，界面照样提示「未同步到本地」。
    final uri = deletedWorkUri(_base, e);
    if (uri == null) {
      _toast(kDeletedNotLocalMessage);
      return;
    }
    final lib = e.libId.trim().isEmpty ? cfg.lib : e.libId.trim();
    try {
      final r = await http
          .get(uri, headers: _headersFor(lib))
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
            list.add(withWorkLib(w, lib));
          }
        }
      }
      if (list.isEmpty) {
        list.add(withWorkLib(work, lib));
      }
      var start = intOf(m['index']);
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
      if (mounted) _toast('打开作品失败：${errorText(err)}');
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
          .post(syncRetryUri(_base),
              headers: {
                ..._headersFor(e.libId.trim()),
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
      _toast('重试失败：${errorText(err)}');
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
          for (final e in g.items.take(
              _shownPerGroup[g.key] ?? kDeletedPageSize)) ...[
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
          // owner 2026-11-27：一组超过一页时给「再显示 N 条」，避免页面无限长。
          if (g.items.length > (_shownPerGroup[g.key] ?? kDeletedPageSize))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TextButton.icon(
                key: ValueKey('deleted-more-${g.key}'),
                onPressed: () => setState(() {
                  final cur = _shownPerGroup[g.key] ?? kDeletedPageSize;
                  _shownPerGroup[g.key] = cur + kDeletedPageSize;
                }),
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(
                    '再显示 ${g.items.length - (_shownPerGroup[g.key] ?? kDeletedPageSize)} 条'
                    '（已显示 ${_shownPerGroup[g.key] ?? kDeletedPageSize}/${g.items.length}）'),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // 计数与页头摘要都按**当前作用域**算：从单元库页进来时不该显示全库总数，
    // 否则「共 320 条」下面只列 12 条，看着像丢记录。
    final scopeItems = _visibleItems;
    final stats = DeletedStats.of(scopeItems);
    return Scaffold(
      appBar: AppBar(
          // 从单元库进来看得出作用域，不然和总览页长得一样。
          title: Text(widget.unitRel.isEmpty
              ? '删除监测'
              : '删除监测 · ${_scopeName}'),
          actions: [
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
                            '共 ${scopeItems.length} 条'
                            '${report.items.length == report.total ? '' : '（服务端共 ${report.total}）'}'
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
                              label: Text('全部媒体库 ${scopeItems.length}',
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
                  if (scopeItems.isEmpty)
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
                                // 单单元库作用域下「服务端记录总数 > 0」是常态
                                // （别的库有记录），不能据此说「未解析到条目」。
                                widget.unitRel.isNotEmpty
                                    ? '该单元库暂无删除记录'
                                    : (report.total > 0
                                        ? '服务端记录总数 ${report.total}，但未解析到条目'
                                        : '暂无删除记录'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey)),
                            const SizedBox(height: 6),
                            Text(
                                (widget.unitRel.isEmpty && report.total > 0)
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
        // owner 2026-11-25：「重新打开后也同步重新显示」。
        // 只落盘不够：已经渲染好的卡片/词条不会自己重算。递增唯一变更信号，
        // 让订阅它的卡片（作者卡/基础库卡/播放页词条）立即按新设置重绘。
        LibraryBadge.revision.value++;
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
///
/// 数字与字符串**必须同一条解析**：旧实现分两支——`num` 走 `round()`、
/// 字符串走「剔除非数字字符再 `int.tryParse`」。于是同一个 `1.5`：
/// 传数字得 **2**，传字符串 `"1.5"` 却得 **15**（小数点被剔掉，1.5 变成 15）
/// ——推荐页一批拉了十倍的作品，而设置里看着还是 1.5 那个意思。
/// `"20条"` 与 `"２０"`（全角）也同样需要归一。
///
/// 现在先走 [numOrNull]（带全角折叠），解析不了再退到「剔除非数字」。
int parseRecommendCount(dynamic raw) {
  if (raw == null) return kRecommendDefaultCount;
  int clampCount(num v) => v.round().clamp(0, kRecommendMaxCount);
  if (raw is num) {
    if (raw is double && !raw.isFinite) return kRecommendDefaultCount;
    return clampCount(raw);
  }
  final s = foldFullWidthAscii('$raw').trim();
  if (s.isEmpty) return kRecommendDefaultCount;
  // 千分位先去掉：`1,000` 不能变成 1（用户输入 1000，期望是上限 500）。
  final t = s.replaceAll(RegExp(r'[,，]'), '');
  // 第一种：整个串就是一个数（含小数）——与 num 分支完全同一结果。
  final n = numOrNull(t);
  if (n != null) return clampCount(n);
  // 第二种：带单位/其它字符（`20条`、`1.5 倍`）。取**串里第一个数字片段**
  // 再交给同一条 clamp。不能写「剔除非数字字符」：那样 `1.5 倍` 会变成
  // 15（小数点被剔掉），而 `1.5` 是 2——同一串小数两种结果。
  final m = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(t);
  if (m == null) return kRecommendDefaultCount;
  final v = numOrNull(m.group(0));
  if (v == null) return kRecommendDefaultCount;
  return clampCount(v);
}

/// 实际请求数量：0（用户设为「默认」）或空时用 40。
int recommendRequestCount(int raw) =>
    raw <= 0 ? kRecommendDefaultCount : raw.clamp(1, kRecommendMaxCount);

/// 推荐作品去重键：库 + 作品 id（无库时只用 id）。
String recommendWorkKey(dynamic w) {
  if (w is! Map) return '';
  final id = '${w['id'] ?? ''}';
  if (id.isEmpty) return '';
  final lib = workLibTag(w);
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
          title: const Text('爬虫设置'),
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
          subtitle: const Text('按媒体库分类 · 向下继承 · 逐级分发'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LibraryBadgeColorsPage())),
        ),
        ListTile(
          leading: const Icon(Icons.workspaces_outline),
          title: const Text('库角标'),
          subtitle: const Text('媒体库 / 单元库 / 基础库的图案与颜色 · 立即生效'),
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
          // 只重置播放参数：按键绑定属于另一个页面，不能被这一页的按钮带走
          // （此前调 `resetDefaults()`，用户改过的 Ctrl+J… 全部静默丢失）。
          onPressed: () {
            setState(() => AppSettings.resetPlayback());
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
          // 只重置按键：播放倍速/预载属于另一个页面，不能被这一页的按钮带走。
          onPressed: () {
            setState(() => AppSettings.resetKeys());
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
    LibBadgeKind.top: '媒体库',
    LibBadgeKind.unit: '单元库',
    LibBadgeKind.basic: '基础库',
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
                  // owner 2026-11-25：候选格必须预览**自己那个图案**。
                  // 原来这里没传 pattern，八格全都画当前选中图案，
                  // 看上去「图标都是一样的」。
                  LibCornerBadge(kind: kind, pattern: i),
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
      final r = await http
          .get(cfg.u('/api/settings'), headers: cfg.headers)
          .timeout(const Duration(seconds: 10));
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
      defaultIdx = j['default'] == null ? null : intOf(j['default']);
      accountCount = j['accountCount'] == null
          ? list.where((c) => c.account).length
          : intOf(j['accountCount'], list.where((c) => c.account).length);
      err = null;
      if (setLoading) loading = false;
    });
  }

  Future<Map<String, dynamic>> _send(
      String path, Map<String, dynamic> body) async {
    final r = await http
        .post(cfg.u(path),
            headers: {...cfg.headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
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
      _toast('重命名失败：${errorText(e)}');
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
      _toast('删除失败：${errorText(e)}');
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

  /// 每条连接各自的**默认库** id（`/api/libraries` 的 `default`）。
  ///
  /// 此前只有一个全局 `defaultId`：两台服务器各有一个默认库时，后读到的
  /// 那台会顶掉前一台，第一台的默认库在「已注册媒体库」里永远不标星；
  /// 而两台恰好同 id 时又都标星——两种错法都源于「默认」是**每条连接**
  /// 的属性，不是进程级的。键是连接 id，不是地址（地址可能被改）。
  final Map<String, String> defaultIdByServer = <String, String>{};

  /// 某条连接的默认库 id（没有就返回空串，不猜）。
  String defaultIdOf(String serverId) =>
      defaultIdByServer[serverId.trim()] ?? '';
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

  /// 封面菜单（历史 / 回滚 / 恢复自动 / 清除）共用的 HTTP 客户端。
  /// 与周边五个项目页同一口径：页面内复用、`dispose` 时关闭。
  final http.Client _coverClient = http.Client();

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
    _coverClient.close();
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
    // 「基础库的 `_cover/` 在库根」这条语义只在 `lib_cover.resolveBasicCover`
    // 里（`rel` 固定空串，与单元库的 `<rel>/_cover/` 区分开）。
    final hit = resolveBasicCover(
      version: b.coverVersion,
      ext: b.coverExt,
      bestThumb: top?.thumb ?? '',
      crawlerThumb: b.crawlerCover,
      // G：没手动封面、没播放数据时用服务端下发的第一张作品封面。
      firstThumb: b.firstCover,
    );
    if (hit.path.isEmpty) {
      // 诊断：区分「服务端没下发 cv」和「下发了但拼接失败」。
      CrashLog.instance.record(
        '封面缺失 ${b.id} cv=${b.crawlerCover.trim().isEmpty ? '(空)' : '(有)'} rel=${b.rel}',
        kind: 'cover',
      );
      return '';
    }
    return cfg.mediaUrl(hit.path, lib: b.id);
  }

  /// 0.9.9 自动生成规则：单元库取整棵子树里本机播放量最高的基础库。
  /// 判定只有 `unit_library_view.topPlayedBasicOf` 一处（与单元库页卡片同一个
  /// 答案）：此前本函数用「整库次数之和」、卡片那边用「单条作品最大次数」，
  /// 同一个单元库在两个页面会给出不同的「最高播放基础库」。
  BasicLib? _topPlayedBasic(UnitLibrary u) => topPlayedBasicOf(u);

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
        // 索引已重建：类型筛选的 kinds 缓存与库元数据缓存必须一起作废，
        // 否则新作品在「按类型筛选」／单元库树里要等到重启 App 才出现。
        clearAuthorTypeCache(id);
        LibMeta.invalidate(id);
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
      // 每台服务器各取一次注册表与 v2 索引。此前是串行的 `for` + `await`：
      // N 台服务器就是 N 次完整往返，每条各 10s 上限——连接多时首页首屏
      // 一直白等到最慢的那台返回，而这几份数据彼此完全独立（与 0.9.327
      // 修掉的 `/api/nodes` 是同一处遗漏）。改为有界并发（4 路，与爬虫
      // 设置页、搜索页同一口径）。
      //
      // `mapConcurrent` 保序：结果与 `use` 一一对应，因此下面挑 `default`
      // 仍按 `use` 的顺序「第一个非空」，与串行版的先到先得等价。
      final fetched = await mapConcurrent<ServerConn, ({
        ServerLibraries snap,
        String def,
      })>(use, 4, (s) async {
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
              list = librariesWithDisplayNames(mapsOf(j['libraries']));
              def = '${j['default'] ?? ''}';
            }
          }
          Map<String, dynamic>? treeJson;
          if (rs[1].statusCode == 200) {
            final j = jsonOf(rs[1]);
            if (j is Map) treeJson = Map<String, dynamic>.from(j);
          }
          return (
            snap: ServerLibraries(server: s, libraries: list, tree: treeJson),
            def: def,
          );
        } catch (e) {
          return (
            snap: ServerLibraries(server: s, error: errorText(e)),
            def: '',
          );
        }
      });
      // 每台服务器的默认库各记一份（键是它自己的连接 id）。并发回填时
      // 直接按结果写表即可：键不同，不存在互相覆盖。
      //
      // 先清空再写：断连/删除的连接不该把「它那台的默认库」留在表里——
      // 否则重新添加一台同 id 的连接时，会拿旧默认库去标星。
      defaultIdByServer.clear();
      for (final r in fetched) {
        if (r.def.isEmpty) continue;
        final sid = r.snap.server.id.trim();
        if (sid.isEmpty) continue;
        defaultIdByServer[sid] = r.def;
      }
      final snaps = [for (final r in fetched) r.snap];

      final merged = mergeRegisteredLibraries(snaps);
      final treeJson = mergeLibraryTrees(snaps);
      // 记录库 → 连接，之后播放/统计/媒体都按所属 IP 路由。
      final bindings = buildBindings(servers: use, libraries: merged);
      final byBase = {for (final s in use) s.base: s};
      if (treeJson != null) {
        for (final raw in listOf(treeJson['basicLibraries'])) {
          if (raw is! Map) continue;
          final id = '${raw['id'] ?? ''}'.trim();
          final s = byBase[serverOriginOf(raw).base];
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
            warn = '刷新失败：${errorText(e)}（显示的是上次结果）';
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
      // 每台服务器自己的库根名：媒体库卡片的名字必须来自它那台机器，
      // 不能让全局 `TopNodeName` 被最后一台覆盖（见 `LibMeta.topName`）。
      final rootNames = <String, String>{};
      // 0.9.328：逐台读取此前同样是串行 `for` + `await`（每条 8s 上限）。
      // 与 `load()` 的注册表读取、0.9.327 的 `/api/nodes` 是同一处遗漏：
      // 这几份 `libraries.json` 彼此独立，串行时首屏白等 N×8s。
      // 结果按 `servers` 保序，因此下面「全局根名只由首条连接写」的判断
      // （`identical(s, servers.first)`）语义不变。
      final fetched = await mapConcurrent<ServerConn, ({
        ServerConn server,
        Map<String, dynamic>? tree,
      })>(servers, 4, (s) async {
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
          if (r.statusCode != 200) return (server: s, tree: null);
          final j = jsonOf(r);
          if (j is! Map) return (server: s, tree: null);
          return (server: s, tree: Map<String, dynamic>.from(j));
        } catch (_) {
          return (server: s, tree: null);
        }
      });
      final snaps = <ServerLibraries>[];
      for (final r in fetched) {
        final s = r.server;
        final j = r.tree;
        if (j == null) continue;
        // owner 2026-11-22：顶级节点名＝媒体库根目录名。先到先用，
        // 多个连接时以首条连接（servers.first，与文件结构页一致）为准。
        //
        // 0.9.324：按连接各记一份（`rootNames`），卡片取名用它；全局值
        // 仍只由首条连接写，供没有 meta 的旧页面（文件结构页）使用。
        final rn = TopNodeName.nameFromRoot('${j['root'] ?? ''}');
        if (rn.isNotEmpty) rootNames[s.id] = rn;
        if (identical(s, servers.first)) {
          TopNodeName.setFromRoot('${j['root'] ?? ''}');
        }
        snaps.add(ServerLibraries(
            server: s, libraries: const [], tree: j));
      }

      final merged = mergeLibraryTrees(snaps);
      if (merged == null) {
        if (mounted) setState(() => tree = null);
        return;
      }
      final t = LibraryTree.parse(merged);
      // 节点文件夹由 owner 在「文件结构」里指定；默认为空 = 只有顶级 SECRET。
      //
      // 0.9.326：**每条连接各取一次** `/api/nodes`，并把节点归给**它自己**那条
      // 连接。旧实现只读 `servers.first`，再用这台的 `serverId/base/label` 覆盖
      // 全部节点：
      //   · 第二台服务端的节点文件夹整批不上屏（那台的层级塌成「一层目录当卡片」）；
      //   · 第一台恰好有同名 rel 时，第二台的基础库被挂到第一台的节点上，
      //     封面与鉴权按第一台去请求 —— 必然 404，而界面看着「有卡片、没图」。
      final nodesPerServer = await _fetchNodesPerServer();
      // 封面指针有两个来源，取并集：`/api/libraries.json` 的整棵树（全部层级
      // 都有，实测 6/6）优先，`/api/nodes` 的 covers 兜底（只覆盖被标记为节点
      // 的 rel，实测 31 条里仅 4 条带封面）。此前只认后者，第 3 层那 2 条单元库
      // 的指针永远到不了卡片——当场靠本地覆盖撑着，页面一重建就回落。
      //
      // owner 2026-11-26：表键带连接（`unitCoverKey`）。rel 相对各自库根，
      // 两台服务端同名目录的 rel 一模一样；只按 rel 查会让 B 的卡片拿到 A 的
      // 指针，去 A 的机器上取 B 的文件。下面**不再**按 rel 重新拆一遍键——
      // 拆开时只能丢了连接字段，等于把这个 bug 再写回去一次。
      final treeCovers = <String, String>{};
      final rawTreeCovers = merged['unitCovers'];
      if (rawTreeCovers is Map) {
        for (final e in rawTreeCovers.entries) {
          final k = '${e.key}';
          final v = '${e.value ?? ''}'.trim();
          if (k.isEmpty || v.isEmpty) continue;
          treeCovers[k] = v;
        }
      }

      /// 一条连接的节点：`/api/nodes` 标记 ∪ 该连接自己带封面指针的 rel。
      ///
      /// 补封面那部分不能省：树里有指针但没被标记的 rel 没有节点承载，
      /// 卡片就拿不到那张封面。反向解析走 `node_key`（唯一实现）。
      ///
      /// 0.9.327：rel 去重与封面优先级都收到 `unitCoverTable`（与
      /// `LibMeta.load` 同一条链）——此前两处各排一遍，结果同一张卡在两个
      /// 入口显示的封面不一样：首页认 `libraries.json` 的整树指针，从设置页
      /// 进单元库页只认 `/api/nodes` 的 `covers`（那里只有节点才带）。
      List<LibNode> nodesOfServer(ServerConn s) {
        final payload = nodesPerServer[s.id] ?? NodesPayload.empty;
        final rels = <String>{
          ...payload.rels,
          for (final k in treeCovers.keys)
            if (nodeKeyHasServer(k, s.id)) nodeKeyRel(k),
        }.toList(growable: false)
          ..sort();
        final covers = unitCoverTable(
          serverId: s.id,
          rels: rels,
          treeCovers: treeCovers,
          nodesCovers: payload.covers,
        );
        return [
          for (final rel in rels)
            LibNode(
              id: 'node:$rel',
              rel: rel,
              name: splitRel(rel).isEmpty ? rel : splitRel(rel).last,
              // owner 2026-11-24：必须带上服务端下发的封面指针，
              // 否则选完过往封面返回界面就回落到自动封面。
              coverUrl: covers[normalizeUnitRel(rel)] ?? '',
              // serverId 必须是连接 id（buildUnitTree 按它归组与归属），
              // 不能写成 cardLabel——那会让分层再次错位。
              serverId: s.id,
              serverBase: s.base,
              serverLabel: s.cardLabel,
            ),
        ];
      }

      final nodes = [for (final s in servers) ...nodesOfServer(s)];
      final units = buildUnitTree(
        nodes: nodes,
        basics: t?.allBasics ?? const <BasicLib>[],
        topName: TopNodeName.current,
        topNameOf: (sid) => rootNames[sid] ?? '',
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
    // 封面菜单的四条请求共用本页的客户端（页面销毁时关闭）：此前每条各建
    // 一个 `http.Client()` 再由函数自己 close，一次「看历史 → 回滚」就白开
    // 三次连接池，且与其余项目页的写法不一致。
    final client = _coverClient;
    Uri versionsUri() {
      final base = cfg.u('/api/cover/versions', lib: libId);
      if (unitRel.isEmpty) return base;
      // 追加参数走 `api_url.withQueryParam`：分隔符判定与编码都只在那一条链上
      // （旧写法在这里自己写了 `contains('?') ? '&' : '?'`，是第二份）。
      return Uri.parse(
          withQueryParam(base.toString(), 'unitRel', unitRel));
    }

    final restoreUri = cfg.u('/api/cover/restore', lib: libId);
    final clearUri = cfg.u('/api/cover/clear', lib: libId);
    return CoverMenuActions(
      libId: libId,
      unitRel: unitRel,
      headers: headers,
      urlOf: (p) => cfg.mediaUrl(p, lib: libId),
      pickLocal: () => uploadCoverFromPicker(libId: libId, unitRel: unitRel),
      listVersions: () => fetchCoverVersions(
          url: versionsUri(), headers: headers, client: client),
      restore: (v) => restoreCoverVersion(
        url: restoreUri,
        headers: headers,
        libId: libId,
        unitRel: unitRel,
        version: v.version,
        ext: v.ext,
        client: client,
      ),
      restoreAuto: () => clearCustomCover(
        url: clearUri,
        headers: headers,
        libId: libId,
        unitRel: unitRel,
        hard: false,
        client: client,
      ),
      clearAll: () => clearCustomCover(
        url: clearUri,
        headers: headers,
        libId: libId,
        unitRel: unitRel,
        hard: true,
        client: client,
      ),
      onChanged: () => coverRevision.value++,
    );
  }

  /// G：单元库子树里第一个非空的 `fc`（第一张作品封面）。
  /// 「第一个非空」只有 `UnitLibrary.firstWorkCover` 一处实现。
  ({String lib, String path})? _firstFcOfUnit(UnitLibrary u) => u.firstWorkCover;

  /// P3：顶级单元库卡片的连接状态。只按节点自带的连接标识查当前连接表，
  /// 不看任何目录名文本；查不到就不显示（不猜）。
  ///
  /// 返回三态布尔而不是文案：卡片只画一个绿/红圆点，中间不再有
  /// 「字符串 → 再比回布尔」这一层往返。
  bool? _topNodeStatus(UnitLibrary u) {
    final id = u.node.serverId.trim();
    if (id.isEmpty) return null;
    for (final s in shownServers) {
      if (s.id != id) continue;
      return s.enabled;
    }
    return null;
  }

  /// P3：首页顶级单元库卡片专用封面——**只认 owner 设过的封面**。
  ///
  /// 顺序：服务端 `cover.u`（owner 手动指定）> 自定义 `_cover/<version>`。
  /// 两者都没有就返回空串，卡片用词条色块占位；不取爬虫封面/作品图，
  /// 避免首页把某个作者的封面当成媒体库封面。
  String _topNodeCoverUrl(UnitLibrary u) {
    // 手动指针的解析（trim / 取库段 / 路由）只有 `lib_cover.manualCoverUrl`
    // 一处（单元库卡片与单元库页也走它）。
    final manual = manualCoverUrl(u.node.coverUrl,
        build: (path, libId) => cfg.mediaUrl(path, lib: libId));
    if (manual.isNotEmpty) return manual;
    // 第二级（自定义 `_cover/`）也走同一个入口：单元库的 `_cover/` 在节点目录
    // 下（`resolveUnitCover` 包住 rel 的语义），避免这段顺序成为第三份手写链。
    final hit = resolveUnitCover(
      unitRel: u.rel,
      version: u.node.coverVersion,
      ext: u.node.coverExt,
    );
    if (hit.path.isEmpty) return '';
    return cfg.mediaUrl(hit.path, lib: u.coverLib?.id);
  }

  /// L5-C：单元库封面。
  /// 0.9.35：owner 手动设置的单元库封面（服务端 `unit-covers.json` → `cover.u`）
  /// 优先 > 手动 `_cover/` > 子树最高播放基础库的封面 > 第一个有封面的基础库。
  String _unitCoverUrl(UnitLibrary u) {
    final manual = manualCoverUrl(u.node.coverUrl,
        build: (path, libId) => cfg.mediaUrl(path, lib: libId));
    if (manual.isNotEmpty) return manual;
    // owner 2026-11-21：单元库以前只传 firstThumb（服务端 `fc`，常指向视频），
    // 从没把「爬虫封面 cv」传进来 —— 而 cv 才是真正有图片的那条链路。
    // 这就是单元库卡片长期灰着的原因。
    // 爬虫封面：整棵子树里第一个非空 `cv`，扫描本体在 `UnitLibrary.firstCrawlerCover`
    // （`unit_library_view.unitCoverUrl` 走同一个属性）。
    final top = _topPlayedBasic(u);
    // 单元库的 `_cover/` 在节点目录下（`resolveUnitCover` 包住 rel 语义）；
    // 旧写法自己传 `rel: u.rel` 并在注释里解释“哪个入口用 rel”，
    // 与 `basicCoverUrl` 的 `rel: ''` 只靠注释区分。
    final hit = resolveUnitCover(
      unitRel: u.rel,
      version: u.node.coverVersion,
      ext: u.node.coverExt,
      crawlerThumb: u.firstCrawlerCover,
      firstThumb: _firstFcOfUnit(u)?.path ?? '',
    );
    if (hit.path.isNotEmpty) {
      // 子树第一张作品封面按所属基础库路由；自定义 `_cover/` 保持原解析。
      final custom = hit.source == CoverSource.custom;
      final fc = _firstFcOfUnit(u);
      return custom
          ? cfg.mediaUrl(hit.path)
          : cfg.mediaUrl(hit.path,
              lib: fc != null && hit.path == fc.path ? fc.lib : null);
    }
    // 自动生成：整棵子树里本机播放量最高的基础库，走该基础库完整封面链
    // （手动 > 爬虫 > 自动），并按基础库所属连接解析媒体地址。
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

  /// 每条连接各读一次 `/api/nodes`（连接 id → 解析结果）。
  Future<Map<String, NodesPayload>> _fetchNodesPerServer() async {
    if (servers.isEmpty) return <String, NodesPayload>{};
    // 0.9.327：连接之间**有界并发**（4 路，与爬虫设置页同一口径）。
    // 串行时 N 台服务器就是 N 次完整往返，每条各 8s 上限——三台以上时首页
    // 首屏在「节点还没读完」这件事上白等十几秒，而这几份数据彼此独立。
    // 单条失败仍然只是「那台缺席」：不进表、不造假条目。
    final payloads = await mapConcurrent<ServerConn, NodesPayload?>(
        servers, 4, (s) async {
      final h = {
        'Authorization': _authFor(s),
      };
      try {
        final r = await http
            .get(Uri.parse('${s.base}/api/nodes'), headers: h)
            .timeout(const Duration(seconds: 8));
        if (r.statusCode != 200) return null;
        return parseNodesPayload(jsonOf(r));
      } catch (_) {
        return null;
      }
    });
    final out = <String, NodesPayload>{};
    for (var i = 0; i < servers.length; i++) {
      final p = payloads[i];
      if (p != null) out[servers[i].id] = p;
    }
    return out;
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

  /// 「文件结构」：列出库下全部文件夹，勾选哪些是节点文件夹（单元库）。
  ///
  /// 0.9.327：把**全部在线连接**交给页面。此前只传 `servers.first`，多连接
  /// 时第二台服务器在「文件结构」里根本选不到，那台的节点文件夹永远设不了
  /// （首页却照常画出它的卡片）。页面内可按服务器切换，保存写回当前那台。
  Future<void> _openFolders() async {
    if (servers.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FolderStructurePage(
        sources: [
          for (final s in servers)
            FolderSource(
              id: s.id,
              label: s.cardLabel,
              base: s.base,
              headersOf: () => {'Authorization': _authFor(s)},
            ),
        ],
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

  /// A1：打开作者文件夹挂载面板（合并/拆分/编辑组成员）。
  ///
  /// 面板里**不再有**「新建作者目录」：建作者属于作者页（owner 2026-11-27），
  /// 挂载解决的是「已有文件夹怎么归类」。
  ///
  /// 地址与鉴权都取该单元库**所属连接**（[_unitConn]），与爬虫配置、删除监测
  /// 同一份判定——避免在一个页面里出现「用的不是同一个连接」。
  void _openUnitAuthorMount(UnitLibrary u) {
    if (u.rel.trim().isEmpty) return;
    final c = _unitConn(u);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => UnitAuthorMountPage(
        unit: u,
        base: c.base,
        headers: c.headers,
      ),
    ));
  }

  /// 单元库 → 「发请求用的连接」：地址 / 鉴权头 / 库 id（**唯一出口**）。
  ///
  /// 此前 `_openUnitAuthorMount` 与 `_openUnitCrawler` 各写一遍同一段：
  /// 先取 `basics.first.id` 的 base/headers，再遍历 `servers` 按**地址字符串**
  /// 匹配连接。两处都有两个问题：
  ///  1. 地址字符串比对不归一——连接表里的 base 已被 `normalizeBase`（补协议、
  ///     去尾斜杠、全角折叠），节点字段却可能带 `/` 或大写协议，永远比不中；
  ///     比不中就拿绑定表的账号去敲该单元库的服务器（401 / 串库）；
  ///  2. `lib=` 参数在两处各算一次，改一处就与 base 不同源。
  /// 现在只此一处：按连接 id 找（记录自带），找不到再按归一化地址回落。
  ({String base, Map<String, String> headers, String libId}) _unitConn(
      UnitLibrary u) {
    final firstBasic = u.basics.isNotEmpty ? u.basics.first.id : null;
    final s = serverOfOrigin(
      servers,
      ServerOrigin(
        id: u.node.serverId.trim(),
        base: u.node.serverBase.trim(),
        label: u.node.serverLabel.trim(),
      ),
      fallbackBase: cfg.baseFor(firstBasic),
    );
    final base = u.node.serverBase.trim().isNotEmpty
        ? u.node.serverBase.trim()
        : (s != null && s.base.isNotEmpty ? s.base : cfg.baseFor(firstBasic));
    final headers = s != null
        ? <String, String>{'Authorization': _authFor(s)}
        : cfg.headersFor(firstBasic);
    // 没有基础库时**不猜库 id**：`cfg.lib` 是默认注册库，可能属于另一台
    // 服务器，把它当本页的 `lib=` 只会让服务端查一个不存在的库（空结果与
    // 「真的没有记录」不可区分）。空串表示「该服务端自己决定」（不带 `lib`）。
    final libId = firstBasic ??
        (cfg.lib.isNotEmpty && sameBase(cfg.baseFor(cfg.lib), base)
            ? cfg.lib
            : '');
    return (base: base, headers: headers, libId: libId);
  }

  /// L5-D：打开单元库级爬虫配置（顶级 SECRET 不提供）。
  void _openUnitCrawler(UnitLibrary u) {
    if (u.rel.trim().isEmpty) return;
    final c = _unitConn(u);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => UnitCrawlerPage(
        unit: u,
        base: c.base,
        headers: c.headers,
        libId: c.libId,
        onOpenDeletedMonitor: () => Navigator.of(ctx).push(MaterialPageRoute(
            builder: (_) => DeletedMonitorPage(
                  unitRel: u.rel,
                  unitName: u.name,
                  base: c.base,
                  headers: c.headers,
                  libId: c.libId,
                ))),
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
    // owner 2026-11-27：作者卡要能看到「属于哪个媒体库」。本页只收一个基础库，
    // 父级（媒体库根）只有这里有单元库树才能算；拿不到就不传（不编造）。
    final media = root == null ? null : mediaRootForBasic(root, b.id);
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
        sourceUnitId: unit?.id ?? '',
        sourceColor: unit == null
            ? LibraryBadge.gray
            : LibraryBadge.colorForUnit(unit.id,
                order: UnitBadgeRegistry.orderOr(unitOrder)),
        sourceMediaLabel: media?.name ?? '',
        sourceMediaId: media?.id ?? '',
        // 与作者卡/首页同一条配色链（同一个 `order`），否则同一个媒体库
        // 在两页是两个颜色。
        sourceMediaColor: media == null
            ? LibraryBadge.gray
            : LibraryBadge.colorForUnit(media.id,
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
    cfg.libName = libraryDisplayName('${l['id']}', '${l['name'] ?? ''}');
    final origin = serverOriginOf(l);
    // 账号/密码：**没写这个键**才回落到当前连接（旧格式/离线快照）；
    // 写了但为空串是有意的（该连接本来不需鉴权），不能当「缺失」处理。
    if (origin.base.isNotEmpty) {
      cfg.bindLibrary(cfg.lib, origin.base,
          user: origin.hasUser ? origin.user : cfg.user,
          pass: origin.hasPass ? origin.pass : cfg.pass,
          server: origin.id,
          label: origin.label);
    }
    await savePrefString('lib', cfg.lib);
    await savePrefString('lib_bindings_v1', encodeBindings(cfg._bindings));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _setDefault(Map<String, dynamic> l) async {
    try {
      final id = '${l['id']}';
      final sb = serverOriginOf(l).base;
      final r = await http
          .post(_u('/api/libraries/default', id, sb),
              headers: {
                ...cfg.headersFor(id),
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'id': l['id']}))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已将「${l['name']}」设为默认媒体库')));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('设置失败：${errorText(e)}')));
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
      final sb = serverOriginOf(l).base;
      final r = await http
          .post(_u('/api/libraries/delete', id, sb),
              headers: {
                ...cfg.headersFor(id),
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'id': l['id']}))
          .timeout(const Duration(seconds: 15));
      final j = jsonOf(r);
      throwIfApiFailed(r.statusCode, j);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已移除库注册（数据保留）')));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：${errorText(e)}')));
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
      // 「往哪台服务器注册新库」= 当前激活的连接。地址与账号必须同源：
      // 此前地址取激活连接、鉴权头却写 `cfg.headers`（**当前库**那条连接的
      // 账号）——激活的连接不是当前库所属那台时，就是拿 A 的密码敲 B 的门，
      // 界面只写「添加失败」。同理不再附带 `lib=<默认库>` 查询参数：注册库是
      // 服务器级操作，不属于任何一个库。
      final at = await () async {
        final sp = await SharedPreferences.getInstance();
        final active = sp.getString('active_server_v1') ?? '';
        for (final s in servers) {
          if (s.id == active) return s;
        }
        return servers.isEmpty ? null : servers.first;
      }();
      final atBase = at?.base ?? cfg.base;
      final atHeaders = at == null
          ? cfg.headers
          : <String, String>{
              'Authorization': basicAuthHeader(at.user, at.pass),
            };
      final r = await http
          .post(_u('/api/libraries', '', atBase),
              headers: {...atHeaders, 'Content-Type': 'application/json'},
              body: jsonEncode({
                'id': lid,
                'name': name.text.trim(),
                'desc': desc.text.trim(),
                'base': base.text.trim(),
                'dir': dir.text.trim(),
              }))
          .timeout(const Duration(seconds: 15));
      final j = jsonOf(r);
      throwIfApiFailed(r.statusCode, j);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('媒体库已添加')));
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('添加失败：${errorText(e)}')));
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
    // 「默认」按这条记录**自己的连接**查：两台服务器可以各有各的默认库。
    final isDef = id.isNotEmpty && id == defaultIdOf(serverOriginOf(l).id);
    final cr = mapOrNull(l['crawler']) ?? const <String, dynamic>{};
    final scripts = listOf(l['crawlerScripts']);
    return ListTile(
      // owner 2026-11-27：「各个地方都要适应多媒体库管理」。
      // 这个圆点原本标的是 `cfg.lib`（单库时代的「当前库」），但主页现在
      // 多库并列、没有任何库是「当前」的；继续用它会让用户以为别的库
      // 没在生效。改为标服务端注册表的**默认库**（与「设为默认媒体库」同一项）。
      leading: Icon(
          isDef ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: isDef ? Colors.amber : Colors.grey),
      title: Text(
          '${libraryDisplayName('$id', '${l['name']}')}  ${isDef ? '★' : ''}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$id · ${l['count'] ?? 0} 条 / ${l['cols'] ?? 0} 个同步源',
              style: const TextStyle(fontSize: 12)),
          Text('${l['base']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          if (serverOriginOf(l).label.isNotEmpty)
            Text('连接：${serverOriginOf(l).label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(
              '爬虫：${boolOf(cr['enabled']) ? '已启用' : '未启用'} · ${cr['schedule'] ?? '04:10'} · 脚本 ${scripts.length} 个 · ${boolOf(l['indexOk']) ? '索引正常' : '索引缺失'}',
              style: TextStyle(
                  fontSize: 11,
                  color:
                      boolOf(l['indexOk']) ? Colors.grey : Colors.redAccent)),
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
          const PopupMenuItem(value: 'default', child: Text('设为默认媒体库')),
          const PopupMenuItem(value: 'crawler', child: Text('爬虫配置')),
          const PopupMenuItem(value: 'maint', child: Text('维护检查')),
          const PopupMenuItem(value: 'delete', child: Text('删除库（保留文件）')),
        ],
      ),
      onTap: () {
        // 「点了另一个库 = 作用域变了」只用于决定返回时是否通知上级刷新，
        // 不代表界面上还有「当前库」这个概念（圆点已改标默认库）。
        changed = changed || id != cfg.lib;
        _switchTo(l);
      },
    );
  }
}


/// 设置 → 爬虫设置：独立管理页，不再打开主页（避免套叠重复）。
/// 爬虫设置页「一台服务器」的取数结果（`_loadServerPart` 的返回）。
class _CrawlerServerPart {
  final String serverId;
  final List<Map<String, dynamic>> libs;
  final Map<String, Map<String, dynamic>> crawlers;

  /// 这一台服务器上「配置没读出来」的库 id（与「配置为空」区分开）。
  final Set<String> crawlFailed;
  final CrawlerMetaUnits? meta;
  final Map<String, bool> flags;

  const _CrawlerServerPart({
    required this.serverId,
    required this.libs,
    required this.crawlers,
    required this.crawlFailed,
    required this.meta,
    required this.flags,
  });
}

class MediaCrawlerSettingsPage extends StatefulWidget {
  const MediaCrawlerSettingsPage({super.key});
  @override
  State<MediaCrawlerSettingsPage> createState() =>
      _MediaCrawlerSettingsPageState();
}

class _MediaCrawlerSettingsPageState extends State<MediaCrawlerSettingsPage> {
  /// 按媒体库分节后的条目（每节先注册库、再单元库）。
  ///
  /// 0.9.322：页面上原来有两份互不相干的列表——按媒体库分节可折叠的单元库
  /// 条目，和一条平铺的注册库条目。现在两者都进 [_sections]，同一个媒体库
  /// 的设置只在一个地方。分组规则在 `crawler_sections.crawlerSectionsOf`。
  List<CrawlerSection> _sections = const [];
  bool loading = true;
  String? err;

  /// 本次载入的在线连接（`id → 连接`）：单元库条目的地址与鉴权从这里取。
  ///
  /// 此前条目页用 `cfg.baseFor/lib.headersFor`——绑定表只在首页聚合时建立，
  /// 从设置页直接进入时是空的，第二台服务端的单元库会拿默认那台的地址与
  /// 账号去请求（401，或恰好同名库时读到别人的数据）。
  Map<String, ServerConn> _serversById = const <String, ServerConn>{};

  /// `crawlerConfigKey(连接, 库)` → 该库配置读取失败。
  final Set<String> _crawlFailed = <String>{};

  /// `<连接>\u0001<注册库 id>` → 爬虫配置（`/api/crawler?id=`）。
  ///
  /// 键必须带连接（`crawler_sections.crawlerConfigKey`）：只按库 id 建键时，
  /// 两台服务端各有一个 `lib-1` 就共用一条配置——A 的「不自动抓取」会把
  /// B 的「每 30 分钟」盖掉，而两行各自显示自己的库名，看不出哪里错。
  final Map<String, Map<String, dynamic>> crawlers = {};

  /// `<连接>\u0001<rel>` → 是否有爬虫脚本（合并各连接的 `/api/nodes`）。
  Map<String, bool> unitFlags = const {};

  /// owner 2026-11-27：「各爬虫脚本条目按媒体库分类折叠收纳」。
  ///
  /// 默认全部折叠——40 多个单元库 + 脚本条目全展开，一屏塞不下也找不到东西。
  /// 键带连接（`crawler_sections.unitScopeKey`）：名字会变，两台服务端同名
  /// 媒体库也不能共用一个开关。
  final Set<String> crawlerSectionOpen = <String>{};

  @override
  void initState() {
    super.initState();
    load();
  }

  /// 本次请求的连接表：**在线**连接优先，没有配置时用当前连接。
  Future<List<ServerConn>> _liveServers() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final all = migrateLegacy(
        servers: decodeServers(sp.getString('servers_v1')),
        base: sp.getString('base') ?? cfg.base,
        user: sp.getString('user') ?? cfg.user,
        pass: sp.getString('pass') ?? cfg.pass,
      );
      final visible = liveServers(all);
      if (visible.isNotEmpty) return visible;
    } catch (_) {}
    if (cfg.base.isEmpty) return const <ServerConn>[];
    return <ServerConn>[
      ServerConn(
          id: cfg.serverIdFor(),
          label: cfg.serverLabelFor(),
          base: cfg.base,
          user: cfg.user,
          pass: cfg.pass)
    ];
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      crawlers.clear();
      _crawlFailed.clear();
      final servers = await _liveServers();
      if (servers.isEmpty) throw Exception('未配置服务器');
      _serversById = {for (final s in servers) s.id: s};

      // 每个连接各取一次：注册库列表 + 单元库元数据 + 脚本表。
      // 此前只用 `cfg.base` / `LibMeta.load(cfg.lib)`：第二台服务端的库与
      // 单元库在这页一条都不出现（主页面却看得到）。
      //
      // 连接之间并发（每个连接三件事彼此独立，串行时 N 台服务器 =
      // 3N 次往返）；同一个连接内注册库的爬虫配置也并发（40 多个库串行
      // await 会让这一页开屏等十几秒）。
      final parts = await mapConcurrent<ServerConn, _CrawlerServerPart>(
          servers, 4, (s) => _loadServerPart(s));
      final metas = <CrawlerMetaUnits>[];
      final libsByServer = <String, List<Map<String, dynamic>>>{};
      final flagsByServer = <String, Map<String, bool>>{};
      for (final p in parts) {
        if (p.libs.isNotEmpty) libsByServer[p.serverId] = p.libs;
        if (p.meta != null) metas.add(p.meta!);
        if (p.flags.isNotEmpty) flagsByServer[p.serverId] = p.flags;
        crawlers.addAll(p.crawlers);
        for (final f in p.crawlFailed) {
          _crawlFailed.add(crawlerConfigKey(p.serverId, f));
        }
      }

      final sections = crawlerSectionsOf(
          metas: metas, librariesByServer: libsByServer);
      if (!mounted) return;
      setState(() {
        _sections = sections;
        unitFlags = mergeCrawlerFlags(flagsByServer);
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

  /// 一台服务器在这页需要的三份数据（库列表 / 元数据 / 脚本表 / 爬虫配置）。
  ///
  /// 抽成一个方法而不是在 `load` 里逐台 await：这样连接之间、注册库之间
  /// 都能并发，且每份结果自带来源 id（不再靠共享 map 的写入顺序）。
  Future<_CrawlerServerPart> _loadServerPart(ServerConn s) async {
    final headers = {'Authorization': basicAuthHeader(s.user, s.pass)};
    var libs = const <Map<String, dynamic>>[];
    final crawlers = <String, Map<String, dynamic>>{};
    CrawlerMetaUnits? meta;
    var flags = const <String, bool>{};
    try {
      final r = await http
          .get(Uri.parse('${s.base}/api/libraries'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        // 每条库记录都要打上来源连接：这一页有两条入口会把它交给
        // `CrawlerConfigPage` / `MaintenancePage`，那两页的地址与鉴权由
        // `libraryBaseOf` / `libraryHeadersOf` 从记录自身取；不打标就只能
        // 回落绑定表，而绑定表里没有第二台服务器的库——请求打到默认那台。
        libs = [
          for (final raw in mapsOf(jsonMapOf(r)['libraries']))
            withServerOrigin(raw,
                id: s.id,
                base: s.base,
                label: s.cardLabel,
                user: s.user,
                pass: s.pass),
        ];
      }
    } catch (_) {}

    final ids = [
      for (final l in libs) '${l['id'] ?? ''}'.trim()
    ].where((id) => id.isNotEmpty).toList(growable: false);
    // 读失败的库要单独记下来：`null` 与「真的没有配置」在界面上是两件事。
    // 此前两者都落成「不自动抓取 · 脚本 0 个」——401/超时看起来像一条真设置。
    final fetched = await mapConcurrent<String, Map<String, dynamic>?>(ids, 6,
        (id) async {
      try {
        final cr = await http
            .get(Uri.parse(libApiUrl(s.base, '/api/crawler', id)),
                headers: headers)
            .timeout(const Duration(seconds: 8));
        if (cr.statusCode == 200) return jsonMapOf(cr);
      } catch (_) {}
      return null;
    });
    final failed = <String>{};
    for (var i = 0; i < ids.length; i++) {
      final cj = fetched[i];
      if (cj != null) {
        crawlers[crawlerConfigKey(s.id, ids[i])] = cj;
      } else {
        failed.add(ids[i]);
      }
    }

    // 元数据按该连接的**第一个注册库**取：`cfg.lib` 只属于默认连接，
    // 拿去请求别台服务器的库树必然空。
    final primary = ids.isEmpty ? '' : ids.first;
    if (primary.isNotEmpty) {
      try {
        // 来源显式传给 `LibMeta.load`：绑定表只在首页聚合后建立，
        // 从设置页直接进来时它是空的——这里自己知道读的是哪台服务器，
        // 再让函数去「猜」就会把第二台的库 id 拿去请求默认服务器。
        final m = await LibMeta.load(primary,
            source: MetaSource.ofServer(
                id: s.id, base: s.base, user: s.user, pass: s.pass));
        meta = (tops: m.tops, units: m.units);
      } catch (_) {}
    }

    try {
      final nr = await http
          .get(Uri.parse('${s.base}/api/nodes'), headers: headers)
          .timeout(const Duration(seconds: 8));
      if (nr.statusCode == 200) flags = unitCrawlerFlags(jsonOf(nr));
    } catch (_) {}
    return _CrawlerServerPart(
        serverId: s.id,
        libs: libs,
        crawlers: crawlers,
        crawlFailed: failed,
        meta: meta,
        flags: flags);
  }

  Map _cfgOf(Map<String, dynamic>? j) =>
      mapOrNull(j == null ? null : j['crawler']) ?? const <String, dynamic>{};

  int _scriptCount(Map<String, dynamic>? j) =>
      listLengthOf(j == null ? null : j['scripts']);

  /// 条目副标题：频率 + 脚本数；**读失败时说实话**。
  ///
  /// 旧写法在 `j == null` 时写「不自动抓取 · 脚本 0 个」——超时与 401 看起来
  /// 跟一条真设置一模一样，用户会以为那台服务器的抓取被关掉了。
  String _libSummary(String serverId, String libId, Map<String, dynamic>? j) {
    if (j == null && _crawlFailed.contains(crawlerConfigKey(serverId, libId))) {
      return '配置读取失败（网络或鉴权）· 脚本数未知';
    }
    return '${_freqText(j)} · 脚本 ${_scriptCount(j)} 个';
  }

  String _freqText(Map<String, dynamic>? j) {
    final iv = intOf(_cfgOf(j)['intervalMin']);
    if (iv <= 0) return '不自动抓取';
    return everyMinutesLabel(iv);
  }

  /// 本页全部条目：按媒体库分节，节内先注册库、再单元库。
  ///
  /// 分组规则（谁属于哪个媒体库、去重、稳定排序）只在
  /// `crawler_sections.crawlerSectionsOf` 一处；这里只负责画。
  List<Widget> _sectionWidgets() {
    if (_sections.isEmpty) {
      return const <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text('没有可显示的媒体库（未连接或服务端未下发库树）',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
      ];
    }
    final out = <Widget>[];
    for (final s in _sections) {
      if (s.units.isEmpty && s.libraries.isEmpty) continue;
      final sid = s.serverId;
      final withScripts =
          s.units.where((u) => unitHasCrawlerScript(unitFlags, u, serverId: sid)).length;
      if (s.isOther) {
        // 「其它」节不折叠：条目本来就少，且没有可点开的媒体库标题。
        out.add(const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text('其它（不属于任何媒体库）',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ));
        for (final l in s.libraries) {
          out.add(_libTile(l));
        }
        for (final u in s.units) {
          out.add(_unitTile(u, sid));
        }
        continue;
      }
      final open = crawlerSectionOpen.contains(s.key);
      out.add(_crawlerSectionHeader(
        section: s,
        subtitle: '${s.libraries.length} 个库 · ${s.units.length} 个单元库'
            ' · $withScripts 个有脚本',
      ));
      if (!open) continue;
      for (final l in s.libraries) {
        out.add(_libTile(l));
      }
      for (final u in s.units) {
        out.add(_unitTile(u, sid));
      }
    }
    return out;
  }

  /// 可折叠的媒体库分节头。默认折叠，点一下展开该媒体库下的条目。
  Widget _crawlerSectionHeader({
    required CrawlerSection section,
    required String subtitle,
  }) {
    final open = crawlerSectionOpen.contains(section.key);
    return InkWell(
      key: ValueKey('crawler-section-${section.key}'),
      onTap: () => setState(() {
        if (!crawlerSectionOpen.remove(section.key)) {
          crawlerSectionOpen.add(section.key);
        }
      }),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 6),
        child: Row(children: [
          Icon(Icons.layers_outlined, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(LibraryBadge.stripIndex(section.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Icon(open ? Icons.expand_less : Icons.expand_more,
              size: 20, color: Colors.grey),
        ]),
      ),
    );
  }

  /// 注册库条目：爬虫配置 / 维护检查两个入口。
  ///
  /// 连接从该条目自己的来源字段取（`serverOriginOf` 与聚合时写的是同一套
  /// 键）；跨连接时菜单里的页面才知道该去哪台服务器。
  Widget _libTile(Map<String, dynamic> l) {
    final id = '${l['id'] ?? ''}'.trim();
    final sid = serverOriginOf(l).id;
    // 配置按「连接 + 库 id」取：同名的库在两台服务端各有一份。
    final cfgOfLib = crawlers[crawlerConfigKey(sid, id)];
    final failed = _crawlFailed.contains(crawlerConfigKey(sid, id));
    return ListTile(
      leading: const Icon(Icons.library_books_outlined),
      title: Text(libraryDisplayName(id, '${l['name'] ?? id}'),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('$id · ${_libSummary(sid, id, cfgOfLib)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11, color: failed ? Colors.orange : null)),
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
    );
  }

  /// 单个单元库的配置入口；没有脚本时置灰并写明「为什么不能设置」。
  ///
  /// [serverId] 是所在分节的连接：条目自己没带连接标识（旧树）时用它，
  /// 否则跨连接进入会打到默认库那台服务器。
  Widget _unitTile(UnitLibrary u, String serverId) {
    final sid = u.node.serverId.trim().isNotEmpty ? u.node.serverId.trim() : serverId;
    final has = unitHasCrawlerScript(unitFlags, u, serverId: sid);
    return ListTile(
      enabled: has,
      leading: Icon(
        has ? Icons.folder_copy_outlined : Icons.folder_off_outlined,
        color: has ? null : Colors.grey,
      ),
      // owner 2026-11-25：「爬虫设置还有任何地方里也都同步应用省略序号设置」。
      // 这里原来直接显示 u.name，序号 `(1) ` 会露出来，与卡片/词条不一致。
      title: Text(LibraryBadge.stripIndex(u.name),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        has
            ? '已配置爬虫脚本 · 可单独设置同步频率'
            : '该单元库没有爬虫脚本，因此不支持同步设置',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            TextStyle(fontSize: 11, color: has ? Colors.grey : Colors.orange),
      ),
      trailing: Icon(Icons.chevron_right,
          color: has ? null : Colors.grey.withValues(alpha: 0.4)),
      onTap: has
          ? () async {
              // owner 2026-11-25：「总爬虫设置里进入单元库爬虫设置和相应单元库
              // 封面进入爬虫设置里看到的内容不一样，总的里面进入后没有日志」。
              //
              // 根因：这里传的是 `libId: cfg.lib`（默认注册库），而日志面板按
              // `/api/sync/logs?lib=` 过滤——库 id 不对就永远查不到该单元库的
              // 日志。单元库页那条入口传的是 `u.basics.first.id`，所以那边有日志。
              //
              // 统一口径：库 id 取该单元库自己的第一个基础库；base/headers 都按
              // 条目所属连接取（跨连接时 Admin 头不能错配）。
              final libId = u.basics.isNotEmpty
                  ? u.basics.first.id
                  : (sid == cfg.serverIdFor() ? cfg.lib : '');
              // 地址/账号取条目所属连接（本页自己刚读到的连接表），
              // 拿不到才回落绑定表：避免「地址是 A、账号是 B」。
              final conn = _serversById[sid];
              final base = u.node.serverBase.trim().isNotEmpty
                  ? u.node.serverBase.trim()
                  : (conn?.base.isNotEmpty == true
                      ? conn!.base
                      : cfg.baseFor(libId));
              final headers = conn != null
                  ? {'Authorization': basicAuthHeader(conn.user, conn.pass)}
                  : cfg.headersFor(libId);
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (c) => UnitCrawlerPage(
                        unit: u,
                        base: base,
                        headers: headers,
                        libId: libId,
                        onOpenDeletedMonitor: () =>
                            Navigator.of(c).push(MaterialPageRoute(
                                builder: (_) => DeletedMonitorPage(
                                      unitRel: u.rel,
                                      unitName: u.name,
                                      base: base,
                                      headers: headers,
                                      libId: libId,
                                    ))),
                      )));
              load();
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    var libCount = 0;
    var unitCount = 0;
    var withScripts = 0;
    for (final s in _sections) {
      libCount += s.libraries.length;
      unitCount += s.units.length;
      withScripts += s.units
          .where((u) => unitHasCrawlerScript(unitFlags, u, serverId: s.serverId))
          .length;
    }
    return Scaffold(
      appBar: AppBar(title: const Text('爬虫设置'), actions: [
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
                    child: Text('$libCount 个库 · $unitCount 个单元库'
                        ' · $withScripts 个有爬虫脚本',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
                  // owner 2026-11-25：「设置里也按各个媒体库分类好，哪个媒体库
                  // 的设置就归到对应的下面去」。
                  // owner 2026-11-27：「各爬虫脚本条目按媒体库分类折叠收纳」。
                  // 注册库条目与单元库条目在同一个分节里，不再一平铺一折叠。
                  ..._sectionWidgets(),
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
  List<UnitCrawlerScript> scripts = const [];

  String get libId => '${widget.lib['id']}';

  /// 地址与鉴权都优先取**这条记录自己**的来源连接。
  ///
  /// 绑定表（`cfg.baseFor/headersFor`）只在首页加载库列表时建立；从设置页
  /// 直接进入这一页（首屏还没聚合过）时表是空的，跨连接就会拿默认服务器的
  /// 地址与账号去请求另一台的库。
  String get _base => libraryBaseOf(widget.lib, cfg.baseFor(libId));
  Map<String, String> get _headers =>
      libraryHeadersOf(widget.lib, cfg.headersFor(libId));

  Uri _u(String path) => Uri.parse(libApiUrl(_base, path, libId));

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
          .get(_u('/api/crawler'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      final j = jsonMapOf(r);
      throwIfApiFailed(r.statusCode, j);
      final c = mapOrNull(j['crawler']) ?? const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        enabled = boolOf(c['enabled']);
        schedule = '${c['schedule'] ?? '04:10'}';
        intervalMin = intOf(c['intervalMin']);
        note = '${c['note'] ?? ''}';
        scripts = UnitCrawlerScript.listFrom(j['scripts']);
      });
    } catch (e) {
      if (mounted) setState(() => err = errorText(e));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final r = await http
          .post(_u('/api/crawler'),
              headers: {
                ..._headers,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'enabled': enabled,
                'schedule': schedule.trim(),
                'intervalMin': intervalMin,
                'note': note,
              }))
          .timeout(const Duration(seconds: 15));
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
      // 名字统一走 `libraryDisplayName`：与设置列表/网络设置同一个出口，
      // 目录名带 `(1) ` 前缀时这里也不再露出一份没剥序号的写法。
      appBar: AppBar(
          title: Text('爬虫配置 · '
              '${libraryDisplayName('${widget.lib['id']}', '${widget.lib['name']}')}'),
          actions: [
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
                      title: Text(s.name),
                      subtitle: Text(formatBytes(s.size),
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

  /// 同 `CrawlerConfigPage`：地址与鉴权取这条记录自己的来源连接。
  String get _base => libraryBaseOf(widget.lib, cfg.baseFor(libId));
  Map<String, String> get _headers =>
      libraryHeadersOf(widget.lib, cfg.headersFor(libId));

  Uri _u(String path) => Uri.parse(libApiUrl(_base, path, libId));

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
              headers: _headers)
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
      final r = await http
          .post(_u('/api/maintenance'),
              headers: {
                ..._headers,
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'action': 'run-crawler', 'lib': libId}))
          .timeout(const Duration(seconds: 20));
      final j = jsonOf(r);
      throwIfApiFailed(r.statusCode, j);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('爬虫已启动（进程 ${j['pid']}），日志：${j['log']}')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('启动失败：${errorText(e)}')));
      }
    }
    if (mounted) setState(() => running = false);
  }

  String _list(Object? v) => stringsOf(v).join(', ');

  String _deadLine(dynamic e) {
    if (e is! Map) return '$e';
    final kind = e['kind'] == 'm' ? '媒体' : (e['kind'] == 'th' ? '封面' : '音频');
    return '同步源${e['idx']} · ${e['id']} · $kind · ${e['reason']}';
  }

  @override
  Widget build(BuildContext context) {
    final deep = data['deep'] is Map ? data['deep'] as Map : null;
    final deepOk = deep == null || boolOf(deep['ok']);
    final ok = boolOf(data['indexOk']) && boolOf(data['baseOk']) && deepOk;
    return Scaffold(
      appBar: AppBar(
          title: Text('维护 · '
              '${libraryDisplayName('${widget.lib['id']}', '${widget.lib['name']}')}'),
          actions: [
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
                  _row('索引', '${boolOf(data['indexOk']) ? '正常' : '缺失/损坏'}'),
                  _row('作品/同步源',
                      '${data['total'] ?? 0} / ${data['collections'] ?? 0}'),
                  _row('索引文件', '${data['cFiles'] ?? 0} 个'),
                  _row('缺失', _list(data['missing'])),
                  _row('孤儿', _list(data['orphans'])),
                  _row('损坏', _list(data['bad'])),
                  _row('媒体目录存在', '${boolOf(data['baseOk']) ? '是' : '否'}'),
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
                    if (listOf(deep['dead']).isNotEmpty)
                      _row(
                          '失效明细',
                          listOf(deep['dead'])
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
      final ls = librariesWithDisplayNames(mapsOf(lj['libraries']));
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
          libraryDisplayName('${pick['id']}', '${pick['name'] ?? ''}');
      if (changed) {
        await savePrefString('lib', cfg.lib);
      }
    } catch (_) {}
  }

  /// 「文件结构」：勾选哪些目录是节点文件夹（单元库）。
  ///
  /// 0.9.327：与库页同一个入口口径——把磁盘上全部在线连接交给页面，
  /// 由页面按服务器切换。此前只传 `cfg.base` / `cfg.headers`（当前库那条
  /// 连接），第二台服务器在这页不可见。
  Future<void> _openFolders() async {
    final all = await loadServersFromPrefs();
    final live = liveServers(all);
    final sources = <FolderSource>[
      for (final s in live)
        FolderSource(
          id: s.id,
          label: s.cardLabel,
          base: s.base,
          headersOf: () => {'Authorization': basicAuthHeader(s.user, s.pass)},
        ),
    ];
    // 一条在线连接都读不到时仍要能打开页面：用当前连接兜底（地址/账号
    // 都来自 `cfg`，这是唯一还知道的一份）。
    if (sources.isEmpty && cfg.base.isNotEmpty) {
      sources.add(FolderSource(
        id: cfg.serverIdFor(),
        label: cfg.serverLabelFor(),
        base: cfg.base,
        headersOf: () => cfg.headers,
      ));
    }
    if (sources.isEmpty) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FolderStructurePage(
        sources: sources,
        // 保存成功已经会让首页重拉快照；返回时再 bump 一次是为了覆盖
        // 「另一台服务器上改了节点、本页缓存还没过期」这一种——两处都只是
        // 重读，不新增状态。
        onSaved: (_) async {
          if (mounted) setState(() => _libEpoch++);
        },
      ),
    ));
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
    return listLengthOf(j['libraries']);
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
    // 作者/头像：作废当前索引后重拉一次，并通知已渲染头像重建。
    // 作用域标记一起清，否则 `ensureAuthorAvatarsLoaded` 会因为「已加载」
    // 直接返回（刷新按钮什么都不做）。
    reloadAuthors: () async {
      final scopeKey = authorAvatarScopeKey;
      _authorAvatarScope = '';
      authorAvatarIndex.clear();
      await ensureAuthorAvatarsLoaded();
      // 请求途中连接又变了：那一份结果已经被新一轮覆盖，这里不再提升版本。
      if (_authorAvatarScope != scopeKey) return;
      authorAvatarRevision.value++;
    },
  );
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

  /// 选中库的元数据是否正在读取。
  ///
  /// 空列表有两种原因：「这个库本期确实没有播放」和「还没算出它包含哪些
  /// 基础库」。同一个空态文案说两句不同的事，用户只会以为数据丢了。
  bool metaLoading = false;

  /// 选中库包含的基础库 id（`sel` 是注册库 id，`libs` 行里是基础库 id）。
  ///
  /// 这是本轮修掉的真缺陷：`sel` 此前被直接当 `big_id`（历史分组 id）去比，
  /// 两个命名空间永远不相等，点「某库」进来看不到任何作者。归属判定改由
  /// `rank_filter.authorInLibrary` 一处完成，这里只提供它要的集合。
  Set<String> get _memberBasics {
    if (sel.isEmpty || sel == 'all') return const <String>{};
    // **只认选中库自己那份 meta**。回落 `metas[cfg.lib]` 会把「当前库的基础库」
    // 当成选中库的成员——换一个库看就会列出别人家的作者，而且看不出原因。
    final meta = metas[sel];
    // 拿不到元数据时返回空集：**不猜**归属。`authorInLibrary` 对空集一律
    // 返回 false，界面上会显示「该库本期还没有播放记录」——比把注册库 id
    // 硬当基础库 id 去比（必然全不中、且原因看不出来）更诚实。
    if (meta == null) return const <String>{};
    final ids = <String>{
      for (final b in meta.filterBasics) b.id,
      for (final b in meta.allBasics) b.id,
    };
    // 当前库本身可能就是基础库 id（从基础库页进来）——直接当成员。
    if (meta.basicById(sel) != null) ids.add(sel);
    return ids;
  }

  @override
  void initState() {
    super.initState();
    sel = widget.initialLib ?? 'all';
    loadLibs();
    load();
  }

  Future<void> loadLibs() async {
    try {
      // 库列表＝**注册库**（`/api/libraries` 的 `libraries`），不是历史分组。
      //
      // 此前这里从 `meta.bigNames`（`basicLibraries[].big_id`）造列表，而服务端
      // 早已不再下发 `big_id`（`grep big_id` = 0）：列表恒空、`libName` 恒回落到
      // id，从「各库排行」点进来的选中项也不在列表里。排行榜的「按库看」说的
      // 是媒体库，和「各库排行」页列的是同一批东西。
      final r = await http
          .get(cfg.u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      final reg = r.statusCode == 200
          ? librariesWithDisplayNames(mapsOf(jsonMapOf(r)['libraries']))
          : const <Map<String, dynamic>>[];
      await _ensureMeta(cfg.lib);
      if (!mounted) return;
      // 同名媒体库之间没有次序依据；`List.sort` 不稳定 → 下拉刷新一次换一次
      // 顺序、选中项还跟着跳。稳定排序 + id 作为最终键。
      final list = stableSort(reg, (a, b) {
        final c = '${a['name']}'.compareTo('${b['name']}');
        return c != 0 ? c : '${a['id']}'.compareTo('${b['id']}');
      });
      setState(() => libs = list);
      if (sel.isNotEmpty && sel != 'all' && !metas.containsKey(sel)) {
        _loadMetaFor(sel);
      }
    } catch (_) {}
  }

  /// 为某个库装载元数据并写进 [metas]（**本页唯一的写入点**）。
  ///
  /// 此前 `loadLibs` 与 `load` 各自 `LibMeta.load(cfg.lib)` 再各自
  /// `metas[cfg.lib] = meta`：`initState` 同时启动两者 → 两次 await、两次
  /// setState，第二份结果无条件覆盖第一份。缓存命中时是浪费；一旦两次请求
  /// 落在不同的 5 分钟窗口里，先写好的那份会被更旧的一份顶掉（谁后 return
  /// 谁说话）。现在两条路径都走这里，`LibMeta` 自身的缓存与并发合并在
  /// 下层完成，页面只负责「装完写一次」。
  Future<LibMeta?> _ensureMeta(String lib, {bool showLoading = false}) async {
    if (lib.trim().isEmpty) return null;
    if (showLoading && mounted) setState(() => metaLoading = true);
    LibMeta? meta;
    try {
      meta = await LibMeta.load(lib);
    } catch (_) {
      meta = null;
    }
    if (!mounted) return meta;
    setState(() {
      if (meta != null) metas[lib] = meta;
      if (showLoading) metaLoading = false;
    });
    return meta;
  }

  /// 为选中的库加载元数据（`loadLibs` 只装了当前库那份）。
  Future<void> _loadMetaFor(String lib) =>
      _ensureMeta(lib, showLoading: true);

  Future<void> load() async {
    if (mounted) setState(() => err = null);
    try {
      // 0.9.8：排行榜数据源改为全部基础库；大库筛选在本地按作者所属基础库收敛。
      // `lib=all` 的地址是激活连接、`cfg.headers` 却是当前库那条；两者
      // 分属两台机器时名次与数字来自 A、凭据是 B 的（401 或串库）。
      final scope = cfg.aggregate('/api/rank?period=$period&metric=$metric');
      final r = await http
          .get(scope.uri, headers: scope.headers)
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
      final j = jsonOf(r);
      await _ensureMeta(cfg.lib);
      if (!mounted) return;
      final list = listOf(j is Map ? j['authors'] : null);
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
    // 列表自己的高度（`_listViewportHeight`），不是窗口：上方还有周期条
    // 与说明行，按窗口算会把屏幕外的一行也预热进来。首帧前不预热。
    final viewportHeight = _listViewportHeight;
    if (viewportHeight == null) return;
    final mq = MediaQuery.of(context);
    // 行步进来自尺寸表：此前这里用 `firstScreenRowCount` 的默认 72 行高，
    // 实测 `AuthorRankTile` 是 67 + 1dp 分隔线 = 68 —— 预热多算约 7%，
    // 最后一行取的是屏幕外的头像。
    final n = firstScreenRowCount(
        viewportHeight: viewportHeight, rowExtent: kAuthorRankRowExtent);
    if (n <= 0) return;
    // 行库用于**路由**：决定地址走哪条连接、带哪份鉴权头。
    // 缩略图路由用**该行自己的库**，不用 `sel`：`sel` 是注册库 id，
    // 而头像路径 `/media/<基础库>/…` 里带的是基础库 id，拿注册库 id 去
    // 换地址会把它当成「未知库」再补一次前缀（同一张图 404）。
    // 空行库回落当前库：绑定表里注册库与基础库都有条目（首页聚合时
    // `buildBindings` 给两侧都写了 bindingEntry），所以这里不需要再换算。
    String libOf(Map e) {
      final own = '${e['lib'] ?? ''}'.trim();
      return own.isEmpty ? cfg.lib : own;
    }
    prefetchAvatarItems(
      [
        for (final e in visibleRows.take(n))
          (path: '${e['avatar'] ?? ''}', lib: libOf(e)),
      ],
      limit: n,
      displaySize: AuthorAvatar.rankSize,
      devicePixelRatio: mq.devicePixelRatio,
      urlOf: (path, lib) => cfg.mediaUrl(path, lib: lib),
      headersOf: cfg.headersFor,
    );
  }

  /// 榜单列表自己的可用高度（0.9.300）。
  ///
  /// 此前预热用 `MediaQuery.size.height`（整窗口），而列表上压着 AppBar +
  /// 周期条（46）+ 说明行（约 24）：按窗口算出的行数偏多，末行预热的是
  /// 屏幕外那张头像。高度现在来自列表自己的 `LayoutBuilder`。
  double? _listViewportHeight;

  Map<String, dynamic> _rowMap(dynamic e) =>
      e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};

  /// 榜单行用的元数据：选中库优先 → 行自己的库 → 当前库。
  ///
  /// 「选中库优先」是从「各库排行」点进来的场景（`sel` 是那个注册库）；
  /// 行自己的库用于 `lib=all` 下跨连接作者（词条要按作者所在库的颜色/名称）。
  LibMeta? _rowMeta(Map<String, dynamic> e) {
    final want = [
      if (sel.isNotEmpty && sel != 'all') sel,
      '${e['lib'] ?? ''}'.trim(),
      cfg.lib,
    ];
    for (final id in want) {
      if (id.isEmpty) continue;
      final hit = metas[id];
      if (hit != null) return hit;
    }
    return metas.isEmpty ? null : metas.values.first;
  }

  /// 按选中库收敛作者（`sel == 'all'` 时全量）。
  ///
  /// 归属判定只有 `rank_filter.authorInLibrary` 一处：榜单行自带 `libs`
  /// （服务端 `lib=all` 下发的来源基础库），`sel` 再展开成它包含的基础库集合。
  /// 此前这里拿 `sel`（注册库 id）去比 `bigIdFor(...)`（历史分组 id），
  /// 两个命名空间永不相等 —— 点「某库」进来一条都不显示。
  List<Map<String, dynamic>> get _visibleRows {
    if (sel == 'all') return [for (final e in rows) _rowMap(e)];
    final members = _memberBasics;
    return [
      for (final e in rows)
        if (authorInLibrary(
          memberBasics: members,
          basicId:
              _rowMeta(_rowMap(e))?.basicIdForPath('${_rowMap(e)['avatar'] ?? ''}') ??
                  '',
          rowLibs: stringsOf(_rowMap(e)['libs']),
        ))
          _rowMap(e)
    ];
  }

  Future<void> _open(String name) async {
    dynamic row;
    for (final e in rows) {
      if (e is Map && '${e['name'] ?? ''}' == name) {
        row = e;
        break;
      }
    }
    final ls = row is Map ? stringsOf(row['libs']) : const <String>[];
    final target = ls.isEmpty ? [sel == 'all' ? cfg.lib : sel] : ls;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            AuthorPage(name: name, libs: target.isEmpty ? null : target)));
    if (mounted) load();
  }


  @override
  Widget build(BuildContext context) {
    final visible = _visibleRows;
    return Scaffold(
      appBar: AppBar(title: const Text('排行榜'), actions: [
        // owner 2026-11-27：「多库排行放在作者总览页不该是排行榜页码」。
        // 各库排行是排行榜的另一个维度（库 vs 作者），入口应在排行榜页内，
        // 作者总览页只留作者相关动作。
        IconButton(
            tooltip: '各库排行',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LibraryRankPage())),
            icon: const Icon(Icons.stacked_bar_chart)),
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
          // 列表自己的约束即预热几何（`_listViewportHeight`）。
          child: LayoutBuilder(builder: (context, cons) {
            if (cons.maxHeight != _listViewportHeight) {
              _listViewportHeight = cons.maxHeight;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _prefetchRankAvatars();
              });
            }
            return loading
              ? const Center(child: CircularProgressIndicator())
              : err != null
                  ? LoadErrorView(
                      message: '加载失败：$err',
                      onRetry: load)
                  : visible.isEmpty && metaLoading
                      ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? Center(
                          child: Text(
                              // 指标与作用域都由 `rank_metric.rankEmptyText`
                              // 一处表达：页面不再自己拼分支。
                              rankEmptyText(metric,
                                  scoped: sel.isNotEmpty && sel != 'all'),
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
                            final score = intOf(e['score']);
                            final rowLib = sel == 'all'
                                ? '${e['lib'] ?? cfg.lib}'
                                : (sel.isEmpty ? cfg.lib : sel);
                            // 0.9.15：排行榜每行都用有效 meta（缺行库时回退到当前库），
                            // 否则作者词条会退化成 SECRET/旧词条。
                            final meta = _rowMeta(_rowMap(e));
                            // 行库名先查注册库列表（媒体库），再查该行 meta 的
                            // 基础库名（`lib=all` 行的 `lib` 是基础库 id）。
                            String libName(String id) {
                              for (final l in libs) {
                                if ('${l['id']}' == id) {
                                  return libraryDisplayName(
                                      '${l['id']}', '${l['name'] ?? ''}');
                                }
                              }
                              final b = meta?.basicById(id);
                              if (b != null) return displayLibraryName(b.id, b.name);
                              return displayLibraryName(id, id);
                            }

                            return AuthorRankTile(
                              rank: i + 1,
                              rankColor: rankColorFor(context, i),
                              name: name,
                              avatar: av,
                              lib: rowLib,
                              libName: libName(rowLib),
                              meta: meta,
                              works: intOf(e['works']),
                              plays: intOf(e['plays']),
                              drops: intOf(e['drops']),
                              metric: metric,
                              score: score,
                              onTap: name.isEmpty ? null : () => _open(name),
                            );
                          },
                        );
          }),
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

  /// 服务端注册表里的默认库 id（`/api/libraries` 的 `default`）。
  ///
  /// 此前行尾那枚词条标的是「当前」＝`cfg.lib`——那是单库时代的措辞与口径：
  /// 多库里没有任何一个库是「当前」，服务端只有「默认」。口径改成默认库后，
  /// 词条文字与网络设置页的「默认」是同一个意思。
  String defaultId = '';

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
      final list = librariesWithDisplayNames(mapsOf(j['libraries']));
      defaultId = '${j['default'] ?? ''}'.trim();

      final loaded = <String, Map<String, dynamic>>{};
      // 每个在线库要单独取一份 `authors.json` 统计。此前是**串行** await：
      // N 个库就是 N 次往返（超时上限各 8s），库多时这一页要等十几秒，
      // 而它们彼此完全独立。改有界并发（`concurrency.mapConcurrent`，与搜索
      // 页同一个入口）；顺序不影响结果——`buildLibraryRank` 自己排序。
      final want = <String>[
        for (final lib in list)
          if ('${lib['id'] ?? ''}'.isNotEmpty && libraryOnline(lib))
            '${lib['id']}',
      ];
      var offline = list.length - want.length;
      final pages = await mapConcurrent<String, Map<String, dynamic>?>(
        want,
        6,
        (id) async {
          try {
            final sr = await http
                .get(cfg.u('/api/author_stats.json', lib: id),
                    // 地址按该库路由，鉴权头也必须按该库：`cfg.headers` 是
                    // 当前库那条连接的账号，跨连接时会 401。
                    headers: cfg.headersFor(id))
                .timeout(const Duration(seconds: 8));
            if (sr.statusCode != 200) return null;
            return statsAuthors(jsonOf(sr));
          } catch (_) {
            return null;
          }
        },
      );
      for (var i = 0; i < want.length; i++) {
        final st = pages[i];
        if (st == null) {
          offline++;
          continue;
        }
        loaded[want[i]] = st;
      }

      final ranked = buildLibraryRank(
        libs: list,
        stats: loaded,
        metric: metric,
        // 「默认库」不是「当前库」：服务端只下发 `default`，多库里没有任何
        // 一个库是「当前」（owner 2026-11-27「各地方都要适应多媒体库管理」）。
        defaultLib: defaultId.isEmpty ? null : defaultId,
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
                // 切指标必须**重新排名**：名次与右侧数字是同一条榜单的两个
                // 字段，只换数字不换名次就会出现「播放量第 1、水滴数却比
                // 第 3 名还少」。数据已经在内存里，不必重新请求。
                setState(() {
                  metric = 'play';
                  rows = rankOrder(rows, metric);
                });
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('总水滴数'),
              selected: metric == 'drop',
              onSelected: (_) {
                if (metric == 'drop') return;
                setState(() {
                  metric = 'drop';
                  rows = rankOrder(rows, metric);
                });
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
                    // 数字来自服务端 `/api/author_stats.json`，不是这台设备。
                    // 写「本机」会让用户以为统计只算当前手机/电脑上的播放，
                    // 换个设备看同一份榜单还会怀疑数据不一致。
                    ' · 统计来自服务端',
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
                                if (r.isDefault)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                        color: Colors.lightBlueAccent
                                            .withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(4)),
                                    child: const Text('默认',
                                        style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.lightBlueAccent)),
                                  ),
                              ]),
                              // 类型在前、数字在后；两项顺序不随指标变
                              // （此前播放量榜是「N 播放」、水滴榜是「播放 N」，
                              // 同一个数字切一次指标就换位置）。
                              subtitle: Text(
                                  rankDetailLine(
                                      plays: r.plays, drops: r.drops),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                              trailing: RankScoreCell(
                                  label: rankMetricLabel(metric),
                                  value: score,
                                  color: Colors.lightBlueAccent),
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
  /// 与库卡片同一个圆角（`card_metrics.kCardRadius`）：作者总览卡与基础库页
  /// 作者卡视觉上必须一致，此前 12 在两处各写一份。
  static const double radius = kCardRadius;

  /// 卡片固定行高：唯一数字在 `grid_spec.kAuthorCardExtent`
  /// （页面 delegate 与首屏预热都从那里读）。
  static const double extent = kAuthorCardExtent;

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
                    child: Text('${formatCount(works)} 作品',
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
                works: works,
                stats: stats,
                // 150dp 卡只放得下一行词条：单条上限必须比信息区小，
                // 否则媒体库+单元库两级各占一行、第二行压到头像上。
                chipMaxWidth: kAuthorCardChipMaxWidth,
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
  /// 当前排行指标（`play` / `drop`）：决定右侧分数格子的类型文字。
  final String metric;
  final int score;
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
    this.metric = 'play',
    this.score = 0,
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
          works: works,
        ),
        const SizedBox(height: 2),
        // 排行榜明细行**故意保留精确数字**：这一行是用来互相比较的
        // （同一屏里几个作者的播放量谁多谁少），缩写会把 1.2万 和 1.3万
        // 压成同一个读数。它不是「同一读数两处写法」，是另一个用途。
        //
        // 顺序与右侧分数格子统一：类型在前、数字在后（`rank_metric.dart`）。
        Text(rankDetailLine(plays: plays, drops: drops, works: works),
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]),
      // 分数格子宽度固定、类型在上数字在下：切指标时数字不左右挪
      // （此前 `💧 4` 与 `2000` 宽度不同，整列数字对不齐）。
      trailing: RankScoreCell(
        label: rankMetricLabel(metric),
        value: score,
        color: Colors.lightBlueAccent,
      ),
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

  /// 作者网格自己的可用尺寸（0.9.300）。
  ///
  /// 此前首屏头像预热用 `MediaQuery.size`（整个窗口），而网格上压着
  /// AppBar + 排序条 + 计数行（约 100dp）——按窗口算出的行数偏多，末行预热
  /// 的是屏幕外那张头像（白拉一次请求）。尺寸现在来自网格自己的
  /// `LayoutBuilder`：预热与排布同一份约束。
  Size? _gridViewport;

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
  //
  // 0.9.338：这两张表**立即**属于某一条连接。`_avLookup` 只加不清，切过
  // 激活连接后新连接的作者仍在表里（同名同库 id 时）——于是「已查过」成立，
  // 兜底头像永远不拉，卡片停在首字占位，直到重启 App。作者头像索引
  // （`_authorAvatarScope`）上一批已经把「已加载」改成作用域比较，这里是同一
  // 族里最后一处，口径必须一致：连接一变就当作没查过，并丢掉旧图。
  final Map<String, String> _avFallback = {};
  final Set<String> _avLookup = {};

  /// 上面两张表的作用域（`authorAvatarScopeKey`）。空串＝尚未写入。
  String _avScope = '';

  /// 作用域变了就清空兜底缓存；返回当前作用域。
  ///
  /// 只在 [load] 开头调一次：`_authorCell` 在 build 里跑，在里面改表会
  /// 在构造帧中触发重建。
  void _syncAvScope() {
    final scope = authorAvatarScopeKey;
    if (_avScope == scope) return;
    _avScope = scope;
    _avFallback.clear();
    _avLookup.clear();
  }

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
    if (j == null || !serviceSaidOk(j)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('同步启动失败：${serverErrorText(j) ?? '网络错误'}')));
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
      if (boolOf(s['running'])) return;
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

  /// 新建作者目录（`@作者名`）。
  ///
  /// owner 2026-11-27：这件事属于**作者页**，不属于挂载设置页——
  /// 挂载解决的是「已有文件夹怎么归类」，建目录是在作者容器里造新作者。
  /// 同一批里已把 `unit_author_mount_page` 的那份入口连同实现一起删掉，
  /// 这里是**唯一**入口（服务端 `POST /api/unit/authors/create`）。
  Future<void> _createAuthor() async {
    final meta = _metaForAuthorPage();
    final basics = meta == null
        ? const <BasicLib>[]
        : (meta.allBasics.isNotEmpty ? meta.allBasics : meta.basics);
    if (basics.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('还没有可用的基础库')));
      return;
    }
    var lib = basics.first.id;
    final nameCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setD) => AlertDialog(
          title: const Text('新建作者目录'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: lib,
                decoration:
                    const InputDecoration(labelText: '基础库', isDense: true),
                items: [
                  for (final b in basics)
                    DropdownMenuItem(
                        value: b.id,
                        child: Text(b.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setD(() => lib = v ?? lib),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('author-create-name'),
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '作者名（会建成 @作者名 目录）',
                  isDense: true,
                ),
                onChanged: (_) => setD(() {}),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('取消')),
            FilledButton(
              key: const ValueKey('author-create-ok'),
              onPressed: nameCtl.text.trim().isEmpty
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(bad)));
      return;
    }
    try {
      final r = await http
          .post(
            Uri.parse(unitAuthorCreateUrl(cfg.baseFor(lib))),
            headers: {
              ...cfg.headersFor(lib),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'lib': lib, 'name': nameCtl.text.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      final j = jsonOf(r);
      if (r.statusCode == 409) throw Exception('该作者目录已存在');
      throwIfApiFailed(r.statusCode, j);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已创建作者目录')));
      await load(quiet: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorText(e))));
    }
  }

  Future<void> loadLibs() async {
    try {
      final meta = await LibMeta.load(cfg.lib);
      if (!mounted) return;
      setState(() {
        metas[cfg.lib] = meta;
      });
      try {
        // 地址与 `lib=`、鉴权头必须同源。此前地址写 `cfg.base`（**激活连接**
        // 的 base），参数与账号却按 `cfg.lib`：用户切过连接但没切库时，
        // 请求打到 A 却问着 B 的库 id，返回 200 但脚本表为空——那个空表
        // 与“这个库确实没有爬虫脚本”完全一样，卡片上的入口看起来就是坏的。
        final cr = await http
            .get(
                Uri.parse(libApiUrl(
                    cfg.baseFor(cfg.lib), '/api/crawler', cfg.lib)),
                headers: cfg.headersFor(cfg.lib))
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
    _syncAvScope();
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
      // 聚合请求的地址与鉴权必须同源，否则切过连接没切库时作者总览整页为空。
      final arScope = cfg.aggregate('/api/authors.json');
      final ar = await http
          .get(arScope.uri, headers: arScope.headers)
          .timeout(const Duration(seconds: 20));
      final sr = await http
          .get(cfg.u('/api/author_stats.json', lib: cfg.lib),
              headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (ar.statusCode != 200) throw Exception(httpErrorText(ar.statusCode));
      // 作者索引可能上千作者：解析放 isolate。
      final m = await parseJsonMapAsync(ar.bodyBytes);
      for (final e in m.entries) {
        final v = mapOrNull(e.value);
        if (v == null) continue;
        final ls = stringsOf(v['libs']);
        // 0.9.293：写入侧原来在五处各写一遍；这里是唯一「没有 libs 时兜到
        // 当前库」的一处，保留语义但走同一个写入函数。
        auMap[e.key] =
            withWorkLib(v, ls.isNotEmpty ? ls.first : cfg.lib);
        if (ls.isNotEmpty) auLibs[e.key] = ls;
      }
      dynamic sj;
      if (sr.statusCode == 200) {
        try {
          sj = jsonOf(sr);
        } catch (_) {}
      }
      final authStats = mapOrNull(sj is Map ? sj['authors'] : null);
      if (authStats != null) {
        for (final e in authStats.entries) {
          final v = mapOrNull(e.value);
          if (v == null) continue;
          stMap['${e.key}'] = v;
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

  Map<String, dynamic> _s(String name) =>
      mapOrNull(stats[name]) ?? const <String, dynamic>{};


  int _metric(MapEntry<String, Map<String, dynamic>> e) {
    final s = _s(e.key);
    switch (sort) {
      case 'visits':
        return intOf(s['v']);
      case 'visited':
        return intOf(s['lv']);
      case 'works':
        return intOf(e.value['n']);
      case 'drops':
        return intOf(s['dr']);
      default:
        return intOf(s['p']);
    }
  }

  /// I7：排序只在数据/排序方式变化时执行一次，结果缓存在 [_ordered]，
  /// build 与滚动回调都只读缓存，避免上千作者反复排序。
  ///
  /// owner 2026-11-19：作者总览不再做顶部筛选，始终展示全部作者；
  /// 分页只用 [_shown] 控制渲染条数，数据不动。
  void _applyOrder({bool resetShown = true}) {
    _ordered = sortAuthorEntries(authors,
        metric: _metric, works: (e) => intOf(e.value['n']), name: (e) => e.key);
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
    // 网格还没排过（首帧前）不预热：拿窗口尺寸顶替一次就会多拉一整行，
    // 而且再也不会被纠正。尺寸一到手 LayoutBuilder 会重排预热。
    final viewport = _gridViewport;
    if (viewport == null) return;
    final mq = MediaQuery.of(context);
    // 几何全部来自 `kAuthorGrid`（与页面 delegate 同一份规格）：此前这里
    // 自己写一遍 150/10/10/170，页面 delegate 再写一遍，改一处就预热到屏幕外。
    final n = kAuthorGrid.prefetchCount(
      viewport,
      // 0.9.292：与网格实际 `padding` 同一常量（`kAuthorGridPagePadding`）。
      padding: kAuthorGridPagePadding,
    );
    if (n <= 0) return;
    // 0.9.289：整条链（空路径排掉 → 地址 → w= → 解码宽度 → 鉴权头）只有
    // `avatar_prefetch.prefetchAvatarItems` 一处，与排行榜那份合流。
    prefetchAvatarItems(
      [
        for (final e in _ordered.take(n))
          (
            path: '${e.value['av'] ?? ''}',
            lib: workLibOf(e.value, fallback: cfg.lib)
          ),
      ],
      limit: n,
      displaySize: AuthorAvatar.gridSize,
      devicePixelRatio: mq.devicePixelRatio,
      urlOf: (path, lib) => cfg.mediaUrl(path, lib: lib),
      headersOf: cfg.headersFor,
    );
  }

  String _fmtDate(int sec) {
    if (sec <= 0) return '未访问';
    // 日期格式化唯一实现在 time_labels：这里以前自己 padLeft 了一份，
    // 且直接 `DateTime.fromMillisecondsSinceEpoch(sec * 1000)`——一个坏的
    // `lv`（服务端写错成毫秒/超大值）会在 build 阶段抛 RangeError。
    final d = yearMonthDayOfSec(sec);
    return d.isEmpty ? '未访问' : d;
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
        return '访问 ${intOf(s['v'])} 次';
      case 'visited':
        return '最近 ${_fmtDate(intOf(s['lv']))}';
      case 'works':
        return '${formatCount(intOf(e.value['n']))} 个作品';
      case 'drops':
        return '水滴 ${intOf(s['dr'])}';
      default:
        return '播放 ${intOf(s['p'])}';
    }
  }

  // T1：为缺头像的作者取一张作品图兜底（每条作者+库只发一次请求）。
  Future<void> _fetchFallbackAvatar(String name, String lib, String idx) async {
    if (!mounted) return;
    // 作用域先归一：请求途中用户切了连接时，这份结果不能再写进新一轮的表
    // （与 `_authorAvatarScope` 的「取发请求时那一份」同一条规则）。
    final scope = authorAvatarScopeKey;
    // 分隔符不在这里手写：`node_key.scopedKey` 是作用域键的唯一拼装口。
    final key = scopedKey(scope, '$lib|$name');
    if (_avLookup.contains(key)) return;
    _avLookup.add(key);
    try {
      final r = await http
          .get(cfg.u('/api/a/$idx.json', lib: lib),
              headers: cfg.headersFor(lib))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return;
      final m = jsonOf(r);
      final pick = pickFallbackAvatar(avatarCandidatesFromWorks(
          [for (final w in listOf(m is Map ? m['works'] : null)) if (w is Map) w]));
      if (pick == null || pick.isEmpty || !mounted) return;
      // 期间连接又变了：这份图属于上一台服务器，不能落到新一轮的表里。
      if (authorAvatarScopeKey != scope) return;
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

  /// 作者页用的元数据：当前库优先，没有就取手里任何一份。
  ///
  /// 这两处（新建作者目录的「基础库下拉」、作者卡词条）此前各写了一遍
  /// `metas[cfg.lib] ?? (metas.isEmpty ? null : metas.values.first)`：
  /// 字节相同的两行，改一处就变成「下拉里可选的基础库」与「卡片上贴的词条」
  /// 来自不同的库——两边都自洽，界面上只是「这个词条怎么不是我这个库的」。
  LibMeta? _metaForAuthorPage() =>
      metas[cfg.lib] ?? (metas.isEmpty ? null : metas.values.first);

  Widget _authorCell(MapEntry<String, Map<String, dynamic>> e) {
    final av = '${e.value['av'] ?? ''}';
    final lib = workLibOf(e.value, fallback: cfg.lib);
    final meta = _metaForAuthorPage();

    // T1：av 优先；没有 av 用作品图兜底；都拿不到才显示首字母占位。
    // 键带作用域：表本身按连接清空，键里再带一次是为了「清理还没跑到」
    // 的那一帧也不会读到上一台服务器的图。
    final fallbackKey =
        scopedKey(authorAvatarScopeKey, '$lib|${e.key}');
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
      works: intOf(e.value['n']),
      subtitle: _sub(e),
      onTap: () => _open(e.key),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作者'), actions: [
        IconButton(
            tooltip: '新建作者目录',
            onPressed: _createAuthor,
            icon: const Icon(Icons.person_add_alt_1_outlined)),
        const HomeAction(),
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
          // 作者总览的网格是 `kAuthorGrid`（150 / 间距 10 / 固定行高 170），
          // 骨架此前按作品网格（180 / 2 / 3:4）铺——加载完成时列数与行高
          // 一起变，整屏重排。骨架必须与被它盖住的那页同一份几何。
          ? const WorkGridSkeleton(
              count: 18, grid: kAuthorGrid, padding: kAuthorGridPagePadding)
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
                              // 播放/访问/水滴都由服务端 `/api/author_stats.json`
                              // 汇总（多设备共用一份），不是「本机」。
                              '$_shownLen/${_ordered.length} 位作者 · 播放/访问/水滴来自服务端',
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
                            // 网格自己的约束即预热几何（`_gridViewport`）。
                            return LayoutBuilder(builder: (context, cons) {
                              if (cons.biggest != _gridViewport) {
                                _gridViewport = cons.biggest;
                                // 帧后发：不在 build 里启动图片请求。
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) {
                                  if (mounted) _prefetchAvatars();
                                });
                              }
                              return GridView.builder(
                                controller: _scroll,
                                padding: kAuthorGridPagePadding,
                                gridDelegate: kAuthorGrid.delegate,
                                itemCount: _shownLen,
                                itemBuilder: (_, i) => _authorCell(_ordered[i]),
                              );
                            });
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

/// 邻页 widget 缓存的键。
///
/// 0.9.293：此前是手拼字符串 `'$i|${it['id']}|$lib|$cover|$memW'`，读取侧
/// 又用 `indexOf('|')` + `substring` 手拆回索引——同一组数据的两种说法，
/// 封面路径里一旦出现 `|` 就拆错。现在键是结构化对象，比较与取索引都由
/// 编译器保证。
class _NeighborKey {
  const _NeighborKey({
    required this.index,
    required this.workId,
    required this.image,
  });

  final int index;
  final String workId;
  final PlayerImage image;

  @override
  bool operator ==(Object other) =>
      other is _NeighborKey &&
      other.index == index &&
      other.workId == workId &&
      other.image == image;

  @override
  int get hashCode => Object.hash(index, workId, image);
}

/// C：PageView 邻页（预载页）。独立 StatefulWidget，State 与已解码封面
/// 在父级 setState 时保留；封面未就绪时用纯黑占位，绝不黑屏闪烁。
class _NeighborPage extends StatefulWidget {
  const _NeighborPage({
    required this.index,
    required this.image,
    this.onAspect,
  });

  final int index;

  /// 邻页封面的唯一参数来源（地址/鉴权头/解码宽度三项同源）。
  final PlayerImage image;

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
    if (widget.image.isEmpty) return;
    try {
      // 0.9.292：探比例必须与渲染用**同一个 provider 形状**。
      // 0.9.293：两边都直接向 `PlayerImage` 要 provider——地址、鉴权头、
      // 解码宽度在构造那一刻就定死，不会「探比例一套、渲染另一套」。
      final provider = widget.image.provider(cacheManager: DiziCache.manager);
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
    if (widget.image.isEmpty) return fallback;
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
            imageUrl: widget.image.url,
            httpHeaders: widget.image.headers,
            memCacheWidth: widget.image.decodeWidth,
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
  // Windows：窗口缩放/最大化期间先拒绝切换全屏，避免 media_kit 在尺寸
  // 变化中重排纹理导致原生崩溃。
  //
  // owner 2026-11-25：「win 版第一次全屏还是会卡一下，不退回去感觉都要
  // 崩溃了」。原因就在下面 `didChangeMetrics`：它只为了让这个标志生效
  // 而调了两次 `setState`，而这个标志**从来没有参与过 build**——每次
  // 窗口尺寸变化（进/出全屏本身就是一次）都白白重建整个播放页，包括
  // 视频舞台与全部浮层。现在它只是 [toggleFs] 读的一个普通字段：写入不
  // 触发重建，语义不变，重建次数为 0。
  bool _winResizing = false;
  Timer? _winResizeTimer;

  /// 切换期间用户又点了全屏：记录最后一次意图，结束后补执行。
  bool? _fsPending;

  bool _taskbarMeasureScheduled = false;
  // C：邻页 widget 复用缓存：同一实例返回给 PageView，setState 时不重建。
  final Map<_NeighborKey, Widget> _neighborPages = <_NeighborKey, Widget>{};

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
  // 每条作品可带 _lib（跨库列表），否则用本页 lib，最后回退当前库。
  // 0.9.293：这个三段兜底与 `WorkGrid._libFor` 此处逐字符相同；现在两者
  // 都转发 `work_lib.workLibOf`（唯一的兜底语义出处）。
  String _libFor(dynamic w) =>
      workLibOf(w, fallback: widget.lib ?? cfg.lib);

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

  /// 播放设置读盘的完成信号。`open()` 会等它，保证起播时用的就是上次的值。
  Future<void>? _prefsReady;
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
    // owner 2026-11-26 追加：「每次退出播放或退出软件后播放设置要沿用上次」。
    //
    // 这里先给默认值保证首帧可用；真正的恢复走 [_prefsReady]，**open() 会等它**
    // ——此前是 `unawaited(_restorePlaybackPrefs())` 与 postFrame 里的 open()
    // 赛跑，恢复晚到时播放器已按默认倍速起播，用户看到的就是「没记忆」。
    speed = AppSettings.defaultSpeed;
    _prefsReady = _restorePlaybackPrefs();
    _ensureMetaFor(_curLib);
    _bindPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus.requestFocus();
      PerfDiagnostics.instance.endSpan(
          'page:player', <String, Object?>{'works': widget.works.length});
      // 先等上次的播放设置读回来，再起播——否则默认倍速会先跑一拍。
      final ready = _prefsReady;
      if (ready != null) {
        unawaited(ready.then((_) {
          if (mounted) open(widget.start);
        }));
      } else {
        open(widget.start);
      }
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
    for (var d = -3; d <= 3; d++) {
      final i = cur + d;
      if (i < 0 || i >= widget.works.length) continue;
      final img = _playerImageFor(i);
      if (img.isEmpty) continue;
      if (d == 0) {
        // 当前条只要那张「网格尺寸」底图：它就是播放页海报的 placeholder，
        // 命中后首帧零等待；从作者页/深链直接进播放页时也能提前缓存。
        // 与 `_posterPreview` 同一个入口（`gridImageProvider`）。
        try {
          precacheImage(
            gridImageProvider(
              cover: img.cover,
              headers: img.headers,
              devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
              cacheManager: DiziCache.manager,
            ),
            context,
            onError: (_, __) {},
          );
        } catch (_) {}
        continue;
      }
      try {
        // 0.9.292/0.9.293：预载的键必须与 `_NeighborPage` 的渲染键相同。
        // 现在两边都从同一个 `PlayerImage` 取三元组（地址/头/宽度），
        // 不可能再出现「预载一个键、渲染另一个键」。
        precacheImage(
          img.provider(cacheManager: DiziCache.manager),
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
    // 只记录「窗口正在变化」，**不 setState**：这个标志不参与 build，
    // 重建整棵播放页（含视频舞台）纯属无谓开销，正是第一次切全屏卡顿
    // 的直接来源。`_winResizing` 唯一的读者是 [toggleFs] 的早退判断。
    _winResizing = true;
    _winResizeTimer?.cancel();
    _winResizeTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      _winResizing = false;
      // 尺寸稳定后补执行「变化期间点过的全屏切换」。此前 toggleFs 在这段
      // 窗口里直接 return，点击被静默吞掉（用户看到的是「按了没反应」）。
      // 已经等于当前状态（例如窗口自己已变成目标态）就把意图清掉，不空转。
      final want = _fsPending;
      if (!_fsBusy && want != null) {
        _fsPending = null;
        if (want != fs) scheduleMicrotask(toggleFs);
      }
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
      at: msFromIso('${w['d'] ?? ''}'),
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
      dropDayLeft = intOf(r['dayLeft'], 1);
      dropWeekLeft = intOf(r['weekLeft'], 3);
      dropTotal = intOf(r['total'], 0);
      gDropDayLeft = intOf(r['gDayLeft'], gDropDayLeft);
      gDropWeekLeft = intOf(r['gWeekLeft'], gDropWeekLeft);
      gDropDayLimit = intOf(r['gDayLimit'], 5);
      gDropWeekLimit = intOf(r['gWeekLimit'], 15);
    });
  }

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
        dropDayLeft = intOf(r['dayLeft'], dropDayLeft);
        dropWeekLeft = intOf(r['weekLeft'], dropWeekLeft);
        dropTotal = intOf(r['total'], dropTotal);
        gDropDayLeft = intOf(r['gDayLeft'], gDropDayLeft);
        gDropWeekLeft = intOf(r['gWeekLeft'], gDropWeekLeft);
        gDropDayLimit = intOf(r['gDayLimit'], gDropDayLimit);
        gDropWeekLimit = intOf(r['gWeekLimit'], gDropWeekLimit);
      } else {
        dropTotal = before;
        dropGlow = false;
      }
    });
    if (r != null && boolOf(r['ok'])) {
      _toast('已送 1 颗小水滴 · 今日剩余 $dropDayLeft · 本周剩余 $dropWeekLeft');
    } else {
      _toast(serverErrorText(r) ?? '发送失败，请检查网络');
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
      // 单图作品的 `m` 可能是字符串（服务端两种写法都出现过）；直接
      // `as List` 会抛 CastError，自动轮播的定时器里没人接，整条播放页卡死。
      final n = workMediaPaths(w).length;
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
    // 单图作品的 `m` 是字符串：只认 List 会让「保存到本机」对这类作品
    // 一律报「暂无可保存的媒体」。
    final paths = workMediaPaths(w);
    final first = paths.isEmpty ? '' : paths.first;
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
      // 下载整条作品文件：内容可能几百 MB，超时按体量放宽（仍要有限，
      // 否则断网时这个 Future 永远不结束，界面一直显示「正在保存…」）。
      final resp = await http
          .get(Uri.parse(url), headers: cfg.headersFor(_libFor(w)))
          .timeout(const Duration(minutes: 5));
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
          unitFraction(_commentFractionNow - d.delta.dy / screenH);
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
          final t = Curves.easeOut.transform(unitFraction(_menuAnim.value));
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
          final scrim = unitFraction(frac / kCommentPanelInitialFraction);
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
    // 窗口正在变化（含刚进/出过全屏的 320ms）：记下意图、等稳定后补执行，
    // 而不是丢弃——丢弃会让人以为按钮坏了，还会让界面状态与真实窗口错位。
    if (Platform.isWindows && _winResizing) {
      _fsPending = next;
      return;
    }
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
      // 同上：`m` 为字符串时 `as List` 会抛异常，方向键切图直接崩。
      final n = workMediaPaths(w).length;
      // 没有可展示图片（封面链断/字段缺失）时 `clamp(0, -1)` 本身会抛。
      if (n == 0) return;
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
    // 固定键位。**空格不在这里**：它在默认绑定里就是 `playPause` 的主键，
    // 也是可以改绑的普通键。
    //
    // 旧实现下面还有一段 `if (k == space) togglePause()`，与自定义绑定表
    // 构成同一键的两条路径：用户把 `playPause` 改绑到别的键之后，空格明明
    // 「未绑定」却仍然暂停（固定分支接住了），与「改绑生效」自相矛盾；
    // 把空格改绑给别的动作时，又有两处都声称拥有这个键。
    // 一个键只能有一条归属：空格属于绑定表，方向键/Esc 属于固定键位。
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
    // owner 2026-11-26：退出播放页时也要落盘播放设置。
    //
    // 此前只有「用户点了某个开关」才写入，退出时什么都不存——所以「退出播放
    // 或退出软件后沿用上次设置」根本不成立：没动过的值从来没被记下来，而
    // 动过的值若在恢复完成前退出，还会被这里的默认值盖掉。
    _persistPlaybackPrefs();
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
  // 0.9.292：公式只有 `decode_plan.screenDecodeWidth` 一处（与图文原图
  // `picView` 同源）——此前这里 `fallback: 360 / clamp(360,2160)`，那里
  // `fallback: 1080 / 无上限`，同一张图在两个页面两个缓存键。
  int _posterDecodeWidth(BuildContext c) => screenDecodeWidth(
        viewportWidth: MediaQuery.sizeOf(c).width,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(c),
      );

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
      urls: standardCoverUrls(
        lib: l,
        mediaUrlOf: cfg.mediaUrl,
        urlOf: cfg.u,
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
      // 与 `WorkCard`、与 `_prefetchNeighborCovers` 同一个入口，缓存键才一致。
      image: gridImageProvider(
        cover: cover,
        headers: cfg.headersFor(lib),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        cacheManager: DiziCache.manager,
      ),
      fit: fit,
      alignment: align,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => const SizedBox.expand(),
    );
  }

  /// 是否已为某条作品建过邻页（决定图文落页时该用哪张「已解码」的底图）。
  bool _neighborPageBuilt(int i) =>
      _neighborPages.keys.any((k) => k.index == i);

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
    final img = _playerImageFor(cur);
    if (img.isEmpty) return const SizedBox.shrink();
    // 只有「底图就是当前这张」才铺，多图作品翻到第二张以后不能拿首图冒充。
    final pageUrl = cfg.mediaUrl(path, lib: lib);
    if (img.url != withImageWidth(pageUrl, kPlayerImageWidth)) {
      return const SizedBox.shrink();
    }
    // 邻页已建 → 用邻页那张（帧尺寸、已解码）；否则退回作品卡的 440px 版本
    // （`gridImageProvider`，与 `_posterPreview` / `_prefetchNeighborCovers` 同源）。
    final ImageProvider provider = _neighborPageBuilt(cur)
        ? img.provider(cacheManager: DiziCache.manager)
        : gridImageProvider(
            cover: img.cover,
            headers: img.headers,
            devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
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
                      builder: (context, _, __) {
                        final av = avatarFor(w);
                        // 0.9.291：播放页这处曾是全 App **第三份**手写头像渲染
                        // （38dp / 自算 memCacheWidth / 自己的错误占位），现在
                        // 与作者总览、排行榜、作者主页、基础库页共用
                        // `author_avatar_view` 的唯一绘制实现。
                        return GestureDetector(
                          // owner 2026-11-21：头像热区必须显式 opaque——图片
                          // 还在加载（占位为空）时中心像素没有可命中对象，
                          // 点击会穿透到舞台被当成暂停。
                          behavior: HitTestBehavior.opaque,
                          onTap: _authorTapOpen,
                          child: AuthorAvatarView(
                            // 必须传剥过 `@` 的名字：占位取首字符，传
                            // `@张三` 会画出 `@`（不剥前缀的第二份解析）。
                            name: authorLabel,
                            mediaPath: av,
                            // 兜底图可能来自作者所在的基础库，按图片自身的库
                            // 路由与鉴权，避免跨库 401 一直显示默认头像。
                            lib: avatarLibOf(av, fallbackLib: _curLib),
                            size: kAvatarPlayerSize,
                            urlOf: (path, {String? lib}) =>
                                cfg.mediaUrl(path, lib: lib),
                            headersOf: ([String? lib]) => cfg.headersFor(lib),
                          ),
                        );
                      },
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

  /// 播放页第 [i] 条作品的封面参数（地址/鉴权头/解码宽度）。
  ///
  /// 0.9.293：这五项此前各自展开——预载、邻页渲染、图文底图、舞台海报、
  /// 裁切预览各拼一遍 `withImageWidth(cover, kPlayerImageWidth)` +
  /// `cfg.headersFor(lib)` + `_posterDecodeWidth(context)`。现在只有这一处
  /// 产 [PlayerImage]，任何一处写错都会立刻在本函数里体现，而不是悄悄
  /// 变成「预载一个缓存键、渲染另一个缓存键」。
  PlayerImage _playerImageFor(int i) {
    final it = _workAt(i);
    final lib = _libFor(it);
    return PlayerImage(
      cover: _posterCoverUrl(it, lib: lib),
      lib: lib,
      headers: cfg.headersFor(lib),
      decodeWidth: _posterDecodeWidth(context),
    );
  }

  /// C：邻页封面页。按作品/封面/解码宽度缓存 widget 实例，
  /// 播放页 setState 时返回同一实例，Element 直接跳过重建。
  Widget _neighborPageFor(int i) {
    final it = _workAt(i);
    final img = _playerImageFor(i);
    // 键里带作品 id：同一位置换了作品（续播追加、过滤变化）必须重建。
    final key = _NeighborKey(
      index: i,
      workId: '${it['id'] ?? ''}',
      image: img,
    );
    return _neighborPages.putIfAbsent(key, () {
      return _NeighborPage(
        index: i,
        image: img,
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
    // 0.9.292：与视频海报同一个公式（`screenDecodeWidth`）——此前这里自己写
    // `fallback: 1080` 且没有上限，宽屏/NaN 时会与海报分叉成两个缓存键。
    final decodeW = screenDecodeWidth(
      viewportWidth: MediaQuery.sizeOf(context).width,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
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
    // 图文也按**作品所属库**取鉴权头：`lib` 参数可能来自另一个服务端的库
    // （跨连接进入的图文作品），拿当前库的账号去取图就是 401，界面显示
    // 「图片加载失败」而文件其实好好的。与视频/海报同一口径 `headersFor`。
    final imgHeaders = cfg.headersFor(lib);
    if (isGifPath(path)) {
      return Image.network(url,
          key: ValueKey('gif-$cur-$img-$_imgReload'),
          headers: imgHeaders,
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
        httpHeaders: imgHeaders,
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
    // 0.9.293：裁切预览与海报同源（同一张图、同一解码宽度），
    // 因此点「裁切封面」时那张大图通常已解码完成，预览不空等。
    final posterImg = PlayerImage(
      cover: _posterCoverUrl(w),
      lib: lib,
      headers: cfg.headersFor(lib),
      decodeWidth: _posterDecodeWidth(context),
    );
    preview ??= posterImg.isEmpty
        ? null
        : posterImg.provider(cacheManager: DiziCache.manager);
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
      final r = await http
          .post(
            cfg.u(req.scope.path, lib: lib),
            headers: {
              ...cfg.headersFor(lib),
              'Content-Type': 'application/json',
            },
            body: jsonEncode(req.toBody()),
          )
          .timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) {
        _toast('${req.failText}：${coverErrorText(r.statusCode)}');
        return;
      }
      _toast(req.doneText);
      // 封面已写入服务端：通知主页/库页重新拉取封面索引，立即显示新封面。
      coverRevision.value++;
    } catch (e) {
      _toast('${req.failText}：${errorText(e)}');
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
                  final dur = formatBadgeDuration(numOrNull(chs[i]['du']));
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
                value: volumeSliderValue(volume, muted: muted),
                max: 100,
                onChanged: _setVolume,
              ),
            ),
          ),
          SizedBox(
            width: 30,
            child: Text(volumePercentShown(volume, muted: muted).toString(),
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
      //
      // owner 2026-11-25：非全屏下移进度层的尝试**已回退**。
      // 那次把 lift 设成 -kScrubHotZoneHeight，整层被推出舞台 Stack 的
      // 裁剪范围，Windows 上进度条直接消失。owner：「算了，进度条回退吧」
      // 「不用改了，原来也挺好的」。
      // 保持原样：非全屏 lift=0（贴舞台底边，与任务栏上缘重合）。
      return _scrubOverlay(
        progress: progress,
        lift: fs ? _taskbarH : 0.0,
      );
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
                // owner 2026-11-25：「windows 版进度条也不能点击跳转」——
                // 桌面端鼠标点击跳转是标准交互，这里补上；**移动端仍然只认
                // 拖动**（手指在细条上点一下多半是误触，不是想跳转）。
                onTapDown: desktop
                    ? (d) => _scrubTapSeek(d.localPosition, width)
                    : null,
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

  /// 指针位置 → 0–1 的进度比例；不可用时返回 null。
  ///
  /// 换算规则只在 [scrubFractionOf] 一处（`player_controls.dart`）：拖动、
  /// 桌面端点按、悬停预览三处共用，避免出现「点按跳得准、拖动跳得偏」。
  double? _scrubFractionOf(Offset p, double width) {
    if (!mounted) return null;
    return scrubFractionOf(p.dx, width);
  }

  void _scrubStart(Offset p, double width) {
    final f = _scrubFractionOf(p, width);
    if (f == null) return;
    _scrubThinTimer?.cancel();
    _scrubFrac = f;
    _scrubFracVN.value = f;
    setState(() => _scrubActive = true);
  }

  void _scrubMove(Offset p, double width) {
    if (!mounted || !_scrubActive) return;
    final next = _scrubFractionOf(p, width);
    if (next == null) return;
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
    _settleScrub(f ?? 0, seek: f != null);
  }

  /// 桌面端点按进度条跳转（owner 2026-11-25）。
  ///
  /// 与拖动松手**共用同一个出口** [\_settleScrub]：比例换算、seek、细条淡出
  /// 三件事只有一份实现，不会出现「点按跳得准、拖动跳得偏」这种两套口径。
  void _scrubTapSeek(Offset p, double width) {
    final f = _scrubFractionOf(p, width);
    if (f == null) return;
    _settleScrub(f);
  }

  /// 进度条跳转的唯一出口：[f] 为 0–1；[seek] 为 false 时只收尾不跳转。
  void _settleScrub(double f, {bool seek = true}) {
    if (!mounted) return;
    if (seek && dur.inMilliseconds > 0) {
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
      // 换算走 [scrubFractionOf]：宽度未知时它返回 null，而旧写法
      // `NaN.clamp(0,1)` 返回 1.0 —— 松手直接跳到片尾。
      final f = scrubFractionOf(p.dx, width);
      if (f == null) return;
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
        dragFrac = scrubFractionOf(p.dx, width);
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
        final f = scrubFractionOf(d.localPosition.dx, width);
        if (f == null) return;
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
          dragFrac = unitFraction((k + 0.5) / pics.length);
        });
      },
      onHorizontalDragUpdate: (d) {
        final f = scrubFractionOf(d.localPosition.dx, width);
        if (f == null) return;
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
        ? unitFraction(pos.inMilliseconds / dur.inMilliseconds)
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
    _neighborPages.removeWhere((k, _) => k.index < cur - 2 || k.index > cur + 2);
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
                        // 0.9.293：海报的三项参数与邻页/预载/图文底图同源。
                        final posterImg = _playerImageFor(cur);
                        final posterCover = posterImg.cover;
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
                                        imageUrl: posterImg.url,
                                        httpHeaders: posterImg.headers,
                                        memCacheWidth: posterImg.decodeWidth,
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
                top: pad.top + kStageToolbarTopOffset,
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
                              value:
                                  volumeSliderValue(volume, muted: muted) / 100.0,
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
                            '${volumePercentShown(volume, muted: muted)}%',
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
      // 下移一行避开返回/主页/封面按钮；数字只有 `kPlayerNoticeTop` 一处。
      top: pad.top + kPlayerNoticeTop,
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
              margin:
                  const EdgeInsets.symmetric(horizontal: kPlayerNoticeMarginX),
              padding: const EdgeInsets.symmetric(
                  horizontal: kPlayerNoticePaddingX,
                  vertical: kPlayerNoticePaddingY),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(kPlayerNoticeRadius),
              ),
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: kPlayerNoticeFontSize, color: Colors.white),
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
              libs = librariesWithDisplayNames(mapsOf(lj['libraries'])
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
    // 推荐池是 `lib=all`（激活连接），鉴权也必须取激活连接那份。
    final scope = cfg.aggregate('/api/recommend?n=$n&seed=$seed');
    final r = await http
        .get(scope.uri, headers: scope.headers)
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw Exception(httpErrorText(r.statusCode));
    final j = jsonOf(r);
    final out = <Map<String, dynamic>>[];
    for (final w in listOf(j is Map ? j['works'] : null)) {
      if (w is! Map) continue;
      final m = Map<String, dynamic>.from(w);
      out.add(withWorkLib(m, workLibOf(m, fallback: cfg.lib)));
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
    final types = await loadAuthorTypes(ids, serverIdOf: cfg.serverIdFor);
    if (!mounted) return;
    setState(() {
      meta = m;
      authorTypes = types;
      typesLoading = false;
    });
  }

  /// 筛选面板选项：只由 `author_filter_options` 一处汇总（本页作用域＝当前库）。
  AuthorFilterOptions get _options =>
      authorFilterOptionsOfMetas(meta == null ? const [] : [meta!]);

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
    final libId = workLibTag(w);
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
    // 汇总一次，四个维度与摘要共用（getter 每次调用都会重新汇总并排序）。
    final opts = _options;
    final res = await showAuthorFilterSheet(
      context: context,
      initial: authorFilter.value,
      basics: opts.basics,
      bigs: opts.bigs,
      units: opts.units,
      tops: opts.tops,
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
    // 摘要要四张名称表；getter 每次调用都会重新汇总 + 排序，这里取一次。
    final opts = _options;
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
                        ? '${authorFilterSummary(authorFilter.value, opts)} · 命中 ${visible.length}/${works.length}'
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
      final list = librariesWithDisplayNames(mapsOf(j['libraries']));
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
            ? (metas[lib]?.filterBasics ?? const <BasicLib>[])
            : (metas[lib]?.basics ?? const <BasicLib>[]);
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
      final key = '${workLibTag(e)}|${w is Map ? w['a'] ?? '' : ''}';
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
  ///
  /// 地址按 `lib` 路由（`cfg.u(..., lib: lib)`），鉴权头也必须按同一个 `lib`
  /// 取。0.9.325 之前这里写的是 `cfg.headers`——那是**当前库**那条连接的账号：
  /// 搜索范围切到另一台服务器上的库时，请求打到 B 却带 A 的密码，全部 401，
  /// 界面上表现为「这个库里一条作品都没有」（空列表与真的没有作品长得一样）。
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
                headers: cfg.headersFor(lib))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) break;
        final j = jsonOf(r);
        final batch = listOf(j is Map ? j['works'] : null);
        ws.addAll(batch);
        offset += batch.length;
        final total =
            j is Map ? intOf(j['total']) : 0;
        if (batch.isEmpty || (total > 0 && offset >= total)) break;
      } catch (_) {
        break;
      }
    }
    return ws;
  }

  // ---- J11：作者筛选（与总览/排行/推荐同一状态与组件） ----

  /// 筛选面板选项：只由 `author_filter_options` 一处汇总（本页作用域＝全部库）。
  AuthorFilterOptions get _options =>
      authorFilterOptionsOfMetas(metas.values.toList());

  bool _matchesFilter(Map<String, dynamic> e, AuthorFilterState f) {
    final w = e['w'];
    if (w is! Map) return false;
    // 0.9.293：`'${e['_lib']}'` 在字段缺失时会得到字面量 "null"——比空串
    // 更难发现（`metas['null']` 取不到，静默退化成「无元数据」）。
    final lib = workLibTag(e);
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
    // 每条库各自属于哪台连接：类型索引缓存与 kinds 都是按 (库, 连接) 存，
    // 两台服务器各有 `lib-1` 时不能共用一份（同 `LibMeta` 的缓存键规则）。
    final map = await loadAuthorTypes(targets, serverIdOf: cfg.serverIdFor);
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
    final opts = _options;
    final res = await showAuthorFilterSheet(
      context: context,
      initial: authorFilter.value,
      basics: opts.basics,
      bigs: opts.bigs,
      units: opts.units,
      tops: opts.tops,
      grades: const ['S', 'A', 'B', 'C', 'D'],
      count: (f) => all.where((e) => _matchesFilter(e, f)).length,
    );
    if (res == null || !mounted) return;
    authorFilter.apply(res);
  }

  @override
  Widget build(BuildContext context) {
    final opts = _options;
    final base = authorFilter.value.isActive
        ? all.where((e) => _matchesFilter(e, authorFilter.value)).toList()
        : all;
    // 搜索词与被搜字段都走 [foldForMatch]（全角折叠 + 小写）：
    // 中文输入法下打出的全角字母/数字/括号与半角是同一个字，此前这里用裸
    // `contains`——搜「ＡＢ」搜不到标题里的「AB」，同一个搜索框在作者页能命中、
    // 在这里不能。只用于比较，标题与作者名本身不改写。
    final k = foldForMatch(kw);
    final res = k.isEmpty
        ? const []
        : base.where((e) {
            final w = e['w'];
            return foldForMatch('${w['ti']}').contains(k) ||
                foldForMatch('${w['a']}').contains(k);
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
              ? '${authorFilterSummary(authorFilter.value, opts)} · 命中 ${res.length}/${all.length}'
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
                          if (e['w'] is Map)
                            {
                              ...mapOrNull(e['w'])!,
                              '_lib': workLibTag(e),
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
///
/// 守卫必须判 `isFinite`，只判 `<= 0` 拦不住 NaN/Infinity：实测
/// `avatarCropDisplaySize(Size(1000,500), double.nan, 1)` 返回
/// `Size(NaN, NaN)`、`viewSide == infinity` 返回 `Size(infinity, infinity)`。
/// 这两个值会直接进 `SizedBox(width:, height:)` —— 无界宽度让父级布局断言
/// 失败，NaN 则让 `RawImage` 整块不画（真机表现是裁剪页一片黑，日志无异常）。
Size avatarCropDisplaySize(Size image, double viewSide, double zoom) {
  if (!image.width.isFinite ||
      !image.height.isFinite ||
      !viewSide.isFinite ||
      image.width <= 0 ||
      image.height <= 0 ||
      viewSide <= 0) {
    return Size.zero;
  }
  final z = avatarCropClampZoom(zoom);
  final scale = max(viewSide / image.width, viewSide / image.height) * z;
  final w = image.width * scale;
  final h = image.height * scale;
  if (!w.isFinite || !h.isFinite) return Size.zero;
  return Size(w, h);
}

/// 平移夹紧：显示尺寸超出视窗的一半即上限，另一方向不许移动。
///
/// `max(0.0, NaN)` **返回 NaN**（不是 0），随后 `clamp(-NaN, NaN)` 得到一个
/// NaN 偏移——`Transform.translate` 拿到它以后整张图不画。显示尺寸或视窗
/// 非有限时按「没有可平移空间」处理，偏移归零。
Offset avatarCropClampOffset(Offset offset, Size display, double viewSide) {
  if (!display.width.isFinite ||
      !display.height.isFinite ||
      !viewSide.isFinite) {
    return Offset.zero;
  }
  final mx = max(0.0, (display.width - viewSide) / 2);
  final my = max(0.0, (display.height - viewSide) / 2);
  final dx = offset.dx.isFinite ? offset.dx : 0.0;
  final dy = offset.dy.isFinite ? offset.dy : 0.0;
  if (!mx.isFinite || !my.isFinite) return Offset.zero;
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
    r = await http
        .get(cfg.u('/api/author-grade.json', lib: lib),
            headers: cfg.headersFor(lib))
        .timeout(const Duration(seconds: 10));
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
    r = await http
        .post(
          cfg.u('/api/author/avatar', lib: libId),
          headers: {
            ...cfg.headersFor(libId),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'lib': libId,
            'author': author,
            'data': base64Encode(pngBytes),
          }),
        )
        .timeout(const Duration(seconds: 30));
  } catch (e) {
    return AuthorEditResult(false, '上传失败：${errorText(e)}');
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
    r = await http
        .post(
          cfg.u('/api/author/bio', lib: libId),
          headers: {
            ...cfg.headersFor(libId),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'lib': libId, 'author': author, 'bio': clean}),
        )
        .timeout(const Duration(seconds: 15));
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
    r = await http
        .post(
          cfg.u(kAuthorAvatarSetPath, lib: libId),
          headers: {
            ...cfg.headersFor(libId),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(authorAvatarSetBody(
              lib: libId, author: author, file: file)),
        )
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    return AuthorEditResult(false, '设置头像失败：${errorText(e)}');
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
    r = await http
        .post(
          cfg.u(kAuthorAvatarSetPath, lib: libId),
          headers: {
            ...cfg.headersFor(libId),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(authorAvatarClearBody(lib: libId, author: author)),
        )
        .timeout(const Duration(seconds: 20));
  } catch (e) {
    return AuthorEditResult(false, '清除头像失败：${errorText(e)}');
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
      if (mounted) setState(() => _error = '图片解码失败：${errorText(e)}');
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
        ..showSnackBar(SnackBar(content: Text('生成头像失败：${errorText(e)}')));
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

/// 一个库的作者主页取数结果（`AuthorPage.load` 的并发单元）。
///
/// 只有「索引命中 + 作者卡 200」才算 [ok]；其余（索引无此人、非 200、
/// 异常）都是一个「这个库没有该作者」的确定答案，不进合并也不发访问上报。
/// 四个字段按 `_libs` 顺序先到先得，与改造前串行版语义一致。
class _AuthorLibFetch {
  final String lib;
  final bool ok;
  final List<Map<String, dynamic>> works;
  final String uid;
  final String bio;
  final String av;

  const _AuthorLibFetch({
    required this.lib,
    required this.works,
    required this.uid,
    required this.bio,
    required this.av,
  }) : ok = true;

  const _AuthorLibFetch.failed(this.lib)
      : ok = false,
        works = const <Map<String, dynamic>>[],
        uid = '',
        bio = '',
        av = '';
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

  /// 平台稳定标识（抖音 `sec_uid`）。
  ///
  /// owner 2026-11-26：「新增 uid 显示，有爬虫的库作者页标注平台 uid，
  /// 无则留空」。只有服务端索引里带 `uid` 时才显示（爬虫同步过的库才有）。
  ///
  /// owner 2026-11-27 追加用途：本机手动头像改按 uid 存，作者改名后仍能找到。
  String platformUid = '';

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
  /// owner 2026-11-27：按挂载的作者文件夹筛选。
  /// 取值为 `<库>\u0001<@目录>`（[AuthorDirOption.key]）；空串 = 全部目录。
  String dirFilter = '';
  /// 目录筛选项缓存：只在 `_refreshFilter` 重算，build 不重扫作品。
  List<({AuthorDirOption option, int count})> _dirChoices = const [];
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
  ///
  /// owner 2026-11-27：带上平台 uid 一起查——作者在平台改名后，服务端已按
  /// uid 并成一个人，而本机覆盖可能还是旧名字的键。不传 uid 就只查名字，
  /// 行为与旧版一致。
  String get manualAv =>
      AuthorAvatarStore.instance.pathFor(widget.name, uid: platformUid) ?? '';

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
              // 0.9.291：库归属判断只有 `libFromMediaPath` 一处（同义写法
              // 此前在本文件出现四份，四份各自决定兜底库）。
              final l = libFromMediaPath(p, fallbackLib: primaryLib);
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
                    await AuthorAvatarStore.instance.clear(widget.name, uid: platformUid);
                    if (!mounted) return;
                    setState(() {
                      if (r.path.isNotEmpty) av = r.path;
                    });
                    authorAvatarRevision.value++;
                    _toast(r.message);
                    return;
                  }
                  // 头像目录里的文件但扩展名服务端不收（gif/heic/avif/bmp）：
                  // 旧行为是静默走「只存本机」，点完没有任何说明，用户以为
                  // 跨设备生效了。这里按可注册性分开提示（不进 white list 的
                  // 判定仍只有 `isServerAvatarFileName` 一处）。
                  final localOnly = isServerAvatarDirPath(p);
                  final ok = await AuthorAvatarStore.instance
                      .setPath(widget.name, p, uid: platformUid);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop();
                  if (!mounted) return;
                  authorAvatarRevision.value++;
                  setState(() {});
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(
                        content: Text(!ok
                            ? '这张图不能作头像'
                            : localOnly
                                ? '已设为头像（该格式服务端不收，仅本机生效）'
                                : '已设为该作者头像')));
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
                        displaySize: kAvatarCandidateSize,
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
      _toast('打开文件选择器失败：${errorText(e)}');
      return;
    }
    if (picked == null) return;
    List<int> bytes;
    try {
      bytes = await picked.readAsBytes();
    } catch (e) {
      _toast('读取图片失败：${errorText(e)}');
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
    await AuthorAvatarStore.instance.clear(widget.name, uid: platformUid);
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
    await AuthorAvatarStore.instance.clear(widget.name, uid: platformUid);
    if (!mounted) return;
    setState(() => av = _crawledAv);
    authorAvatarRevision.value++;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已恢复自动头像')));
  }

  /// owner 2026-11-25：作者文件夹挂载入口（作者主页）。
  ///
  /// owner 原话：「这套机制怎么想挂载入口也应该在作者主页吧，单元库点进去
  /// 再选哪个作者吗？搞笑」。挂载是**作者维度**的操作——打开某个人，才该
  /// 看到他在哪些基础库/文件夹里、是否已合并。
  ///
  /// 地址与鉴权头必须同源（与作品、头像、简介同一口径）。
  ///
  /// 0.9.334：此前写的是 `base: cfg.base` + `headers: cfg.headersFor(lib)`——
  /// 地址取**当前连接**、账号取**作者所属库那条连接**。从另一台服务器的
  /// 单元库进入作者页时（`primaryLib` 属于 B，`cfg.base` 还是 A），面板是
  /// 拿 A 的地址配 B 的密码去问挂载列表：401 或空列表，而“这个作者没有
  /// 任何挂载”与“请求本身发错了”长得一模一样，界面上看不出区别。
  Future<void> _openAuthorMount() async {
    final lib = primaryLib.isEmpty ? cfg.lib : primaryLib;
    await showAuthorMountSheet(
      context: context,
      authorName: widget.name,
      base: cfg.baseFor(lib),
      headers: cfg.headersFor(lib),
    );
    // 面板里可能做过合并/拆分：关掉后一律重载，不依赖它是否回传结果
    // （用户也可能中途按返回键关掉，那条路径不会有返回值）。
    if (!mounted) return;
    await load();
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
    // 同上：目录可能被合并/拆分/移动，旧的目录选择不一定还存在。
    dirFilter = '';
    // 各库作品先分别收齐，再统一交给 mergeAuthorWorks 合并。
    //
    // 之前这里是「边拉边用 seen 集合去重」——与 author_merge.dart 里那份
    // 带单测的合并规则是同一件事的第二份实现。两份实现的好处是零，代价是
    // 改规则时必然漏一处：这里改了就与单测脱节，单测绿着、真实路径却是另一套。
    // 现在只保留一份：按 _libs 顺序传入，先到先得 = 主库优先，语义不变。
    //
    // 0.9.331：**每库两条请求改为有界并发**。此前是串行 `for` + 两次 `await`：
    // 作者被合并到 N 个单元库时就是 N 次完整往返（各 20s 上限），页面一直
    // 白等到最慢那个库，而每个库的请求彼此独立。`mapConcurrent` 保序，
    // 因此下面「先到先得」的 `bio/av/uid/primaryLib` 仍由 `_libs` 顺序决定。
    final fetched = await mapConcurrent<String, _AuthorLibFetch>(_libs, 4,
        (lib) async {
      try {
        final r = await http
            .get(cfg.u('/api/authors.json', lib: lib),
                headers: cfg.headersFor(lib))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) return _AuthorLibFetch.failed(lib);
        final idx = jsonMapOf(r);
        // 服务端作者索引存在 `作者` / `@作者` 两种键；名字可能来自作品 `a`
        // 或媒体路径里的 `%40作者`。统一按裸名匹配，避免「进页后空白」。
        final info = authorInfoFromIndex(idx, widget.name);
        if (info == null) return _AuthorLibFetch.failed(lib);
        final d = await http
            .get(cfg.u('/api/a/${info['i']}.json', lib: lib),
                headers: cfg.headersFor(lib))
            .timeout(const Duration(seconds: 20));
        if (d.statusCode != 200) return _AuthorLibFetch.failed(lib);
        final m = jsonOf(d);
        // 本库作品打上 `_lib` 后整批交给合并器；去重与顺序由它保证。
        return _AuthorLibFetch(
          lib: lib,
          works: [
            for (final w in listOf(m is Map ? m['works'] : null))
              if (w is Map) withWorkLib(w, lib),
          ],
          uid: '${info['uid'] ?? ''}'.trim(),
          bio: '${m is Map ? (m['bio'] ?? '') : ''}',
          av: '${m is Map ? (m['av'] ?? '') : ''}',
        );
      } catch (_) {
        return _AuthorLibFetch.failed(lib);
      }
    });
    final perLib = <List<Map<String, dynamic>>>[];
    for (final f in fetched) {
      if (!f.ok) continue;
      if (platformUid.isEmpty) platformUid = f.uid;
      if (bio.isEmpty) bio = f.bio;
      if (av.isEmpty) av = f.av;
      if (primaryLib.isEmpty) primaryLib = f.lib;
      perLib.add(f.works);
      postStat('visit', widget.name, lib: f.lib);
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
    // K3：手动名单按库拉取并缓存，刷新后重取。同样逐库独立 → 有界并发。
    final manual = <String>{};
    final manualLibs = _libs.toSet().toList();
    final manualParts = await mapConcurrent<String, Set<String>>(
        manualLibs, 4, (l) => fetchManualWorkIds(l));
    for (final part in manualParts) {
      manual.addAll(part);
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

  String _libOfWork(dynamic w) => workLibOf(w, fallback: primaryLib);

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
    final st = intOf(j['status']);
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
          if (!serviceSaidOk(j)) {
            errors.add(_deleteFailureText(j));
            continue;
          }
          files += intOf(j['count']);
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
          if (j != null && serviceSaidOk(j)) {
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
        final paths = workMediaPaths(w);
        final media = paths.isEmpty ? '' : paths.first;
        if (isMediaPath(media)) {
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
      _toast('读取目录失败：${errorText(e)}');
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
        if (dry == null || !serviceSaidOk(dry)) {
          errors.add(serverErrorText(dry) ?? '网络错误');
          continue;
        }
        final j = await postWorkMove(lib, id, target, confirm: true);
        if (j != null && serviceSaidOk(j)) {
          done++;
        } else {
          errors.add(serverErrorText(j) ?? '网络错误');
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
    // owner 2026-11-27：目录筛选放在来源库之前——目录本身已带库信息，
    // 先按目录收敛后剩下的来源库选项只会是同一批。
    final dir = _dirFilterOption;
    if (dir != null) {
      scoped = filterWorksByAuthorDir(
        scoped,
        lib: dir.lib,
        authorDir: dir.authorDir,
        fallbackLib: primaryLib,
      );
    }
    final byLib = filterWorksByLib(
      scoped,
      lib: libFilter,
      fallbackLib: primaryLib,
    );
    filteredWorks = filterWorksByType(byLib, typeFilter);
    typeCounts = workTypeCounts(works);
    // 目录筛选项与上面同一轮重算：作品集合变了（合并/拆分/刷新）才重扫一次。
    final dirs = authorDirOptionsOfWorks(works, fallbackLib: primaryLib);
    _dirChoices = dirs.length > 1 ? dirs : const [];
  }

  /// 当前选中的目录筛选项（未选/已失效 → null）。
  AuthorDirOption? get _dirFilterOption {
    final want = dirFilter.trim();
    if (want.isEmpty) return null;
    for (final o in _dirChoices) {
      if (o.option.key == want) return o.option;
    }
    return null;
  }

  /// 是否横跨多个库（决定目录词条带不带库名前缀）。
  bool get _dirsSpanLibs {
    final libs = <String>{};
    for (final o in _dirChoices) {
      libs.add(o.option.lib);
    }
    return libs.length > 1;
  }

  /// 目录词条文案：`[库名 · ]@目录 条数`。
  String _dirLabel(AuthorDirOption o, int count, {required bool showLib}) {
    if (!showLib) return '${o.authorDir} $count';
    final lib = o.lib.isEmpty ? '未知库' : libLabel(o.lib);
    return '$lib · ${o.authorDir} $count';
  }

  /// 作品 → 所属顶级单元库 id；拿不到返回空串（不猜）。
  String _topOfWork(dynamic raw) {
    if (raw is! Map) return '';
    final m = meta;
    if (m == null) return '';
    var basic = '${raw['_bid'] ?? ''}'.trim();
    if (basic.isEmpty) {
      final libId = workLibTag(raw);
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
  ///
  /// 0.9.347：遍历与回落规则收进 `LibMeta.topLabelFor` —— 删除监测页那份
  /// 与这里逐字相同，两页同一个媒体库必须显示同一个名字。
  String _topLabel(String id) => meta?.topLabelFor(id) ?? id;

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

  /// 目录筛选（库 + `@目录`）：空串 = 全部目录。
  ///
  /// 换目录时把来源库选择归零：目录已经限定了库，留着旧的库选择会出现
  /// 「点了目录还是空列表」而两个选中词条互相矛盾。
  void _setDirFilter(String key) {
    if (dirFilter == key) return;
    setState(() {
      dirFilter = key;
      libFilter = '';
      _refreshFilter();
    });
  }

  /// 基础库展示名：优先当前库元数据里的名称，其次 id 本身。
  ///
  /// 只在多库合并时用（单库不显示筛选条），所以查不到名称时直接给 id 也能读。
  String libLabel(String id) {
    for (final b in (meta?.allBasics ?? const <BasicLib>[])) {
      if (b.id == id) {
        return displayLibraryName(b.id, b.name);
      }
    }
    for (final b in (meta?.basics ?? const <BasicLib>[])) {
      if (b.id == id) return displayLibraryName(b.id, b.name);
    }
    return displayLibraryName(id, id);
  }

  // 点击头像放大查看（可双指缩放，点任意处关闭）；长按设置/清除手动头像。
  void _showAvatar(BuildContext context) {
    final src = effectiveAv;
    if (src.isEmpty) return;
    final srcLib = libFromMediaPath(src, fallbackLib: primaryLib);
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
          // 0.9.291：作者主页收起栏的等级词条曾是**第三份手写**（圆角 4、
          // 底色 18% 透明度、字号 11/w700），与其它页的等级词条不同。
          // 现共用同一个组件：等级词条在全 App 只能有一种长相。
          AuthorBadgeRow(grade: grade),
        ]),
      );
    }
    return Padding(
      // 与加载骨架（`_AuthorPageSkeleton`）读同一个常量：两处都写 14 时，
      // 改一处就会让「加载完成」那一刻整块信息区横向跳一下。
      padding: const EdgeInsets.all(kAuthorHeaderPadding),
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
            const SizedBox(width: kAuthorHeaderAvatarGap),
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
                    // owner 2026-11-26：这个作者分布在几个基础库，就贴几条
                    // 词条（他挂了几处文件夹一目了然），不再只贴主库一条。
                    basicIds: _libs,
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
                  // 平台 uid：只有爬虫同步过的库才带；拿不到就整行不显示
                  // （owner：「无则留空」，不猜、不用作者名冒充）。
                  if (platformUid.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        const Text('平台 UID',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            platformUid,
                            key: const ValueKey('author-platform-uid'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                                fontFeatures: [FontFeature.tabularFigures()]),
                          ),
                        ),
                        InkWell(
                          onTap: () async {
                            await Clipboard.setData(
                                ClipboardData(text: platformUid));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已复制 UID')));
                          },
                          borderRadius: BorderRadius.circular(4),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.copy, size: 13, color: Colors.grey),
                          ),
                        ),
                      ]),
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
        // owner 2026-11-25：作者文件夹挂载入口放在作者主页（不是单元库页）。
        // 挂载是作者维度的事：打开某人才看得到他分布在哪些库/文件夹。
        // 单个库的作者也可能需要并入别处，所以不受 loading/多选状态限制。
        IconButton(
          key: const ValueKey('author-mount-btn'),
          tooltip: '作者文件夹挂载（这个作者在哪些库/文件夹）',
          icon: const Icon(Icons.folder_shared_outlined),
          onPressed: _openAuthorMount,
        ),
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
              // owner 2026-11-27：按挂载的作者文件夹筛选。
              //
              // 合并后的作者把各目录的作品并成一列，「这条来自哪个目录」
              // 界面上原本没有出口。作者只挂一处（常态）时整行不出现。
              if (_dirChoices.isNotEmpty)
                HorizontalChipBar(
                  key: const ValueKey('author-dir-filter'),
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    Center(
                      child: FilterChip(
                          label: Text('全部文件夹 ${works.length}',
                              style: const TextStyle(fontSize: 12)),
                          selected: _dirFilterOption == null,
                          showCheckmark: false,
                          onSelected: (_) => _setDirFilter('')),
                    ),
                    for (final o in _dirChoices)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Center(
                          child: FilterChip(
                              key: ValueKey('author-dir-${o.option.key}'),
                              // 多库时才带库名前缀：两个库各有一个同名
                              // `@目录` 时，两条一模一样的词条点哪个都像错的。
                              label: Text(
                                  _dirLabel(o.option, o.count,
                                      showLib: _dirsSpanLibs),
                                  style: const TextStyle(fontSize: 12)),
                              selected: dirFilter == o.option.key,
                              showCheckmark: false,
                              onSelected: (_) => _setDirFilter(o.option.key)),
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

// 网格骨架：**与真实网格同一份几何**（0.9.300 · 第七十三批）。
//
// 此前这里写死 `EdgeInsets.all(12)` 与 `kWorkGrid`：
//
// ```
// 骨架  GridView(padding: EdgeInsets.all(12),       delegate: kWorkGrid)
// 真网格 GridView(padding: workGridPadding(context), delegate: kWorkGrid)  ← 竖向安全区
// ```
//
// 手机上有 24–80dp 的竖向安全区，于是「加载完成」那一刻整屏卡片向下跳一截、
// 列宽也变（all(12) 的左右 12 vs 真网格左右 0 + 安全区），不是渐入而是一次重排。
// 两处都「各自算得出一个内边距」，所以既不报错也没有第二份实现可对比。
//
// 现在骨架屏收两个参数：网格规格与页面内边距，默认值就是作品网格 + 真实网格
// 用的那个 `workGridPadding`；作者总览页传 `kAuthorGrid`（骨架必须与被它盖住的
// 那页同一个网格，否则加载完成时列数/行高一起变）。
class WorkGridSkeleton extends StatelessWidget {
  final int count;

  /// 骨架要模仿的网格规格；默认作品网格。
  final LibGridSpec grid;

  /// 页面内边距；为空时用作品网格的真实内边距（[workGridPadding]）。
  final EdgeInsets? padding;

  const WorkGridSkeleton({
    super.key,
    this.count = 18,
    this.grid = kWorkGrid,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return _SkeletonPulse(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        // 与 `WorkGrid._buildGrid` 同一个出口：骨架屏不得自己挑内边距。
        padding: padding ?? workGridPadding(context),
        gridDelegate: grid.delegate,
        itemCount: count,
        itemBuilder: (_, __) => const SkeletonBlock(radius: BorderRadius.zero),
      ),
    );
  }
}

// 作者主页骨架：头像/简介占位 + 作品网格
//
// 0.9.306：这条骨架此前自己写了一遍头部几何（`all(14)` / 64 / 圆形 `32`
// / 间距 12），与真实头部（`kAuthorHeaderPadding` + `AuthorAvatar.headerSize`）
// 是两份。头像尺寸一改，骨架就按旧尺寸铺，加载完成那一刻头部整块换成另一个
// 高度。现在四处都读 `card_metrics` 的同一组常量。
class _AuthorPageSkeleton extends StatelessWidget {
  const _AuthorPageSkeleton();

  @override
  Widget build(BuildContext context) {
    return _SkeletonPulse(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(kAuthorHeaderPadding),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SkeletonBlock(
                width: kAvatarHeaderSize,
                height: kAvatarHeaderSize,
                radius: BorderRadius.all(
                    Radius.circular(kAvatarHeaderSize / 2))),
            const SizedBox(width: kAuthorHeaderAvatarGap),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    // 三个宽度在 `card_metrics` 立了名：它们只描述占位块的
                    // 相对长短，不对应真实文字宽度（那是 Expanded 里的换行文本）。
                    SkeletonBlock(
                        width: kAuthorHeaderLineShort, height: 10),
                    SizedBox(height: 10),
                    SkeletonBlock(
                        width: kAuthorHeaderLineMedium, height: 12),
                    SizedBox(height: 8),
                    SkeletonBlock(width: kAuthorHeaderLineLong, height: 12),
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

  /// 网格自己的可用尺寸（0.9.300）。
  ///
  /// 此前预热拿 `MediaQuery.size`（整个窗口）：作者主页的网格上面压着
  /// AppBar + 可折起的信息头 + 几条筛选条，实际可用高度常只有窗口的
  /// 六成——按窗口算「两屏」就会多预热四成看不见的封面（每张都要真发一次
  /// 请求），而「算出来多少」和「真实排多少」两处各自都算得通，所以不报错。
  ///
  /// 现在尺寸来自网格自己的 `LayoutBuilder`：预热与排布同一份约束。
  /// 布局阶段只写字段、不 `setState`（与作者页头部测量同一做法）。
  Size? _gridViewport;

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
    // 尺寸未知（首帧还没经过 `LayoutBuilder`）时先不预热，也不记「已预热」：
    // 否则会用窗口尺寸顶替一次，再也不会被纠正。
    if (_gridViewport == null) return;    _prefetchedFor = works;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchFirstScreen();
    });
  }

  void _prefetchFirstScreen() {
    final works = widget.works;
    if (works.isEmpty) return;
    // 网格尺寸未知（首帧前）不预热：拿窗口尺寸顶替一次就会多拉一整行，
    // 而且 `_prefetchedFor` 已经记下「这份列表预热过了」，再也不会被纠正。
    final viewport = _gridViewport;
    if (viewport == null) return;
    final mq = MediaQuery.of(context);
    // 0.9.288：整条链只有 `work_card_prefetch.prefetchWorkCovers` 一处
    // （与 `basic_lib_page` 共用）。本网格只负责「取哪些作品」与「按作品
    // 各自的库取鉴权头」——收藏夹/搜索/推荐可能跨库，headers 必须随图走，
    // 与 `WorkCard.headers` 一致，缓存键才对得上。
    prefetchWorkCovers(
      // 几何与 `_buildGrid` 的 delegate / padding 同源（`kWorkGrid` +
      // `workGridPadding`）：此前这里写 `EdgeInsets.zero`，而网格实际拿到
      // 的是 `ScrollView` 自补安全区后的那一份——首屏行数多算，末行预热
      // 的是屏幕外那张封面。
      // 网格自己的尺寸，不是窗口尺寸：作者主页/搜索页的网格上方还有整块
      // 头部与筛选条，按窗口算会把屏幕外的一整行也预热进来。
      viewport: viewport,
      grid: kWorkGrid,
      padding: workGridPadding(context),
      devicePixelRatio: mq.devicePixelRatio,
      // 惰性 `map`：作者主页/收藏夹可能上千条，但只预热首屏那 24 张。
      // 写成列表字面量会先为每一条跑 `workCoverUrl` + 拼两份标准地址。
      items: works.map((w) {
        final lib = _libFor(w);
        return (
          cover: workCoverUrl(
            w,
            lib: lib,
            urls: standardCoverUrls(
              lib: lib,
              mediaUrlOf: cfg.mediaUrl,
              urlOf: cfg.u,
            ),
          ),
          headers: cfg.headersFor(lib),
        );
      }),
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
      workLibOf(w, fallback: widget.lib ?? cfg.lib);

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
    // 网格自己的约束既是排布依据，也是预热的几何来源（`_gridViewport`）。
    return LayoutBuilder(builder: (context, cons) {
      final size = cons.biggest;
      if (size != _gridViewport) {
        _gridViewport = size;
        // 首帧尺寸到手后才排预热；这里只登记，帧后执行。
        _schedulePrefetch();
      }
      return _gridContent(context, works, shown);
    });
  }

  Widget _gridContent(BuildContext context, List<dynamic> works, int shown) {
    return GridView.builder(
      controller: _scroll,
      // 与 `_prefetchFirstScreen` 的 `padding:` 同一个出口。
      padding: workGridPadding(context),
      gridDelegate: kWorkGrid.delegate,
      itemCount: shown,
      itemBuilder: (_, i) {
        final w = works[i];
        final lib = _libFor(w);
        // 封面统一走 work_cover：th → 图文首图 → 视频抽帧（带版本参数避开旧缓存）
        final cover = workCoverUrl(
          w,
          lib: lib,
          urls: standardCoverUrls(
            lib: lib,
            mediaUrlOf: cfg.mediaUrl,
            urlOf: cfg.u,
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
              // owner 2026-11-26：「多选作品打开后为什么点击对应作品右上角的
              // 那个圆圈内区域不能选中该作品，点击作品卡本身其他地方是有效的」。
              //
              // 根因：这个圆圈只是个装饰 `Container`，没有任何点击处理。它盖在
              // 卡片之上，点到它就落在圆圈上、事件不会传给下面卡片的 `onTap`，
              // 于是「点圆圈没反应，点别处有效」。
              //
              // 现在圆圈自己接点击；同时把命中区放大到 ≥44dp（视觉仍是 22dp），
              // 手指不用瞄准一个小圆点。
              child: GestureDetector(
                key: ValueKey('work-select-circle-$wid'),
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onToggleSelect?.call(wid),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 6),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black45,
                          border:
                              Border.all(color: Colors.white70, width: 1.5),
                        ),
                        child: selected
                            ? const Icon(Icons.check,
                                size: 15, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
                ),
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
