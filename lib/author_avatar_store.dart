/// 作者头像手动设置（本机覆盖，0.9.41）。
///
/// 背景：owner 指定的头像优先级是「手动设置 > 爬虫获取 > 自动生成」。
/// 前两项此前只靠爬虫落盘的 `_avatar/` 与 `av` 字段，客户端没有「手动指定」
/// 的入口——某个作者被爬虫取了张不好看的头像时只能等下次爬取。
///
/// 这里做**本机**覆盖：作者主页长按头像，可从该作者任意作品图里挑一张设为
/// 头像，也可一键清除回到爬虫/自动结果。覆盖只写本机 SharedPreferences，
/// 不上传、不改媒体文件、不改服务端数据；换设备/重装后回到原头像。
///
/// 2026-11-23 批 A：库内 `<库>/.avatars/<file>` 头像改为走服务端
/// `POST /api/avatar/set` 注册（跨设备生效）；本机覆盖仍用于普通作品图。
/// 两种来源的优先级不变：手动 > 爬虫 > 自动。
///
/// 键按**作者名**（服务端 `/api/authors.json` 本身就是按名字合并的，
/// 同名即同一作者），所以作者总览、排行榜、作者主页三处入口看到的是同一张。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'http_error_text.dart';
import 'media_path.dart';
import 'media_priority.dart';
import 'prefs_json.dart';

/// 本机覆盖表：`作者名 -> 媒体路径`（JSON object）。
const String kAuthorAvatarPrefsKey = 'author_avatar_overrides_v1';

/// 覆盖表的键：作者名去掉首尾空白。
String authorAvatarKey(String name) => name.trim();

/// 只接受能作为媒体地址的相对/绝对图片路径，避免把任意字符串写进偏好。
///
/// 绝对地址判定转发 `media_path.isAbsoluteMediaUrl`（忽略大小写协议）。旧写法
/// 自己写了 `startsWith('http://')`，于是 `HTTP://nas/x.jpg`（从浏览器地址栏
/// 复制、大小写不归一）被当成非法值**静默丢弃**：
///
/// ```
/// encodeAuthorAvatarOverrides({'a': 'HTTP://nas/x.jpg'})  -> {}   ← 实测
/// ```
///
/// 用户点完「设为头像」以为存上了，重启就回原头像。
bool _validAvatarValue(String v) {
  final s = v.trim();
  if (s.isEmpty || s.length > 600) return false;
  return s.startsWith('/') || isAbsoluteMediaUrl(s);
}

/// 解析偏好里的覆盖表；坏数据按空表处理（不抛异常、不影响启动）。
Map<String, String> parseAuthorAvatarOverrides(String? raw) {
  final out = <String, String>{};
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return out;
  try {
    final j = jsonDecode(s);
    if (j is! Map) return out;
    for (final e in j.entries) {
      final k = authorAvatarKey('${e.key}');
      final v = '${e.value}';
      if (k.isEmpty || !_validAvatarValue(v)) continue;
      out[k] = v.trim();
    }
  } catch (_) {
    return out;
  }
  return out;
}

/// 序列化覆盖表（键排序，便于测试与 diff）。
String encodeAuthorAvatarOverrides(Map<String, String> m) {
  final keys = m.keys.where((k) => k.trim().isNotEmpty).toList()..sort();
  final out = <String, String>{};
  for (final k in keys) {
    final v = m[k];
    if (v == null || !_validAvatarValue(v)) continue;
    out[k.trim()] = v.trim();
  }
  return jsonEncode(out);
}

/// 服务端自定义头像的媒体地址特征：
///  - 旧落点：`/media/<lib>/@manual-avatar/<作者>/_avatar/...`；
///  - 批 A（2026-11-23）：`/media/<lib>/.avatars/<file>`。
///
/// 上传/注册的头像由服务端下发后，作者页与索引都会返回这些前缀，
/// 客户端据此判断「恢复自动」是否有服务端覆盖需要清理。
bool isManualAvatarPath(String? path) {
  final p = path ?? '';
  return p.contains('/@manual-avatar/') ||
      p.contains('/%40manual-avatar/') ||
      p.contains('/.avatars/');
}

/// 服务端头像「按文件注册」接口（批 A，2026-11-23）：`POST /api/avatar/set`。
/// set `{lib, author, file}`；clear `{lib, author, clear:true}`。
const String kAuthorAvatarSetPath = '/api/avatar/set';

/// 服务端头像文件名：只允许不含路径分隔符的 JPG/PNG/WebP。
///
/// 服务端从 `<库>/.avatars/<file>` 解析，客户端不传路径，避免目录穿越。
bool isServerAvatarFileName(String file) {
  final f = file.trim();
  if (f.isEmpty || f.length > 160) return false;
  if (f.contains('/') || f.contains('\\') || f.contains('..')) return false;
  return RegExp(r'\.(?:jpe?g|png|webp)$', caseSensitive: false).hasMatch(f);
}

/// 从媒体地址解析 `<库>/.avatars/<file>`，返回库 id 与文件名；否则 null。
///
/// 只认精确的三段式 `/media/<lib>/.avatars/<file>`；旧目录
/// `@manual-avatar/...` 不是「按文件注册」的来源，交给旧上传链路处理。
({String lib, String file})? serverAvatarFileFromPath(String? mediaPath) {
  // 先剥 `?query` / `#fragment`：`av` 里的头像地址可能带缓存参数
  // （`/media/lib/.avatars/a.jpg?w=200`）。旧写法直接按 `/` 切三段，
  // 文件段是 `a.jpg?w=200`，`isServerAvatarFileName` 判为非法 → 返回 null，
  // 于是「设置头像」静默退化成**只存本机**（跨设备不生效），而那张图本身
  // 完全可以用于注册。实测 `serverAvatarFileFromPath(
  // '/media/lib/.avatars/a.jpg?w=200')` 返回 null。
  // `/media/` 尾部走 `mediaRelOrNull`：前缀判定与切片同一个出口（自己 trim），
  // 不再手写 `substring(7)`——那是这条规则在第四个文件里的第二份拷贝。
  final rest = mediaRelOrNull(stripMediaSuffix(mediaPath ?? ''));
  if (rest == null) return null;
  final parts = rest.split('/');
  if (parts.length != 3 || parts[1] != '.avatars') return null;
  final lib = decodeComponentOrRaw(parts[0]);
  final file = decodeComponentOrRaw(parts[2]);
  if (lib.isEmpty || !isServerAvatarFileName(file)) return null;
  return (lib: lib, file: file);
}

/// `/api/avatar/set` 设置请求体。
Map<String, dynamic> authorAvatarSetBody({
  required String lib,
  required String author,
  required String file,
}) =>
    <String, dynamic>{
      'lib': lib.trim(),
      'author': author.trim(),
      'file': file.trim(),
    };

/// `/api/avatar/set` 清除请求体（「恢复自动」）。
Map<String, dynamic> authorAvatarClearBody({
  required String lib,
  required String author,
}) =>
    <String, dynamic>{
      'lib': lib.trim(),
      'author': author.trim(),
      'clear': true,
    };

/// 头像接口 HTTP 状态码 → 可读原因；未知状态码只报数字。
///
/// 400/500 走 [httpErrorText] 的通用归类；只有 404 是本业务特指的。
String authorAvatarApiErrorText(int status) =>
    httpErrorText(status, overrides: const {
      400: '请求格式不对或文件名非法',
      404: '基础库或头像文件不存在',
      500: '服务端写入注册表失败',
    });

/// 作者头像来源优先级：手动覆盖 > 作品自带 `av`/爬虫作者头像 > 自动兜底图。
///
/// B3（owner 2026-11-19）：此前播放页先看作品自带 `av` 再看手动覆盖，
/// 手动挑的头像会被爬虫结果盖回去。这里把优先级收成一个纯函数，
/// 播放页与其它入口共用，避免两处口径再次分叉。
/// 空串/null 视为「没有」，直接看下一档。
///
/// 0.9.226：本函数此前自己写了一遍「逐档取第一个非空」，与
/// `media_priority.pickAvatarPath`（封面/头像共用的唯一规则）是**两份实现**，
/// 而且它丢掉了「同级新图优先」——只传了路径，没有 `at`。两处规则一旦
/// 有人改一处（例如把爬虫提到兜底之后），另一个入口不会跟着变。
/// 现在只转发，时间戳也一并透传；不传时间时行为与旧实现完全一致。
String resolveAuthorAvatarPath({
  String? manual,
  String? crawled,
  String? fallback,
  int manualAt = 0,
  int crawledAt = 0,
  int fallbackAt = 0,
}) =>
    pickAvatarPath(
      manual: manual ?? '',
      crawler: crawled ?? '',
      auto: fallback ?? '',
      manualAt: manualAt,
      crawlerAt: crawledAt,
      autoAt: fallbackAt,
    );

/// 手动头像全局状态：`ChangeNotifier`，三处作者头像都监听它即时刷新。
class AuthorAvatarStore extends ChangeNotifier {
  AuthorAvatarStore._();

  static final AuthorAvatarStore instance = AuthorAvatarStore._();

  Map<String, String> _paths = <String, String>{};
  bool _ready = false;

  /// 是否已从本机读取过（未读取时按无覆盖处理）。
  bool get ready => _ready;

  /// 已设置手动头像的作者数。
  int get count => _paths.length;

  /// 该作者的手动头像路径；没有返回 null。
  String? pathFor(String name) => _paths[authorAvatarKey(name)];

  bool has(String name) => pathFor(name) != null;

  /// 从 SharedPreferences 读一次；失败按空处理。
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _paths = parseAuthorAvatarOverrides(sp.getString(kAuthorAvatarPrefsKey));
    } catch (_) {
      _paths = <String, String>{};
    }
    _ready = true;
    notifyListeners();
  }

  /// 设为该作者的头像。返回 false 表示路径不合法。
  Future<bool> setPath(String name, String mediaPath) async {
    final k = authorAvatarKey(name);
    final v = mediaPath.trim();
    if (k.isEmpty || !_validAvatarValue(v)) return false;
    _paths = <String, String>{..._paths, k: v};
    _ready = true;
    notifyListeners();
    await _persist();
    return true;
  }

  /// 清除该作者的手动头像（回到爬虫/自动结果）。
  Future<void> clear(String name) async {
    final k = authorAvatarKey(name);
    if (!_paths.containsKey(k)) return;
    final next = <String, String>{..._paths}..remove(k);
    _paths = next;
    _ready = true;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() => savePrefString(
      kAuthorAvatarPrefsKey, encodeAuthorAvatarOverrides(_paths));

  /// 仅供测试：注入初始状态。
  @visibleForTesting
  void debugSeed(Map<String, String> m) {
    _paths = parseAuthorAvatarOverrides(encodeAuthorAvatarOverrides(m));
    _ready = true;
    notifyListeners();
  }
}
