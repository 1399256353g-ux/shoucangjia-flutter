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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  runApp(const App());
}

// 轻触震动：iOS/Android 生效，桌面端静默忽略
void hapticTap() {
  try {
    HapticFeedback.lightImpact();
  } catch (_) {}
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
  Uri u(String path) {
    if (base.isEmpty || lib.isEmpty) return Uri.parse('$base$path');
    final sep = path.contains('?') ? '&' : '?';
    return Uri.parse('$base$path${sep}lib=${Uri.encodeQueryComponent(lib)}');
  }

  // 媒体路径统一带库前缀：/media/<lib>/<相对路径>
  String media(String p) {
    if (lib.isEmpty || !p.startsWith('/media/')) return p;
    final rest = p.substring(7);
    if (rest.startsWith('$lib/')) return p;
    return '/media/${Uri.encodeComponent(lib)}/$rest';
  }
}

final cfg = Cfg();
final navKey = GlobalKey<NavigatorState>();

// 作者统计上报（播放/访问），失败静默，不影响播放
void postStat(String type, String author) {
  if (cfg.base.isEmpty || author.isEmpty) return;
  try {
    http
        .post(cfg.u('/api/stats'),
            headers: {...cfg.headers, 'Content-Type': 'application/json'},
            body: jsonEncode({'type': type, 'author': author}))
        .ignore();
  } catch (_) {}
}

// 小水滴：每个作品每日 1 颗、每周 3 颗，服务端按作者累计
Future<Map<String, dynamic>?> fetchDropStatus(String id) async {
  if (cfg.base.isEmpty || id.isEmpty) return null;
  try {
    final r = await http
        .get(cfg.u('/api/drops?id=${Uri.encodeQueryComponent(id)}'),
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
    {required String target, int? idx, bool full = false}) async {
  if (cfg.base.isEmpty) return null;
  try {
    final r = await http
        .post(cfg.u('/api/sync'),
            headers: {...cfg.headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'target': target,
              if (idx != null) 'idx': idx,
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

Future<Map<String, dynamic>?> sendDrop(String id, String author) async {
  if (cfg.base.isEmpty || id.isEmpty || author.isEmpty) return null;
  try {
    final r = await http
        .post(cfg.u('/api/drops'),
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
    if (mounted) setState(() => ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    return MaterialApp(
      title: 'Dizi',
      navigatorKey: navKey,
      theme: ThemeData.dark(useMaterial3: true),
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
          title: const Text('收藏夹管理'),
          subtitle: const Text('同步选择 · 默认收藏夹 · 拖动排序 · 重命名 · 删除'),
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CollectionAdminPage())),
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
                  color: Colors.white10,
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
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(10)),
          child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.keyboard, size: 26, color: Colors.white54),
                SizedBox(height: 8),
                Text('请按下要绑定的按键…',
                    style: TextStyle(fontSize: 13, color: Colors.white70)),
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
  List<Map<String, dynamic>> cols = [];
  int? defaultIdx;
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
    final list = ((j['collections'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((e) => e['deleted'] != true)
        .toList();
    if (!mounted) return;
    setState(() {
      cols = list;
      defaultIdx = (j['default'] as num?)?.toInt();
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
              'idx': c['idx'],
              'name': c['name'],
              'sync': c['sync'] != false,
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

  Future<void> _rename(Map<String, dynamic> c) async {
    final ctrl = TextEditingController(text: '${c['name']}');
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
      final j = await _send(
          '/api/collections/rename', {'idx': c['idx'], 'name': name});
      _apply(j);
    } catch (e) {
      _toast('重命名失败：$e');
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除收藏夹'),
        content: Text('将从 App 中移除「${c['name']}」，清除该收藏夹的索引数据并关闭同步。\n\n'
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
      final j = await _send('/api/collections/delete', {'idx': c['idx']});
      _apply(j);
      _toast('已移除「${c['name']}」并关闭同步');
    } catch (e) {
      _toast('删除失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏夹管理'), actions: [
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
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(children: [
                          Icon(Icons.info_outline,
                              size: 14, color: Colors.grey),
                          SizedBox(width: 6),
                          Expanded(
                              child: Text('拖动左侧把手排序；开关控制是否同步；★ 为默认收藏夹',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey))),
                        ]),
                      ),
                      Expanded(
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: cols.length,
                          onReorder: _reorder,
                          itemBuilder: (_, i) {
                            final c = cols[i];
                            final isDefault =
                                defaultIdx == (c['idx'] as num).toInt();
                            final sync = c['sync'] != false;
                            return ListTile(
                              key: ValueKey('col-${c['idx']}'),
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
                                    child: Text('${c['name']}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)),
                              ]),
                              subtitle:
                                  Text('${c['count'] ?? 0} 个作品 · 序号 ${c['idx']}'
                                      '${sync ? '' : ' · 不同步'}'),
                              trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: sync,
                                      onChanged: (v) {
                                        setState(() => c['sync'] = v);
                                        _save();
                                      },
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert),
                                      onSelected: (v) async {
                                        if (v == 'default') {
                                          setState(() => defaultIdx =
                                              (c['idx'] as num).toInt());
                                          await _save();
                                        } else if (v == 'rename') {
                                          await _rename(c);
                                        } else if (v == 'delete') {
                                          await _delete(c);
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'default',
                                            child: Text('设为默认收藏夹')),
                                        PopupMenuItem(
                                            value: 'rename',
                                            child: Text('重命名')),
                                        PopupMenuItem(
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
    cfg.libName = '${l['name'] ?? l['id']}';
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
          cfg.libName = '${pick['name'] ?? cfg.lib}';
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
            'name': pc['name'] ?? base['name'],
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
      setState(() => cols = list);
      for (final c in list) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(cfg.libName.isEmpty ? '抖音收藏夹' : cfg.libName),
          actions: [
            IconButton(
                icon: const Icon(Icons.library_books_outlined),
                tooltip: '媒体库',
                onPressed: () async {
                  final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(builder: (_) => const LibraryPage()));
                  if (changed == true) await load();
                }),
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
          ]),
      body: err != null
          ? Center(child: Text('加载失败：$err'))
          : cols.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  itemCount: cols.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = cols[i];
                    final cover = covers['${c['idx']}'];
                    final isDefault = defaultIdx != null &&
                        (c['idx'] as num).toInt() == defaultIdx;
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 48,
                          height: 64,
                          child: cover == null
                              ? Container(color: Colors.black26)
                              : CachedNetworkImage(
                                  imageUrl: cfg.base + cfg.media(cover),
                                  httpHeaders: cfg.headers,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 144),
                        ),
                      ),
                      title: Text(
                          '(${c['idx']}) ${c['name']}${isDefault ? '  ★' : ''}',
                          style: TextStyle(
                              color: isDefault ? Colors.amber : null)),
                      subtitle: c['sync'] == false
                          ? const Text('同步已关闭',
                              style:
                                  TextStyle(fontSize: 11, color: Colors.grey))
                          : null,
                      trailing: Text('${c['count']}',
                          style: const TextStyle(color: Colors.grey)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              CollectionPage(name: c['name'], idx: c['idx']))),
                    );
                  },
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
                        : ListView.separated(
                            itemCount: dels.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final d = dels[i];
                              return ListTile(
                                leading: const Icon(Icons.delete_outline,
                                    color: Colors.grey),
                                title: Text('${d['ti'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '@${d['a'] ?? ''} · ${d['d'] ?? ''} · 已在抖音删除',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                trailing: Text(
                                    '${(d['at'] ?? '').toString().split('T').first}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.grey)),
                              );
                            },
                          ))
                    : (list.isEmpty && kw.isNotEmpty
                        ? Center(
                            child: Text('无匹配作品：$kw',
                                style: const TextStyle(color: Colors.grey)))
                        : WorkGrid(works: list)),
              ),
            ]),
    );
  }
}

// 排行榜：按周/月/年/总统计作者播放量或小水滴
class RankPage extends StatefulWidget {
  const RankPage({super.key});
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
  List rows = [];
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
      final r = await http.get(cfg.u('/api/rank?period=$period&metric=$metric'),
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
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AuthorPage(name: name)));
    if (mounted) load();
  }

  Color _rankColor(int i) {
    if (i == 0) return const Color(0xFFFFC107);
    if (i == 1) return const Color(0xFFB0BEC5);
    if (i == 2) return const Color(0xFFBF8970);
    return Colors.white38;
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
                                                color: _rankColor(i)))),
                                    ClipOval(
                                      child: SizedBox(
                                        width: 42,
                                        height: 42,
                                        child: av.isEmpty
                                            ? Container(
                                                color: Colors.blueGrey,
                                                alignment: Alignment.center,
                                                child: Text(
                                                    name.isEmpty
                                                        ? '?'
                                                        : name[0],
                                                    style: const TextStyle(
                                                        fontSize: 18)))
                                            : CachedNetworkImage(
                                                imageUrl:
                                                    cfg.base + cfg.media(av),
                                                httpHeaders: cfg.headers,
                                                fit: BoxFit.cover,
                                                memCacheWidth: 126,
                                                errorWidget: (_, __, ___) =>
                                                    Container(
                                                        color: Colors.blueGrey,
                                                        alignment:
                                                            Alignment.center,
                                                        child: Text(
                                                            name.isEmpty
                                                                ? '?'
                                                                : name[0],
                                                            style:
                                                                const TextStyle(
                                                                    fontSize:
                                                                        18)))),
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
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.white60)),
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
  String sort = 'plays';
  bool loading = true;
  String? err;
  bool fullSync = true;
  bool syncing = false;
  Timer? syncTimer;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((sp) {
      if (mounted) {
        setState(() => fullSync = sp.getBool('sync_full_authors') ?? true);
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
    await sp.setBool('sync_full_authors', v);
  }

  Future<void> _syncAuthors() async {
    if (syncing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('立即同步作者'),
        content: Text(fullSync
            ? '将重新抓取全部作者的头像、简介与作品信息，耗时较长。\n\n同步在 NAS 后台运行。'
            : '只补抓缺少头像/简介的作者，速度较快。\n\n同步在 NAS 后台运行。'),
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
    final j = await startServerSync(target: 'authors', full: fullSync);
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

  Future<void> load() async {
    if (mounted) setState(() => err = null);
    try {
      final rs = await Future.wait([
        http.get(cfg.u('/api/authors.json'), headers: cfg.headers),
        http.get(cfg.u('/api/author_stats.json'), headers: cfg.headers),
      ]);
      if (rs[0].statusCode != 200) throw Exception('HTTP ${rs[0].statusCode}');
      final m = jsonDecode(rs[0].body) as Map<String, dynamic>;
      dynamic sj;
      if (rs[1].statusCode == 200) {
        try {
          sj = jsonDecode(rs[1].body);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        authors = m.entries
            .where((e) => e.value is Map)
            .map((e) =>
                MapEntry(e.key, Map<String, dynamic>.from(e.value as Map)))
            .toList();
        stats = (sj is Map && sj['authors'] is Map)
            ? Map<String, dynamic>.from(sj['authors'] as Map)
            : {};
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
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AuthorPage(name: name)));
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('作者'), actions: [
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
                          child: Text('${authors.length} 位作者 · 播放/访问/水滴为本机统计',
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.grey))),
                      Text('全量同步',
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
                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _open(e.key),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 10),
                                  decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(12)),
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
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                        e.key.isEmpty
                                                            ? '?'
                                                            : e.key[0],
                                                        style: const TextStyle(
                                                            fontSize: 24)))
                                                : CachedNetworkImage(
                                                    imageUrl: cfg.base +
                                                        cfg.media(av),
                                                    httpHeaders: cfg.headers,
                                                    fit: BoxFit.cover,
                                                    memCacheWidth: 174,
                                                    errorWidget: (_, __, ___) => Container(
                                                        color: Colors.blueGrey,
                                                        alignment:
                                                            Alignment.center,
                                                        child: Text(
                                                            e.key.isEmpty
                                                                ? '?'
                                                                : e.key[0],
                                                            style:
                                                                const TextStyle(
                                                                    fontSize:
                                                                        24)))),
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
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white60)),
                                        Text('${_num(e.value['n'])} 作品',
                                            maxLines: 1,
                                            style: const TextStyle(
                                                fontSize: 9,
                                                color: Colors.white38)),
                                      ]),
                                ),
                              );
                            }),
                  ),
                ]),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final List works;
  final int start;
  const PlayerPage({super.key, required this.works, required this.start});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late final PageController pc = PageController(initialPage: widget.start);
  // Windows：显式使用安全硬件解码，避免窗口缩放/最大化时纹理重建导致崩溃
  late final Player player = Player(
    configuration: const PlayerConfiguration(
      title: 'Dizi',
      bufferSize: 32 * 1024 * 1024,
    ),
  );
  late final VideoController vc = VideoController(
    player,
    configuration: const VideoControllerConfiguration(hwdec: 'auto-safe'),
  );
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
  bool loading = true;
  bool muted = false;
  double volume = 100;
  double lastVol = 100;
  bool showVol = false;
  bool ui = true;
  bool fs = false;
  bool dragging = false;
  bool barHover = false;
  int pointers = 0;
  double _hoverDx = -1;
  double _hoverDy = -1;
  bool autoplay = true;
  bool loopOne = false;
  double? dragFrac;
  bool resumeAfterDrag = false;
  bool dropBusy = false;
  int dropDayLeft = 1;
  int dropWeekLeft = 3;
  int dropTotal = 0;
  double speed = 1.0;
  Duration pos = Duration.zero;
  Duration dur = Duration.zero;
  Timer? autoTimer;
  Timer? hideTimer;
  Timer? retryTimer;
  bool manualPic = false;
  StreamSubscription? subPos;
  StreamSubscription? subDur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cur = widget.start;
    speed = AppSettings.defaultSpeed;
    player.setPlaylistMode(PlaylistMode.none);
    player.stream.completed.listen((done) {
      if (!done || !mounted) return;
      final w = widget.works[cur];
      if (w['t'] != 'v') {
        // 图文：整首歌放完才切下一条；单条循环时重新播放；都不开就停下图片轮播
        if (paused) return;
        if (autoplay && !loopOne) {
          next();
        } else if (loopOne) {
          try {
            player.seek(Duration.zero);
            player.play();
            setState(() => img = 0);
          } catch (_) {}
        } else {
          pauseAuto();
        }
        return;
      }
      // 视频播完：单条循环就重播本条，否则按连播设置切下一条
      if (loopOne) {
        try {
          player.seek(Duration.zero);
          player.play();
        } catch (_) {}
      } else if (autoplay) {
        next();
      }
    });
    player.stream.playing.listen((v) {
      if (mounted && widget.works[cur]['t'] == 'v' && v != !paused) {
        setState(() => paused = !v);
      }
    });
    subPos = player.stream.position.listen((p) {
      if (!mounted) return;
      // 位置流每 100ms 左右触发一次；全量 setState 会让视频层频繁重建、
      // 在 Windows 上造成卡顿与音画不同步。这里节流到 200ms，
      // 但跳转/拖动后的大幅变化立即刷新。
      final now = DateTime.now().millisecondsSinceEpoch;
      final bigJump = (p.inMilliseconds - pos.inMilliseconds).abs() > 1200;
      if (!bigJump && now - _lastPosSet < 200) return;
      _lastPosSet = now;
      setState(() => pos = p);
    });
    subDur = player.stream.duration.listen((d) {
      if (mounted) setState(() => dur = d);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus.requestFocus();
      open(widget.start);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 从后台/模拟器切回时焦点可能丢失，方向键会失效；恢复时重新拿回焦点
    if (state == AppLifecycleState.resumed && mounted) {
      focus.requestFocus();
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

  Future<void> open(int i) async {
    final my = ++_openToken;
    autoTimer?.cancel();
    retryTimer?.cancel();
    manualPic = false;
    _pendingPage = null;
    setState(() {
      cur = i;
      img = 0;
      loading = true;
      paused = false;
      dropDayLeft = 1;
      dropWeekLeft = 3;
      dropTotal = 0;
    });
    try {
      await player.stop();
    } catch (_) {}
    if (my != _openToken) return;
    final w = widget.works[i];
    _refreshDrop('${w['id'] ?? ''}', my);
    postStat('play', '${w['a'] ?? ''}');
    try {
      if (w['t'] == 'v') {
        await player.open(Media(cfg.base + cfg.media(w['m'][0].toString()),
            httpHeaders: cfg.headers));
      } else if ((w['au'] ?? '').toString().isNotEmpty) {
        await player.open(Media(cfg.base + cfg.media(w['au'].toString()),
            httpHeaders: cfg.headers));
      }
    } catch (_) {}
    if (my != _openToken) return;
    try {
      await player.setVolume(volume);
      await player.setRate(speed);
    } catch (_) {}
    if (!paused) {
      try {
        await player.play();
      } catch (_) {}
      // open 后再确认一次速率，避免个别 Windows 解码器在起播时重置为 1x
      try {
        await player.setRate(speed);
      } catch (_) {}
    }
    if (mounted && my == _openToken) {
      setState(() {
        loading = false;
        if (w['t'] != 'v') paused = false;
      });
    }
    retryTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted &&
          my == _openToken &&
          w['t'] == 'v' &&
          dur.inMilliseconds == 0) {
        player.open(Media(cfg.base + cfg.media(w['m'][0].toString()),
            httpHeaders: cfg.headers));
        player.play();
      }
    });
    if (w['t'] != 'v') startAuto();
  }

  Future<void> _refreshDrop(String id, int token) async {
    if (id.isEmpty) return;
    final r = await fetchDropStatus(id);
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
    setState(() => dropBusy = true);
    final r = await sendDrop(id, author);
    if (!mounted) return;
    setState(() {
      dropBusy = false;
      if (r != null) {
        dropDayLeft = _intOf(r['dayLeft'], dropDayLeft);
        dropWeekLeft = _intOf(r['weekLeft'], dropWeekLeft);
        dropTotal = _intOf(r['total'], dropTotal);
      }
    });
    if (r != null && r['ok'] == true) {
      hapticTap();
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
      if (img < n - 1) {
        setState(() => img++);
      } else if (loopOne || hasAudio) {
        // 单条循环，或还有背景音乐没放完：图片回到第一张继续
        setState(() => img = 0);
      } else {
        next();
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

  // 全屏且功能隐藏时，第一次点击只呼出功能区，第二次才暂停
  void onStageTap() {
    focus.requestFocus();
    if (!ui) {
      showUi();
      return;
    }
    hapticTap();
    togglePause();
    showUi();
  }

  // 打开当前作品作者主页：先暂停，返回后按原状态恢复
  Future<void> openAuthor() async {
    final name = '${widget.works[cur]['a'] ?? ''}';
    if (name.isEmpty) return;
    final resume = !paused;
    try {
      player.pause();
    } catch (_) {}
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => AuthorPage(name: name)));
    if (resume && mounted && !fs) {
      try {
        player.play();
      } catch (_) {}
    }
  }

  void togglePause() {
    final isV = widget.works[cur]['t'] == 'v';
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
    setState(() {
      muted = !muted;
      if (muted) {
        lastVol = volume;
        volume = 0;
      } else {
        volume = lastVol > 0 ? lastVol : 100;
      }
    });
    player.setVolume(volume);
  }

  void toggleLoop() {
    // 单条循环与连播互不影响状态：循环开时优先循环，关掉后连播设置保持原样
    setState(() => loopOne = !loopOne);
    player.setPlaylistMode(loopOne ? PlaylistMode.single : PlaylistMode.none);
  }

  void toggleAutoplay() {
    setState(() {
      autoplay = !autoplay;
      if (autoplay) loopOne = false;
    });
    player.setPlaylistMode(loopOne ? PlaylistMode.single : PlaylistMode.none);
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
      setState(() => img = (img + dir).clamp(0, n - 1));
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
    autoTimer?.cancel();
    hideTimer?.cancel();
    retryTimer?.cancel();
    _wheelUnlock?.cancel();
    _wheelIdle?.cancel();
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
    player.dispose();
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
          child: Video(controller: vc, controls: NoVideoControls),
        ),
      );
    });
  }

  // 长简介/文案：弹出完整内容，避免被单行截断
  // 图文单张渲染：GIF 用 Image.network 才能播放动画，其余走缓存图
  Widget picView(String path) {
    final low = path.toLowerCase();
    if (low.endsWith('.gif') || low.contains('.gif?')) {
      return Image.network(cfg.base + cfg.media(path),
          headers: cfg.headers, fit: BoxFit.contain, gaplessPlayback: true);
    }
    return CachedNetworkImage(
        imageUrl: cfg.base + cfg.media(path),
        httpHeaders: cfg.headers,
        fit: BoxFit.contain);
  }

  void showCaption(String text) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151515),
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Expanded(
                  child: Text('作品简介',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70)),
                ),
                IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close,
                        size: 18, color: Colors.white54)),
              ]),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(text,
                      style: const TextStyle(
                          fontSize: 14, height: 1.5, color: Colors.white)),
                ),
              ),
            ]),
          ),
        ),
      ),
    ).whenComplete(() {
      // 关闭弹层后把焦点还给播放页，方向键可以继续翻页
      if (mounted) focus.requestFocus();
    });
  }

  String fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
    return Focus(
      focusNode: focus,
      autofocus: true,
      onKeyEvent: onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Listener(
          onPointerSignal: onWheel,
          // 双指轻触/捏合：清屏（再次双指恢复功能区）
          onPointerDown: (_) {
            // 点击画面时确保键盘焦点仍在播放页，避免模拟器丢焦点后方向键失效
            if (!focus.hasFocus) focus.requestFocus();
            pointers++;
            if (pointers == 2) {
              hapticTap();
              if (ui) {
                hideTimer?.cancel();
                setState(() => ui = false);
              } else {
                showUi();
              }
            }
          },
          onPointerUp: (_) {
            if (pointers > 0) pointers--;
          },
          onPointerCancel: (_) {
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
                physics:
                    (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
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
                            imageUrl: cfg.base + cfg.media(it['th'].toString()),
                            httpHeaders: cfg.headers,
                            fit: BoxFit.contain);
                  }
                  if (it['t'] == 'v') {
                    return GestureDetector(
                      onTap: onStageTap,
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
                              imageUrl:
                                  cfg.base + cfg.media(it['th'].toString()),
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
                    onTap: onStageTap,
                    onHorizontalDragEnd: (d) {
                      stopAuto();
                      final v = d.primaryVelocity ?? 0;
                      setState(() {
                        if (v < -100) {
                          img = (idx + 1).clamp(0, pics.length - 1);
                        } else if (v > 100) {
                          img = (idx - 1).clamp(0, pics.length - 1);
                        }
                      });
                    },
                    child: Stack(fit: StackFit.expand, children: [
                      picView(pics[idx]),
                      if (pics.length > 1)
                        Positioned(
                            top: 2,
                            right: 4,
                            child: SafeArea(
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
                            )),
                    ]),
                  );
                },
              ),
              Positioned(
                left: 8,
                top: 8,
                child: IgnorePointer(
                  ignoring: !ui,
                  child: AnimatedOpacity(
                    opacity: ui ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: SafeArea(
                      child: IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white70),
                          style: IconButton.styleFrom(
                              backgroundColor: Colors.black45)),
                    ),
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
                left: 14,
                right: 80,
                bottom: 96,
                child: IgnorePointer(
                  ignoring: !ui,
                  child: AnimatedOpacity(
                    opacity: ui ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: GestureDetector(
                      onTap: openAuthor,
                      child: Row(children: [
                        if ((w['av'] ?? '').toString().isNotEmpty)
                          ClipOval(
                              child: CachedNetworkImage(
                                  imageUrl:
                                      cfg.base + cfg.media(w['av'].toString()),
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
                              ]),
                              Row(children: [
                                Expanded(
                                  child: Text('${w['ti'] ?? ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.white70)),
                                ),
                                if (('${w['ti'] ?? ''}').length > 24)
                                  GestureDetector(
                                    onTap: () =>
                                        showCaption('${w['ti'] ?? ''}'),
                                    child: const Padding(
                                      padding: EdgeInsets.only(
                                          left: 6, top: 2, bottom: 2),
                                      child: Icon(Icons.unfold_more,
                                          size: 16, color: Colors.white54),
                                    ),
                                  ),
                              ]),
                            ])),
                      ]),
                    ),
                  ),
                ),
              ),
              if (showVol && ui)
                Positioned(
                  right: 16,
                  bottom: 128,
                  child: Container(
                    width: 220,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      IconButton(
                        onPressed: toggleMute,
                        tooltip: '静音',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                            muted || volume == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                            size: 18,
                            color: Colors.white70),
                      ),
                      Expanded(
                        child: Slider(
                          value: volume.clamp(0, 100),
                          min: 0,
                          max: 100,
                          onChanged: (v) {
                            setState(() {
                              volume = v;
                              muted = v == 0;
                            });
                            player.setVolume(v);
                          },
                        ),
                      ),
                    ]),
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
                          left: 12,
                          right: 12,
                          top: 10,
                          bottom: 6 + MediaQuery.of(context).padding.bottom),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Row(children: [
                          Text(
                              isV
                                  ? '${fmt(pos)} / ${fmt(dur)}'
                                  : '${idx + 1}/${pics.length}',
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
                                return SizedBox(
                                  height: 30,
                                  child: Row(
                                    children: List.generate(pics.length, (k) {
                                      final active = k <= idx;
                                      return Expanded(
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            stopAuto();
                                            setState(() => img = k);
                                          },
                                          child: Container(
                                            height: 30,
                                            alignment: Alignment.center,
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 120),
                                              height: k == idx ? 6 : 3,
                                              margin:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 1.5),
                                              decoration: BoxDecoration(
                                                color: active
                                                    ? (k == idx
                                                        ? Colors.white
                                                        : Colors.white70)
                                                    : Colors.white24,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
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
                                    setState(() => img = (f * (pics.length - 1))
                                        .round()
                                        .clamp(0, pics.length - 1));
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
                          IconButton(
                              onPressed: () =>
                                  setState(() => showVol = !showVol),
                              tooltip: '音量',
                              icon: Icon(
                                  muted || volume == 0
                                      ? Icons.volume_off
                                      : (volume < 50
                                          ? Icons.volume_down
                                          : Icons.volume_up),
                                  color: Colors.white70)),
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
                          IconButton(
                              onPressed: (dropBusy ||
                                      dropDayLeft <= 0 ||
                                      dropWeekLeft <= 0)
                                  ? null
                                  : _sendDrop,
                              tooltip:
                                  '小水滴：今日剩 $dropDayLeft/1，本周剩 $dropWeekLeft/3，累计 $dropTotal',
                              icon: dropBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white54))
                                  : Icon(Icons.water_drop,
                                      size: 21,
                                      color: dropDayLeft > 0 && dropWeekLeft > 0
                                          ? Colors.lightBlueAccent
                                          : Colors.white24)),
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
  List all = [];
  bool loading = true;
  String kw = '';

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  Future<void> loadAll() async {
    try {
      final r = await http.get(cfg.u('/api/index.json'), headers: cfg.headers);
      final cols = (jsonDecode(r.body)['collections'] as List);
      for (final c in cols) {
        final rr = await http.get(cfg.u('/api/c/${c['idx']}.json'),
            headers: cfg.headers);
        if (rr.statusCode != 200) continue;
        final ws = (jsonDecode(rr.body)['works'] as List);
        for (var i = 0; i < ws.length; i++) {
          all.add({'w': ws[i], 'works': ws, 'i': i, 'col': c['name']});
        }
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
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
                  child: Text('输入关键词，跨所有收藏夹搜索',
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
                                  imageUrl:
                                      cfg.base + cfg.media(w['th'].toString()),
                                  httpHeaders: cfg.headers,
                                  fit: BoxFit.cover)),
                      title: Text('${w['ti']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('@${w['a']} · ${e['col']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              PlayerPage(works: e['works'], start: e['i']))),
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
  const AuthorPage({super.key, required this.name});
  @override
  State<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends State<AuthorPage> {
  String bio = '';
  String av = '';
  List works = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r =
          await http.get(cfg.u('/api/authors.json'), headers: cfg.headers);
      final idx = jsonDecode(r.body) as Map;
      final info = idx[widget.name];
      if (info != null) {
        final d = await http.get(cfg.u('/api/a/${info['i']}.json'),
            headers: cfg.headers);
        final m = jsonDecode(d.body);
        bio = (m['bio'] ?? '').toString();
        av = (m['av'] ?? '').toString();
        works = (m['works'] as List);
        postStat('visit', widget.name);
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.name}')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipOval(
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
                                  imageUrl: cfg.base + cfg.media(av),
                                  httpHeaders: cfg.headers,
                                  width: 64,
                                  height: 64,
                                  fit: BoxFit.cover)),
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
              const Divider(height: 1),
              Expanded(child: WorkGrid(works: works)),
            ]),
    );
  }
}

class WorkGrid extends StatelessWidget {
  final List works;
  const WorkGrid({super.key, required this.works});
  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 3 / 4,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2),
      itemCount: works.length,
      itemBuilder: (_, i) {
        final w = works[i];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayerPage(works: works, start: i))),
          child: Stack(fit: StackFit.expand, children: [
            (w['th'] ?? '').toString().isEmpty
                ? Container(color: Colors.black26)
                : CachedNetworkImage(
                    imageUrl: cfg.base + cfg.media(w['th'].toString()),
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
          ]),
        );
      },
    );
  }
}
