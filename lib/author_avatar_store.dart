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
/// 键按**作者名**（服务端 `/api/authors.json` 本身就是按名字合并的，
/// 同名即同一作者），所以作者总览、排行榜、作者主页三处入口看到的是同一张。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本机覆盖表：`作者名 -> 媒体路径`（JSON object）。
const String kAuthorAvatarPrefsKey = 'author_avatar_overrides_v1';

/// 覆盖表的键：作者名去掉首尾空白。
String authorAvatarKey(String name) => name.trim();

/// 只接受能作为媒体地址的相对/绝对图片路径，避免把任意字符串写进偏好。
bool _validAvatarValue(String v) {
  final s = v.trim();
  if (s.isEmpty || s.length > 600) return false;
  if (!(s.startsWith('/') || s.startsWith('http://') || s.startsWith('https://'))) {
    return false;
  }
  return true;
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

  /// 全部覆盖（只读副本，诊断/测试用）。
  Map<String, String> get overrides => Map<String, String>.unmodifiable(_paths);

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

  Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kAuthorAvatarPrefsKey, encodeAuthorAvatarOverrides(_paths));
    } catch (_) {}
  }

  /// 仅供测试：注入初始状态。
  @visibleForTesting
  void debugSeed(Map<String, String> m) {
    _paths = parseAuthorAvatarOverrides(encodeAuthorAvatarOverrides(m));
    _ready = true;
    notifyListeners();
  }
}
