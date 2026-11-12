import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
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
    SharedPreferences.getInstance().then((sp) {
      cfg.base = sp.getString('base') ?? '';
      cfg.user = sp.getString('user') ?? 'zzx';
      cfg.pass = sp.getString('pass') ?? '';
      setState(() => ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!ready) {
      return const MaterialApp(
          home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    return MaterialApp(
      title: '抖音收藏夹',
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

  Future<void> save() async {
    cfg.base = base.text.trim().replaceAll(RegExp(r'/+$'), '');
    cfg.user = user.text.trim();
    cfg.pass = pass.text;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('base', cfg.base);
    await sp.setString('user', cfg.user);
    await sp.setString('pass', cfg.pass);
    if (mounted) {
      Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('连接 NAS')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
            controller: base,
            decoration: const InputDecoration(
                labelText: 'NAS 地址', hintText: 'http://192.168.2.4:8090')),
        const SizedBox(height: 12),
        TextField(
            controller: user, decoration: const InputDecoration(labelText: '用户名')),
        const SizedBox(height: 12),
        TextField(
            controller: pass,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码')),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: save, child: const Text('保存并连接')),
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

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await http.get(cfg.u('/api/index.json'), headers: cfg.headers);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final list = (jsonDecode(r.body)['collections'] as List);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('抖音收藏夹'), actions: [
        IconButton(
            icon: const Icon(Icons.search),
            tooltip: '搜索',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SearchPage()))),
        IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsPage()))),
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
                      title: Text('(${c['idx']}) ${c['name']}'),
                      trailing: Text('${c['count']}',
                          style: const TextStyle(color: Colors.grey)),
                      onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => CollectionPage(
                                  name: c['name'], idx: c['idx']))),
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
    http.get(cfg.u('/api/c/${widget.idx}.json'), headers: cfg.headers).then((r) {
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
  bool paused = false;
  bool loading = true;
  bool muted = false;
  bool ui = true;
  bool fs = false;
  bool dragging = false;
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
    player.setPlaylistMode(PlaylistMode.loop);
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
        await player.open(Media(cfg.base + w['m'][0], httpHeaders: cfg.headers));
      } else if ((w['au'] ?? '').toString().isNotEmpty) {
        await player.open(Media(cfg.base + w['au'], httpHeaders: cfg.headers));
      }
    } catch (_) {}
    if (my != _openToken) return;
    try {
      await player.setVolume(muted ? 0 : 100);
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
      if (mounted && my == _openToken && w['t'] == 'v' && dur.inMilliseconds == 0) {
        player.open(Media(cfg.base + w['m'][0], httpHeaders: cfg.headers));
        player.play();
      }
    });
    if (w['t'] != 'v') startAuto();
  }

  void startAuto() {
    autoTimer?.cancel();
    if (manualPic) return;
    autoTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final w = widget.works[cur];
      if (w['t'] == 'v') return;
      final n = (w['m'] as List).length;
      if (img < n - 1) {
        setState(() => img++);
      } else {
        next();
      }
    });
  }

  void stopAuto() {
    manualPic = true;
    autoTimer?.cancel();
  }

  void next() {
    if (cur < widget.works.length - 1) {
      pc.nextPage(
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  void prev() {
    if (cur > 0) {
      pc.previousPage(
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  void togglePause() {
    if (paused) {
      player.play();
    } else {
      player.pause();
    }
  }

  void toggleMute() {
    setState(() => muted = !muted);
    player.setVolume(muted ? 0 : 100);
  }

  void cycleSpeed() {
    setState(() {
      speed = speed >= 2.0 ? 1.0 : (speed >= 1.5 ? 2.0 : 1.5);
    });
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
      hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => ui = false);
      });
    }
  }

  void onWheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastWheel < 260) return;
    if (e.scrollDelta.dy > 8) {
      _lastWheel = now;
      next();
    } else if (e.scrollDelta.dy < -8) {
      _lastWheel = now;
      prev();
    }
  }

  KeyEventResult onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyJ) {
      next();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyK) {
      prev();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.space) {
      togglePause();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyM) {
      toggleMute();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      toggleFs();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyL) {
      final w = widget.works[cur];
      if (w['t'] != 'v') {
        stopAuto();
        setState(() => img = (img + 1).clamp(0, (w['m'] as List).length - 1));
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyH) {
      final w = widget.works[cur];
      if (w['t'] != 'v') {
        stopAuto();
        setState(() => img = (img - 1).clamp(0, (w['m'] as List).length - 1));
      }
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
                      onTap: () {
                        togglePause();
                        showUi();
                      },
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
                    onTap: () {
                      togglePause();
                      showUi();
                    },
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
                      CachedNetworkImage(
                          imageUrl: cfg.base + pics[idx],
                          httpHeaders: cfg.headers,
                          fit: BoxFit.contain),
                      if (pics.length > 1)
                        Positioned(
                            bottom: 120,
                            left: 0,
                            right: 0,
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                    pics.length,
                                    (k) => Container(
                                          width: 5,
                                          height: 5,
                                          margin: const EdgeInsets.symmetric(
                                              horizontal: 3),
                                          decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: k == idx
                                                  ? Colors.white
                                                  : Colors.white30),
                                        )))),
                    ]),
                  );
                },
              ),
              Positioned(
                left: 8,
                top: 8,
                child: SafeArea(
                  child: IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon:
                          const Icon(Icons.arrow_back, color: Colors.white70),
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.black45)),
                ),
              ),
              if (paused)
                const IgnorePointer(
                  child: Center(
                    child: Icon(Icons.play_arrow,
                        size: 76, color: Colors.white30),
                  ),
                ),
              Positioned(
                left: 14,
                right: 80,
                bottom: 96,
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
                        const CircleAvatar(radius: 19, child: Icon(Icons.person)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text('@${w['a']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text('${w['ti'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white70)),
                          ])),
                    ]),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
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

                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => seekAt(d.localPosition),
                              onHorizontalDragStart: (_) =>
                                  setState(() => dragging = true),
                              onHorizontalDragUpdate: (d) =>
                                  seekAt(d.localPosition),
                              onHorizontalDragEnd: (_) =>
                                  setState(() => dragging = false),
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
                                      widthFactor: progress,
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
                            onPressed: toggleMute,
                            icon: Icon(muted ? Icons.volume_off : Icons.volume_up,
                                color: Colors.white70)),
                        IconButton(
                            onPressed: cycleSpeed,
                            icon: Text('${speed}x',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white70))),
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
      final r = await http.get(cfg.u('/api/authors.json'), headers: cfg.headers);
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
                                          style: const TextStyle(
                                              fontSize: 26))))
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
