import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_tree.dart' show toggleStar;

/// 0.9.6：星标（单元库）全局状态。
///
/// 星标原先只存在 `_LibraryPageState.stars` 里，各页面拿的是入栈时的
/// `Set` 快照，所以在子页点亮/取消后，父页或更深一层页面仍是旧值
/// （返回后图标不变、星标计数不对）。这里用单例 + `ChangeNotifier`
/// 持有唯一真相，页面监听它即可即时同步。
class StarStore extends ChangeNotifier {
  StarStore._();

  static final StarStore instance = StarStore._();

  /// 与既有偏好键保持一致，升级时不丢用户星标。
  static const String prefKey = 'lib_tree_stars_v1';

  List<String> _ids = const <String>[];
  bool _ready = false;

  /// 是否已从本地读取过（未读取时页面回落到构造参数里的快照，便于测试）。
  bool get ready => _ready;

  /// 保持标记顺序（星标页按标记时间倒序展示依赖顺序）。
  List<String> get ordered => List<String>.unmodifiable(_ids);

  Set<String> get ids => Set<String>.unmodifiable(_ids);

  int get count => _ids.length;

  bool contains(String id) => _ids.contains(id);

  /// 从 SharedPreferences 读取一次；失败按空处理，不影响首页其它内容。
  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _ids = List<String>.from(sp.getStringList(prefKey) ?? const <String>[]);
    } catch (_) {
      _ids = const <String>[];
    }
    _ready = true;
    notifyListeners();
  }

  /// 切换某个单元库的星标；最大数量由 [toggleStar] 控制（20）。
  Future<void> toggle(String id) async {
    _ids = toggleStar(_ids, id);
    _ready = true;
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(prefKey, _ids);
    } catch (_) {}
  }

  /// 仅供测试：注入初始状态。
  @visibleForTesting
  void debugSeed(Iterable<String> ids) {
    _ids = List<String>.from(ids);
    _ready = true;
    notifyListeners();
  }

  /// 仅供测试：回到未初始化状态，避免单例跨用例污染。
  @visibleForTesting
  void debugReset() {
    _ids = const <String>[];
    _ready = false;
  }
}
