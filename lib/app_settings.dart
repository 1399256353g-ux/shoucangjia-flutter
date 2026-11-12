import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// 全局设置：播放参数 + 桌面按键绑定，持久化到 SharedPreferences。
/// 序列化与业务逻辑保持纯函数，便于单元测试。
class AppSettings {
  static const String prefsKey = 'app_settings_v1';

  static double defaultSpeed = 1.0;
  static int imageIntervalSec = 3;
  static int hideUiSec = 3;

  static final Map<PlayerAction, int> keyIds =
      Map<PlayerAction, int>.from(_defaultKeyIds);

  static Map<String, dynamic> toJson() => {
        'speed': defaultSpeed,
        'imageInterval': imageIntervalSec,
        'hideUi': hideUiSec,
        'keys': {
          for (final e in keyIds.entries) e.key.name: e.value,
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
    final keys = j['keys'];
    if (keys is Map) {
      for (final a in PlayerAction.values) {
        final v = keys[a.name];
        if (v is num) keyIds[a] = v.toInt();
      }
    }
  }

  static void resetDefaults() {
    defaultSpeed = 1.0;
    imageIntervalSec = 3;
    hideUiSec = 3;
    keyIds
      ..clear()
      ..addAll(_defaultKeyIds);
  }

  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(prefsKey);
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) applyJson(j);
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

  /// 绑定/解绑：若目标键已被别的动作占用则交换，保证一键一动作。
  static void bind(PlayerAction action, int keyId) {
    final old = keyIds[action];
    PlayerAction? conflict;
    for (final e in keyIds.entries) {
      if (e.key != action && e.value == keyId) {
        conflict = e.key;
        break;
      }
    }
    if (conflict != null && old != null) keyIds[conflict] = old;
    keyIds[action] = keyId;
  }

  static String keyLabel(PlayerAction action) =>
      keyLabelById(keyIds[action] ?? 0);

  static String keyLabelById(int id) {
    if (id == LogicalKeyboardKey.space.keyId) return '空格';
    if (id == LogicalKeyboardKey.enter.keyId) return '回车';
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

  /// 返回该按键对应的动作（自定义绑定优先）。
  static PlayerAction? actionFor(LogicalKeyboardKey k) {
    for (final e in keyIds.entries) {
      if (e.value == k.keyId) return e.key;
    }
    return null;
  }
}
