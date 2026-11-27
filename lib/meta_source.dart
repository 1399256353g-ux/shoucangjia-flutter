/// `LibMeta.load` 的「读哪台服务器」显式参数（唯一实现）。
///
/// 背景：`LibMeta.load(lib)` 内部一律走 `cfg.u(path, lib: lib)` /
/// `cfg.headersFor(lib)` / `cfg.baseFor(lib)`。而这三者是**绑定表**的读取口，
/// 绑定表只在首页聚合库列表时建立（`buildBindings`）：
///
///  - 从设置页直接进入（首屏还没聚合）时表是空的 → 回落 `cfg.base`
///    （默认那台服务器）；
///  - 爬虫设置页按连接逐台取元数据时，第二台服务端的库 id 被拿去请求
///    默认服务器：要么 404（叶节点全落 SECRET），要么**恰好**同名库 id
///    存在，于是拿到另一台服务器的整棵树而界面显示第二台的名字。
///
/// 这类「地址按 lib 路由、来源却由一张可能为空的表决定」的缺陷在
/// 0.9.319–0.9.322 已连续修过四处（同步/小水滴/图文/配置页）。这里是同族
/// 最后一处：调用方**知道自己读的是哪台服务器**时，把连接显式传进来，
/// 不再让函数去猜。
///
/// 缓存键也必须带连接：两台服务端各有一个 `lib-1` 时，只按 `lib` 做键
/// 会让后到的一份把先到的一份顶掉（首页看得到、设置页看不到）。
library;

import 'api_url.dart';
import 'basic_auth.dart';
import 'node_key.dart' show scopedKey, scopedKeyIsFor;
import 'server_origin.dart';

/// 一条读取来源：连接 id + 地址 + 账号。
///
/// `none` 表示「按当前绑定路由」（旧行为，单连接/调用方不知道来源时）。
class MetaSource {
  final String serverId;
  final String base;
  final String user;
  final String pass;

  /// 现成的鉴权头（调用方手里只有拼好的头、没有账号密码时用）。
  ///
  /// 优先于 [user]/[pass]：删除监测这类页面拿到的是父页面传下来的
  /// `headers`，再从里面反解账号密码只会多出一条会分叉的解析路径。
  final Map<String, String> headerOverride;

  const MetaSource({
    this.serverId = '',
    this.base = '',
    this.user = '',
    this.pass = '',
    this.headerOverride = const <String, String>{},
  });

  /// 不指定来源：由 `cfg` 绑定表决定（旧行为）。
  static const MetaSource none = MetaSource();

  /// 地址为空即视为「未指定」——空地址不能拿去拼请求。
  bool get isEmpty => base.trim().isEmpty;

  bool get isScoped => !isEmpty;

  /// 从一条带来源字段的记录（库/节点）构造。
  factory MetaSource.ofOrigin(dynamic record) {
    final o = serverOriginOf(record);
    return MetaSource(
        serverId: o.id, base: o.base, user: o.user, pass: o.pass);
  }

  /// 从一条已配置的连接构造（不依赖 `multi_server`，避免把连接模型
  /// 拖进这个纯路由文件）。
  factory MetaSource.ofServer({
    required String id,
    required String base,
    required String user,
    required String pass,
  }) =>
      MetaSource(serverId: id, base: base, user: user, pass: pass);

  /// 已知地址与鉴权头、但不知道连接 id（记录从上一页透传下来）。
  factory MetaSource.ofBase(String base, Map<String, String> headers) =>
      MetaSource(base: base, headerOverride: headers);

  /// 解析该库在这条连接上的接口地址。
  ///
  /// 未指定来源时返回 null，由调用方回落到 `cfg.u`。
  Uri? apiUri(String lib, String path) {
    if (isEmpty) return null;
    return Uri.parse(libApiUrl(base, path, lib));
  }

  /// 该库在这条连接上的鉴权头；未指定来源时返回 null。
  Map<String, String>? headers() {
    if (isEmpty) return null;
    if (headerOverride.isNotEmpty) return headerOverride;
    return {'Authorization': basicAuthHeader(user, pass)};
  }
}

/// 元数据缓存键：指定来源时带连接 id，否则就是库 id（旧键）。
///
/// 分隔符与 `node_key` / `unitScopeKey` 同一个（`\u0001`）：库 id 与连接 id
/// 都可能含 `:`、`/`，用它们做分隔会出现两条不同记录拼出同一个键。
String metaCacheKey(String lib, MetaSource source) {
  final l = lib.trim();
  if (source.isEmpty) return l;
  final sid = source.serverId.trim();
  if (sid.isEmpty) {
    // 有地址没 id（手工构造的连接）：用地址做作用域，仍不允许跨服务器共用。
    return scopedKey(l, source.base);
  }
  return scopedKey(l, sid);
}

/// [key] 是否属于库 [lib]（不带来源的键与任何作用域键都算）。
///
/// `invalidate(lib)` 要清掉该库**全部连接**的缓存，而不只是默认那一份。
/// 判定只有一处（`node_key.scopedKeyIsFor`）：它与作者类型索引那边是**同一个
/// 函数体**，两处各写一份时总有一处忘记排除 `lib-1` / `lib-10` 这类前缀关系。
bool metaKeyIsFor(String key, String lib) => scopedKeyIsFor(key, lib);
