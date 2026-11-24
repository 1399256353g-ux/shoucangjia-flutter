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
