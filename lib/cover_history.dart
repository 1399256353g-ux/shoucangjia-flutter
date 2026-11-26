/// owner 2026-11-23：库封面历史（服务端 `_cover/` 最近 5 个版本 + `current`）。
///
/// 只做两件事：解析服务端 `/api/cover/versions` 的版本列表；调用
/// `/api/cover/restore` / `/api/cover/clear`。图片本身仍走媒体接口，
/// 本文件不读写本地文件、不缓存图片字节。
library;

import 'dart:convert';
import 'json_num.dart';

import 'package:http/http.dart' as http;

import 'media_path.dart';
import 'http_json.dart';
import 'lib_cover.dart'
    show normalizeCoverVersionName, normalizeCoverExt, coverVersionFileName;

import 'http_error_text.dart';
import 'cover_admin.dart' show coverScopeBody;

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
  ///
  /// 拼装只有 `lib_cover.coverVersionFileName` 一处（与 `coverImageRel` 同源）：
  /// 此前这里自己写 `'$version.$ext'`，与请求路径的拼法各写一遍。
  String get fileName => coverVersionFileName(version, ext: ext);
}

/// 单条版本 JSON → [CoverVersion]；非法条目返回 null。
///
/// 版本名与扩展名都走 `lib_cover` 的同一份规则：
///  - 版本名：`normalizeCoverVersionName(clip: false)`——读取侧**不截断**。
///    旧写法 `^[A-Za-z0-9_-]{1,40}$` 是本文件的第二份白名单，与写入侧
///    `normalizeCoverVersion` 只差「超长」这一种输入（45 字的版本名在这里
///    被拒、在写入侧被截断成另一个文件名）。
///  - 扩展名：`cover_ext.normalizeCoverExt`——旧写法又写了一遍
///    `startsWith('.')` 截点 + 白名单，`'png?w=1'` 同样回落 `jpg`。
CoverVersion? coverVersionFromJson(dynamic raw) {
  if (raw is! Map) return null;
  final v = normalizeCoverVersionName(
      '${raw['v'] ?? raw['version'] ?? ''}',
      clip: false);
  if (v.isEmpty) return null;
  final e = normalizeCoverExt('${raw['e'] ?? raw['ext'] ?? 'jpg'}');
  final u = '${raw['u'] ?? raw['url'] ?? ''}'.trim();
  final at = intOf(raw['at']);
  return CoverVersion(
    version: v,
    ext: e,
    url: isMediaPath(u) ? u : '',
    at: at < 0 ? 0 : at,
    current: boolOf(raw['current']),
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
///
/// 400/413/500 三条与其它封面/头像接口完全一致，走 [httpErrorText]；
/// 只有 404 是本业务特指的（旧版本已被清理或服务端未升级）。
String coverActionErrorText(int status) =>
    httpErrorText(status, overrides: const {
      404: '该封面版本已不存在（或服务端未升级）',
    });

/// 列出版本列表：`GET /api/cover/versions?lib=&unitRel=`。
Future<CoverListResult> fetchCoverVersions({
  required Uri url,
  required Map<String, String> headers,
}) async {
  try {
    final r = await http
        .get(url, headers: headers)
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) {
      return CoverListResult(
          false, '读取封面历史失败：${coverActionErrorText(r.statusCode)}');
    }
    final json = jsonOf(r);
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
  http.Client? client,
}) async {
  if (libId.trim().isEmpty || version.trim().isEmpty) {
    return const CoverActionResult(false, '缺少库或版本标识');
  }
  // 版本名与扩展名在这里归一，**不直接透传调用方给的值**。
  //
  // 旧写法把 `version` / `ext` 原样写进请求体：`lib_cover.coverVersionFromJson`
  // 早已把两者归一到「剥后缀 → 取末段 → 白名单」，但这条写入路径自己没做，
  // 于是任何一处调用方（历史面板以外的入口、测试、将来新增的恢复入口）
  // 传进 `.png`、`PNG`、`png?w=480` 时，服务端落盘的指针与磁盘上的文件名
  // 不是一个名字——恢复「成功」，封面却退回默认图。
  //
  // 读取侧与写入侧现在共用同一对函数：版本名 `normalizeCoverVersionName`
  // （读取侧不截断）、扩展名 `normalizeCoverExt`。
  final v = normalizeCoverVersionName(version, clip: false);
  if (v.isEmpty) {
    return const CoverActionResult(false, '封面版本名非法');
  }
  final e = normalizeCoverExt(ext);
  final c = client ?? http.Client();
  try {
    final r = await c
        .post(
          url,
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(coverScopeBody(
            lib: libId,
            unitRel: unitRel,
            extra: <String, dynamic>{'v': v, 'e': e},
          )),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      return CoverActionResult(
          false, '切换封面失败：${coverActionErrorText(r.statusCode)}');
    }
    String u = '';
    try {
      final j = jsonOf(r);
      if (j is Map) u = '${j['u'] ?? ''}'.trim();
    } catch (_) {}
    return CoverActionResult(true, '已切换到该封面', url: u);
  } catch (_) {
    return const CoverActionResult(false, '切换封面失败：网络异常');
  } finally {
    if (client == null) c.close();
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
          body: jsonEncode(coverScopeBody(
            lib: libId,
            unitRel: unitRel,
            extra: <String, dynamic>{'hard': hard},
          )),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      return CoverActionResult(
          false, '操作失败：${coverActionErrorText(r.statusCode)}');
    }
    return CoverActionResult(true, hard ? '已清除自定义封面' : '已恢复自动封面');
  } catch (_) {
    return const CoverActionResult(false, '操作失败：网络异常');
  }
}
