import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';

void main() {
  setUp(() => AppSettings.resetDefaults());

  test('defaults', () {
    expect(AppSettings.defaultSpeed, 1.0);
    expect(AppSettings.imageIntervalSec, 3);
    expect(AppSettings.hideUiSec, 3);
    expect(AppSettings.keyLabel(PlayerAction.next), 'J');
    expect(AppSettings.actionFor(LogicalKeyboardKey.keyJ), PlayerAction.next);
  });

  test('json round trip', () {
    AppSettings.defaultSpeed = 1.5;
    AppSettings.imageIntervalSec = 7;
    AppSettings.hideUiSec = 5;
    AppSettings.bind(PlayerAction.mute, LogicalKeyboardKey.keyN.keyId);
    AppSettings.stripLibIndex = false;
    final j = AppSettings.toJson();
    AppSettings.resetDefaults();
    AppSettings.applyJson(j);
    expect(AppSettings.stripLibIndex, isFalse);
    expect(AppSettings.defaultSpeed, 1.5);
    expect(AppSettings.imageIntervalSec, 7);
    expect(AppSettings.hideUiSec, 5);
    expect(AppSettings.actionFor(LogicalKeyboardKey.keyN), PlayerAction.mute);
  });

  test('invalid values fall back and clamp', () {
    AppSettings.applyJson({
      'speed': 42,
      'imageInterval': -3,
      'hideUi': 999,
      'keys': {'next': 'oops'},
    });
    expect(AppSettings.defaultSpeed, 3.0);
    expect(AppSettings.imageIntervalSec, 1);
    expect(AppSettings.hideUiSec, 30);
    expect(AppSettings.keyLabel(PlayerAction.next), 'J');
  });

  test('binding conflicts swap keys instead of duplicating', () {
    final oldNext = AppSettings.keyIds[PlayerAction.next]!;
    final oldPause = AppSettings.keyIds[PlayerAction.playPause]!;
    AppSettings.bind(PlayerAction.next, oldPause);
    expect(AppSettings.actionFor(LogicalKeyboardKey.space), PlayerAction.next);
    expect(AppSettings.keyIds[PlayerAction.playPause], oldNext);
    expect(
        AppSettings.keyIds.values.toSet().length, PlayerAction.values.length);
  });

  test('arrows kept as fixed navigation', () {
    AppSettings.bind(PlayerAction.next, LogicalKeyboardKey.keyN.keyId);
    expect(AppSettings.actionFor(LogicalKeyboardKey.arrowDown), isNull);
    expect(AppSettings.toJson()['keys']['next'],
        {'k': LogicalKeyboardKey.keyN.keyId, 'm': 0});
  });

  group('组合键', () {
    test('单键与带修饰键的组合互不冲突', () {
      final fId = LogicalKeyboardKey.keyF.keyId;
      final jId = LogicalKeyboardKey.keyJ.keyId;
      AppSettings.bind(PlayerAction.fullscreen, fId);
      // Ctrl+F 不抢占单键 F
      expect(
          AppSettings.bindCombo(
              PlayerAction.mute, KeyCombo(fId, KeyCombo.modCtrl)),
          isTrue);
      expect(AppSettings.keyIds[PlayerAction.fullscreen], fId);
      expect(AppSettings.actionForCombo(fId, 0), PlayerAction.fullscreen);
      expect(AppSettings.actionForCombo(fId, KeyCombo.modCtrl),
          PlayerAction.mute);
      // 单键 J 也不会被 Ctrl+J 影响（默认 next = J）
      expect(AppSettings.actionForCombo(jId, 0), PlayerAction.next);
      expect(AppSettings.actionForCombo(jId, KeyCombo.modCtrl), isNull);
    });

    test('完全相同的组合才算冲突并互换', () {
      final nId = LogicalKeyboardKey.keyN.keyId;
      final combo = KeyCombo(nId, KeyCombo.modCtrl | KeyCombo.modShift);
      AppSettings.bindCombo(PlayerAction.mute, combo);
      final oldNext = AppSettings.keyBindings[PlayerAction.next]!;
      AppSettings.bindCombo(PlayerAction.next, combo);
      // 目标组合被 mute 占着：两者互换，仍然一对一
      expect(AppSettings.keyBindings[PlayerAction.next], combo);
      expect(AppSettings.keyBindings[PlayerAction.mute], oldNext);
      expect(AppSettings.actionForCombo(nId, combo.mods), PlayerAction.next);
      expect(AppSettings.keyBindings.values.toSet().length,
          PlayerAction.values.length);
    });

    test('只有修饰键的组合被拒绝', () {
      final before = Map.of(AppSettings.keyBindings);
      expect(
          AppSettings.bindCombo(PlayerAction.next,
              KeyCombo(LogicalKeyboardKey.controlLeft.keyId, KeyCombo.modCtrl)),
          isFalse);
      expect(
          AppSettings.bindCombo(PlayerAction.next,
              KeyCombo(LogicalKeyboardKey.shift.keyId, KeyCombo.modShift)),
          isFalse);
      expect(AppSettings.keyBindings, before);
    });

    test('标签与序列化往返', () {
      AppSettings.bindCombo(PlayerAction.playPause,
          KeyCombo(LogicalKeyboardKey.keyF.keyId,
              KeyCombo.modCtrl | KeyCombo.modShift));
      expect(AppSettings.keyLabel(PlayerAction.playPause), 'Ctrl+Shift+F');
      final j = AppSettings.toJson();
      AppSettings.resetDefaults();
      expect(AppSettings.keyLabel(PlayerAction.playPause), '空格');
      AppSettings.applyJson(j);
      expect(AppSettings.keyLabel(PlayerAction.playPause), 'Ctrl+Shift+F');
      expect(
          AppSettings.actionForCombo(LogicalKeyboardKey.keyF.keyId,
              KeyCombo.modCtrl | KeyCombo.modShift),
          PlayerAction.playPause);
    });

    test('旧格式（纯数字）仍能读入', () {
      AppSettings.applyJson({
        'keys': {'next': LogicalKeyboardKey.keyN.keyId},
      });
      expect(AppSettings.keyBindings[PlayerAction.next],
          KeyCombo(LogicalKeyboardKey.keyN.keyId));
      expect(AppSettings.keyLabel(PlayerAction.next), 'N');
    });
  });
}
