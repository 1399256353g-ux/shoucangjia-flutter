// J7 多网络连接：一个 NAS 地址（IP:端口）就是一条「连接」。
//
// 规则：
//  - 可添加多条连接，每条有独立地址与账号；
//  - P5 连接语义：关闭一条连接＝与该服务端**断连**——不再向它发任何请求、
//    密码字段立即清空（不保存明文），重新开启必须重新输入密码；
//  - 多个连接指向同一个库（库 id 相同）时只显示一份，优先取靠前且可见的连接；
//  - 删除连接只删除本机配置，不动 NAS 数据。
//
// 本文件只放纯逻辑（解析 / 合并 / 去重 / 映射），便于单测。

import 'dart:convert';

import 'json_num.dart';
import 'text_fold.dart';

class ServerConn {
  final String id;
  final String label;
  final String base;
  final String user;
  final String pass;

  /// 是否处于「已连接」状态。false 表示已断连：不参与聚合与请求，
  /// 且 [pass] 必为空（断连时清掉，重开要重新输入）。
  final bool enabled;

  const ServerConn({
    required this.id,
    required this.label,
    required this.base,
    required this.user,
    required this.pass,
    this.enabled = true,
  });

  String get title => label.trim().isEmpty ? base : label.trim();

  /// 供 UI 卡片使用的名称：**没填就是空串**，不回退成网址（owner 2026-11-24）。
  ///
  /// 历史问题：媒体库卡片取 `title`，而 `title` 在 label 为空时回退成 `base`，
  /// 于是首页卡片上只显示一串 `http://192.168.x.x:8090`，库名完全消失。
  /// 这里只返回用户真正填过的名称，空串交由调用方回退到「媒体库根目录名」。
  String get cardLabel => label.trim();

  /// 历史字段名（旧代码/旧测试用 `visible` 表达同一件事）。
  bool get visible => enabled;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'base': base,
        'user': user,
        'pass': pass,
        'enabled': enabled,
      };

  ServerConn copyWith({
    String? label,
    String? base,
    String? user,
    String? pass,
    bool? enabled,
  }) =>
      ServerConn(
        id: id,
        label: label ?? this.label,
        base: base ?? this.base,
        user: user ?? this.user,
        pass: pass ?? this.pass,
        enabled: enabled ?? this.enabled,
      );

  static ServerConn? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final base = normalizeBase('${raw['base'] ?? ''}');
    if (base.isEmpty) return null;
    var id = '${raw['id'] ?? ''}'.trim();
    if (id.isEmpty) id = 'srv-${base.hashCode.abs()}';
    // 新格式 `enabled`；旧格式只有 `visible`，按同一语义读入。
    // 不能写 `!= false`：`0` / `"false"` / `"0"` 都不是布尔 false，
    // 于是被断连的旧记录读回来又变成「已连接」，且密码重新保留。
    final enabled = boolOf(
        raw.containsKey('enabled') ? raw['enabled'] : raw['visible'], true);
    return ServerConn(
      id: id,
      label: '${raw['label'] ?? ''}'.trim(),
      base: base,
      user: '${raw['user'] ?? 'zzx'}',
      // 断连的连接不保留任何凭据（历史数据里可能还留着，读入即丢弃）。
      pass: enabled ? '${raw['pass'] ?? ''}' : '',
      enabled: enabled,
    );
  }
}

/// 断开一条连接：清密码、置未连接。调用方负责落盘。
//
// 断连后的连接不再参与合并、不再发请求，界面上显示叉号；
// 重新开启只能通过 [reconnectServer] 输入密码。
ServerConn disconnectServer(ServerConn s) =>
    s.copyWith(enabled: false, pass: '');

/// 重新连接：写入用户刚输入的密码并恢复启用状态。
ServerConn reconnectServer(ServerConn s, String pass) =>
    s.copyWith(enabled: true, pass: pass);

/// 可以发起请求 / 参与聚合的连接。
List<ServerConn> liveServers(List<ServerConn> all) =>
    [for (final s in all) if (s.enabled) s];

/// 已断连的连接数量（>0 时主页左上角显示叉号）。
int disconnectedCount(List<ServerConn> all) =>
    all.where((s) => !s.enabled).length;

/// 规范化地址：去空格、补协议、去尾部斜杠；**无法成为可用地址时返回空串**。
///
/// 旧实现有两处顺序/大小写缺口，实测都会产出「看起来像地址、其实打不通」的串：
///
/// ```
/// 'http://'          -> 先剥尾斜杠变成 'http:'，再补协议 -> 'http://http:'（host=http）
/// 'HTTP://NAS:8090'  -> startsWith('http://') 为 false（大小写敏感）
///                        -> 'http://HTTP://NAS:8090'（host=http，端口无）
/// ```
///
/// 前者是「用户只填了协议」的常见中间态，后者是 owner 从浏览器地址栏
/// 复制大写协议的结果。两种都会让该连接的所有请求打到不存在的主机上，
/// 界面只显示「连接失败」，看不出是地址被自己改坏了。
///
/// 所以这里先认协议（http/https，忽略大小写）、再剥尾斜杠、最后用
/// `Uri` 校验 host 非空；不合法返回空串，由调用方按「地址不能为空」处理。
String normalizeBase(String raw) {
  final input = raw.trim();
  if (input.isEmpty) return '';
  // 全角折叠只用于**识别**：折叠是严格一对一的（长度不变），所以折叠串上的
  // 下标可以直接拿去切原串——路径段保持用户输入的原样，不被改写。
  //
  // 中文输入法打出的 `nas：8090`（全角冒号）此前会被 `Uri` 编成
  // `host = nas%EF%BC%9A8090`，是「语法合法、永远连不上」的地址；
  // `http://nas:８０９０`（全角数字）则直接落到「地址不能为空」。
  final folded = foldFullWidthAscii(input);
  final m = RegExp(r'^(https?):/*', caseSensitive: false).firstMatch(folded);
  var scheme = 'http';
  var start = 0;
  if (m != null) {
    scheme = m.group(1)!.toLowerCase();
    start = m.end;
  } else if (folded.contains('://')) {
    // 非 http(s) 协议（ftp/file/...）：本 App 只说 http(s)，不猜着改。
    return '';
  }
  final tailOrig = input.substring(start);
  final tailFold = folded.substring(start);
  // 去尾部所有 `/`：在折叠串上定位长度，再按同一长度切原串。
  var end = tailFold.length;
  while (end > 0 && tailFold.codeUnitAt(end - 1) == 0x2F) {
    end--;
  }
  if (end == 0) return '';
  final bodyOrig = tailOrig.substring(0, end);
  final bodyFold = tailFold.substring(0, end);
  // 主机段里的空白一律去掉再校验：`Uri.tryParse('http:// nas:8090')` **不报错**，
  // 它把空格编进主机名（`host == '%20nas'`），产出一个「语法合法、永远连不上」
  // 的地址。这类输入几乎全是手输/复制时的多余空格（`http:// nas`、
  // `nas :8090`），去掉空白正是用户本意；真正的空格文件名只可能出现在路径里，
  // 而连接地址不带路径。校验仍然在下面照常做（去掉后可能变成空主机）。
  final cut = bodyFold.indexOf('/');
  final authority = cut < 0 ? bodyFold : bodyFold.substring(0, cut);
  // 分隔符本身也归一成半角 `/`：中文输入法里 `／`（U+FF0F）就是斜杠。
  // 漏掉这一步时 `http://nas／8090` 会把 `／8090` 当成路径粘在主机上
  // （host 变成 `nas%EF%BC%8F8090`），`http://nas：8090／path` 更直接
  // 得到一个解析失败的串 → 用户看到「地址不能为空」。
  // 分隔符之后的字符仍保留原样：那是路径内容，不是用户写错的分隔符。
  final tail = cut < 0 ? '' : '/${bodyOrig.substring(cut + 1)}';
  final cleanAuthority = authority.replaceAll(RegExp(r'\s+'), '');
  if (cleanAuthority.isEmpty) return '';
  final url = '$scheme://$cleanAuthority$tail';
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return '';
  // 端口越界同样只是「看起来是地址」：`Uri` 接受 `:0` 与 `:65536`，但
  // 一个用不出站连接、一个超出 16 位范围，请求只会失败且看不出原因。
  if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) return '';
  return url;
}

/// 解析连接列表；坏数据跳过，重复地址只保留第一条。
List<ServerConn> decodeServers(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final j = jsonDecode(raw);
    if (j is! List) return const [];
    final out = <ServerConn>[];
    final seenBase = <String>{};
    final seenId = <String>{};
    for (final e in j) {
      final s = ServerConn.fromJson(e);
      if (s == null) continue;
      if (!seenBase.add(s.base)) continue;
      if (!seenId.add(s.id)) continue;
      out.add(s);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

String encodeServers(List<ServerConn> servers) =>
    jsonEncode([for (final s in servers) s.toJson()]);

/// 新版没有连接但旧版存了单条 `base` 时，自动迁移为第一条连接。
List<ServerConn> migrateLegacy({
  required List<ServerConn> servers,
  required String base,
  required String user,
  required String pass,
}) {
  if (servers.isNotEmpty) return servers;
  final b = normalizeBase(base);
  if (b.isEmpty) return servers;
  return [
    ServerConn(id: 'legacy', label: '默认连接', base: b, user: user, pass: pass)
  ];
}

/// 一条连接抓到的库列表 / 库树。
class ServerLibraries {
  final ServerConn server;
  final List<Map<String, dynamic>> libraries;
  final Map<String, dynamic>? tree;
  final String? error;

  const ServerLibraries({
    required this.server,
    this.libraries = const [],
    this.tree,
    this.error,
  });
}

/// 给库/树节点补上来源连接字段，便于切换时路由到正确的 IP。
Map<String, dynamic> _tag(Map raw, ServerConn s) => {
      ...Map<String, dynamic>.from(raw),
      '_serverId': s.id,
      '_serverBase': s.base,
      '_serverLabel': s.cardLabel,
      '_serverUser': s.user,
      '_serverPass': s.pass,
    };

/// 聚合已注册库：按库 id 去重，先出现的连接优先。
List<Map<String, dynamic>> mergeRegisteredLibraries(
    List<ServerLibraries> snapshots) {
  final seen = <String>{};
  final out = <Map<String, dynamic>>[];
  for (final snap in snapshots) {
    if (!snap.server.visible) continue;
    for (final raw in snap.libraries) {
      final m = Map<String, dynamic>.from(raw);
      final id = '${m['id'] ?? ''}'.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(_tag(m, snap.server));
    }
  }
  return out;
}

/// 聚合 v2 库树：大库与基础库都按 id 去重。
Map<String, dynamic>? mergeLibraryTrees(List<ServerLibraries> snapshots) {
  final seenBig = <String>{};
  final seenBasic = <String>{};
  final bigs = <Map<String, dynamic>>[];
  final basics = <Map<String, dynamic>>[];
  var any = false;
  for (final snap in snapshots) {
    if (!snap.server.visible || snap.tree == null) continue;
    final t = snap.tree!;
    final rb = t['bigLibraries'];
    final rs = t['basicLibraries'];
    if (rb is! List || rs is! List) continue;
    any = true;
    for (final raw in rb) {
      if (raw is! Map) continue;
      final id = '${raw['id'] ?? ''}'.trim();
      if (id.isEmpty || !seenBig.add(id)) continue;
      bigs.add(_tag(raw, snap.server));
    }
    for (final raw in rs) {
      if (raw is! Map) continue;
      final id = '${raw['id'] ?? ''}'.trim();
      if (id.isEmpty || !seenBasic.add(id)) continue;
      basics.add(_tag(raw, snap.server));
    }
  }
  if (!any) return null;
  return {
    ...{
      'bigLibraries': bigs,
      'basicLibraries': basics,
    }
  };
}

/// 单条绑定记录的唯一拼装口。
///
/// 字段集合必须与 [decodeBindings] 读的字段**完全对称**：
/// 此前 [buildBindings] 与 `main.dart` 的一段内联代码各拼一次 `{base,user,pass,server}`
/// 形状，而 `label` 只有前者写，`decodeBindings` 两边都不读——
/// 一处加字段另两处不跟，就成了「写进去、读不回来」。
Map<String, String> bindingEntry(ServerConn s) => {
      'base': s.base,
      'user': s.user,
      'pass': s.pass,
      'server': s.id,
      // owner 2026-11-24：首页媒体库卡片要显示连接名，绑定必须带上它。
      'label': s.cardLabel,
    };

/// 库 → 连接映射，持久化后启动时就能按库路由。
Map<String, Map<String, String>> buildBindings({
  required List<ServerConn> servers,
  required List<Map<String, dynamic>> libraries,
}) {
  final byId = {for (final s in servers) s.id: s};
  final out = <String, Map<String, String>>{};
  for (final l in libraries) {
    final id = '${l['id'] ?? ''}'.trim();
    final sid = '${l['_serverId'] ?? ''}'.trim();
    if (id.isEmpty || sid.isEmpty) continue;
    final s = byId[sid];
    if (s == null) continue;
    out[id] = bindingEntry(s);
  }
  return out;
}

/// 按当前**在线**连接修剪绑定表。
///
/// P5 的硬要求是「断连后密码立即清除、不再向该服务端发任何请求」。只在断开时
/// 调一次 [Cfg.dropServerBindings] 不够：绑定表同时落盘在 `lib_bindings_v1`，
/// 内存里删了、盘上还在，下次启动 `decodeBindings` 又把旧密码读回来，
/// 库路由依然指向已断连的服务端。
///
/// 所以把「绑定表必须与在线连接一致」做成启动时的一次性修剪：
///  - `server` 不在在线列表 → 整条丢弃（路由与凭据一起消失）；
///  - 旧格式没有 `server` 字段 → 按 base 匹配，匹配不上同样丢弃；
///  - 命中在线连接 → 用连接的当前值重建（用户改过密码时不会留下旧密码）。
Map<String, Map<String, String>> pruneBindings(
  Map<String, Map<String, String>> bindings,
  List<ServerConn> live,
) {
  final byId = {for (final s in live) s.id: s};
  final byBase = {for (final s in live) s.base: s};
  final out = <String, Map<String, String>>{};
  bindings.forEach((libId, b) {
    final sid = '${b['server'] ?? ''}'.trim();
    final s = sid.isNotEmpty
        ? byId[sid]
        : byBase[normalizeBase('${b['base'] ?? ''}')];
    if (s == null) return;
    out[libId] = bindingEntry(s);
  });
  return out;
}

/// 解析持久化的库映射；坏项跳过。
///
/// 必须把 [buildBindings] 写进去的 `label` 读回来：此前这里只读
/// base/user/pass/server，每次重启后 `serverLabelFor()` 一律返回空串，
/// 首页媒体库卡片上的连接名在首次启动后消失（写进去、读不回来）。
Map<String, Map<String, String>> decodeBindings(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const {};
  try {
    final j = jsonDecode(raw);
    if (j is! Map) return const {};
    final out = <String, Map<String, String>>{};
    j.forEach((k, v) {
      if (v is! Map) return;
      final base = normalizeBase('${v['base'] ?? ''}');
      if (base.isEmpty) return;
      out['$k'] = {
        'base': base,
        'user': '${v['user'] ?? 'zzx'}',
        'pass': '${v['pass'] ?? ''}',
        'server': '${v['server'] ?? ''}',
        'label': '${v['label'] ?? ''}',
      };
    });
    return out;
  } catch (_) {
    return const {};
  }
}

String encodeBindings(Map<String, Map<String, String>> bindings) =>
    jsonEncode(bindings);

/// 新增连接时生成稳定且不重复的 id。
String nextServerId(List<ServerConn> servers) {
  var n = servers.length + 1;
  final used = {for (final s in servers) s.id};
  while (used.contains('srv-$n')) {
    n++;
  }
  return 'srv-$n';
}
