import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app_settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const App());
}

class Cfg {
  String base = '';
  String user = 'zzx';
  String pass = '';
  Map<String, String> get headers => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
      };
  Uri u(String path) => Uri.parse('$base$path');
}

final cfg = Cfg();
final navKey = GlobalKey<NavigatorState>();

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
                          color:
                              testOk == true ? Colors.green : Colors.redAccent))),
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
          onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const KeyBindingsPage())),
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
        const Text('默认播放倍速',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
      appBar: AppBar(title: const Text('抖音收藏夹'), actions: [
        if (defaultIdx != null)
          IconButton(
              icon: const Icon(Icons.star, color: Colors.amber),
              tooltip: '打开默认收藏夹',
              onPressed: openDefault),
        IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const SearchPage()))),
        IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsHubPage()));
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
                                  imageUrl: cfg.base + cover,
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
  String filter = 'all';
  String sort = 'new';

  List get view {
    var v = List.from(works);
    if (filter == 'v') v = v.where((w) => w['t'] == 'v').toList();
    if (filter == 'p') v = v.where((w) => w['t'] == 'p').toList();
    if (filter == 'del') v = v.where((w) => w['del'] == 1).toList();
    if (sort == 'old') {
      v.sort((a, b) => '${a['d']}'.compareTo('${b['d']}'));
    } else if (sort == 'title') {
      v.sort((a, b) => '${a['ti']}'.compareTo('${b['ti']}'));
    } else {
      v.sort((a, b) => '${b['d']}'.compareTo('${a['d']}'));
    }
    return v;
  }

  @override
  void initState() {
    super.initState();
    http
        .get(cfg.u('/api/c/${widget.idx}.json'), headers: cfg.headers)
        .then((r) {
      setState(() => works = (jsonDecode(r.body)['works'] as List));
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = view;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name), actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          onSelected: (v) => setState(() => sort = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'new', child: Text('最新在前')),
            PopupMenuItem(value: 'old', child: Text('最早在前')),
            PopupMenuItem(value: 'title', child: Text('按标题')),
          ],
        ),
      ]),
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
                  Text('${list.length}',
                      style: const TextStyle(color: Colors.grey)),
                ]),
              ),
              Expanded(child: WorkGrid(works: list)),
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

class _PlayerPageState extends State<PlayerPage> {
  late final PageController pc = PageController(initialPage: widget.start);
  late final Player player = Player();
  late final VideoController vc = VideoController(player);
  final FocusNode focus = FocusNode();
  int cur = 0;
  int img = 0;
  int _openToken = 0;
  int _lastWheel = 0;
  int _navAt = 0;
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
  bool autoplay = true;
  bool loopOne = false;
  double? dragFrac;
  bool resumeAfterDrag = false;
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
      if (mounted) setState(() => pos = p);
    });
    subDur = player.stream.duration.listen((d) {
      if (mounted) setState(() => dur = d);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      focus.requestFocus();
      open(widget.start);
    });
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
    });
    try {
      await player.stop();
    } catch (_) {}
    if (my != _openToken) return;
    final w = widget.works[i];
    try {
      if (w['t'] == 'v') {
        await player
            .open(Media(cfg.base + w['m'][0], httpHeaders: cfg.headers));
      } else if ((w['au'] ?? '').toString().isNotEmpty) {
        await player.open(Media(cfg.base + w['au'], httpHeaders: cfg.headers));
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
        player.open(Media(cfg.base + w['m'][0], httpHeaders: cfg.headers));
        player.play();
      }
    });
    if (w['t'] != 'v') startAuto();
  }

  void startAuto() {
    autoTimer?.cancel();
    autoTimer = null;
    if (manualPic || paused) return;
    final t = Timer.periodic(
        Duration(seconds: AppSettings.imageIntervalSec), (timer) {
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
  void _step(int delta) {
    final base = _pendingPage ?? cur;
    final target =
        (base + delta).clamp(0, widget.works.length - 1).toInt();
    if (target == base) return;
    _pendingPage = target;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _navAt < 450) {
      pc.jumpToPage(target);
    } else {
      pc.animateToPage(target,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
    _navAt = now;
  }

  // 全屏且功能隐藏时，第一次点击只呼出功能区，第二次才暂停
  void onStageTap() {
    if (!ui) {
      showUi();
      return;
    }
    togglePause();
    showUi();
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

  void toggleFs() {
    setState(() => fs = !fs);
    if (fs) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      showUi();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      setState(() => ui = true);
    }
  }

  void showUi() {
    if (!mounted) return;
    setState(() => ui = true);
    hideTimer?.cancel();
    if (fs) {
      hideTimer = Timer(Duration(seconds: AppSettings.hideUiSec), () {
        if (mounted) setState(() => ui = false);
      });
    }
  }

  void onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastWheel < 150) return;
    if (e.scrollDelta.dy > 1) {
      _lastWheel = now;
      next();
    } else if (e.scrollDelta.dy < -1) {
      _lastWheel = now;
      prev();
    }
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
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final bound = AppSettings.actionFor(k);
    if (bound != null) {
      doAction(bound);
      return KeyEventResult.handled;
    }
    // 固定键位：方向键翻页/切图，空格暂停，Esc 退出（不随自定义绑定变化）
    if (k == LogicalKeyboardKey.arrowDown) {
      next();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      prev();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      _stepImage(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _stepImage(-1);
      return KeyEventResult.handled;
    }
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
    autoTimer?.cancel();
    hideTimer?.cancel();
    retryTimer?.cancel();
    subPos?.cancel();
    subDur?.cancel();
    player.dispose();
    pc.dispose();
    focus.dispose();
    super.dispose();
  }

  // 长简介/文案：弹出完整内容，避免被单行截断
  // 图文单张渲染：GIF 用 Image.network 才能播放动画，其余走缓存图
  Widget picView(String path) {
    final low = path.toLowerCase();
    if (low.endsWith('.gif') || low.contains('.gif?')) {
      return Image.network(cfg.base + path,
          headers: cfg.headers, fit: BoxFit.contain, gaplessPlayback: true);
    }
    return CachedNetworkImage(
        imageUrl: cfg.base + path,
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
    );
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
      onKeyEvent: onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Listener(
          onPointerSignal: onWheel,
          child: MouseRegion(
            onHover: (_) => showUi(),
            child: Stack(children: [
              PageView.builder(
                controller: pc,
                scrollDirection: Axis.vertical,
                itemCount: widget.works.length,
                onPageChanged: open,
                itemBuilder: (_, i) {
                  final it = widget.works[i];
                  if (i != cur) {
                    return (it['th'] ?? '').toString().isEmpty
                        ? Container(color: Colors.black)
                        : CachedNetworkImage(
                            imageUrl: cfg.base + it['th'],
                            httpHeaders: cfg.headers,
                            fit: BoxFit.contain);
                  }
                  if (it['t'] == 'v') {
                    return GestureDetector(
                      onTap: onStageTap,
                      onLongPressStart: (_) => player.setRate(2.0),
                      onLongPressEnd: (_) => player.setRate(speed),
                      child: Stack(fit: StackFit.expand, children: [
                        if ((it['th'] ?? '').toString().isNotEmpty)
                          CachedNetworkImage(
                              imageUrl: cfg.base + it['th'],
                              httpHeaders: cfg.headers,
                              fit: BoxFit.contain),
                        Video(controller: vc, controls: NoVideoControls),
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
                          icon:
                              const Icon(Icons.arrow_back, color: Colors.white70),
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
                    onTap: () async {
                      player.pause();
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => AuthorPage(name: '${w['a']}')));
                      if (!paused && mounted) player.play();
                    },
                    child: Row(children: [
                      if ((w['av'] ?? '').toString().isNotEmpty)
                        ClipOval(
                            child: CachedNetworkImage(
                                imageUrl: cfg.base + w['av'],
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
                                        fontSize: 12,
                                        color: Colors.white70)),
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
                              final f = (p.dx / cons.maxWidth).clamp(0.0, 1.0);
                              player.seek(dur * f);
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
                              child: SizedBox(
                                height: 30,
                                child: Stack(
                                  alignment: Alignment.centerLeft,
                                  children: [
                                    Container(
                                        height: dragging ? 7 : 3,
                                        color: Colors.white24),
                                    FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: dragFrac ?? progress,
                                      child: Container(
                                          height: dragging ? 7 : 3,
                                          color: dragging
                                              ? Colors.white
                                              : Colors.white70),
                                    ),
                                  ],
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
                                color:
                                    loopOne ? Colors.white70 : Colors.white24)),
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
                                  imageUrl: cfg.base + w['th'],
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
                                  imageUrl: cfg.base + av,
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
                    imageUrl: cfg.base + w['th'],
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
