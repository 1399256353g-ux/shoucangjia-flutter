import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 字符串配置的读写：所有「落盘」都走这里。
///
/// 单一来源（owner 2026-11-24 第九批）：此前 `AppSettings.save`、
/// `LibraryCornerBadge.save`、`LibraryBadge` 的五个 save*、`AuthorGrade.cacheLocal`
/// 与 `AuthorGrade.save`、`AuthorAvatarStore._persist`、`ContinueWatchingStore._persist`、
/// `WatchProgress.flush`、`WorkPlays.flush`、`AppTheme.select`、以及 `main.dart`
/// 里的连接表/库绑定/排序偏好，各自写了一份
/// `try { final sp = await SharedPreferences.getInstance();
///         await sp.setString(key, ...); } catch (_) {}`。
///
/// 其中最容易出事的不是重复本身，而是**「存的是 JSON 还是字符串」在每处各判一次**：
/// 本轮就踩到一次——统一入口时把已经序列化好的字符串又 `jsonEncode` 了一遍，
/// 存进去变成带引号的 `"{\"w\":2.0,...}"`，读回时 `jsonDecode` 得到 String 而不是
/// Map，自定义外观静默失效（`library_entry_style_test` 立刻抓到）。
/// 所以这里只提供**一个**入口、只接字符串：编码由调用方在自己那一层做完，
/// 本文件不猜「这个值要不要转 JSON」。
///
/// 保存失败不能影响交互（配置是尽力而为），异常在此统一吞掉，
/// 而不是散落在十几个类的静态方法里各吞一次。
Future<void> savePrefString(String key, String value) async {
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(key, value);
  } catch (_) {
    // 存储不可用（权限/磁盘满）时保留进程内状态，下次写入再试。
  }
}

/// 读一个字符串键；不存在或读取失败返回 null。
Future<String?> readPrefString(String key) async {
  try {
    final sp = await SharedPreferences.getInstance();
    return sp.getString(key);
  } catch (_) {
    return null;
  }
}

/// 偏好里的 JSON 文本 → 解析结果；空串/坏 JSON 返回 null（**唯一实现**）。
///
/// 本机持久化的五张表（连接表 `servers_v1`、库绑定 `lib_bindings_v1`、
/// 观看进度 `watch_progress_v1`、继续观看 `continue_watching_v1`、
/// 本地播放量 `work_plays_v2`、头像覆盖表）此前各写一遍
/// `if (raw == null || raw.isEmpty) return …; try { jsonDecode(raw) } catch (_) { return … }`
/// ——四五份「读盘 → 能不能用」的判断，只差空串的判定用 `isEmpty` 还是
/// `trim().isEmpty`（纯空格的那份 `jsonDecode('   ')` 抛异常、被 catch 成空表，
/// 结果一致但多一次异常）。现在只在这里判一次。
///
/// 返回 `Object?`：对象/数组由调用方自己 `is Map` / `is List` 分流（那才是
/// 各表真正的结构差异），这里只负责「这段文本能不能变成 JSON」。
Object? decodePrefJson(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return null;
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}
