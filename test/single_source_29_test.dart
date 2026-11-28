// 第四十五批契约（0.9.263）：
//
// P0「按键绑定支持组合键」这一项此前被记为「已完成」。组合键的**捕获**确实
// 有了（`KeyCaptureDialog` 把修饰键掩码并进 `KeyCombo`），但**准入与读入**
// 两条路径都没有校验掩码本身，于是存在两个「界面说已绑定、按键永远没反应」
// 的静默失效：
//
//  1. 修饰键掩码没有值域。`bindComboError(KeyCombo(102, 16))` 返回 null（放行），
//     而 `currentMods()` 只会置低 4 位——任何真实按键都算不出 16，
//     `actionForCombo(102, 16)` 永远匹配不到。更糟的是 `comboLabel` 只读低 4 位，
//     把它显示成裸 `F`：用户按 F 没反应，页面上却写着 F。
//     `m = -1` 同理放行，并被显示成 `Ctrl+Shift+Alt+Win+J` 这样一个既按不出来、
//     也不可能生效的组合。
//  2. 落盘读入不去重。`applyJson` 按 `PlayerAction.values` 顺序逐条赋值、不查
//     是否已有别的动作占了同一组合。手改配置或两次并发保存之后，两个动作同时
//     绑在 `F` 上：界面两行都显示 `F`，`actionForCombo` 只返回先命中的那个，
//     另一个动作永远触发不了。写路径 `bindCombo` 是互斥的（互换旧绑定），
//     读路径却允许共存——同一条规则两条口径。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';

void main() {
  final f = LogicalKeyboardKey.keyF.keyId;
  final j = LogicalKeyboardKey.keyJ.keyId;

  setUp(AppSettings.resetDefaults);
  tearDown(AppSettings.resetDefaults);

  group('修饰键掩码必须落在已知位域内', () {
    test('越界位（16/32）被拒绝，不再放行', () {
      expect(AppSettings.bindComboError(KeyCombo(f, 16)), isNotNull);
      expect(AppSettings.bindComboError(KeyCombo(f, 32)), isNotNull);
      expect(AppSettings.bindComboError(KeyCombo(f, KeyCombo.modAll + 1)),
          isNotNull);
    });

    test('负数掩码被拒绝', () {
      // `-1` 的每一位都是 1：旧实现既放行、又把它显示成四个修饰键全按。
      expect(AppSettings.bindComboError(KeyCombo(j, -1)), isNotNull);
    });

    test('合法掩码仍然放行（0 与 1..15 全部）', () {
      for (var m = 0; m <= KeyCombo.modAll; m++) {
        expect(AppSettings.bindComboError(KeyCombo(f, m)), isNull,
            reason: 'mods=$m 应当合法');
      }
    });

    test('越界掩码不会成为生效绑定（写路径与读路径一致）', () {
      AppSettings.bindCombo(PlayerAction.fullscreen, KeyCombo(f, 16));
      // 拒绝后应保持默认（F），而不是被写成 m=16 的死绑定。
      expect(AppSettings.keyBindings[PlayerAction.fullscreen], KeyCombo(f));
      // 归一后 `16` 与 `0` 是同一个组合（16 在已知位域里没有任何位），
      // 所以按 F 命中全屏；**不存在**一个只有 16 才能命中的死组合。
      expect(AppSettings.actionForCombo(f, 16), PlayerAction.fullscreen);
      expect(AppSettings.actionForCombo(f, 0), PlayerAction.fullscreen);
    });

    test('落盘里的越界掩码读入时只保留已知位（不会成为按不出来的死绑定）', () {
      AppSettings.applyJson({
        'keys': {
          'mute': {'k': f, 'm': 16},
          'back': {'k': j, 'm': -1},
        }
      });
      // 0.9.381：越界位**不是**未知修饰键，只是同一位域的无效值。读入时按
      // `& modAll` 归一，剩下的已知低位就是真正参与比较的那部分：
      //   `m=16` 只剩 0 位             → 等价于单键 F；
      //   `m=-1` 在已知位域内全为 1    → 等价于 Ctrl+Shift+Alt+Win+J。
      // 关键不变量：不会再存在「界面说已绑定、按键永远匹配不上」的条目——
      // 归一后的组合与真实按键算出来的掩码可以精确相等。
      expect(AppSettings.keyBindings[PlayerAction.mute], KeyCombo(f));
      expect(AppSettings.keyBindings[PlayerAction.back],
          KeyCombo(j, KeyCombo.modAll));
      expect(AppSettings.actionForCombo(f, 16), PlayerAction.mute);
      expect(AppSettings.actionForCombo(f, 0), PlayerAction.mute);
      expect(AppSettings.actionForCombo(j, KeyCombo.modAll), PlayerAction.back);
    });

    test('显示层只读已知位，不产出四个修饰键的假标签', () {
      expect(AppSettings.modsParts(-1), isEmpty);
      expect(AppSettings.modsParts(16), isEmpty);
      expect(AppSettings.comboLabel(KeyCombo(j, -1)), 'J');
      // 合法掩码顺序不变。
      expect(
          AppSettings.comboLabel(KeyCombo(
              j, KeyCombo.modCtrl | KeyCombo.modShift)),
          'Ctrl+Shift+J');
    });
  });

  group('同一组合只能对应一个动作（写路径与读路径同一条规则）', () {
    test('读入时的重复绑定只保留先读到的一个', () {
      AppSettings.applyJson({
        'keys': {
          'mute': {'k': f, 'm': 0},
          'fullscreen': {'k': f, 'm': 0},
        }
      });
      // 先读到 mute → 它拿到 F；F 的原持有者（fullscreen，默认键就是 F）
      // 按写路径的互换语义接管 mute 原来的键（M），不会两行都写 F。
      expect(AppSettings.keyBindings[PlayerAction.mute], KeyCombo(f));
      expect(AppSettings.keyBindings[PlayerAction.fullscreen],
          KeyCombo(LogicalKeyboardKey.keyM.keyId));
      // 关键：不变量成立——任何组合最多一个动作。
      final seen = <KeyCombo>{};
      for (final c in AppSettings.keyBindings.values) {
        expect(seen.add(c), isTrue, reason: '组合 $c 被两个动作同时占用');
      }
    });

    test('重绑到当前已占用的组合会互换，不会留下两行同键', () {
      final muteKey = AppSettings.keyBindings[PlayerAction.mute]!;
      final fsKey = AppSettings.keyBindings[PlayerAction.fullscreen]!;
      expect(muteKey, isNot(fsKey));
      // 把 mute 绑到 fullscreen 现在用的键上 → 两者互换。
      expect(AppSettings.bindCombo(PlayerAction.mute, fsKey), isTrue);
      expect(AppSettings.keyBindings[PlayerAction.mute], fsKey);
      expect(AppSettings.keyBindings[PlayerAction.fullscreen], muteKey);
    });

    test('重绑到自身当前组合不算冲突（自我冲突会要点两次才生效）', () {
      final cur = AppSettings.keyBindings[PlayerAction.mute]!;
      expect(AppSettings.conflictOwner(PlayerAction.mute, cur), isNull);
      expect(AppSettings.bindCombo(PlayerAction.mute, cur), isTrue);
      expect(AppSettings.keyBindings[PlayerAction.mute], cur);
    });

    test('conflictOwner 报出真正的占用者', () {
      final fsKey = AppSettings.keyBindings[PlayerAction.fullscreen]!;
      expect(AppSettings.conflictOwner(PlayerAction.mute, fsKey),
          PlayerAction.fullscreen);
      // 「是否被别人占用」只由 conflictOwner 一处回答（0.9.359 删掉了
      // 它的布尔包装 isComboTakenByOther：那样同一判定就有两个名字）。
      expect(AppSettings.conflictOwner(PlayerAction.fullscreen, fsKey),
          isNot(PlayerAction.fullscreen));
    });

    test('单键与组合键不互相冲突（Ctrl+J ≠ J）', () {
      final single = KeyCombo(j);
      final combo = KeyCombo(j, KeyCombo.modCtrl);
      expect(AppSettings.bindCombo(PlayerAction.mute, single), isTrue);
      // 组合键占用不影响单键持有者。
      expect(AppSettings.conflictOwner(PlayerAction.prev, combo), isNull);
      expect(AppSettings.keyBindings[PlayerAction.mute], single);
      expect(AppSettings.bindCombo(PlayerAction.prev, combo), isTrue);
      expect(AppSettings.keyBindings[PlayerAction.mute], single);
      expect(AppSettings.actionForCombo(j, 0), PlayerAction.mute);
      expect(AppSettings.actionForCombo(j, KeyCombo.modCtrl),
          PlayerAction.prev);
    });
  });
}
