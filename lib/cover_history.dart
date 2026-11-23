/// owner 2026-11-23：库封面历史（服务端 `_cover/` 最近 5 个版本 + `current`）。
///
/// 只做两件事：解析服务端 `/api/cover/versions` 的版本列表；调用
/// `/api/cover/restore` / `/api/cover/clear`。图片本身仍走媒体接口，
/// 本文件不读写本地文件、不缓存图片字节。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// `_cover/` 里的一个历史版本。
class CoverVersion {
  /// 版本名（不含扩展名），如 `c20261123120000`。
  final String version;

  /// 扩展名（不含点），服务端白名单 jpg/jpeg/png/webp。
  final String ext;

  /// 服务端相对媒体路径（`/media/<lib>/_cover/<version>.<ext>`）。
  final String url;

  /// 秒级时间戳（服务端 mtime/记录时间）；0 表示未知。
  final int at;

  /// 是否是当前正在使用的封面。
  final bool current;

  const CoverVersion({
    required this.version,
    required this.ext,
    required this.url,
    this.at = 0,
    this.current = false,
  });

  /// 版本 + 扩展名，用于去重与比较。
  String get fileName => '$version.$ext';
}

/// 服务端返回的版本名只允许 `[A-Za-z0-9_-]`，避免路径穿越。
final RegExp _kCoverVersionName = RegExp(r'^[A-Za-z0-9_-]{1,40}$');

const Set<String> _kCoverExts = <String>{'jpg', 'jpeg', 'png', 'webp'};

/// 单条版本 JSON → [CoverVersion]；非法条目返回 null。
CoverVersion? coverVersionFromJson(dynamic raw) {
  if (raw is! Map) return null;
  final v = '${raw['v'] ?? raw['version'] ?? ''}'.trim();
  if (!_kCoverVersionName.hasMatch(v)) return null;
  var e = '${raw['e'] ?? raw['ext'] ?? 'jpg'}'.trim().toLowerCase();
  if (e.startsWith('.')) e = e.substring(1);
  if (!_kCoverExts.contains(e)) e = 'jpg';
  final u = '${raw['u'] ?? raw['url'] ?? ''}'.trim();
  final at = raw['at'] is num ? (raw['at'] as num).toInt() : 0;
  return CoverVersion(
    version: v,
    ext: e,
    url: u.startsWith('/media/') ? u : '',
    at: at < 0 ? 0 : at,
    current: raw['current'] == true,
  );
}

/// 解析 `/api/cover/versions`：最多保留 [limit] 条（服务端已排序，保持原序）。
List<CoverVersion> parseCoverVersions(dynamic json, {int limit = 5}) {
  final map = json is Map ? json : const <String, dynamic>{};
  final raw = map['versions'];
  if (raw is! List) return const <CoverVersion>[];
  final out = <CoverVersion>[];
  final seen = <String>{};
  for (final entry in raw) {
    final v = coverVersionFromJson(entry);
    if (v == null || v.url.isEmpty) continue;
    if (!seen.add(v.fileName)) continue;
    out.add(v);
    if (out.length >= limit) break;
  }
  return out;
}

/// 读取历史失败/成功的结果。
class CoverListResult {
  final bool ok;
  final String message;
  final List<CoverVersion> versions;

  const CoverListResult(this.ok, this.message,
      {this.versions = const <CoverVersion>[]});
}

/// 切换/清除封面的结果。
class CoverActionResult {
  final bool ok;
  final String message;

  /// 成功切换后的相对媒体路径（恢复自动/清除时为空）。
  final String url;

  const CoverActionResult(this.ok, this.message, {this.url = ''});
}

/// 服务端状态码 → 可读文案（不把原始响应体暴露给用户）。
String coverActionErrorText(int status) {
  switch (status) {
    case 400:
      return '请求格式不对';
    case 404:
      return '该封面版本已不存在（或服务端未升级）';
    case 413:
      return '图片过大';
    case 500:
      return '服务端写入失败';
    default:
      return 'HTTP $status';
  }
}

/// 列出版本列表：`GET /api/cover/versions?lib=&unitRel=`。
Future<CoverListResult> fetchCoverVersions({
  required Uri url,
  required Map<String, String> headers,
}) async {
  try {
    final r =
        await http.get(url, headers: headers).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) {
      return CoverListResult(
          false, '读取封面历史失败：${coverActionErrorText(r.statusCode)}');
    }
    final json = jsonDecode(utf8.decode(r.bodyBytes));
    return CoverListResult(true, '', versions: parseCoverVersions(json));
  } catch (_) {
    return const CoverListResult(false, '读取封面历史失败：网络异常');
  }
}

/// 把 `current`（基础库）或 `unit-covers.json`（单元库）指回旧版本。
Future<CoverActionResult> restoreCoverVersion({
  required Uri url,
  required Map<String, String> headers,
  required String libId,
  String unitRel = '',
  required String version,
  String ext = 'jpg',
}) async {
  if (libId.trim().isEmpty || version.trim().isEmpty) {
    return const CoverActionResult(false, '缺少库或版本标识');
  }
  try {
    final r = await http
        .post(
          url,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'lib': libId,
            if (unitRel.isNotEmpty) 'unitRel': unitRel,
            'v': version,
            'e': ext,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      return CoverActionResult(
          false, '切换封面失败：${coverActionErrorText(r.statusCode)}');
    }
    String u = '';
    try {
      final j = jsonDecode(r.body);
      if (j is Map) u = '${j['u'] ?? ''}'.trim();
    } catch (_) {}
    return CoverActionResult(true, '已切换到该封面', url: u);
  } catch (_) {
    return const CoverActionResult(false, '切换封面失败：网络异常');
  }
}

/// 恢复自动封面（[hard] = false，只删指针）或清除全部自定义封面（[hard] = true）。
Future<CoverActionResult> clearCustomCover({
  required Uri url,
  required Map<String, String> headers,
  required String libId,
  String unitRel = '',
  bool hard = false,
}) async {
  if (libId.trim().isEmpty) {
    return const CoverActionResult(false, '缺少库标识');
  }
  try {
    final r = await http
        .post(
          url,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode({
            'lib': libId,
            if (unitRel.isNotEmpty) 'unitRel': unitRel,
            'hard': hard,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      return CoverActionResult(
          false, '操作失败：${coverActionErrorText(r.statusCode)}');
    }
    return CoverActionResult(
        true, hard ? '已清除自定义封面' : '已恢复自动封面');
  } catch (_) {
    return const CoverActionResult(false, '操作失败：网络异常');
  }
}
