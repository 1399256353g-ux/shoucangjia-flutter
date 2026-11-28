import 'dart:convert';
import 'json_num.dart';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'prefs_json.dart';
import 'playback_prefs.dart' show clampSpeed;
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

/// 默认键位（**只能**由 `LogicalKeyboardKey` 推导，不写数字字面量）。
///
/// 历史缺陷（本批修掉）：这里原先手写了 ASCII 码，而且**一半写成了大写**。
/// Flutter 给字母键分配的 keyId 是 **小写** ASCII 码
/// （`keyJ.keyId == 106`、`keyF.keyId == 102`、`keyM.keyId == 109`、
/// `keyL.keyId == 108`、`keyH.keyId == 104`），而表里写的是
/// `mute: 77`（`'M'`）、`fullscreen: 70`（`'F'`）、`forward: 76`（`'L'`）、
/// `back: 72`（`'H'`）。
///
/// 后果是四个默认快捷键**从来没生效过**：
///  - 播放页 `actionForCombo(102, 0)` 匹配不到 70，按键落到固定键位分支后
///    什么也不做（不是「没绑」，是「绑了一个不存在的键」）；
///  - 按键设置页把这几项显示成「未绑定」（`keyLabelById(70)` 查不到键）。
/// `J`/`K` 看起来正常，只因为那两个数恰好写成了小写码——同一张表里两种口径，
/// 正说明「手写数字」这件事本身就是错的。
///
/// 现在一律从 [LogicalKeyboardKey] 取，键位改了也不会再漂。
Map<PlayerAction, int> defaultKeyIds() => <PlayerAction, int>{
      PlayerAction.next: LogicalKeyboardKey.keyJ.keyId,
      PlayerAction.prev: LogicalKeyboardKey.keyK.keyId,
      PlayerAction.playPause: LogicalKeyboardKey.space.keyId,
      PlayerAction.mute: LogicalKeyboardKey.keyM.keyId,
      PlayerAction.fullscreen: LogicalKeyboardKey.keyF.keyId,
      PlayerAction.forward: LogicalKeyboardKey.keyL.keyId,
      PlayerAction.back: LogicalKeyboardKey.keyH.keyId,
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

  /// 四个修饰键位的全部合法位：掩码必须落在 `0..modAll` 之内。
  static const int modAll = modShift | modCtrl | modAlt | modMeta;

  final int keyId;
  final int mods;

  const KeyCombo(this.keyId, [this.mods = 0]);

  bool get isBound => keyId != 0;

  // 0.9.359：`copyWith` 已删。lib/ 与 test/ 双零调用——它是「一个组合
  // 拆成两步改」的入口，而绑定层只有「整条替换」（[AppSettings.bindCombo]）
  // 与「互换」两种动作。留着它意味着将来有人用 `c.copyWith(mods: …)` 造出
  // 一个**未经准入**的组合（`bindComboError` 拦不住），而 `==` 又认为它
  // 与合法组合等价。

  Map<String, dynamic> toJson() => {'k': keyId, 'm': mods};

  /// 把任意掩码归一到已知位域（`0..modAll`）。
  ///
  /// 越界/负数**不是**「未知的修饰键」，而是同一位域的无效值：
  /// Flutter 只为 Shift/Ctrl/Alt/Meta 置位，`_currentMods` 也已 `& modAll`。
  /// 历史落盘里有 `{"k":102,"m":16}` / `m:-1`（手工改过 / 旧版本），
  /// 这两种组合真实键盘永远算不出来，又被 `bindComboError` 拒绝——若不归一，
  /// 用户按下 Ctrl+F 也匹配不上，只能靠重绑一次才恢复。归一本身不改语义：
  /// 越界位描述的不是任何真实按键，剩下的低位就是参与比较的那部分。
  static int normalizeMods(int raw) => raw & modAll;

  /// 兼容三种历史/新格式：纯数字（旧单键）、`{k,m}`、以及带 `id` 的对象。
  ///
  /// 键码/修饰键一律走 [intOf]，不用 `as num?`：落盘 JSON 里这两个字段可能是
  /// 字符串（`{"k":"32"}`，旧版本或手工改过的配置）。裸 cast 遇到字符串会抛
  /// `_TypeError`，而 `applyJson` 是在**启动时**调用的——整份设置（速度、
  /// 预载、词条、全部按键绑定）会一起退回默认，用户只会觉得「设置总是自己变」。
  static KeyCombo? fromJson(Object? v) {
    if (v is num) {
      final k = intOrNull(v);
      return k == null ? null : KeyCombo(k, 0);
    }
    if (v is Map) {
      final rawKey = v['k'] ?? v['id'];
      if (rawKey == null || '${rawKey}'.trim().isEmpty) return null;
      final k = intOf(rawKey);
      if (k == 0) return null;
      // 大写字母码归一小写（`'F' == 70` → 102）：否则这条历史配置
      // 「显示得像已绑定、按下永远不匹配」。归一放在**读入**这一步，
      // 落盘与运行期只有一种键码。
      return KeyCombo(AppSettings.normalizeKeyId(k),
          normalizeMods(intOf(v['m'] ?? v['mods'])));
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

/// 全局设置：播放设置 + 桌面按键绑定，持久化到 SharedPreferences。
/// 序列化与业务逻辑保持纯函数，便于单元测试。
class AppSettings {
  static const String prefsKey = 'app_settings_v1';

  static double defaultSpeed = 1.0;
  static int imageIntervalSec = 3;
  static int hideUiSec = 3;

  /// 图文自动切换间隔的合法区间（秒）——**唯一一份**。
  ///
  /// 0.9.361：`1..20` 此前写了三遍（读盘 `applyJson` 夹紧、设置页 Slider 的
  /// `value` 夹紧、Slider 的 `min`/`max`/`divisions`），`1..30` 同样写三遍
  /// 给「全屏隐藏控制栏时间」。改上限时只改到 slider 而没改读盘，会出现
  /// 「本次调到 20 生效、重启后又被读回 15」——因为边界本来就两份。
  static const int imageIntervalMinSec = 1;
  static const int imageIntervalMaxSec = 20;
  static const int hideUiMinSec = 1;
  static const int hideUiMaxSec = 30;

  /// 图文间隔夹到合法区间。
  static int clampImageInterval(int v) =>
      v.clamp(imageIntervalMinSec, imageIntervalMaxSec);

  /// 全屏隐藏时间夹到合法区间。
  static int clampHideUi(int v) => v.clamp(hideUiMinSec, hideUiMaxSec);

  /// M6：滑动方向前后各预载多少条（0 = 关闭）。
  static int preloadPerSide = preloadDefaultPerSideFor(
      mobile: Platform.isAndroid || Platform.isIOS);

  /// M6：预加载缓存内存上限（MB）。
  static int preloadMemoryMb = preloadDefaultMemoryMb;

  /// 词条是否自动省略库名前的序号（`(1) 名称` → `名称`）。
  static bool stripLibIndex = true;

  /// 视频填充模式覆盖：null = 按源比例自动（竖屏铺满 / 横屏适应），
  /// 用户手动选择后优先于自动判定。默认自动即竖屏「铺满」。
  static VideoFit? videoFitOverride;

  /// 动作 → 按键组合（修饰键 + 主键）。单键就是 `mods == 0` 的组合。
  static final Map<PlayerAction, KeyCombo> keyBindings = {
    for (final e in defaultKeyIds().entries) e.key: KeyCombo(e.value),
  };

  static Map<String, dynamic> toJson() => {
        'speed': defaultSpeed,
        'imageInterval': imageIntervalSec,
        'hideUi': hideUiSec,
        'preloadPerSide': preloadPerSide,
        'preloadMemory': preloadMemoryMb,
        'stripIndex': stripLibIndex,
        'videoFit': videoFitOverride?.name,
        'keys': {
          for (final e in keyBindings.entries) e.key.name: e.value.toJson(),
        },
      };

  /// 容错解析：非法或缺失字段回落默认值。
  static void applyJson(Map<String, dynamic> j) {
    resetDefaults();
    // 数值字段一律走 json_num：`as num?` 遇到字符串（`"speed": "1.5"`）会抛
    // `_TypeError`，而这里是启动路径——异常让整份设置退回默认而不是只跳过
    // 那一个坏字段，表现是「重启后速度/预载/按键全丢」。
    // 用 null 判断「字段存在且可解析」，缺失字段保持 resetDefaults 的值。
    if (j['speed'] != null) {
      // 区间夹紧与显示层/写入层同一份（[clampSpeed]）——此前这里又写一遍
      // `clamp(0.5, 3.0)`，改一处就漂移。
      defaultSpeed = clampSpeed(doubleOf(j['speed'], defaultSpeed)).toDouble();
    }
    if (j['imageInterval'] != null) {
      imageIntervalSec =
          clampImageInterval(intOf(j['imageInterval'], imageIntervalSec));
    }
    if (j['hideUi'] != null) {
      hideUiSec = clampHideUi(intOf(j['hideUi'], hideUiSec));
    }
    if (j['preloadPerSide'] != null) {
      preloadPerSide = clampPreloadPerSide(intOf(j['preloadPerSide'], preloadPerSide));
    }
    if (j['preloadMemory'] != null) {
      preloadMemoryMb = clampPreloadMemoryMb(intOf(j['preloadMemory'], preloadMemoryMb));
    }
    // 布尔字段同样走 json_num 的三态解析：落盘里写成 `"false"` / `0`
    // 时裸 `is bool` 判定会静默保留默认值（true），用户关掉的「省略序号」
    // 重启后又自己打开。`boolOrNull` 无法判断（字段缺失/写坏）才留默认。
    final si = boolOrNull(j['stripIndex']);
    if (si != null) stripLibIndex = si;
    final vf = j['videoFit'];
    if (vf is String) {
      for (final m in VideoFit.values) {
        if (m.name == vf) {
          videoFitOverride = m;
          break;
        }
      }
    }
    _applyKeysJson(j['keys']);
  }

  /// 落盘 `keys` 字段 → [keyBindings]。两趟处理，两趟解决的是**不同**问题：
  ///
  /// 1. **配置内部去重**（第一趟）。手改配置或两次并发保存之后，可能有两个
  ///    动作都写成同一个组合。旧实现逐条直接赋值、完全不查重复，于是两行都
  ///    显示 `F`（都「已绑定」），而 `actionForCombo` 只返回先命中的那个——
  ///    另一个动作永远触发不了，且没有任何提示。配置里的重复只能保留一条，
  ///    按 `PlayerAction.values` 顺序取先到的（与 `decodeServers` 等其它
  ///    读入路径的「先到先得」一致）。
  /// 2. **套用时走写路径的互换语义**（第二趟）。合法配置里用户完全可以把某个
  ///    动作改绑到另一个动作**默认值**上（把静音绑到 `F`，而 `F` 本来是全屏
  ///    的默认键）。这一步若直接赋值，全屏会保留 `F`、静音也拿到 `F`，又是
  ///    两行同键；若「发现冲突就跳过」，用户刚保存的绑定会被静默丢弃。
  ///    写路径的语义是互换，读入必须一致。
  ///
  /// 两趟缺一不可：只用互换、按顺序逐条套用，重复条目的第二次互换会把第一次
  /// 的结果**原样换回去**（实测：`mute:F` + `fullscreen:F` 读完后两者仍是
  /// 各自的默认值，配置里那条改绑等于没发生）。
  static void _applyKeysJson(Object? keys) {
    if (keys is! Map) return;
    // 第一趟：准入 + 配置内部去重。
    final picked = <PlayerAction, KeyCombo>{};
    final used = <KeyCombo>{};
    for (final a in PlayerAction.values) {
      final c = KeyCombo.fromJson(keys[a.name]);
      // 落盘配置同样要过准入：旧版本允许把动作绑到保留键/越界掩码，
      // 读入时丢弃该条，让固定键位保持可用。
      if (c == null || bindComboError(c) != null) continue;
      // 去重键用归一后的组合：`{k:102,m:0}` 与 `{k:70,m:0}`（大写 F）
      // 指向同一个真实按键，配置里两条都写时必须只留一条。
      final norm = KeyCombo(normalizeKeyId(c.keyId),
          KeyCombo.normalizeMods(c.mods));
      if (!used.add(norm)) continue;
      picked[a] = norm;
    }
    // 第二趟：按写入顺序套用，冲突走互换（与 [bindCombo] 同一条规则）。
    for (final a in PlayerAction.values) {
      final c = picked[a];
      if (c != null) bindCombo(a, c);
    }
  }

  /// 播放参数恢复默认（**不动按键绑定，也不动词条显示开关**）。
  ///
  /// 修的是「点『播放设置 → 恢复默认』把按键绑定也一起清掉」：这一页只展示
  /// 速度/间隔/预载/填充，按钮却调了全量重置；用户在按键页辛苦改的 Ctrl+J…
  /// 一次「恢复默认播放参数」就全丢，而且没有任何提示。
  ///
  /// 同一类问题还剩一处：`stripLibIndex`（词条省略序号）属于设置首层的
  /// 「词条」开关，不在本页任何一行上。它原来也在这个函数里被重置——
  /// 用户在该页点一次「恢复默认」，别处关掉的「显示序号」会自己打开，
  /// 而这一页从头到尾没出现过那个开关。现在它归 [resetLabelPrefs]。
  static void resetPlayback() {
    defaultSpeed = 1.0;
    imageIntervalSec = 3;
    hideUiSec = 3;
    preloadPerSide = preloadDefaultPerSideFor(
        mobile: Platform.isAndroid || Platform.isIOS);
    preloadMemoryMb = preloadDefaultMemoryMb;
    videoFitOverride = null;
  }

  /// 词条/标签显示开关恢复默认（**不动播放参数，也不动按键绑定**）。
  ///
  /// 目前只有 [stripLibIndex]。单独一个函数的理由与 [resetKeys] 相同：
  /// 它有自己的入口（设置首层「词条省略序号」），不该被任何一个别的
  /// 「恢复默认」按钮连带重置。
  static void resetLabelPrefs() {
    stripLibIndex = true;
  }

  /// 按键绑定恢复默认（**不动播放参数**）。
  ///
  /// 与 [resetPlayback] 对称：「按键绑定 → 恢复默认」此前同样调全量重置，
  /// 用户改到一半的播放倍速/预载被一起打回默认值。
  static void resetKeys() {
    keyBindings
      ..clear()
      ..addAll({
        for (final e in defaultKeyIds().entries) e.key: KeyCombo(e.value),
      });
  }

  /// 全部恢复默认（三页各自的重置是上面三个；这里保留给「清空全部设置」
  /// 这类真的需要全量的场景，以及测试基线）。
  ///
  /// 不是「三个函数的第二份实现」：[applyJson] 读入前必须先回到已知状态，
  /// 那条路径需要的就是全量；单页按钮则必须只碰自己那一半。
  static void resetDefaults() {
    resetPlayback();
    resetKeys();
    resetLabelPrefs();
  }

  static Future<void> load() async {
    try {
      // 读盘判定只有 `readPrefJson` 一处（空串 / 纯空格 / 坏 JSON 都是 null）。
      final j = await readPrefJson(prefsKey);
      if (j is Map) applyJson(Map<String, dynamic>.from(j));
      // Windows 上多路视频预载会让整机明显卡顿：老配置一次性降为「不预载」，
      // 用户仍可在「播放设置」里手动开回来。
      if (Platform.isWindows &&
          await readPrefBool('lowload_migrated_v1') != true) {
        preloadPerSide = 0;
        await save();
        await savePrefBool('lowload_migrated_v1', true);
      }
    } catch (_) {
      // 设置损坏时保留默认值，不影响启动
    }
  }

  static Future<void> save() => savePrefString(prefsKey, jsonEncode(toJson()));

  /// 绑定组合键。冲突检测按「修饰键 + 主键」整体比较：
  /// 与已有单键 `F` 冲突的是组合 `F(mods=0)`，`Ctrl+F` 不算冲突。
  /// 若目标组合已被别的动作占用则互换，保证一个组合只对应一个动作。
  /// 只有修饰键（Shift/Ctrl/Alt/Meta）不能单独成为组合，直接忽略。
  static bool bindCombo(PlayerAction action, KeyCombo combo) {
    // 准入按**传入的形状**判，归一放在准入之后。
    //
    // 顺序不能反：把 `KeyCombo(70)`（大写 F 的历史码）先归一再准入，
    // 它就变成合法的小写 `F`，于是「写进一个键盘发不出来的键码」这条
    // 陈旧配置被悄悄接受——准入层存在的意义正是拦住这种条目。
    // 归一只解决「历史落盘里已经有的条目怎么读」（`fromJson` / 匹配 / 冲突），
    // 不改变「什么可以写」。
    if (bindComboError(combo) != null) return false;
    combo = KeyCombo(normalizeKeyId(combo.keyId),
        KeyCombo.normalizeMods(combo.mods));
    final old = keyBindings[action];
    final conflict = conflictOwner(action, combo);
    if (conflict != null && old != null) keyBindings[conflict] = old;
    keyBindings[action] = combo;
    return true;
  }

  /// 该组合此刻被**哪个别的动作**占用；没被占用返回 null。
  ///
  /// 「同一组合只对应一个动作」这条规则只能有一处实现：写路径（[bindCombo]
  /// 互换旧绑定）与读路径（[applyJson] 丢弃重复项）各抄一遍那个循环之后，
  /// 总有一处忘记排除 [action] 自身，于是「重绑到当前同一个键」被判成自我
  /// 冲突——点一次没反应，点两次才生效。
  static PlayerAction? conflictOwner(PlayerAction action, KeyCombo combo) {
    // 先归一：否则落盘里的大写键码/越界掩码条目在写路径上「看不见」，
    // 两个动作会同时拿到同一个真实按键。
    final k = normalizeKeyId(combo.keyId);
    final m = KeyCombo.normalizeMods(combo.mods);
    for (final e in keyBindings.entries) {
      if (e.key == action) continue;
      if (normalizeKeyId(e.value.keyId) == k &&
          KeyCombo.normalizeMods(e.value.mods) == m) {
        return e.key;
      }
    }
    return null;
  }

  // 0.9.359：`isComboTakenByOther` 已删。它是 [conflictOwner] 的布尔包装，
  // `lib/` 内零调用，只有一条测试在断言它——而那条断言紧跟在
  // `conflictOwner(...) != null` 之后，两者永远同真同假。判定只有一处
  // 才保证「写路径互换 / 读路径丢弃重复」不会出现两个说法。

  /// 组合能否成为绑定；不能时给出用户可读的原因（单一判定口）。
  ///
  /// 保留键在**绑定层**拒绝：播放页的 onKey 里自定义绑定先于固定键位判定，
  /// 只要允许把动作绑到方向键/Esc，读取层就必然抢掉翻页与退出——
  /// 所以「保留」必须是一条准入规则，而不是读取顺序里的补丁。
  static String? bindComboError(KeyCombo combo) {
    if (!combo.isBound) return '请按下一个主键';
    // 主键必须是真实存在的键码。
    //
    // 这条不是防御性冗余：历史版本把默认键写成了大写 ASCII 码
    // （`'F' == 70`），而 Flutter 的字母键是小写码（`keyF == 102`），于是
    // 落盘里存着一批**任何键盘都发不出来**的 keyId。读取层若只判「非 0」，
    // 这些条目会一直占用绑定（既显示不出来、也永远触发不了），用户还得
    // 手动逐条重绑。所以「键码真实存在」必须是准入规则的一部分：读盘时
    // 走同一条判定，坏条目自动回落默认值。
    if (LogicalKeyboardKey.findKeyByKeyId(combo.keyId) == null) {
      return '这个键码无法识别，请重新按下按键';
    }
    if (isModifierKeyId(combo.keyId)) return '修饰键不能单独绑定，请再按一个主键';
    if (isReservedKeyId(combo.keyId)) return '方向键与 Esc 是固定键位，不能绑定';
    // 修饰键掩码必须落在已知范围内。
    //
    // 这条与上面的「键码真实存在」是同一类准入规则，不是防御性冗余。两条真实
    // 输入都带得进越界掩码：手工改过的落盘配置（`{"k":102,"m":16}`、`m:-1`），
    // 以及输入法/远程桌面把厂商自定义修饰位塞进 `HardwareKeyboard` 的中间态。
    //
    // 后果不是「多按一个键」，而是**这一项永远触发不了、界面还说已绑定**：
    // `currentMods()` 只会置低 4 位，`actionForCombo(102, 16)` 要求精确等于 16，
    // 任何真实按键都算不出 16；而 `comboLabel` 只读低 4 位，把 `m=16` 显示成
    // 裸 `F`（看起来就是普通单键）。用户按 F 没反应，页面上却写着 F。
    if (combo.mods < 0 || (combo.mods & ~KeyCombo.modAll) != 0) {
      return '修饰键组合无法识别，请重新按下按键';
    }
    return null;
  }

  /// 读取层的键码归一：落盘/历史配置里键码可能是**大写**字母码。
  ///
  /// 键位表已改成本小写码（见 `defaultKeyIds` 的注释），但旧配置里
  /// `{"k":70}` 这类大写码还在。它们不是「坏数据」，只是同一只手按下的
  /// `F`；归一后能正常触发，而不是让那一项永远哑掉、还得逐条重绑。
  /// 只处理 A–Z 这一个区间，其它键码原样返回（媒体键/厂商键没有这种大小写对）。
  /// 见 [KeyCombo.fromJson]：只归一大写字母区间。
  static int normalizeKeyId(int id) {
    const int a = 0x41, z = 0x5A, lower = 0x20;
    return (id >= a && id <= z) ? id + lower : id;
  }

  /// 固定保留键：方向键（翻页/切图）与 Esc（退出全屏/返回）。
  /// 空格可绑，因为它本来就是自定义动作（playPause）的默认键。
  static bool isReservedKeyId(int id) =>
      id == LogicalKeyboardKey.arrowUp.keyId ||
      id == LogicalKeyboardKey.arrowDown.keyId ||
      id == LogicalKeyboardKey.arrowLeft.keyId ||
      id == LogicalKeyboardKey.arrowRight.keyId ||
      id == LogicalKeyboardKey.escape.keyId;

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
  ///
  /// 只看已知的四个位：`mods = -1` 时 `-1 & modCtrl != 0` 对**每一位**都成立，
  /// 旧写法会把 `-1` 显示成 `Ctrl+Shift+Alt+Win`——一个用户既按不出来、
  /// 也不会被 [bindComboError] 放行的组合（越界掩码已准入拦截）。显示层
  /// 仍按「只读已知位」收口，避免任何绕过的调用方产出四个修饰键的假标签。
  static List<String> modsParts(int mods) {
    // 只有落在已知位域内的掩码才解码。`-1` 的每一位都是 1，按位与之后
    // 恰好等于 `modAll` —— 那会把它显示成「四个修饰键全按」，一个既按不
    // 出来、也不会被 [bindComboError] 放行的组合。越界/负数一律当作「没有
    // 已知修饰键」，标签退回裸主键，与「这项没有有效绑定」的观感一致。
    if (mods < 0 || (mods & ~KeyCombo.modAll) != 0) return <String>[];
    final m = mods;
    final parts = <String>[];
    if (m & KeyCombo.modCtrl != 0) parts.add('Ctrl');
    if (m & KeyCombo.modShift != 0) parts.add('Shift');
    if (m & KeyCombo.modAlt != 0) parts.add('Alt');
    if (m & KeyCombo.modMeta != 0) parts.add('Win');
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
    // 能绑但叫不出名字（媒体键/厂商自定义键）时给出可读键码，而不是回「未绑定」——
    // 「未绑定」会让用户以为这一项没设置，进而反复重按。
    //
    // 0.9.353：这里原来拼 `按键#$id`，`$id` 是十进制的 Flutter 内部键码
    // （如 `按键#99999999`），界面上就是一串看不懂的数字——与 owner 说的
    // 「不要出现不明所以的代号」同类。改成十六进制并带单位说明，用户至少
    // 能认出来「这是一个没名字的自定义键」，而不是一串内部 id。
    if (label.isEmpty || label == 'Unidentified') {
      return '自定义键 0x${id.toRadixString(16).toUpperCase()}';
    }
    return label.length == 1 ? label.toUpperCase() : label;
  }

  /// 返回「该主键 + 这些修饰键」精确对应的动作。
  ///
  /// 精确匹配是有意的：`Ctrl+J` 不会触发绑定在 `J` 上的动作，
  /// 避免带修饰键的系统快捷键（Ctrl+C 等）误触发播放动作。
  /// 按下「键码 + 当前修饰键」时应触发的动作；没有精确匹配返回 null。
  ///
  /// 两侧都先归一（[KeyCombo.normalizeMods] / [normalizeKeyId]）：
  /// 「按下」与「绑定」用的必须是同一把尺子，否则历史大写键码永远撞不上，
  /// 而界面上还显示得好好的。单键与组合键在这里是同一条比较——
  /// `Ctrl+J` 的 `mods` 与单键 `J` 的 `0` 天然不等，不需要额外分支。
  static PlayerAction? actionForCombo(int keyId, int mods) {
    final k = normalizeKeyId(keyId);
    final m = KeyCombo.normalizeMods(mods);
    for (final e in keyBindings.entries) {
      if (normalizeKeyId(e.value.keyId) == k &&
          KeyCombo.normalizeMods(e.value.mods) == m) {
        return e.key;
      }
    }
    return null;
  }
}
