/// 单元库作者挂载的**唯一写请求出口**。
///
/// 两个入口（`author_mount_sheet` 作者页面板 / `unit_author_mount_page`
/// 单元库挂载页）此前各写一份 `_send`：
///
/// ```dart
/// final r = await _client.post(
///   Uri.parse(unitAuthorGroupsUrl(base, unit)),
///   headers: {...headers, 'Content-Type': 'application/json'},
///   body: jsonEncode(req.toBody()),
/// ).timeout(kTimeoutWrite);
/// final j = jsonOf(r);
/// throwIfApiFailed(r.statusCode, j);
/// ```
///
/// 六行逐字相同，只有 `base`/`unit` 的取值来源不同（一个是 widget 字段，
/// 一个是页面里的 `_unitRel`）。这份拷贝的危险不在于「重复」，而在于
/// `Content-Type` 与超时档位是**协议的一部分**：日后服务端改成要求
/// `charset=utf-8`、或把写档从 20s 放宽到 30s，改一处漏一处的那次请求会
/// 静默失败——用户看到的是「点了没反应」，两边都不报错。
///
/// 这里只做「发出去 + 判定成功/失败」，**不做** busy 状态、toast 与重新加载：
/// 那些是各页自己的事（作者页要 toast 到 sheet，挂载页要重读自己的状态）。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_timeout.dart';
import 'http_json.dart';
import 'unit_author_groups.dart';

/// POST 一次挂载写请求；失败抛异常（消息可直接展示给用户）。
///
/// 地址只有 [unitAuthorGroupsUrl] 一处，成功判定只有 [throwIfApiFailed] 一处。
Future<void> postUnitAuthorRequest(
  http.Client client, {
  required String base,
  required String unit,
  required Map<String, String> headers,
  required UnitAuthorRequest req,
}) async {
  final r = await client
      .post(
        Uri.parse(unitAuthorGroupsUrl(base, unit)),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: jsonEncode(req.toBody()),
      )
      .timeout(kTimeoutWrite);
  throwIfApiFailed(r.statusCode, jsonOf(r));
}
