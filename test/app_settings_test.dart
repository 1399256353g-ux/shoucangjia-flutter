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
    final j = AppSettings.toJson();
    AppSettings.resetDefaults();
    AppSettings.applyJson(j);
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
    expect(AppSettings.toJson()['keys']['next'], LogicalKeyboardKey.keyN.keyId);
  });
}
