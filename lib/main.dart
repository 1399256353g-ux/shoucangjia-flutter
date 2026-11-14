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
import 'author_grade.dart';
import 'background_pause.dart';
import 'collection_sync.dart';
import 'continue_watching.dart';
import 'cover_badges.dart';
import 'deleted_cover.dart';
import 'emoji_text.dart';
import 'library_badge.dart';
import 'library_rank.dart';
import 'likes.dart';
import 'playback_flow.dart';
import 'pic_zoom.dart';
import 'playback_error.dart';
import 'text_fit.dart';
import 'volume_control.dart';
import 'playback_menu.dart';
import 'preload_plan.dart';
import 'swipe_control.dart';
import 'watch_progress.dart';

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
  Map<String, String> get headers => {
        'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
      };
  // lib 省略时用当前库；显式传入可查询其他库
  Uri u(String path, {String? lib}) {
    final l = lib ?? this.lib;
    if (base.isEmpty || l.isEmpty) return Uri.parse('$base$path');
    final sep = path.contains('?') ? '&' : '?';
    return Uri.parse('$base$path${sep}lib=${Uri.encodeQueryComponent(l)}');
  }

  // 媒体路径统一带库前缀：/media/<lib>/<相对路径>
  String media(String p, {String? lib}) {
    final l = lib ?? this.lib;
    if (l.isEmpty || !p.startsWith('/media/')) return p;
    final rest = p.substring(7);
    if (rest.startsWith('$l/')) return p;
    return '/media/${Uri.encodeComponent(l)}/$rest';
  }
}

final cfg = Cfg();
final navKey = GlobalKey<NavigatorState>();

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

// 所有收藏夹页面共用：确认后同步全部收藏夹（NAS 后台），完成后回调刷新
Future<void> syncAllCollectionsFlow(BuildContext context,
    {Future<void> Function()? onFinished}) async {
  if (cfg.base.isEmpty) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('立即同步所有收藏夹'),
      content: const Text('将同步全部收藏夹的最新作品，并刷新封面、索引与作者信息。\n\n'
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
        content: Text(exit == 0 ? '所有收藏夹同步完成' : '同步结束（退出码 $exit），请查看日志')));
  }
  if (onFinished != null) await onFinished();
}

// 同步全部收藏夹进度：后台任务在 NAS 上运行，这里只轮询状态
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
      title: const Text('正在同步所有收藏夹'),
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
    cfg.base = sp.getString('base') ?? '';
    cfg.user = sp.getString('user') ?? 'zzx';
    cfg.pass = sp.getString('pass') ?? '';
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
  late final TextEditingController base = TextEditingController(
      text: cfg.base.isEmpty ? 'http://192.168.2.4:8090' : cfg.base);
  late final TextEditingController user = TextEditingController(text: cfg.user);
  late final TextEditingController pass = TextEditingController(text: cfg.pass);
  bool testing = false;
  bool? testOk;
  String testMsg = '';

  static String normalize(String raw) {
    var b = raw.trim().replaceAll(RegExp(r'/+$'), '');
    if (b.isEmpty) return b;
    if (!b.startsWith('http://') && !b.startsWith('https://')) {
      b = 'http://' + b;
    }
    return b;
  }

  Map<String, String> get _fieldHeaders => {
        'Authorization': 'Basic '
            '${base64Encode(utf8.encode('${user.text.trim()}:${pass.text}'))}',
      };

  Future<void> test() async {
    final b = normalize(base.text);
    if (b.isEmpty) return;
    setState(() {
      testing = true;
      testOk = null;
      testMsg = '';
    });
    final sw = Stopwatch()..start();
    try {
      final r = await http
          .get(Uri.parse('$b/api/index.json'), headers: _fieldHeaders)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final cols = (jsonDecode(r.body)['collections'] as List?)?.length ?? 0;
      sw.stop();
      if (mounted) {
        setState(() {
          testOk = true;
          testMsg = '连接成功 · $cols 个收藏夹 · ${sw.elapsedMilliseconds}ms';
        });
      }
    } catch (e) {
      sw.stop();
      if (mounted) {
        setState(() {
          testOk = false;
          testMsg = '连接失败：$e';
        });
      }
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Future<void> save() async {
    final b = normalize(base.text);
    cfg.base = b;
    cfg.user = user.text.trim();
    cfg.pass = pass.text;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base', cfg.base);
    await sp.setString('user', cfg.user);
    await sp.setString('pass', cfg.pass);
    if (mounted) {
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      } else {
        nav.pushReplacement(
            MaterialPageRoute(builder: (_) => const HomePage()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('网络连接')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: base,
            decoration: const InputDecoration(
                labelText: 'NAS 地址', hintText: 'http://192.168.2.4:8090')),
        const SizedBox(height: 12),
        TextField(
            controller: user,
            decoration: const InputDecoration(labelText: '用户名')),
        const SizedBox(height: 12),
        TextField(
            controller: pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码')),
        const SizedBox(height: 20),
        Row(children: [
          OutlinedButton.icon(
            onPressed: testing ? null : test,
            icon: testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.network_check),
            label: Text(testing ? '测试中…' : '测试连接'),
          ),
        ]),
        if (testMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              Icon(testOk == true ? Icons.check_circle : Icons.error_outline,
                  size: 16,
                  color: testOk == true ? Colors.green : Colors.redAccent),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(testMsg,
                      style: TextStyle(
                          fontSize: 12,
                          color: testOk == true
                              ? Colors.green
                              : Colors.redAccent))),
            ]),
          ),
        const SizedBox(height: 16),
        FilledButton(onPressed: save, child: const Text('保存并连接')),
        const SizedBox(height: 8),
        const Text('地址留空将回到首次连接页；支持 http/https，自动补全 http://。',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
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
      final list = ((j['libraries'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
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
    final name = '${l['name'] ?? id}';
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
  // 等级词条（D–S），空串表示不显示
  final String grade;
  const LibBadges({
    super.key,
    required this.libIds,
    this.order = const [],
    this.names = const {},
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
            color: labels[i].startsWith('+')
                ? const Color(0xFF6B7280).toARGB32()
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
          title: const Text('网络连接'),
          subtitle: Text(cfg.base.isEmpty ? '未设置' : cfg.base),
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
          title: const Text('收藏夹同步选择'),
          subtitle: const Text('账号全部收藏夹 · 勾选参与同步，未勾选不在主页显示'),
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
      // 默认收藏夹必须保持勾选：关闭时自动改选第一个仍参与同步的收藏夹
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
        title: const Text('重命名收藏夹'),
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
        title: const Text('删除收藏夹'),
        content: Text('将从 App 中移除「${c.name}」，清除该收藏夹的索引数据并关闭同步。\n\n'
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
      appBar: AppBar(title: const Text('收藏夹同步选择'), actions: [
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
              tooltip: '立即同步所有收藏夹',
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
                  ? const Center(child: Text('没有收藏夹'))
                  : Column(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(children: [
                          const Icon(Icons.info_outline,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                                '账号共 $accountCount 个收藏夹 · $enabled 个参与同步。'
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
                                              child: Text('设为默认收藏夹')),
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
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<Map<String, dynamic>> libs = [];
  String? defaultId;
  bool loading = true;
  String? err;
  bool changed = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Uri _u(String path, [String? lib]) {
    final sep = path.contains('?') ? '&' : '?';
    return Uri.parse(
        '${cfg.base}$path${sep}lib=${Uri.encodeQueryComponent(lib ?? cfg.lib)}');
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final r = await http
          .get(_u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final list = ((j['libraries'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        libs = list;
        defaultId = '${j['default'] ?? ''}';
      });
    } catch (e) {
      if (mounted) setState(() => err = '$e');
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _switchTo(Map<String, dynamic> l) async {
    cfg.lib = '${l['id']}';
    cfg.libName = fixDisplayName('${l['name'] ?? l['id']}');
    final sp = await SharedPreferences.getInstance();
    await sp.setString('lib', cfg.lib);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _setDefault(Map<String, dynamic> l) async {
    try {
      final r = await http.post(_u('/api/libraries/default'),
          headers: {...cfg.headers, 'Content-Type': 'application/json'},
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
      final r = await http.post(_u('/api/libraries/delete'),
          headers: {...cfg.headers, 'Content-Type': 'application/json'},
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
      final r = await http.post(_u('/api/libraries'),
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
              icon: const Icon(Icons.add), onPressed: _add, tooltip: '添加库'),
        ]),
        body: err != null
            ? Center(child: Text('加载失败：$err'))
            : loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: libs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final l = libs[i];
                      final id = '${l['id']}';
                      final isCur = id == cfg.lib;
                      final isDef = id == defaultId;
                      final cr = (l['crawler'] as Map?) ?? const {};
                      final scripts =
                          (l['crawlerScripts'] as List?) ?? const [];
                      return ListTile(
                        leading: Icon(
                            isCur
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: isCur ? Colors.amber : Colors.grey),
                        title: Text('${l['name']}  ${isDef ? '★' : ''}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '$id · ${l['count'] ?? 0} 条 / ${l['cols'] ?? 0} 个收藏夹',
                                style: const TextStyle(fontSize: 12)),
                            Text('${l['base']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            Text(
                                '爬虫：${cr['enabled'] == true ? '已启用' : '未启用'} · ${cr['schedule'] ?? '04:10'} · 脚本 ${scripts.length} 个 · ${(l['indexOk'] == true) ? '索引正常' : '索引缺失'}',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: l['indexOk'] == true
                                        ? Colors.grey
                                        : Colors.redAccent)),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'default') _setDefault(l);
                            if (v == 'crawler') {
                              Navigator.of(context)
                                  .push(MaterialPageRoute(
                                      builder: (_) =>
                                          CrawlerConfigPage(lib: l)))
                                  .then((_) => load());
                            }
                            if (v == 'maint') {
                              Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => MaintenancePage(lib: l)));
                            }
                            if (v == 'delete') _delete(l);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                                value: 'default', child: Text('设为默认库')),
                            const PopupMenuItem(
                                value: 'crawler', child: Text('爬虫配置')),
                            const PopupMenuItem(
                                value: 'maint', child: Text('维护检查')),
                            const PopupMenuItem(
                                value: 'delete', child: Text('删除库（保留文件）')),
                          ],
                        ),
                        onTap: () {
                          changed = changed || !isCur;
                          _switchTo(l);
                        },
                      );
                    },
                  ),
      ),
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

  Uri _u(String path) =>
      Uri.parse('${cfg.base}$path?lib=${Uri.encodeQueryComponent(libId)}');

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
          .get(_u('/api/crawler'), headers: cfg.headers)
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
          headers: {...cfg.headers, 'Content-Type': 'application/json'},
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
                  TextFormField(
                    initialValue: schedule,
                    decoration: const InputDecoration(
                        labelText: '每日执行时间（HH:MM）', hintText: '04:10'),
                    onChanged: (v) => schedule = v,
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Expanded(child: Text('间隔（分钟，0 = 仅按时间）')),
                    Text('$intervalMin'),
                  ]),
                  Slider(
                    value: intervalMin.toDouble().clamp(0, 1440),
                    min: 0,
                    max: 1440,
                    divisions: 48,
                    onChanged: (v) => setState(() => intervalMin = v.round()),
                  ),
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
  Uri _u(String path) =>
      Uri.parse('${cfg.base}$path?lib=${Uri.encodeQueryComponent(libId)}');

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
              headers: cfg.headers)
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
          headers: {...cfg.headers, 'Content-Type': 'application/json'},
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
    return '收藏夹${e['idx']} · ${e['id']} · $kind · ${e['reason']}';
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
                  _row('作品/收藏夹',
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List cols = [];
  final Map<String, String> covers = {};
  String? err;
  int? defaultIdx;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final libsR = await http
          .get(cfg.u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (libsR.statusCode == 200) {
        final lj = jsonDecode(libsR.body) as Map<String, dynamic>;
        final ls = ((lj['libraries'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        Map<String, dynamic>? pick;
        for (final e in ls) {
          if (e['id'] == cfg.lib) {
            pick = e;
            break;
          }
        }
        if (pick == null) {
          for (final e in ls) {
            if (e['id'] == lj['default']) {
              pick = e;
              break;
            }
          }
        }
        if (pick == null && ls.isNotEmpty) pick = ls.first;
        if (pick != null) {
          final changed = cfg.lib != pick['id'];
          cfg.lib = '${pick['id']}';
          cfg.libName = fixDisplayName('${pick['name'] ?? cfg.lib}');
          if (changed) {
            final sp = await SharedPreferences.getInstance();
            await sp.setString('lib', cfg.lib);
          }
        }
      }
      final rs = await Future.wait([
        http.get(cfg.u('/api/index.json'), headers: cfg.headers),
        http.get(cfg.u('/api/settings'), headers: cfg.headers),
      ]);
      final r = rs[0];
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      var list = (jsonDecode(r.body)['collections'] as List);
      if (rs[1].statusCode == 200) {
        final p = jsonDecode(rs[1].body) as Map<String, dynamic>;
        defaultIdx = (p['default'] as num?)?.toInt();
        final prefs = (p['collections'] as List?) ?? const [];
        final merged = <Map<String, dynamic>>[];
        for (final raw in prefs) {
          final pc = Map<String, dynamic>.from(raw as Map);
          if (pc['deleted'] == true) continue;
          final i = (pc['idx'] as num).toInt();
          Map<String, dynamic>? base;
          for (final c in list) {
            if ((c['idx'] as num).toInt() == i) {
              base = Map<String, dynamic>.from(c as Map);
              break;
            }
          }
          if (base == null) continue;
          merged.add({
            ...base,
            'name': fixDisplayName('${pc['name'] ?? base['name'] ?? ''}'),
            'sync': pc['sync'] != false,
          });
        }
        for (final c in list) {
          final i = (c['idx'] as num).toInt();
          if (!merged.any((m) => (m['idx'] as num).toInt() == i)) {
            merged.add({...Map<String, dynamic>.from(c as Map), 'sync': true});
          }
        }
        list = merged;
      }
      // 索引里的收藏夹名同样做一次 emoji 修复（含仅用索引的回退分支）。
      list = [
        for (final c in list)
          if (c is Map)
            {
              ...Map<String, dynamic>.from(c),
              'name': fixDisplayName('${c['name'] ?? c['idx'] ?? ''}'),
            }
          else
            c
      ];
      setState(() => cols = list);
      for (final c in list) {
        // 已抓到合集封面的直接使用，其余回退到首条作品封面
        if ((c['cover'] ?? '').toString().isNotEmpty) continue;
        http
            .get(cfg.u('/api/c/${c['idx']}.json'), headers: cfg.headers)
            .then((rr) {
          if (rr.statusCode != 200) return;
          final ws = (jsonDecode(rr.body)['works'] as List);
          if (ws.isEmpty) return;
          final t = (ws[0]['th'] ?? '').toString();
          if (t.isNotEmpty && mounted) {
            setState(() => covers['${c['idx']}'] = t);
          }
        }).catchError((_) {});
      }
    } catch (e) {
      setState(() => err = '$e');
    }
  }

  void openDefault() {
    final i = cols.indexWhere(
        (c) => defaultIdx != null && (c['idx'] as num).toInt() == defaultIdx);
    if (i < 0) return;
    final c = cols[i];
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CollectionPage(name: c['name'], idx: c['idx'])));
  }

  /// G17：点「继续观看」回到原收藏夹列表的同一作品续播；
  /// 收藏夹失效/作品已删除时退化为单条播放，仍按记录位置续播。
  Future<void> _openContinue(ContinueItem it) async {
    final lib = it.lib.isEmpty ? cfg.lib : it.lib;
    List works = [];
    if (it.idx > 0) {
      try {
        final r = await http
            .get(cfg.u('/api/c/${it.idx}.json', lib: lib), headers: cfg.headers)
            .timeout(const Duration(seconds: 10));
        if (r.statusCode == 200) {
          final j = jsonDecode(r.body);
          if (j is Map) works = (j['works'] as List?) ?? [];
        }
      } catch (_) {}
    }
    var start =
        works.indexWhere((w) => w is Map && '${w['id'] ?? ''}' == it.id);
    if (start < 0) {
      works = [
        {
          'id': it.id,
          'ti': it.title,
          'a': it.author,
          'th': it.thumb,
          't': it.type,
        }
      ];
      start = 0;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(
              works: works,
              start: start,
              lib: lib,
              idx: it.idx > 0 ? it.idx : null,
              colName: it.collection,
            )));
  }

  // 星标：点击卡片右上角设为/取消默认收藏夹，真正写回服务端
  Future<void> _setDefault(int idx) async {
    final next = defaultIdx == idx ? null : idx;
    try {
      final r = await http.post(cfg.u('/api/settings'),
          headers: {...cfg.headers, 'Content-Type': 'application/json'},
          // 只提交默认项；服务端保留其余收藏夹的勾选状态与名称
          body: jsonEncode({'default': next}));
      final m = jsonDecode(r.body);
      if (!mounted) return;
      setState(() => defaultIdx = (m['default'] as num?)?.toInt());
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next == null ? '已取消默认收藏夹' : '已设为默认收藏夹')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('设置失败：$e')));
    }
  }

  Future<void> _openLibrary() async {
    final changed = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const LibraryPage()));
    if (changed == true) await load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
          // H10：当前库名与媒体库入口合并为一个按钮，并与右侧功能按钮分隔
          titleSpacing: 4,
          title: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Material(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                key: const ValueKey('lib-selector'),
                onTap: _openLibrary,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    Icon(Icons.library_books_outlined,
                        size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 6),
                    Flexible(
                        child: Text(cfg.libName.isEmpty ? '抖音收藏夹' : cfg.libName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600))),
                    const Icon(Icons.arrow_drop_down, size: 20),
                  ]),
                ),
              ),
            ),
          ),
          actions: [
            IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: '刷新收藏夹',
                onPressed: load),
            // 与「库选择」分隔：右侧为功能按钮/设置
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 1,
                color: theme.dividerColor.withValues(alpha: 0.6),
              ),
            ),
            if (defaultIdx != null)
              IconButton(
                  icon: const Icon(Icons.star, color: Colors.amber),
                  tooltip: '打开默认收藏夹',
                  onPressed: openDefault),
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
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SearchPage()))),
            IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SettingsHubPage()));
                  load();
                }),
            if (cfg.lib == 'douyin')
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz),
                tooltip: '更多',
                onSelected: (v) async {
                  if (v == 'sync-all') {
                    await syncAllCollectionsFlow(context, onFinished: load);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'sync-all', child: Text('立即同步所有收藏夹')),
                ],
              ),
          ]),
      body: err != null
          ? Center(child: Text('加载失败：$err'))
          : cols.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  _ContinueWatchingStrip(onOpen: _openContinue),
                  Expanded(child: LayoutBuilder(builder: (context, cons) {
                    final w = cons.maxWidth;
                    final n = w >= 1200
                        ? 5
                        : w >= 900
                            ? 4
                            : w >= 620
                                ? 3
                                : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: n,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.72,
                      ),
                      itemCount: cols.length,
                      itemBuilder: (_, i) {
                        final c = cols[i];
                        final idx = (c['idx'] as num).toInt();
                        final remote = (c['cover'] ?? '').toString();
                        final fallback = covers['$idx'];
                        final imageUrl = remote.isNotEmpty
                            ? cfg.u(remote).toString()
                            : (fallback == null
                                ? null
                                : cfg.base + cfg.media(fallback));
                        final isDefault =
                            defaultIdx != null && idx == defaultIdx;
                        return _CollectionTile(
                          idx: idx,
                          name: '${c['name']}',
                          count: c['count'] is num
                              ? (c['count'] as num).toInt()
                              : null,
                          imageUrl: imageUrl,
                          isDefault: isDefault,
                          syncOff: c['sync'] == false,
                          onStarTap: () => _setDefault(idx),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => CollectionPage(
                                      name: '${c['name']}', idx: idx))),
                        );
                      },
                    );
                  })),
                ]),
    );
  }
}

/// G17：主页顶部「继续观看」横向列表；没有记录时完全不占位。
class _ContinueWatchingStrip extends StatelessWidget {
  final void Function(ContinueItem) onOpen;
  const _ContinueWatchingStrip({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
        valueListenable: ContinueWatchingStore.revision,
        builder: (context, _, __) {
          final items = ContinueWatchingStore.items;
          if (items.isEmpty) return const SizedBox.shrink();
          final theme = Theme.of(context);
          return SizedBox(
            height: 158,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                child: Row(children: [
                  Icon(Icons.play_circle_outline,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text('继续观看',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${items.length} 条',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) =>
                      _ContinueTile(item: items[i], onOpen: onOpen),
                ),
              ),
            ]),
          );
        });
  }
}

class _ContinueTile extends StatelessWidget {
  final ContinueItem item;
  final void Function(ContinueItem) onOpen;
  const _ContinueTile({required this.item, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = item.thumb.isEmpty
        ? null
        : cfg.base + cfg.media(item.thumb, lib: item.lib);
    return SizedBox(
      width: 172,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onOpen(item),
          onLongPress: () {
            ContinueWatchingStore.remove(item.lib, item.id);
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('已从「继续观看」移除')));
          },
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 86,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                cover == null
                    ? Container(color: Colors.black26)
                    : CachedNetworkImage(
                        imageUrl: cover,
                        httpHeaders: cfg.headers,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.black26)),
                // 底部渐变 + 位置文案
                const DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black54],
                            stops: [0.45, 1]))),
                Positioned(
                    left: 6,
                    bottom: 4,
                    child: Text(
                        formatContinueLabel(item.positionMs, item.durationMs),
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w600))),
                Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(item.isVideo ? '视频' : '图文',
                            style: const TextStyle(
                                fontSize: 9, color: Colors.white)))),
                // 观看进度
                Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                        height: 2,
                        child: LinearProgressIndicator(
                            value: item.fraction,
                            backgroundColor: Colors.white24,
                            minHeight: 2))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Text(item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
              child: Text(
                  [
                    if (item.collection.trim().isNotEmpty)
                      item.collection.trim(),
                    if (item.author.trim().isNotEmpty) item.author.trim(),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// 收藏夹图片卡片：大封面 + 底部渐变信息，默认收藏夹用金色星标
class _CollectionTile extends StatelessWidget {
  final int idx;
  final String name;
  final int? count;
  final String? imageUrl;
  final bool isDefault;
  final bool syncOff;
  final VoidCallback onTap;
  final VoidCallback? onStarTap;
  const _CollectionTile({
    required this.idx,
    required this.name,
    required this.count,
    required this.imageUrl,
    required this.isDefault,
    required this.syncOff,
    required this.onTap,
    this.onStarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl == null)
              const Center(
                  child: Icon(Icons.collections_bookmark_outlined,
                      color: Colors.white24, size: 36))
            else
              CachedNetworkImage(
                imageUrl: imageUrl!,
                httpHeaders: cfg.headers,
                fit: BoxFit.cover,
                memCacheWidth: 720,
                fadeInDuration: const Duration(milliseconds: 180),
                placeholder: (_, __) => Container(color: Colors.black26),
                errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white24)),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.45, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('$idx',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.white70)),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
              child: Tooltip(
                message: isDefault ? '取消默认收藏夹' : '设为默认收藏夹',
                child: InkWell(
                  onTap: onStarTap,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(isDefault ? Icons.star : Icons.star_border,
                        color: isDefault ? Colors.amber : Colors.white38,
                        size: 20),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(fixDisplayName(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDefault ? Colors.amber : Colors.white)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(count == null ? '' : '$count 作品',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.white70)),
                      if (syncOff) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4)),
                          child: const Text('同步已关闭',
                              style: TextStyle(
                                  fontSize: 9, color: Colors.orangeAccent)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CollectionPage extends StatefulWidget {
  final String name;
  final int idx;
  const CollectionPage({super.key, required this.name, required this.idx});
  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  List works = [];
  List deleted = [];
  Map<String, dynamic> authorsIndex = {};
  String filter = 'all';
  String sort = 'new';
  bool searching = false;
  String kw = '';
  final TextEditingController _q = TextEditingController();

  bool _match(Map w) {
    if (kw.isEmpty) return true;
    final k = kw.toLowerCase();
    return '${w['ti'] ?? ''}'.toLowerCase().contains(k) ||
        '${w['a'] ?? ''}'.toLowerCase().contains(k);
  }

  List get view {
    var v = List.from(works.where((w) => _match(w as Map)));
    if (filter == 'v') v = v.where((w) => w['t'] == 'v').toList();
    if (filter == 'p') v = v.where((w) => w['t'] == 'p').toList();
    if (sort == 'old') {
      v.sort((a, b) => '${a['d']}'.compareTo('${b['d']}'));
    } else if (sort == 'title') {
      v.sort((a, b) => '${a['ti']}'.compareTo('${b['ti']}'));
    } else {
      v.sort((a, b) => '${b['d']}'.compareTo('${a['d']}'));
    }
    return v;
  }

  List get deletedView => deleted.where((d) => _match(d as Map)).toList();

  void _openAuthor(String name) {
    if (name.isEmpty) return;
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AuthorPage(name: name)));
  }

  void _previewCover(String path, String title) {
    if (path.isEmpty) return;
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
              imageUrl: cfg.base + cfg.media(path),
              httpHeaders: cfg.headers,
              fit: BoxFit.contain,
              placeholder: (_, __) =>
                  const CircularProgressIndicator(color: Colors.white38),
              errorWidget: (_, __, ___) =>
                  Text(title, style: const TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }

  // 已删除作品行：封面预览 + 跳转作者主页（回库查看该作者其他作品）
  Widget _deletedTile(Map d) {
    final cov = deletedCoverPath(d, authorsIndex);
    final name = '${d['a'] ?? ''}';
    final at = '${(d['at'] ?? '').toString().split('T').first}';
    return InkWell(
      onTap: name.isEmpty ? null : () => _openAuthor(name),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: cov.isEmpty
                ? null
                : () => _previewCover(cov, '${d['ti'] ?? ''}'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 64,
                height: 84,
                child: cov.isEmpty
                    ? Container(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Icon(Icons.image_not_supported_outlined,
                            size: 20,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant))
                    : CachedNetworkImage(
                        imageUrl: cfg.base + cfg.media(cov),
                        httpHeaders: cfg.headers,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest),
                        errorWidget: (_, __, ___) => Container(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: Icon(Icons.broken_image_outlined,
                                size: 20,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant))),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${d['ti'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text('@$name · ${d['d'] ?? ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 2),
                Text('抖音平台已删除${at.isEmpty ? '' : ' · $at'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: Colors.orangeAccent)),
              ])),
          const SizedBox(width: 8),
          SizedBox(
            height: 84,
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              OutlinedButton(
                  onPressed: name.isEmpty ? null : () => _openAuthor(name),
                  style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10)),
                  child: const Text('跳转', style: TextStyle(fontSize: 12))),
            ]),
          ),
        ]),
      ),
    );
  }

  Timer? syncTimer;
  bool syncing = false;

  @override
  void dispose() {
    syncTimer?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      searching = !searching;
      if (!searching) {
        kw = '';
        _q.clear();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await http.get(cfg.u('/api/c/${widget.idx}.json'),
          headers: cfg.headers);
      if (r.statusCode != 200) return;
      final m = jsonDecode(r.body);
      if (!mounted) return;
      setState(() {
        works = (m['works'] as List);
        deleted = (m['deleted'] as List?) ?? [];
      });
    } catch (_) {}
    // 作者索引用于「已删除」列表回退显示头像；失败不影响主列表
    try {
      final a =
          await http.get(cfg.u('/api/authors.json'), headers: cfg.headers);
      if (a.statusCode == 200) {
        final m = jsonDecode(a.body);
        if (m is Map && mounted) {
          setState(() => authorsIndex = Map<String, dynamic>.from(m));
        }
      }
    } catch (_) {}
  }

  Future<void> _syncNow() async {
    if (syncing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('立即同步'),
        content: Text('将从抖音同步「${widget.name}」的最新作品，并刷新封面与索引。\n\n'
            '同步在 NAS 后台运行，可能需要几分钟；期间可继续浏览。'),
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
    final j = await startServerSync(target: 'collection', idx: widget.idx);
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
          .showSnackBar(const SnackBar(content: Text('已开始同步，完成后自动刷新')));
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
            content: Text(code == 0 ? '同步完成' : '同步结束（退出码 $code），请查看日志')));
      }
      await load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = view;
    final dels = deletedView;
    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                controller: _q,
                autofocus: true,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                    hintText: '在本收藏夹内搜索标题或作者', border: InputBorder.none),
                onChanged: (v) => setState(() => kw = v.trim()),
              )
            : Text(widget.name),
        actions: [
          if (cfg.lib == 'douyin')
            IconButton(
                icon: const Icon(Icons.cloud_sync),
                tooltip: '立即同步所有收藏夹',
                onPressed: syncing
                    ? null
                    : () => syncAllCollectionsFlow(context, onFinished: load)),
          IconButton(
              icon: syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_sync_outlined),
              tooltip: syncing ? '同步中…' : '立即同步',
              onPressed: syncing ? null : _syncNow),
          IconButton(
              icon: Icon(searching ? Icons.close : Icons.search),
              tooltip: searching ? '关闭搜索' : '在本收藏夹搜索',
              onPressed: _toggleSearch),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            onSelected: (v) => setState(() => sort = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('最新在前')),
              PopupMenuItem(value: 'old', child: Text('最早在前')),
              PopupMenuItem(value: 'title', child: Text('按标题')),
            ],
          ),
        ],
      ),
      body: works.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(children: [
                  ChoiceChip(
                      label: const Text('全部'),
                      selected: filter == 'all',
                      onSelected: (_) => setState(() => filter = 'all')),
                  const SizedBox(width: 8),
                  ChoiceChip(
                      label: const Text('视频'),
                      selected: filter == 'v',
                      onSelected: (_) => setState(() => filter = 'v')),
                  const SizedBox(width: 8),
                  ChoiceChip(
                      label: const Text('图文'),
                      selected: filter == 'p',
                      onSelected: (_) => setState(() => filter = 'p')),
                  const SizedBox(width: 8),
                  ChoiceChip(
                      label: const Text('已删除'),
                      selected: filter == 'del',
                      onSelected: (_) => setState(() => filter = 'del')),
                  const Spacer(),
                  if (searching && kw.isNotEmpty)
                    Text('命中 ${filter == 'del' ? dels.length : list.length}',
                        style: const TextStyle(color: Colors.grey))
                  else
                    Text('${filter == 'del' ? deleted.length : list.length}',
                        style: const TextStyle(color: Colors.grey)),
                ]),
              ),
              Expanded(
                child: filter == 'del'
                    ? (dels.isEmpty
                        ? Center(
                            child: Text(kw.isNotEmpty ? '无匹配的已删除作品' : '暂无已删除记录',
                                style: const TextStyle(color: Colors.grey)))
                        : Column(children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: Text('本地文件已清理，预览退回作者头像；点「跳转」回库查看该作者其他作品',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                            ),
                            Expanded(
                              child: ListView.separated(
                                itemCount: dels.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) =>
                                    _deletedTile(dels[i] as Map),
                              ),
                            ),
                          ]))
                    : (list.isEmpty && kw.isNotEmpty
                        ? Center(
                            child: Text('无匹配作品：$kw',
                                style: const TextStyle(color: Colors.grey)))
                        : WorkGrid(
                            works: list,
                            collectionIdx: widget.idx,
                            collectionName: widget.name,
                          )),
              ),
            ]),
    );
  }
}

// 排行榜：按周/月/年/总统计作者播放量或小水滴
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
  bool loading = true;
  String? err;

  @override
  void initState() {
    super.initState();
    sel = widget.initialLib ?? cfg.lib;
    loadLibs();
    load();
  }

  Future<void> loadLibs() async {
    try {
      final r = await http
          .get(cfg.u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final list = ((j['libraries'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted || list.isEmpty) return;
      var next = sel;
      var changed = false;
      if (next.isEmpty ||
          (next != 'all' && !list.any((e) => e['id'] == next))) {
        next = '${j['default'] ?? list.first['id']}';
        changed = next != sel;
      }
      setState(() {
        libs = list;
        if (changed) {
          sel = next;
          loading = true;
        }
      });
      if (changed) load();
    } catch (_) {}
  }

  Future<void> load() async {
    if (mounted) setState(() => err = null);
    try {
      final r = await http.get(
          cfg.u('/api/rank?period=$period&metric=$metric',
              lib: sel.isEmpty ? null : sel),
          headers: cfg.headers);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(r.body);
      if (!mounted) return;
      setState(() {
        rows = (j is Map && j['authors'] is List) ? j['authors'] as List : [];
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
    return Scaffold(
      appBar: AppBar(title: const Text('排行榜'), actions: [
        IconButton(
            tooltip: '刷新', onPressed: load, icon: const Icon(Icons.refresh)),
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
                  label: const Text('全部库'),
                  selected: sel == 'all',
                  onSelected: (_) {
                    if (sel == 'all') return;
                    setState(() {
                      sel = 'all';
                      loading = true;
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
                      ? Center(
                          child: Text(
                              metric == 'drop'
                                  ? '本期还没有小水滴，去播放页送一颗吧'
                                  : '本期还没有播放记录',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12)))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final e = rows[i] is Map
                                ? Map<String, dynamic>.from(rows[i] as Map)
                                : <String, dynamic>{};
                            final name = '${e['name'] ?? ''}';
                            final av = '${e['avatar'] ?? ''}';
                            final score = _n(e['score']);
                            return ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                        width: 30,
                                        child: Text('${i + 1}',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    _rankColor(context, i)))),
                                    ClipOval(
                                      child: SizedBox(
                                        width: 42,
                                        height: 42,
                                        child: av.isEmpty
                                            ? Container(
                                                color: Colors.blueGrey,
                                                alignment: Alignment.center,
                                                child:
                                                    Text(name.isEmpty ? '?' : name[0],
                                                        style: const TextStyle(
                                                            fontSize: 18)))
                                            : CachedNetworkImage(
                                                imageUrl: cfg.base +
                                                    cfg.media(av,
                                                        lib: sel == 'all'
                                                            ? '${e['lib'] ?? cfg.lib}'
                                                            : sel),
                                                httpHeaders: cfg.headers,
                                                fit: BoxFit.cover,
                                                memCacheWidth: 126,
                                                errorWidget: (_, __, ___) => Container(
                                                    color: Colors.blueGrey,
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                        name.isEmpty
                                                            ? '?'
                                                            : name[0],
                                                        style: const TextStyle(
                                                            fontSize: 18)))),
                                      ),
                                    ),
                                  ]),
                              title: Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '播放 ${_n(e['plays'])} · 水滴 ${_n(e['drops'])} · ${_n(e['works'])} 作品',
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
      final list = ((j['libraries'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

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
  List<Map<String, dynamic>> libs = [];
  String sel = '';
  final Map<String, List<String>> authorLibs = {};
  String sort = 'plays';
  bool loading = true;
  String? err;
  bool syncing = false;
  Timer? syncTimer;

  @override
  void initState() {
    super.initState();
    sel = cfg.lib;
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
    syncTimer?.cancel();
    super.dispose();
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
      final r = await http
          .get(cfg.u('/api/libraries'), headers: cfg.headers)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final list = ((j['libraries'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted || list.isEmpty) return;
      var next = sel;
      var changed = false;
      if (next.isEmpty ||
          (next != 'all' && !list.any((e) => e['id'] == next))) {
        next = '${j['default'] ?? list.first['id']}';
        changed = next != sel;
      }
      setState(() {
        libs = list;
        if (changed) {
          sel = next;
          loading = true;
        }
      });
      if (changed) load();
    } catch (_) {}
  }

  Future<void> load() async {
    if (mounted) setState(() => err = null);
    final targets = sel == 'all'
        ? libs.map((e) => '${e['id']}').toList()
        : [(sel.isEmpty ? cfg.lib : sel)];
    if (targets.isEmpty) targets.add(cfg.lib);
    final auMap = <String, Map<String, dynamic>>{};
    final stMap = <String, Map<String, dynamic>>{};
    authorLibs.clear();
    try {
      for (final lib in targets) {
        final rs = await Future.wait([
          http.get(cfg.u('/api/authors.json', lib: lib), headers: cfg.headers),
          http.get(cfg.u('/api/author_stats.json', lib: lib),
              headers: cfg.headers),
        ]);
        if (rs[0].statusCode != 200) continue;
        final m = jsonDecode(rs[0].body) as Map<String, dynamic>;
        dynamic sj;
        if (rs[1].statusCode == 200) {
          try {
            sj = jsonDecode(rs[1].body);
          } catch (_) {}
        }
        for (final e in m.entries) {
          if (e.value is! Map) continue;
          final v = Map<String, dynamic>.from(e.value as Map);
          final old = auMap[e.key];
          if (old == null) {
            auMap[e.key] = {...v, '_lib': lib};
          } else {
            old['n'] = _num(old['n']) + _num(v['n']);
            if ('${old['av'] ?? ''}'.isEmpty && '${v['av'] ?? ''}'.isNotEmpty) {
              old['av'] = v['av'];
            }
            if ('${old['bio'] ?? ''}'.isEmpty &&
                '${v['bio'] ?? ''}'.isNotEmpty) {
              old['bio'] = v['bio'];
            }
          }
          (authorLibs[e.key] ??= []).add(lib);
        }
        if (sj is Map && sj['authors'] is Map) {
          for (final e in (sj['authors'] as Map).entries) {
            if (e.value is! Map) continue;
            final v = Map<String, dynamic>.from(e.value as Map);
            final o = stMap['${e.key}'] ?? <String, dynamic>{};
            for (final f in ['p', 'v', 'dr']) {
              o[f] = _num(o[f]) + _num(v[f]);
            }
            o['lv'] =
                _num(o['lv']) > _num(v['lv']) ? _num(o['lv']) : _num(v['lv']);
            stMap['${e.key}'] = o;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        authors = auMap.entries.map((e) => MapEntry(e.key, e.value)).toList();
        stats = stMap;
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

  List<MapEntry<String, Map<String, dynamic>>> get sorted {
    final list = List.of(authors);
    list.sort((a, b) {
      final c = _metric(b).compareTo(_metric(a));
      if (c != 0) return c;
      final w = _num(b.value['n']).compareTo(_num(a.value['n']));
      if (w != 0) return w;
      return a.key.compareTo(b.key);
    });
    return list;
  }

  String _fmtDate(int sec) {
    if (sec <= 0) return '未访问';
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000).toLocal();
    String p(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${p(d.month)}-${p(d.day)}';
  }

  String _selLabel() {
    if (sel == 'all') return '全部库';
    for (final l in libs) {
      if ('${l['id']}' == sel) return '${l['name'] ?? l['id']}';
    }
    return cfg.libName.isEmpty ? '当前库' : cfg.libName;
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

  Future<void> _open(String name) async {
    final ls = authorLibs[name] ?? [sel == 'all' ? cfg.lib : sel];
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AuthorPage(name: name, libs: List<String>.from(ls))));
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作者'), actions: [
        IconButton(
            tooltip: '各库排行',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LibraryRankPage())),
            icon: const Icon(Icons.stacked_bar_chart)),
        IconButton(
            tooltip: syncing ? '同步中…' : '立即同步作者',
            onPressed: syncing ? null : _syncAuthors,
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
                            label: const Text('全部库'),
                            selected: sel == 'all',
                            onSelected: (_) {
                              if (sel == 'all') return;
                              setState(() {
                                sel = 'all';
                                loading = true;
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
                              onSelected: (_) => setState(() => sort = s.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 8, 6),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          size: 13, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              '${authors.length} 位作者 · ${_selLabel()} · 播放/访问/水滴为本机统计',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey))),
                    ]),
                  ),
                  Expanded(
                    child: authors.isEmpty
                        ? const Center(
                            child: Text('暂无作者数据',
                                style: TextStyle(color: Colors.grey)))
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 132,
                                    childAspectRatio: 0.80,
                                    mainAxisSpacing: 10,
                                    crossAxisSpacing: 10),
                            itemCount: sorted.length,
                            itemBuilder: (_, i) {
                              final e = sorted[i];
                              final av = '${e.value['av'] ?? ''}';
                              final ids = authorLibs[e.key] ??
                                  <String>[
                                    sel == 'all'
                                        ? '${e.value['_lib'] ?? cfg.lib}'
                                        : sel
                                  ];
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _open(e.key),
                                child: Stack(children: [
                                  Container(
                                    padding:
                                        const EdgeInsets.fromLTRB(6, 22, 6, 8),
                                    decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          ClipOval(
                                            child: SizedBox(
                                              width: 58,
                                              height: 58,
                                              child: av.isEmpty
                                                  ? Container(
                                                      color: Colors.blueGrey,
                                                      alignment:
                                                          Alignment.center,
                                                      child: Text(
                                                          e.key.isEmpty
                                                              ? '?'
                                                              : e.key[0],
                                                          style: const TextStyle(
                                                              fontSize: 24)))
                                                  : CachedNetworkImage(
                                                      imageUrl: cfg.base +
                                                          cfg.media(av,
                                                              lib:
                                                                  '${e.value['_lib'] ?? (sel == 'all' ? cfg.lib : sel)}'),
                                                      httpHeaders: cfg.headers,
                                                      fit: BoxFit.cover,
                                                      memCacheWidth: 174,
                                                      errorWidget: (_, __, ___) => Container(
                                                          color:
                                                              Colors.blueGrey,
                                                          alignment:
                                                              Alignment.center,
                                                          child: Text(
                                                              e.key.isEmpty ? '?' : e.key[0],
                                                              style: const TextStyle(fontSize: 24)))),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(e.key,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 2),
                                          Text(_sub(e),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)),
                                          Text('${_num(e.value['n'])} 作品',
                                              maxLines: 1,
                                              style: TextStyle(
                                                  fontSize: 9,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withValues(alpha: 0.7))),
                                        ]),
                                  ),
                                  Positioned(
                                    top: 5,
                                    left: 5,
                                    right: 4,
                                    child: LibBadges(
                                      libIds: ids,
                                      order: libs
                                          .map((e) => '${e['id']}')
                                          .toList(),
                                      grade: AuthorGrade.gradeFor(
                                        plays: _num(_s(e.key)['p']),
                                        drops: _num(_s(e.key)['dr']),
                                        works: _num(e.value['n']),
                                      ),
                                      names: {
                                        for (final l in libs)
                                          '${l['id']}':
                                              '${l['name'] ?? l['id']}'
                                      },
                                    ),
                                  ),
                                ]),
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
  // G17：「继续观看」需要回到原收藏夹列表续播
  final int? idx;
  final String? colName;
  const PlayerPage(
      {super.key,
      required this.works,
      required this.start,
      this.lib,
      this.idx,
      this.colName});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// G18：两个播放器槽位。A 播放当前作品，B 在后台静音预缓冲下一条；
/// 切条时交换槽位，预缓冲好的媒体无需重新打开即可起播。
class _PlaybackSlot {
  final String tag;
  late final Player player;
  late final VideoController vc;

  _PlaybackSlot(this.tag) {
    player = Player(
      configuration: const PlayerConfiguration(
        title: 'Dizi',
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    // Windows：显式使用安全硬件解码，避免窗口缩放/最大化时纹理重建导致崩溃
    vc = VideoController(
      player,
      configuration: const VideoControllerConfiguration(hwdec: 'auto-safe'),
    );
  }
}

class _PlayerPageState extends State<PlayerPage>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final PageController pc = PageController(initialPage: widget.start);
  late final _PlaybackSlot _slotA = _PlaybackSlot('a');
  late final _PlaybackSlot _slotB = _PlaybackSlot('b');
  bool _slotAActive = true;
  _PlaybackSlot get _active => _slotAActive ? _slotA : _slotB;
  _PlaybackSlot get _idle => _slotAActive ? _slotB : _slotA;
  // 对播放页其余代码保持原有 player / vc 接口，内部指向当前活动槽位
  Player get player => _active.player;
  VideoController get vc => _active.vc;
  // G18：下一条预缓冲状态
  Timer? _preloadTimer;
  int? _preloadIndex;
  String? _preloadKey;
  bool _preloadReady = false;
  bool _preloadFailed = false;
  int _preloadGen = 0;
  final List<StreamSubscription> _playerSubs = <StreamSubscription>[];
  final FocusNode focus = FocusNode();
  int cur = 0;
  int img = 0;
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
  bool ui = true;
  bool fs = false;
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
  String get _curLib => _libFor(widget.works[cur]);
  double _hoverDx = -1;
  double _hoverDy = -1;
  bool autoplay = true;
  bool loopOne = false;
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
  // G12：加载超时 / 播放器报错提示与重试
  PlaybackFailure? _failure;
  Timer? _loadTimeout;
  bool _buffering = false;
  bool _slowBuffer = false;
  Timer? _slowBufferTimer;
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
    _bindPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus.requestFocus();
      open(widget.start);
    });
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
      final w = widget.works[cur];
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
      if (widget.works[cur]['t'] == 'v' && v != !paused) {
        setState(() => paused = !v);
      }
    }));
    subPos = p.stream.position.listen((position) {
      if (!identical(p, player)) return;
      if (!mounted) return;
      // G10：记录观看位置（内部 3s 节流，不受 UI 刷新节流影响）；
      // _opening 期间播放器会先上报 0 位置，不能用来覆盖已有进度
      if (!_opening && _mediaToken == _openToken && _mediaToken > 0) {
        final cw = widget.works[cur];
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
      _showFailure(classifyPlaybackError(msg));
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
      if (widget.works[cur]['t'] == 'v' && !paused) {
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
    final isV = widget.works[cur]['t'] == 'v';
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

  String _watchIdFor(dynamic w) => '${(w is Map ? w['id'] : null) ?? ''}';

  /// G10：把当前视频的播放位置写入本地记录（强制写，用于切条/退出/切后台）。
  void _saveWatchProgress({bool force = false}) {
    if (widget.works.isEmpty || cur < 0 || cur >= widget.works.length) return;
    final w = widget.works[cur];
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
          idx: widget.idx ?? 0,
          collection: widget.colName ?? '',
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

  /// G18：作废当前预缓冲（例如用户跳到别的作品）。默认顺手停掉空闲槽位，
  /// 避免它在后台继续占带宽。
  void _cancelPreload({bool stopIdle = true}) {
    _preloadTimer?.cancel();
    _preloadTimer = null;
    _preloadGen++;
    _preloadReady = false;
    _preloadFailed = false;
    _preloadIndex = null;
    _preloadKey = null;
    if (stopIdle) {
      try {
        _idle.player.stop();
      } catch (_) {}
    }
  }

  /// G18：当前条起播后，延迟一点在空闲槽位静音打开下一条。
  void _schedulePreload() {
    _preloadTimer?.cancel();
    _preloadTimer = null;
    final next = cur + 1;
    if (next >= widget.works.length) return;
    final nw = widget.works[next];
    final path = preloadMediaPath(nw);
    if (!shouldPreloadNext(
        autoplay: autoplay,
        loopOne: loopOne,
        index: next,
        count: widget.works.length,
        hasMedia: path != null)) {
      return;
    }
    _preloadTimer = Timer(const Duration(milliseconds: 800), () {
      _startPreload(next, path!);
    });
  }

  Future<void> _startPreload(int idx, String path) async {
    if (!mounted || idx != cur + 1 || !autoplay || loopOne) return;
    final gen = ++_preloadGen;
    final nw = widget.works[idx];
    final nlib = _libFor(nw);
    final key = preloadKeyFor(nw, nlib);
    final slot = _idle;
    _preloadIndex = idx;
    _preloadKey = key;
    _preloadReady = false;
    _preloadFailed = false;
    StreamSubscription? err;
    err = slot.player.stream.error.listen((_) {
      if (gen == _preloadGen) _preloadFailed = true;
    });
    try {
      await slot.player.stop();
      // 预缓冲槽位保持静音、暂停；切条时再恢复音量并 play
      await slot.player.setVolume(0);
      await slot.player.open(
        Media(cfg.base + cfg.media(path, lib: nlib),
            httpHeaders: cfg.headers),
        play: false,
      );
      if (gen != _preloadGen) return;
      _preloadReady = !_preloadFailed;
    } catch (_) {
      if (gen == _preloadGen) {
        _preloadReady = false;
        _preloadFailed = true;
      }
    } finally {
      await err.cancel();
    }
  }

  Future<void> open(int i) async {
    // 切条前先把上一条的进度落盘
    _saveWatchProgress(force: true);
    final w = widget.works[i];
    final wl = _libFor(w);
    final key = preloadKeyFor(w, wl);
    // 命中预缓冲：直接使用空闲槽位，跳过 player.open 的等待
    final canUsePreload = _preloadReady &&
        !_preloadFailed &&
        preloadMatches(
            preloadedIndex: _preloadIndex,
            preloadedKey: _preloadKey,
            index: i,
            key: key);
    if (!canUsePreload) _cancelPreload();
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
      loading = true;
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
      final target = _idle;
      _slotAActive = target == _slotA;
      _bindPlayer();
      try {
        await old.player.stop();
      } catch (_) {}
      _mediaToken = my;
      _preloadReady = false;
      _preloadFailed = false;
      _preloadIndex = null;
      _preloadKey = null;
      _preloadGen++;
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
    if (!canUsePreload) {
      try {
        if (w['t'] == 'v') {
          await player.open(Media(
              cfg.base + cfg.media(w['m'][0].toString(), lib: wl),
              httpHeaders: cfg.headers));
        } else if ((w['au'] ?? '').toString().isNotEmpty) {
          await player.open(Media(
              cfg.base + cfg.media(w['au'].toString(), lib: wl),
              httpHeaders: cfg.headers));
        }
        if ((w['t'] == 'v' || (w['au'] ?? '').toString().isNotEmpty) &&
            my == _openToken) {
          _mediaToken = my;
        }
      } catch (e) {
        if (my == _openToken) {
          _opening = false;
          _showFailure(classifyPlaybackError(e));
          return;
        }
      }
    }
    if (my != _openToken) return;
    if (_failure != null) return;
    _loadTimeout?.cancel();
    _loadTimeout = null;
    try {
      await player.setVolume(volume);
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
      if (widget.works[i]['t'] != 'v') return;
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
        player.open(Media(cfg.base + cfg.media(w['m'][0].toString(), lib: wl),
            httpHeaders: cfg.headers));
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
    final w = widget.works[cur];
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
      final w = widget.works[cur];
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
    final target = (base + delta).clamp(0, widget.works.length - 1).toInt();
    if (target == base) return;
    _pendingPage = target;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (instant || now - _navAt < 450) {
      pc.jumpToPage(target);
    } else {
      pc.animateToPage(target,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
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
    if (!ui) {
      showUi();
      _lastStageTapAt = 0;
      return;
    }
    // G14：图片放大时单击只恢复原始大小，不暂停/双击点赞
    if (_picZoom.isZoomed) {
      _resetPicZoom();
      _lastStageTapAt = 0;
      return;
    }
    final w = widget.works[cur];
    final now = DateTime.now().millisecondsSinceEpoch;
    final isDouble = isStageDoubleTap(
        nowMs: now,
        lastMs: _lastStageTapAt,
        lastPos: _lastStageTapAt > 0 ? _lastStageTapPos : null,
        pos: pos);
    if (isDouble) {
      _lastStageTapAt = 0;
      // 第一次点击已经切换过一次暂停；双击时按点击前的状态恢复。
      _restorePauseAfterTap(_tapWasPausedBefore);
      if (!_isLiked(w)) _setLiked(w, true, at: pos);
      showUi();
      return;
    }
    _lastStageTapAt = now;
    _lastStageTapPos = pos ?? Offset.zero;
    _tapWasPausedBefore = paused;
    hapticTap();
    togglePause();
    showUi();
  }

  // 双击点赞时撤销第一次点击带来的暂停切换（视频流事件可能迟到，
  // 因此这里直接按点击前状态强制对齐，不依赖 paused 是否已刷新）。
  void _restorePauseAfterTap(bool wasPaused) {
    final isV = widget.works[cur]['t'] == 'v';
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

  // 打开当前作品作者主页：先暂停，返回后按原状态恢复
  Future<void> openAuthor() async {
    final name = '${widget.works[cur]['a'] ?? ''}';
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

  void togglePause() {
    final isV = widget.works[cur]['t'] == 'v';
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
  void _setVolume(double v) {
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
    // F32：单条循环与连播是完全独立的两组状态。
    // 不再使用 media_kit 原生 PlaylistMode.single（原生 loop-file 会吞掉
    // completed 事件），统一由 completed 回调在 Dart 层重播，
    // 这样关闭循环后连播判定立刻恢复，不会偶发停在片尾。
    setState(() => loopOne = !loopOne);
    if (loopOne) {
      _cancelPreload();
    } else {
      _schedulePreload();
    }
  }

  void toggleAutoplay() {
    // F32：只切连播，不再连带改动单条循环
    setState(() => autoplay = !autoplay);
    if (autoplay) {
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
    if (fs) {
      hideTimer = Timer(Duration(seconds: AppSettings.hideUiSec), () {
        if (!mounted) return;
        // 拖动进度条或鼠标停留在进度条上时不隐藏
        if (dragging || barHover) {
          showUi();
        } else {
          setState(() => ui = false);
        }
      });
    }
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
    final w = widget.works[cur];
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
    _swipeHintTimer?.cancel();
    _preloadTimer?.cancel();
    _preloadGen++;
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
    _slotA.player.dispose();
    _slotB.player.dispose();
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
              key: ValueKey('video-${_active.tag}'),
              controller: vc,
              controls: NoVideoControls),
        ),
      );
    });
  }

  // 长简介/文案：在任务栏内展开缩略全文（H13，参考抖音，不弹独立窗口）
  // 图文单张渲染：GIF 用 Image.network 才能播放动画，其余走缓存图
  Widget picView(String path, {String? lib}) {
    final url = cfg.base + cfg.media(path, lib: lib);
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
    final w = widget.works[cur];
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
    final w = widget.works[cur];
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
            : Icons.error_outline;
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x99000000),
        child: Center(
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
              FilledButton.icon(
                onPressed: _retryPlayback,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重试'),
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(120, 38)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.works[cur];
    final isV = w['t'] == 'v';
    final pics = isV ? <dynamic>[] : (w['m'] as List);
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
              PageView.builder(
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
                    : null,
                scrollDirection: Axis.vertical,
                itemCount: widget.works.length,
                onPageChanged: open,
                itemBuilder: (_, i) {
                  final it = widget.works[i];
                  if (i != cur) {
                    return (it['th'] ?? '').toString().isEmpty
                        ? Container(color: Colors.black)
                        : CachedNetworkImage(
                            imageUrl: cfg.base +
                                cfg.media(it['th'].toString(),
                                    lib: _libFor(it)),
                            httpHeaders: cfg.headers,
                            fit: BoxFit.contain);
                  }
                  if (it['t'] == 'v') {
                    return GestureDetector(
                      onTapUp: (d) => onStageTap(d.localPosition),
                      onHorizontalDragEnd: (d) {
                        // 右划快速进入作者主页
                        final v = d.primaryVelocity ?? 0;
                        if (v > 280) openAuthor();
                      },
                      onLongPressStart: (_) => player.setRate(2.0),
                      onLongPressEnd: (_) => player.setRate(speed),
                      child: Stack(fit: StackFit.expand, children: [
                        if ((it['th'] ?? '').toString().isNotEmpty)
                          CachedNetworkImage(
                              imageUrl: cfg.base +
                                  cfg.media(it['th'].toString(),
                                      lib: _libFor(it)),
                              httpHeaders: cfg.headers,
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
                                ..setTranslationRaw(
                                    _picZoom.offset.dx, _picZoom.offset.dy, 0),
                              child: picView(pics[idx], lib: _curLib),
                            ),
                          ),
                        );
                      }),
                      if (pics.length > 1)
                        Positioned(
                          top: pad.top + 2,
                          right: pad.right + 4,
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
                    ]),
                  );
                },
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
              // G15：左右窄边上下滑（左亮度 / 右音量），中间仍可翻页
              if (_mobileSwipe) ...[
                _swipeEdge(SwipeZone.brightness,
                    swipeEdgeWidth(MediaQuery.of(context).size.width), pad),
                _swipeEdge(SwipeZone.volume,
                    swipeEdgeWidth(MediaQuery.of(context).size.width), pad),
                if (_swipeHint) _swipeHintWidget(pad),
              ],
              Positioned(
                left: pad.left + 8,
                top: pad.top + 8,
                child: IgnorePointer(
                  ignoring: !ui,
                  child: AnimatedOpacity(
                    opacity: ui ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon:
                            const Icon(Icons.arrow_back, color: Colors.white70),
                        style: IconButton.styleFrom(
                            backgroundColor: Colors.black45)),
                  ),
                ),
              ),
              if (paused)
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
                    opacity: ui ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: GestureDetector(
                      onTap: openAuthor,
                      // G11：长按信息区弹出播放菜单（视频区长按仍是 2 倍速）
                      onLongPress: _showWorkMenu,
                      child: Row(children: [
                        if ((w['av'] ?? '').toString().isNotEmpty)
                          ClipOval(
                              child: CachedNetworkImage(
                                  imageUrl: cfg.base +
                                      cfg.media(w['av'].toString(),
                                          lib: _curLib),
                                  httpHeaders: cfg.headers,
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
              if (_volHintVisible && ui && !_swipeHint)
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
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !ui,
                  child: AnimatedOpacity(
                    opacity: ui ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
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
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                                      children: List.generate(pics.length, (k) {
                                        final selected =
                                            k == (dragging ? dragPic : idx);
                                        final active = k <=
                                            (dragging ? (dragPic ?? idx) : idx);
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
                                  final f = (d.localPosition.dx / cons.maxWidth)
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
                                            height:
                                                (dragging || barHover) ? 7 : 3,
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
                          // H14：点击=静音切换；长按/左右拖动调音量（不弹模块）
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: toggleMute,
                            onLongPressStart: _volLongPressStart,
                            onLongPressMoveUpdate: _volLongPressMove,
                            onLongPressEnd: (_) => _volDragEnd(),
                            onHorizontalDragStart: _volDragStart,
                            onHorizontalDragUpdate: _volDragUpdate,
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
                          IconButton(
                              onPressed: cycleSpeed,
                              icon: Text('${speed}x',
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.white70))),
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
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (dropBusy)
                                        const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white54))
                                      else
                                        Icon(Icons.water_drop,
                                            size: 20,
                                            color: dropGlow && dropDayLeft >= 0
                                                ? Colors.lightBlueAccent
                                                : (dropDayLeft > 0 &&
                                                        dropWeekLeft > 0
                                                    ? Colors.white38
                                                    : Colors.white24)),
                                      const SizedBox(height: 1),
                                      Text('$dropTotal',
                                          style: TextStyle(
                                              fontSize: 9,
                                              height: 1.0,
                                              fontWeight: FontWeight.w600,
                                              color: dropGlow
                                                  ? Colors.lightBlueAccent
                                                  : (dropDayLeft > 0 &&
                                                          dropWeekLeft > 0
                                                      ? Colors.white54
                                                      : Colors.white24))),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                              onPressed: toggleFs,
                              icon: Icon(
                                  fs ? Icons.fullscreen_exit : Icons.fullscreen,
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
  bool loading = true;
  String? err;
  int batch = 0;

  @override
  void initState() {
    super.initState();
    load(refresh: false);
  }

  Future<void> load({required bool refresh}) async {
    if (refresh) batch++;
    final seed = DateTime.now().millisecondsSinceEpoch ~/ 1000 + batch * 7919;
    setState(() {
      loading = true;
      err = null;
    });
    try {
      final r = await http.get(cfg.u('/api/recommend?n=40&seed=$seed'),
          headers: cfg.headers);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(r.body);
      if (!mounted) return;
      setState(() {
        works = (j is Map && j['works'] is List) ? j['works'] as List : [];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('推荐'), actions: [
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
              : works.isEmpty
                  ? const Center(
                      child: Text('暂无推荐', style: TextStyle(color: Colors.grey)))
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
                        itemCount: works.length,
                        itemBuilder: (_, i) {
                          final w = works[i];
                          return GestureDetector(
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        PlayerPage(works: works, start: i))),
                            child: Stack(fit: StackFit.expand, children: [
                              (w['th'] ?? '').toString().isEmpty
                                  ? Container(color: Colors.black26)
                                  : CachedNetworkImage(
                                      imageUrl: cfg.base +
                                          cfg.media(w['th'].toString()),
                                      httpHeaders: cfg.headers,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          Container(color: Colors.black26)),
                              Positioned(
                                  left: 4,
                                  top: 4,
                                  child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 2),
                                      color: Colors.black54,
                                      child: Text(w['t'] == 'v' ? '视频' : '图文',
                                          style:
                                              const TextStyle(fontSize: 10)))),
                              Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                      padding: const EdgeInsets.fromLTRB(
                                          6, 10, 6, 5),
                                      decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                              colors: [
                                            Colors.transparent,
                                            Colors.black87
                                          ])),
                                      child: Text(
                                          '@${w['a'] ?? ''} · ${w['d'] ?? ''}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              const TextStyle(fontSize: 10)))),
                            ]),
                          );
                        },
                      ),
                    ),
    );
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
  bool loading = true;
  String kw = '';
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    sel = cfg.lib;
    _init();
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
      final list = ((j['libraries'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
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
        final r = await http.get(cfg.u('/api/index.json', lib: lib),
            headers: cfg.headers);
        if (r.statusCode != 200) continue;
        final cols = (jsonDecode(r.body)['collections'] as List);
        for (final c in cols) {
          final rr = await http.get(cfg.u('/api/c/${c['idx']}.json', lib: lib),
              headers: cfg.headers);
          if (rr.statusCode != 200) continue;
          final ws = (jsonDecode(rr.body)['works'] as List);
          for (var i = 0; i < ws.length; i++) {
            out.add({
              'w': ws[i],
              'works': ws,
              'i': i,
              'col': fixDisplayName('${c['name'] ?? ''}'),
              '_lib': lib,
            });
          }
        }
      }
    } catch (_) {}
    if (!mounted || token != _loadToken) return;
    setState(() {
      all = out;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final res = kw.isEmpty
        ? const []
        : all.where((e) {
            final w = e['w'];
            return '${w['ti']}'.contains(kw) || '${w['a']}'.contains(kw);
          }).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
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
        if (loading) const LinearProgressIndicator(),
        Expanded(
          child: kw.isEmpty
              ? const Center(
                  child: Text('输入关键词，在所选库内搜索',
                      style: TextStyle(color: Colors.grey)))
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
                                  imageUrl: cfg.base +
                                      cfg.media(w['th'].toString(),
                                          lib: '${e['_lib']}'),
                                  httpHeaders: cfg.headers,
                                  fit: BoxFit.cover)),
                      title: Text('${w['ti']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '@${w['a']} · ${e['col']}${sel == 'all' ? ' · ${_libName('${e['_lib']}')}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
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
  List works = [];
  String primaryLib = '';
  bool loading = true;
  bool fullSync = true;
  bool syncing = false;
  Timer? syncTimer;

  List<String> get _libs =>
      (widget.libs == null || widget.libs!.isEmpty) ? [cfg.lib] : widget.libs!;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      if (mounted) {
        setState(() => fullSync = sp.getBool('sync_full_author') ?? true);
      }
    });
    load();
  }

  @override
  void dispose() {
    syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _setFull(bool v) async {
    setState(() => fullSync = v);
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('sync_full_author', v);
  }

  // 单作者同步：仅 douyin 库配置了抓取脚本
  bool get _canSync =>
      primaryLib == 'douyin' ||
      (primaryLib.isEmpty && (cfg.lib.isEmpty || cfg.lib == 'douyin'));

  Future<void> _syncAuthor() async {
    if (syncing || !_canSync) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('同步作者 @${widget.name}'),
        content: Text(fullSync
            ? '将重新抓取该作者在收藏夹内的全部作品信息（头像、简介、封面），耗时较长。\n\n同步在 NAS 后台运行。'
            : '只补抓该作者缺少头像/简介的作品信息，速度较快。\n\n同步在 NAS 后台运行。'),
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
        target: 'author', author: widget.name, lib: primaryLib, full: fullSync);
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
    if (mounted) setState(() => loading = false);
  }

  // 点击头像放大查看（可双指缩放，点任意处关闭）
  void _showAvatar(BuildContext context) {
    if (av.isEmpty) return;
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
              imageUrl: cfg.base +
                  cfg.media(av, lib: primaryLib.isEmpty ? null : primaryLib),
              httpHeaders: cfg.headers,
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
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () => _showAvatar(context),
                        child: ClipOval(
                            child: av.isEmpty
                                ? Container(
                                    width: 64,
                                    height: 64,
                                    color: Colors.blueGrey,
                                    child: Center(
                                        child: Text(
                                            widget.name.isEmpty
                                                ? '?'
                                                : widget.name[0],
                                            style:
                                                const TextStyle(fontSize: 26))))
                                : CachedNetworkImage(
                                    imageUrl: cfg.base +
                                        cfg.media(av,
                                            lib: primaryLib.isEmpty
                                                ? null
                                                : primaryLib),
                                    httpHeaders: cfg.headers,
                                    width: 64,
                                    height: 64,
                                    fit: BoxFit.cover)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                        child: Text('全量同步该作者作品信息（关闭则只补抓缺失）',
                            style:
                                TextStyle(fontSize: 11, color: Colors.grey))),
                    Text('全量',
                        style: TextStyle(
                            fontSize: 11,
                            color: fullSync ? Colors.blue : Colors.grey)),
                    Transform.scale(
                      scale: 0.8,
                      child: Switch(
                          value: fullSync,
                          onChanged: syncing ? null : _setFull),
                    ),
                  ]),
                ),
              const Divider(height: 1),
              Expanded(
                  child: WorkGrid(
                      works: works,
                      lib: primaryLib.isEmpty ? null : primaryLib)),
            ]),
    );
  }
}

class WorkGrid extends StatelessWidget {
  final List works;
  final String? lib;
  // G17：带上所属收藏夹，播放页写「继续观看」时才能一键回到原列表
  final int? collectionIdx;
  final String? collectionName;
  const WorkGrid(
      {super.key,
      required this.works,
      this.lib,
      this.collectionIdx,
      this.collectionName});

  String _libFor(dynamic w) =>
      '${(w is Map ? w['_lib'] : null) ?? lib ?? cfg.lib}';

  @override
  Widget build(BuildContext context) {
    // G10：监听本地观看记录，完成后角标与进度条自动刷新
    return ValueListenableBuilder<int>(
        valueListenable: WatchProgressStore.revision,
        builder: (context, _, __) => _buildGrid(context));
  }

  Widget _buildGrid(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 3 / 4,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2),
      itemCount: works.length,
      itemBuilder: (_, i) {
        final w = works[i];
        final wp = WatchProgressStore.of(
            _libFor(w), '${(w is Map ? w['id'] : null) ?? ''}');
        // G13：视频右下角显示时长，图文显示图片张数
        final coverBadge = workCoverBadge(w);
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayerPage(
                  works: works,
                  start: i,
                  lib: _libFor(w),
                  idx: collectionIdx,
                  colName: collectionName))),
          child: Stack(fit: StackFit.expand, children: [
            (w['th'] ?? '').toString().isEmpty
                ? Container(color: Colors.black26)
                : CachedNetworkImage(
                    imageUrl: cfg.base +
                        cfg.media(w['th'].toString(), lib: _libFor(w)),
                    httpHeaders: cfg.headers,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        Container(color: Colors.black26)),
            Positioned(
                right: 4,
                top: 4,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    color: Colors.black54,
                    child: Text(w['t'] == 'v' ? '视频' : '图文',
                        style: const TextStyle(fontSize: 10)))),
            if (coverBadge != null)
              Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(coverBadge,
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500)))),
            // G10：已看完角标 / 未看完的进度条
            if (wp != null && wp.done)
              Positioned(
                  left: 4,
                  top: 4,
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4)),
                      child: const Text('已看完',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600))))
            else if (wp != null && wp.fraction > 0.01)
              Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                      height: 2,
                      child: LinearProgressIndicator(
                          value: wp.fraction,
                          backgroundColor: Colors.black26,
                          minHeight: 2))),
          ]),
        );
      },
    );
  }
}
