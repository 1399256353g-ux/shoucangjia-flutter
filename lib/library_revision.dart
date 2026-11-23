// 库数据版本通知（「卡片快速刷新」第 4 步：刷新打开中的列表）。
//
// 重建索引后，正开着的该库作品页/作者页必须回到第一页重拉，否则用户看不到
// 新作品。这里只做「按库广播一个自增版本号」，由页面自己决定怎么重拉——
// 不发请求、不缓存数据、不新增定时器。
library;

import 'package:flutter/foundation.dart';

class LibDataRevision {
  LibDataRevision._();

  static final Map<String, ValueNotifier<int>> _rev =
      <String, ValueNotifier<int>>{};

  /// 该库的版本号通知器（首次访问时创建）。
  static ValueListenable<int> listenable(String libId) => _of(libId);

  static ValueNotifier<int> _of(String libId) =>
      _rev.putIfAbsent(libId.trim(), () => ValueNotifier<int>(0));

  /// 该库索引被重建过 → 所有在用列表重拉。
  static void bump(String libId) {
    final id = libId.trim();
    if (id.isEmpty) return;
    final n = _of(id);
    n.value = n.value + 1;
  }

  /// 当前版本号（测试用）。
  static int revisionOf(String libId) => _of(libId).value;
}
