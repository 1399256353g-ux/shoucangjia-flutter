import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/pref_keys.dart';
import 'package:shoucangjia/star_store.dart';


/// 第一百二十六批：组合键的**读写同一把尺子**，以及本机偏好键集中定义。
///
/// 上一批把连接表/设置类读盘收成单源后，按键这一块还剩一处同类问题：
/// 「按下时怎么比」与「落盘/读盘时怎么存」各写一套判定，历史数据（大写
/// 键码、越界掩码）就变成「界面上显示已绑定、按下去没反应」的哑键。
/// 本文件钉住：归一 + 精确相等，且单键与组合键是同一条比较。
void main() {
  setUp(() => AppSettings.resetDefaults());

  group('归一化', () {
    test('大写字母键码归一到小写键码', () {
      expect(AppSettings.normalizeKeyId(0x46), LogicalKeyboardKey.keyF.keyId);
      expect(AppSettings.normalizeKeyId(0x4A), LogicalKeyboardKey.keyJ.keyId);
      // 已经是对的键码原样返回。
      expect(AppSettings.normalizeKeyId(0x66), 0x66);
      // 非字母区间原样返回（空格/方向键/媒体键）。
      expect(AppSettings.normalizeKeyId(LogicalKeyboardKey.space.keyId),
          LogicalKeyboardKey.space.keyId);
      expect(AppSettings.normalizeKeyId(LogicalKeyboardKey.arrowUp.keyId),
          LogicalKeyboardKey.arrowUp.keyId);
    });

    test('掩码只保留已知四位，越界与负数归一', () {
      expect(KeyCombo.normalizeMods(-1), KeyCombo.modAll);
      expect(KeyCombo.normalizeMods(16), 0);
      expect(KeyCombo.normalizeMods(16 | KeyCombo.modCtrl), KeyCombo.modCtrl);
      expect(KeyCombo.normalizeMods(KeyCombo.modShift | KeyCombo.modMeta),
          KeyCombo.modShift | KeyCombo.modMeta);
    });

    test('落盘里的大写键码 / 越界掩码被读成可触发的组合', () {
      final c = KeyCombo.fromJson({'k': 70, 'm': 16});
      expect(c, isNotNull);
      expect(c!.keyId, LogicalKeyboardKey.keyF.keyId);
      expect(c.mods, 0);
      final neg = KeyCombo.fromJson({'k': '70', 'm': -1});
      expect(neg!.keyId, LogicalKeyboardKey.keyF.keyId);
      expect(neg.mods, KeyCombo.modAll);
    });
  });

  group('匹配只有一个口径', () {
    test('单键 J 与 Ctrl+J 互不触发', () {
      AppSettings.bindCombo(
          PlayerAction.next, KeyCombo(LogicalKeyboardKey.keyJ.keyId));
      final j = LogicalKeyboardKey.keyJ.keyId;
      expect(AppSettings.actionForCombo(j, 0), PlayerAction.next);
      expect(AppSettings.actionForCombo(j, KeyCombo.modCtrl), isNull);
    });

    test('绑到大写键码后，用小写真实按键能触发（不再哑键）', () {
      // 绕开 bindCombo 的归一？不——bindCombo 本身也归一，这里直接改表
      // 模拟历史落盘：表里存的就是大写码。
      AppSettings.keyBindings[PlayerAction.mute] =
          const KeyCombo(0x4D); // 'M'
      final m = LogicalKeyboardKey.keyM.keyId;
      expect(AppSettings.actionForCombo(m, 0), PlayerAction.mute);
      // 反过来：表里是小写、按下给大写（极端情况下识别层给大写）也能命中。
      AppSettings.keyBindings[PlayerAction.mute] = KeyCombo(m);
      expect(AppSettings.actionForCombo(0x4D, 0), PlayerAction.mute);
    });

    test('冲突检测也归一：大写码与小写码算同一个键', () {
      AppSettings.keyBindings[PlayerAction.fullscreen] =
          const KeyCombo(0x46); // 'F'
      final f = LogicalKeyboardKey.keyF.keyId;
      expect(AppSettings.conflictOwner(PlayerAction.mute, KeyCombo(f)),
          PlayerAction.fullscreen);
      // 组合键不算冲突。
      expect(
          AppSettings.conflictOwner(
              PlayerAction.mute, KeyCombo(f, KeyCombo.modCtrl)),
          isNull);
    });

    test('bindCombo 落盘后不会留下未经归一的组合', () {
      // 准入层与匹配层各管一段：
      //  - 大写码 70 是「写不进去的形状」，准入必须拒绝（见 single_source_22）；
      //  - 越界掩码同理；
      //  - 合法输入落表时仍是归一后的形状（这里用真实小写码 + Alt）。
      expect(AppSettings.bindCombo(PlayerAction.mute, const KeyCombo(0x4D)),
          isFalse);
      expect(
          AppSettings.bindCombo(
              PlayerAction.mute, const KeyCombo(0x4D, 16 | KeyCombo.modAlt)),
          isFalse);
      final ok = AppSettings.bindCombo(
          PlayerAction.mute,
          KeyCombo(LogicalKeyboardKey.keyM.keyId, KeyCombo.modAlt));
      expect(ok, isTrue);
      final c = AppSettings.keyBindings[PlayerAction.mute]!;
      expect(c.keyId, LogicalKeyboardKey.keyM.keyId);
      expect(c.mods, KeyCombo.modAlt);
    });

    test('占用时互换：原主拿到旧键，双向都可触发', () {
      final f = LogicalKeyboardKey.keyF.keyId;
      final m = LogicalKeyboardKey.keyM.keyId;
      AppSettings.bindCombo(PlayerAction.fullscreen, KeyCombo(f));
      AppSettings.bindCombo(PlayerAction.mute, KeyCombo(m));
      // 把静音绑到 F：全屏拿到静音原来的 M。
      expect(AppSettings.conflictOwner(PlayerAction.mute, KeyCombo(f)),
          PlayerAction.fullscreen);
      AppSettings.bindCombo(PlayerAction.mute, KeyCombo(f));
      expect(AppSettings.actionForCombo(f, 0), PlayerAction.mute);
      expect(AppSettings.actionForCombo(m, 0), PlayerAction.fullscreen);
    });

    test('applyJson 里两条指向同一真实按键时只保留先到的', () {
      AppSettings.applyJson(<String, dynamic>{
        'keys': {
          PlayerAction.next.name: {'k': 0x4A, 'm': 0}, // 大写 J
          PlayerAction.prev.name: {'k': LogicalKeyboardKey.keyJ.keyId, 'm': 0},
        }
      });
      final j = LogicalKeyboardKey.keyJ.keyId;
      expect(AppSettings.actionForCombo(j, 0), isNotNull);
      // 同一键只对应一个动作。
      final owners = PlayerAction.values
          .where((a) =>
              AppSettings.keyBindings[a] != null &&
              AppSettings.keyBindings[a]!.keyId == j)
          .toList();
      expect(owners.length, 1, reason: '同一个真实按键被两个动作占用：$owners');
    });
  });

  group('本机偏好键集中定义', () {
    test('三把本机键字符串只在 pref_keys 里出现，其余是转发', () {
      expect(kLocalPrefKeys, contains(kHiddenWorksPrefsKey));
      expect(kLocalPrefKeys, contains(kFolderUnlockedPrefsKey));
      expect(kLocalPrefKeys, contains(kStarredLibsPrefsKey));
      expect(kLocalPrefKeys.toSet().length, kLocalPrefKeys.length);
    });

    test('转发点的键值与历史落盘逐字相同（升级不丢数据）', () {
      expect(kHiddenWorksPrefsKey, 'hidden_works_v1');
      expect(kFolderUnlockedPrefsKey, 'folder_unlocked_v1');
      expect(kStarredLibsPrefsKey, 'lib_tree_stars_v1');
      expect(StarStore.prefKey, kStarredLibsPrefsKey);
    });
  });
}
