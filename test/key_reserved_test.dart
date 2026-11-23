import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';

/// 保留键是**准入规则**，不是读取顺序里的补丁。
///
/// 播放页 `onKey` 先查自定义绑定、再判固定键位；只要允许把动作绑到
/// 方向键/Esc，固定键位就会被抢掉，翻页与退出随之失效。所以拒绝必须发生在
/// `bindComboError`（唯一判定口），UI 与读盘走同一条规则。
void main() {
  setUp(() => AppSettings.resetDefaults());

  test('方向键与 Esc 被拒绝绑定，且给出了原因', () {
    final reserved = <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.escape,
    ];
    for (final k in reserved) {
      final combo = KeyCombo(k.keyId);
      expect(AppSettings.isReservedKeyId(k.keyId), isTrue, reason: '$k');
      expect(AppSettings.bindComboError(combo), isNotNull, reason: '$k');
      expect(AppSettings.bindCombo(PlayerAction.mute, combo), isFalse,
          reason: '$k');
    }
    // 被拒后绑定表保持默认，没有被写脏。
    expect(AppSettings.actionFor(LogicalKeyboardKey.escape), isNull);
    expect(AppSettings.actionFor(LogicalKeyboardKey.arrowDown), isNull);
  });

  test('带修饰键也不能占用保留键（Ctrl+← 同样抢翻页）', () {
    final combo =
        KeyCombo(LogicalKeyboardKey.arrowLeft.keyId, KeyCombo.modCtrl);
    expect(AppSettings.bindComboError(combo), isNotNull);
    expect(AppSettings.bindCombo(PlayerAction.prev, combo), isFalse);
  });

  test('普通字母键与空格仍可绑定（未被误伤）', () {
    expect(AppSettings.bindComboError(KeyCombo(LogicalKeyboardKey.keyQ.keyId)),
        isNull);
    expect(
        AppSettings.bindComboError(
            KeyCombo(LogicalKeyboardKey.space.keyId, KeyCombo.modCtrl)),
        isNull);
    expect(
        AppSettings.bindCombo(PlayerAction.mute,
            KeyCombo(LogicalKeyboardKey.keyQ.keyId, KeyCombo.modCtrl)),
        isTrue);
  });

  test('纯修饰键仍被拒绝，且原因与保留键不同', () {
    final modOnly = KeyCombo(LogicalKeyboardKey.controlLeft.keyId);
    final arrow = KeyCombo(LogicalKeyboardKey.arrowUp.keyId);
    expect(AppSettings.bindComboError(modOnly), isNotNull);
    expect(AppSettings.bindComboError(arrow), isNotNull);
    expect(AppSettings.bindComboError(modOnly),
        isNot(AppSettings.bindComboError(arrow)));
  });

  test('未绑定（keyId=0）被拒绝', () {
    expect(AppSettings.bindComboError(const KeyCombo(0)), isNotNull);
  });

  test('旧配置里落在保留键上的绑定读入时被丢弃，其余正常恢复', () {
    AppSettings.applyJson({
      'keys': {
        // 历史遗留：动作绑到方向键/Esc，读入必须丢弃。
        'fullscreen': KeyCombo(LogicalKeyboardKey.escape.keyId).toJson(),
        'prev': KeyCombo(LogicalKeyboardKey.arrowDown.keyId).toJson(),
        // 正常项必须照旧恢复。
        'mute': KeyCombo(LogicalKeyboardKey.keyQ.keyId, KeyCombo.modAlt)
            .toJson(),
      },
    });
    expect(AppSettings.keyBindings[PlayerAction.fullscreen]!.keyId,
        isNot(LogicalKeyboardKey.escape.keyId));
    expect(AppSettings.keyBindings[PlayerAction.prev]!.keyId,
        isNot(LogicalKeyboardKey.arrowDown.keyId));
    // 被丢弃的动作回到默认值，而不是变成「未绑定」。
    expect(AppSettings.keyIds[PlayerAction.fullscreen], 70, reason: '默认 F');
    expect(AppSettings.keyIds[PlayerAction.prev], 107, reason: '默认 K');
    expect(AppSettings.actionForCombo(LogicalKeyboardKey.keyQ.keyId,
        KeyCombo.modAlt), PlayerAction.mute);
  });
}
