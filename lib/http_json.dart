// 响应体 → JSON 的唯一实现。
//
// 这件事此前有**两种写法、78 处调用**，且结果不一致：
//
//   jsonDecode(r.body)                       37 处
//   jsonDecode(utf8.decode(r.bodyBytes))     41 处
//
// `http` 包的 `Response.body` 按 `Content-Type` 的 charset 解码；
// **没有 charset 时**：`application/json` 走 utf8，其余一律走 **latin1**。
// 也就是说，同一个服务端接口哪天换了 content-type（`text/html`、
// `application/octet-stream`、代理改写），同一份 UTF-8 响应里的中文就会变成
// `ä½èèç94²` 这种乱码；而 `utf8.decode` 那 41 处永远是对的。
//
// 这不是"理论风险"：`test/http_json_test.dart` 用 `text/html` 头构造同一条
// 中文 JSON，`.body` 解析失败、`jsonOfBytes` 解析正确。
//
// 我们自己的服务端输出的就是 UTF-8，客户端不该把"能不能读懂"这件事交给
// 一个外部响应头决定。所以统一走 `utf8.decode(bodyBytes)`，不再用 `.body`。
//
// 注意与 `json_isolate.dart` 的分工：那个模块解决的是"大 payload 别卡 UI 线程"
// （compute/isolate），这里解决的是"按什么字符集解"。两者互不替代。

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_error_text.dart';

/// 字节 → JSON。[bytes] 必须是 UTF-8 编码（服务端契约）。
///
/// 非 UTF-8 字节会抛 [FormatException]，由调用方现有的 catch 处理；
/// 不用 `allowMalformed` 静默替换成 U+FFFD——坏字节应该当场暴露，
/// 而不是变成一堆看起来像正常数据的东西。
dynamic jsonOfBytes(List<int> bytes) => jsonDecode(utf8.decode(bytes));

/// 响应 → JSON。始终按 UTF-8 解，不看 `Content-Type`。
dynamic jsonOf(http.Response r) => jsonOfBytes(r.bodyBytes);

/// 响应 → JSON Map（服务端绝大多数接口返回对象）。
Map<String, dynamic> jsonMapOf(http.Response r) =>
    jsonOf(r) as Map<String, dynamic>;

/// 响应 → JSON Map；**解析失败或不是对象时返回空 Map**，不抛异常。
///
/// 写接口的收尾普遍是「先尽力解析、再根据 ok/error 决定文案」：解析失败时
/// 不该抛出去（那样用户看到的是一堆 `FormatException` 堆栈），而应回到
/// 「拿状态码说话」的分支。空 Map 让 `apiFailureText` 能给出状态码文案。
Map<String, dynamic> jsonObjectOrEmpty(http.Response r) {
  try {
    final d = jsonOf(r);
    if (d is Map) return Map<String, dynamic>.from(d);
  } catch (_) {}
  return <String, dynamic>{};
}

/// 服务端「成功/失败 + 失败原因」的唯一判定。
///
/// 写接口的收尾此前在 6 处各写一遍：
///
///     if (r.statusCode != 200 || j is! Map || j['ok'] != true) {
///       throw/return (j is Map && j['error'] != null) ? '${j['error']}' : 'HTTP ${r.statusCode}';
///     }
///
/// 三处细节很容易各写错一个：①有的先判 `statusCode == 200` 才解析，
/// 有的先解析再看状态码；②`j['error']` 可能是非字符串（Map/num），
/// 直接插值会把 `{code: 500}` 这样的对象贴到界面上；③状态码文案有的走
/// `httpErrorText`，有的手拼 `HTTP n`，同一个 404 在两个页面是两种说法。
///
/// 这里返回 **null 表示成功**，否则返回可直接展示的失败原因。
/// [statusText] 允许业务传入自己的状态码文案（如封面/头像的 404 特指），
/// 不传则回落到 [httpErrorText] 的通用归类。
///
/// [requireOk] 区分服务端的两种契约，不要靠猜：
///  - `true`（默认）：必须 `ok == true` 才算成功（写接口，缺字段即失败）；
///  - `false`：`200` 且没有显式 `ok:false` 就算成功（老接口只带 `error` 字段，
///    缺 `ok` 时旧调用方是按成功走的）。
/// 第二种此前在 13 处写成 `statusCode != 200 || j['ok'] == false` + 手拼
/// `'${j['error'] ?? 'HTTP ${r.statusCode}'}'`，有两个实打实的缺陷：
/// `j` 不是 Map 时 `j['error']` 直接抛 `NoSuchMethodError`；`error` 是非字符串
/// （Map/num）时把 `{code: 500}` 这样的对象贴到界面上。
String? apiFailureText(
  int status,
  dynamic json, {
  String Function(int status)? statusText,
  bool requireOk = true,
}) {
  final ok = requireOk
      ? status == 200 && serviceSaidOk(json)
      : status == 200 && !serviceSaidFail(json);
  if (ok) return null;
  final serverSaid = serverErrorText(json);
  if (serverSaid != null) return serverSaid;
  final text = statusText ?? httpErrorText;
  return text(status);
}

/// 服务端**明确确认成功**：必须是对象且 `ok` 严格为 `true`（**唯一判定**）。
///
/// `ok == true` 这套判定此前在本文件、`main.dart`（6 处写接口收尾）、
/// `sync_ledger`、`library_refresh` 各写一遍。写接口必须**严格**：`1` /
/// `"true"` / 缺字段都不算成功——它们是「服务端没说成功」而不是「换了个
/// 写法说成功」，放宽会让「请求被打回但没报错」变成静默的成功。
///
/// 与之相对的宽松判定见 [serviceSaidFail]（老读接口契约）。
bool serviceSaidOk(dynamic json) => json is Map && json['ok'] == true;

/// 服务端**明确说了失败**：对象里 `ok` 严格为 `false`。
///
/// 老读接口（缺 `ok` 字段即视为成功）的判断只有这一处，调用方写
/// `!serviceSaidFail(j)` 即可，不再各自写 `!(j is Map && j['ok'] == false)`。
bool serviceSaidFail(dynamic json) => json is Map && json['ok'] == false;

/// 服务端 `error` 字段 → 可直接展示的原因；没有可展示的字符串时返回 null。
///
/// 「有没有失败原因」这一判断此前在多处各写一遍，且两种写法都不对：
/// `'${j['error']}'`（对象/数字也被插值成 `{code: 500}` 贴到界面），
/// `j['error'] != null`（判存在不判类型）。抽成一个函数后，
/// 「哪些响应算带了原因」只有一个答案。
String? serverErrorText(dynamic json) {
  if (json is Map) {
    final e = json['error'];
    if (e is String && e.trim().isNotEmpty) return e.trim();
  }
  return null;
}

/// 读接口的收尾：非成功就抛异常，消息可直接展示给用户。
///
/// 调用点原来是「先算 `'${j['error'] ?? 'HTTP ${r.statusCode}'}'`，再 `throw`」
/// 两行同体代码，散在 13 处；错误字段不是字符串时会把 `{code: 500}`
/// 贴到界面上，`j` 不是 Map 时直接 `NoSuchMethodError`。
void throwIfApiFailed(
  int status,
  dynamic json, {
  bool requireOk = false,
  String Function(int status)? statusText,
}) {
  final bad = apiFailureText(status, json,
      requireOk: requireOk, statusText: statusText);
  if (bad != null) throw Exception(bad);
}

/// 服务端下发的「对象数组」→ `List<Map<String, dynamic>>`（**唯一实现**）。
///
/// 同一段 `((j['list'] as List?) ?? const []).map((e) => Map.from(e as Map))`
/// 此前在 `main.dart` 抄了 6 遍（首页库列表、当前库同步、爬虫页、搜索页、
/// 维护页……）。它们的坏数据行为都是**抛异常**，而位置各不相同：
///
///   - `e` 是字符串或数字（服务端把空列表写成 `[null]`、或版本切换期混进
///     旧格式）→ `_TypeError: type 'String' is not a subtype of Map`；
///   - 首页那条在 `Future.wait` 的 catch 里，表现为**整个连接列表变空**；
///   - 爬虫页那条没有 catch，异常直接进 `setState` 的前一帧，界面卡在加载中；
///   - 搜索页那条会连带把整页结果清空。
///
/// 正确行为是「跳过这条坏数据、保留其余」：一条脏记录不该让整张列表消失，
/// 更不该让界面卡死。所有读列表的地方都走这里。
List<Map<String, dynamic>> mapsOf(dynamic raw) {
  if (raw is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  return out;
}

/// JSON 字段按**列表**读：不是列表时返回空列表（**唯一实现**）。
///
/// `x as List?` 最常见的写法是 `(j['works'] as List?) ?? const []`，读起来
/// 像「没有就是空」，实际判的是 **null**——字段是字符串、数字或对象时照样抛
/// `_TypeError`。这在本项目里反复出现：
///
///   - 基础库页 `j['authors']` / `j['works']` 一旦被服务端写成对象，作者与
///     作品两栏同时停在加载中（异常进不了 setState 前那帧）；
///   - 库树 `json['bigLibraries']` / `groups` 写坏 → 整棵单元库树为空；
///   - 分类树 `item['dirs']` 写坏 → 该分类整个消失（不是丢一层，是丢整枝）。
///
/// 正确行为与 [mapsOf] 一致：**这条字段不可用就当它没有**，不要连累其余。
List<dynamic> listOf(dynamic raw) => raw is List ? raw : const <dynamic>[];

/// JSON 字段的列表长度；不是列表时 0（供只计数的调用方用）。
int listLengthOf(dynamic raw) => raw is List ? raw.length : 0;

/// JSON 字段按**字符串列表**读：跳过非标量条目、去空白、丢空串。
///
/// 用于 `libs` / `ids` / 路径清单这类「只关心元素文本」的字段；
/// 嵌套对象不会被插值成 `{a: 1}` 混进列表。
List<String> stringsOf(dynamic raw) {
  if (raw is! List) return const <String>[];
  final out = <String>[];
  for (final e in raw) {
    if (e == null || e is Map || e is Iterable) continue;
    final s = '$e'.trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

/// 服务端下发的「对象」→ `Map<String, dynamic>`；不是对象时返回 null。
///
/// `Map<String, dynamic>.from(x)` 对字符串/数字会抛 `_TypeError`，对
/// `Map<dynamic, dynamic>` 才会成功。服务端字段类型漂移（`authors` 从对象
/// 变成字符串）时，界面不该整个崩掉。
Map<String, dynamic>? mapOrNull(dynamic raw) =>
    raw is Map ? Map<String, dynamic>.from(raw) : null;
