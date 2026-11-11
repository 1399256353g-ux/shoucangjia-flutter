import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
        'Authorization': 'Basic ${base64Encode(utf8.encode('$user:$pass'))}',
      };
  Uri u(String path) => Uri.parse('$base$path');
}

final cfg = Cfg();

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
    SharedPreferences.getInstance().then((sp) {
      cfg.base = sp.getString('base') ?? '';
      cfg.user = sp.getString('user') ?? 'zzx';
      cfg.pass = sp.getString('pass') ?? '';
      setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) return const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    return MaterialApp(
      title: '收藏夹',
      theme: ThemeData.dark(useMaterial3: true),
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
  late final TextEditingController base = TextEditingController(text: cfg.base.isEmpty ? 'http://192.168.2.4:8090' : cfg.base);
  late final TextEditingController user = TextEditingController(text: cfg.user);
  late final TextEditingController pass = TextEditingController(text: cfg.pass);

  Future<void> save() async {
    cfg.base = base.text.trim().replaceAll(RegExp(r'/+$'), '');
    cfg.user = user.text.trim();
    cfg.pass = pass.text;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base', cfg.base);
    await sp.setString('user', cfg.user);
    await sp.setString('pass', cfg.pass);
    if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomePage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接 NAS')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(controller: base, decoration: const InputDecoration(labelText: 'NAS 地址', hintText: 'http://192.168.2.4:8090')),
        const SizedBox(height: 12),
        TextField(controller: user, decoration: const InputDecoration(labelText: '用户名')),
        const SizedBox(height: 12),
        TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: '密码')),
        const SizedBox(height: 24),
        FilledButton(onPressed: save, child: const Text('保存并连接')),
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
  String? err;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await http.get(cfg.u('/api/index.json'), headers: cfg.headers);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      setState(() => cols = (jsonDecode(r.body)['collections'] as List));
    } catch (e) {
      setState(() => err = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('收藏夹'), actions: [
        IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage()))),
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
                    return ListTile(
                      title: Text('(${c['idx']}) ${c['name']}'),
                      trailing: Text('${c['count']}', style: const TextStyle(color: Colors.grey)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CollectionPage(name: c['name'], idx: c['idx']))),
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

  @override
  void initState() {
    super.initState();
    http.get(cfg.u('/api/c/${widget.idx}.json'), headers: cfg.headers).then((r) {
      setState(() => works = (jsonDecode(r.body)['works'] as List));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: works.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 180, childAspectRatio: 3 / 4, mainAxisSpacing: 2, crossAxisSpacing: 2),
              itemCount: works.length,
              itemBuilder: (_, i) {
                final w = works[i];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerPage(works: works, start: i))),
                  child: Stack(fit: StackFit.expand, children: [
                    (w['th'] ?? '').toString().isEmpty
                        ? Container(color: Colors.black26)
                        : CachedNetworkImage(imageUrl: cfg.base + w['th'], httpHeaders: cfg.headers, fit: BoxFit.cover, errorWidget: (_, __, ___) => Container(color: Colors.black26)),
                    Positioned(right: 4, top: 4, child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), color: Colors.black54, child: Text(w['t'] == 'v' ? '视频' : '图文', style: const TextStyle(fontSize: 10)))),
                  ]),
                );
              },
            ),
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
  int cur = 0;

  @override
  void initState() {
    super.initState();
    cur = widget.start;
  }

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: pc,
        scrollDirection: Axis.vertical,
        itemCount: widget.works.length,
        onPageChanged: (i) => setState(() => cur = i),
        itemBuilder: (_, i) => WorkView(work: widget.works[i], active: i == cur),
      ),
    );
  }
}

class WorkView extends StatefulWidget {
  final Map work;
  final bool active;
  const WorkView({super.key, required this.work, required this.active});
  @override
  State<WorkView> createState() => _WorkViewState();
}

class _WorkViewState extends State<WorkView> {
  Player? player;
  VideoController? vc;
  int img = 0;

  @override
  void initState() {
    super.initState();
    if (widget.work['t'] == 'v') {
      player = Player();
      vc = VideoController(player!);
      player!.open(Media(cfg.base + widget.work['m'][0], httpHeaders: cfg.headers));
    } else if ((widget.work['au'] ?? '').toString().isNotEmpty) {
      player = Player();
      player!.open(Media(cfg.base + widget.work['au'], httpHeaders: cfg.headers));
    }
  }

  @override
  void didUpdateWidget(covariant WorkView old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && player != null) player!.play();
    if (!widget.active && old.active && player != null) player!.pause();
  }

  @override
  void dispose() {
    player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.work;
    final isV = w['t'] == 'v';
    return Stack(children: [
      Positioned.fill(
        child: isV && vc != null
            ? Video(controller: vc!)
            : GestureDetector(
                onTapUp: (d) {
                  final width = MediaQuery.of(context).size.width;
                  setState(() {
                    if (d.localPosition.dx < width / 2) {
                      img = (img - 1).clamp(0, (w['m'] as List).length - 1);
                    } else {
                      img = (img + 1).clamp(0, (w['m'] as List).length - 1);
                    }
                  });
                },
                child: CachedNetworkImage(imageUrl: cfg.base + w['m'][img], httpHeaders: cfg.headers, fit: BoxFit.contain),
              ),
      ),
      Positioned(left: 16, right: 80, bottom: 40, child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          if ((w['av'] ?? '').toString().isNotEmpty)
            ClipOval(child: CachedNetworkImage(imageUrl: cfg.base + w['av'], httpHeaders: cfg.headers, width: 40, height: 40, fit: BoxFit.cover)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('@${w['a']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('ID ${w['ai'] ?? '-'}', style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ])),
        ]),
        const SizedBox(height: 8),
        Text(w['ti'] ?? '', maxLines: 3, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text('${w['d']}${isV ? '' : ' · 图文 ${(w['m'] as List).length} 张'}', style: const TextStyle(fontSize: 11, color: Colors.white60)),
      ])),
    ]);
  }
}
