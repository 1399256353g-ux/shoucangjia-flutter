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
      ? status == 200 && json is Map && json['ok'] == true
      : status == 200 && !(json is Map && json['ok'] == false);
  if (ok) return null;
  if (json is Map) {
    final e = json['error'];
    if (e is String && e.trim().isNotEmpty) return e.trim();
  }
  final text = statusText ?? httpErrorText;
  return text(status);
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
