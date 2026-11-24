/// 接口地址拼接的唯一实现（第十四批，owner 2026-11-24）。
///
/// 「`base` + `/api/...`」这件事此前有六种写法，且都没有真正归一：
///
/// | 位置 | 写法 | 缺口 |
/// |---|---|---|
/// | `lib_cover.absoluteMediaUrl` | `base.trim().replaceFirst(RegExp(r'/+$'), '')` | 对 |
/// | `collection_sync_panel._settingsUri` | 同上（第二份） | 对 |
/// | `sync_ledger.syncLogsUri/syncRetryUri` | `b.endsWith('/') ? '' : '/'` | 双斜杠 `//` 只去掉一个 |
/// | `deleted_monitor.deletedWorkUri` | 同上（第二份） | 同上 |
/// | `unit_crawler.unitCrawlerUrl` | `base.substring(0, base.length - 1)` | 同上 |
///
/// 更关键的是**没有任何一处补协议**：`Uri.parse('192.168.2.4:8090/api/x')`
/// 会抛 `FormatException: Scheme not starting with alphabetic character`，
/// 而 `Uri.parse('nas:8090/api/x')` 不抛——它把 `nas` 当成了 scheme，
/// host 为空、path 变成 `8090/api/x`，请求静静地打到一个不存在的地方。
///
/// 现在只有 [baseForJoin] 一处归一（复用 `multi_server.normalizeBase` 的规则），
/// 所有拼接走 [joinApiUrl] / [apiUri]。
library;

import 'multi_server.dart' show normalizeBase;

/// 可拼接的 base：去空白、补协议、去尾部所有 `/`。
///
/// 与连接配置写入时用的是同一个 [normalizeBase]，所以「配置里存的」与
/// 「拼地址时用的」不可能出现两种口径。
String baseForJoin(String raw) => normalizeBase(raw);

/// `<base><path>?query`，path 缺前导 `/` 时自动补。
///
/// [query] 的值按 `Uri.encodeQueryComponent` 编码（空格→`+`，与既有
/// `/api/unit/*` 的 `rel=%281%29+A` 保持一致）。
String joinApiUrl(String base, String path, {Map<String, String>? query}) {
  final b = baseForJoin(base);
  final p = path.isEmpty
      ? '/'
      : (path.startsWith('/') ? path : '/$path');
  if (query == null || query.isEmpty) return '$b$p';
  final q = query.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  // path 自带查询时接着往后拼，不能出现两个 `?`。
  return '$b$p${p.contains('?') ? '&' : '?'}$q';
}

/// 库作用域接口地址：`<base><path>?lib=<libId>`（lib 为空时不带 lib 参数）。
///
/// 此前这个形状在 `cfg.u`、`_u`（两处页面级 State）里被写了三遍，
/// 其中两遍漏了「path 已带 `?` 时用 `&`」的处理。
String libApiUrl(String base, String path, String libId) => joinApiUrl(
      base,
      path,
      query: libId.trim().isEmpty ? null : {'lib': libId.trim()},
    );

/// [joinApiUrl] 的 Uri 版本；base 为空时返回 null（调用方据此回退空态）。
Uri? apiUri(String base, String path, {Map<String, String>? query}) {
  if (baseForJoin(base).isEmpty) return null;
  return Uri.parse(joinApiUrl(base, path, query: query));
}

/// 只拼查询串（path 自带 `?` 的情况，如 `/api/maintenance?deep=1`）。
/// [flag] 为空时原样返回（调用方按开关决定是否带参数）。
String withQueryFlag(String url, String flag) {
  if (flag.isEmpty) return url;
  return url.contains('?') ? '$url&$flag' : '$url?$flag';
}
