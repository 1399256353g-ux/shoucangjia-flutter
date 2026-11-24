import 'package:flutter/foundation.dart';

import 'http_json.dart';

/// 在 isolate 里把字节解码成 JSON Map。
///
/// 大 payload（libraries.json、authors.json、works.json）在 UI 线程解析会
/// 直接卡住首帧：UTF-8 解码 + JSON 解析都是 CPU 密集操作。统一走这里。
///
/// 字符集规则不在这里重复：解码出口只有一个 `jsonOfBytes`（`http_json.dart`），
/// 这里只负责"把它挪到后台 isolate"。此前这两个文件各写了一份
/// `jsonDecode(utf8.decode(bytes))`，改字符集策略就得改两处。
Map<String, dynamic> parseJsonMapBytes(List<int> bytes) =>
    jsonOfBytes(bytes) as Map<String, dynamic>;

/// 异步版本：解析在后台 isolate 完成，调用方 await 即可。
Future<Map<String, dynamic>> parseJsonMapAsync(List<int> bytes) =>
    compute(parseJsonMapBytes, bytes);
