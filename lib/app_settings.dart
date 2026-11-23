import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'preload_policy.dart';
import 'video_layout.dart';

/// 播放器可重绑定的动作（桌面端，尤其 Windows）。
enum PlayerAction { next, prev, playPause, mute, fullscreen, forward, back }

const Map<PlayerAction, String> actionLabels = {
  PlayerAction.next: '下一条',
  PlayerAction.prev: '上一条',
  PlayerAction.playPause: '播放/暂停',
  PlayerAction.mute: '静音开关',
  PlayerAction.fullscreen: '全屏开关',
  PlayerAction.forward: '图文下一张',
  PlayerAction.back: '图文上一张',
};

const Map<PlayerAction, int> _defaultKeyIds = {
  PlayerAction.next: 106, // J
  PlayerAction.prev: 107, // K
  PlayerAction.playPause: 32, // Space
  PlayerAction.mute: 77, // M
  PlayerAction.fullscreen: 70, // F
  PlayerAction.forward: 76, // L
  PlayerAction.back: 72, // H
};

/// 一个按键组合：修饰键位掩码 + 主键。
///
/// `mods` 为位掩码（shift=1 / ctrl=2 / alt=4 / meta=8）。单键即 `mods == 0`，
/// 与「单击某个字母」是同一套数据，不再区分两套结构。
class KeyCombo {
  static const int modShift = 1;
  static const int modCtrl = 2;
  static const int modAlt = 4;
  static const int modMeta = 8;

  final int keyId;
  final int mods;

  const KeyCombo(this.keyId, [this.mods = 0]);

  bool get isBound => keyId != 0;
  bool get hasMods => mods != 0;

  KeyCombo copyWith({int? keyId, int? mods}) =>
      KeyCombo(keyId ?? this.keyId, mods ?? this.mods);

  Map<String, dynamic> toJson() => {'k': keyId, 'm': mods};

  /// 兼容三种历史/新格式：纯数字（旧单键）、`{k,m}`、以及带 `id` 的对象。
  static KeyCombo? fromJson(Object? v) {
    if (v is num) return KeyCombo(v.toInt(), 0);
    if (v is Map) {
      final k = (v['k'] ?? v['id']) as num?;
      if (k == null) return null;
      final m = (v['m'] ?? v['mods']) as num?;
      return KeyCombo(k.toInt(), m?.toInt() ?? 0);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is KeyCombo && other.keyId == keyId && other.mods == mods;

  @override
  int get hashCode => Object.hash(keyId, mods);

  @override
  String toString() => 'KeyCombo($keyId,$mods)';
}

/// 全局设置：播放参数 + 桌面按键绑定，持久化到 SharedPreferences。
/// 序列化与业务逻辑保持纯函数，便于单元测试。
class AppSettings {
  static const String prefsKey = 'app_settings_v1';

  static double defaultSpeed = 1.0;
  static int imageIntervalSec = 3;
  static int hideUiSec = 3;

  /// M6：滑动方向前后各预载多少条（0 = 关闭）。
  static int preloadPerSide = preloadDefaultPerSideFor(
      mobile: Platform.isAndroid || Platform.isIOS);

  /// M6：预加载缓存内存上限（MB）。
  static int preloadMemoryMb = preloadDefaultMemoryMb;

  /// 词条是否自动省略库名前的序号（`(1) 名称` → `名称`）。
  static bool stripLibIndex = true;

  /// 播放页双击点赞（G9）。关闭后双击不再点赞，两次单击按单击处理。
  static bool doubleTapLike = true;

  /// 视频填充模式覆盖：null = 按源比例自动（竖屏铺满 / 横屏适应），
  /// 用户手动选择后优先于自动判定。默认自动即竖屏「铺满」。
  static VideoFit? videoFitOverride;

  /// 动作 → 按键组合（修饰键 + 主键）。单键就是 `mods == 0` 的组合。
  static final Map<PlayerAction, KeyCombo> keyBindings = {
    for (final e in _defaultKeyIds.entries) e.key: KeyCombo(e.value),
  };

  /// 只读视图：动作 → 主键 id（供旧调用点与测试使用）。
  static Map<PlayerAction, int> get keyIds => {
        for (final e in keyBindings.entries) e.key: e.value.keyId,
      };

  static Map<String, dynamic> toJson() => {
        'speed': defaultSpeed,
        'imageInterval': imageIntervalSec,
        'hideUi': hideUiSec,
        'preloadPerSide': preloadPerSide,
        'preloadMemory': preloadMemoryMb,
        'stripIndex': stripLibIndex,
        'doubleTapLike': doubleTapLike,
        'videoFit': videoFitOverride?.name,
        'keys': {
          for (final e in keyBindings.entries) e.key.name: e.value.toJson(),
        },
      };

  /// 容错解析：非法或缺失字段回落默认值。
  static void applyJson(Map<String, dynamic> j) {
    resetDefaults();
    final s = (j['speed'] as num?)?.toDouble();
    if (s != null) defaultSpeed = s.clamp(0.5, 3.0).toDouble();
    final ii = (j['imageInterval'] as num?)?.toInt();
    if (ii != null) imageIntervalSec = ii.clamp(1, 20);
    final h = (j['hideUi'] as num?)?.toInt();
    if (h != null) hideUiSec = h.clamp(1, 30);
    final pp = (j['preloadPerSide'] as num?)?.toInt();
    if (pp != null) preloadPerSide = clampPreloadPerSide(pp);
    final pm = (j['preloadMemory'] as num?)?.toInt();
    if (pm != null) preloadMemoryMb = clampPreloadMemoryMb(pm);
    final si = j['stripIndex'];
    if (si is bool) stripLibIndex = si;
    final dt = j['doubleTapLike'];
    if (dt is bool) doubleTapLike = dt;
    final vf = j['videoFit'];
    if (vf is String) {
      for (final m in VideoFit.values) {
        if (m.name == vf) {
          videoFitOverride = m;
          break;
        }
      }
    }
    final keys = j['keys'];
    if (keys is Map) {
      for (final a in PlayerAction.values) {
        final v = keys[a.name];
        final c = KeyCombo.fromJson(v);
        if (c != null && c.isBound) keyBindings[a] = c;
      }
    }
  }

  static void resetDefaults() {
    defaultSpeed = 1.0;
    imageIntervalSec = 3;
    hideUiSec = 3;
    preloadPerSide = preloadDefaultPerSideFor(
        mobile: Platform.isAndroid || Platform.isIOS);
    preloadMemoryMb = preloadDefaultMemoryMb;
    stripLibIndex = true;
    doubleTapLike = true;
    videoFitOverride = null;
    keyBindings
      ..clear()
      ..addAll({
        for (final e in _defaultKeyIds.entries) e.key: KeyCombo(e.value),
      });
  }

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw);
        if (j is Map<String, dynamic>) applyJson(j);
      }
      // Windows 上多路视频预载会让整机明显卡顿：老配置一次性降为「不预载」，
      // 用户仍可在「播放参数」里手动开回来。
      if (Platform.isWindows && sp.getBool('lowload_migrated_v1') != true) {
        preloadPerSide = 0;
        await save();
        await sp.setBool('lowload_migrated_v1', true);
      }
    } catch (_) {
      // 设置损坏时保留默认值，不影响启动
    }
  }

  static Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(prefsKey, jsonEncode(toJson()));
    } catch (_) {}
  }

  /// 单键绑定（等价于无修饰键的组合），保留给旧调用点与测试。
  static void bind(PlayerAction action, int keyId) =>
      bindCombo(action, KeyCombo(keyId));

  /// 绑定组合键。冲突检测按「修饰键 + 主键」整体比较：
  /// 与已有单键 `F` 冲突的是组合 `F(mods=0)`，`Ctrl+F` 不算冲突。
  /// 若目标组合已被别的动作占用则互换，保证一个组合只对应一个动作。
  /// 只有修饰键（Shift/Ctrl/Alt/Meta）不能单独成为组合，直接忽略。
  static bool bindCombo(PlayerAction action, KeyCombo combo) {
    if (!combo.isBound || isModifierKeyId(combo.keyId)) return false;
    final old = keyBindings[action];
    PlayerAction? conflict;
    for (final e in keyBindings.entries) {
      if (e.key != action && e.value == combo) {
        conflict = e.key;
        break;
      }
    }
    if (conflict != null && old != null) keyBindings[conflict] = old;
    keyBindings[action] = combo;
    return true;
  }

  static bool isModifierKeyId(int id) =>
      id == LogicalKeyboardKey.shift.keyId ||
      id == LogicalKeyboardKey.shiftLeft.keyId ||
      id == LogicalKeyboardKey.shiftRight.keyId ||
      id == LogicalKeyboardKey.control.keyId ||
      id == LogicalKeyboardKey.controlLeft.keyId ||
      id == LogicalKeyboardKey.controlRight.keyId ||
      id == LogicalKeyboardKey.alt.keyId ||
      id == LogicalKeyboardKey.altLeft.keyId ||
      id == LogicalKeyboardKey.altRight.keyId ||
      id == LogicalKeyboardKey.meta.keyId ||
      id == LogicalKeyboardKey.metaLeft.keyId ||
      id == LogicalKeyboardKey.metaRight.keyId;

  /// 当前硬件键盘上被按住的修饰键位掩码。
  static int currentMods() {
    final hk = HardwareKeyboard.instance;
    var m = 0;
    if (hk.isShiftPressed) m |= KeyCombo.modShift;
    if (hk.isControlPressed) m |= KeyCombo.modCtrl;
    if (hk.isAltPressed) m |= KeyCombo.modAlt;
    if (hk.isMetaPressed) m |= KeyCombo.modMeta;
    return m;
  }

  static String keyLabel(PlayerAction action) {
    final c = keyBindings[action];
    return c == null ? '未绑定' : comboLabel(c);
  }

  /// 组合显示名，固定顺序 Ctrl → Shift → Alt → Win/Meta → 主键。
  static String comboLabel(KeyCombo c) {
    if (!c.isBound) return '未绑定';
    final parts = modsParts(c.mods);
    parts.add(keyLabelById(c.keyId));
    return parts.join('+');
  }

  /// 修饰键显示片段，固定顺序 Ctrl → Shift → Alt → Win。
  static List<String> modsParts(int mods) {
    final parts = <String>[];
    if (mods & KeyCombo.modCtrl != 0) parts.add('Ctrl');
    if (mods & KeyCombo.modShift != 0) parts.add('Shift');
    if (mods & KeyCombo.modAlt != 0) parts.add('Alt');
    if (mods & KeyCombo.modMeta != 0) parts.add('Win');
    return parts;
  }

  static String keyLabelById(int id) {
    if (id == 0) return '未绑定';
    if (id == LogicalKeyboardKey.space.keyId) return '空格';
    if (id == LogicalKeyboardKey.enter.keyId) return '回车';
    if (id == LogicalKeyboardKey.tab.keyId) return 'Tab';
    if (id == LogicalKeyboardKey.backspace.keyId) return '退格';
    if (id == LogicalKeyboardKey.delete.keyId) return 'Del';
    if (id == LogicalKeyboardKey.escape.keyId) return 'Esc';
    if (id == LogicalKeyboardKey.arrowUp.keyId) return '↑';
    if (id == LogicalKeyboardKey.arrowDown.keyId) return '↓';
    if (id == LogicalKeyboardKey.arrowLeft.keyId) return '←';
    if (id == LogicalKeyboardKey.arrowRight.keyId) return '→';
    final k = LogicalKeyboardKey.findKeyByKeyId(id);
    final label = k?.keyLabel ?? '';
    if (label.isEmpty || label == 'Unidentified') return '未绑定';
    return label.length == 1 ? label.toUpperCase() : label;
  }

  /// 返回「该主键 + 这些修饰键」精确对应的动作。
  ///
  /// 精确匹配是有意的：`Ctrl+J` 不会触发绑定在 `J` 上的动作，
  /// 避免带修饰键的系统快捷键（Ctrl+C 等）误触发播放动作。
  static PlayerAction? actionForCombo(int keyId, int mods) {
    for (final e in keyBindings.entries) {
      if (e.value.keyId == keyId && e.value.mods == mods) return e.key;
    }
    return null;
  }

  /// 无修饰键的简写（测试与不需要修饰键的调用点）。
  static PlayerAction? actionFor(LogicalKeyboardKey k) =>
      actionForCombo(k.keyId, 0);
}
