import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 在 isolate 里把字节解码成 JSON Map。
///
/// 大 payload（libraries.json、authors.json、works.json）在 UI 线程解析会
/// 直接卡住首帧：UTF-8 解码 + JSON 解析都是 CPU 密集操作。统一走这里。
Map<String, dynamic> parseJsonMapBytes(List<int> bytes) =>
    jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

/// 异步版本：解析在后台 isolate 完成，调用方 await 即可。
Future<Map<String, dynamic>> parseJsonMapAsync(List<int> bytes) =>
    compute(parseJsonMapBytes, bytes);
