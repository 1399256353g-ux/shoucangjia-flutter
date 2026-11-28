/// 播放设置的持久化（owner 2026-11-24）。
///
/// 需求原文：「添加设置记忆功能，重进播放界面记住沿用上次的播放设置」。
///
/// 之前 `LoopLink` / `shuffle` 只存在播放页内存里，退出播放页就回到默认值
/// （连播开、循环关、乱序关）。这里把这些状态落到 SharedPreferences，
/// 进播放页时先读回。倍速不在这里——它一直归 `AppSettings.defaultSpeed`
/// （见下方 0.9.356 说明）。
///
/// 设计要点：
/// - 纯数据 + 纯函数，便于单测；落盘走 `prefs_json` 的唯一入口；
/// - 坏数据一律回落默认值，不抛异常、不阻塞进页面；
/// - 旧 payload 里的 `speed` 字段读入时忽略（倍速已归 AppSettings）。
library;

import 'dart:convert';

import 'loop_link.dart';
import 'prefs_json.dart';

/// 播放设置的完整快照。
///
/// 0.9.356：**倍速不在这里**。
///
/// 此前倍速有两份存储：设置页写 `AppSettings.defaultSpeed`（`app_settings_v1`），
/// 播放页却用 `playback_prefs_v1` 的 `speed` 覆盖——首进播放页时那个值恒为
/// 默认 1.0，于是「设置页选的倍速一次都不生效」，而设置页副标题还写着
/// 「进入播放器时自动应用」。同一个用户可调的量只允许一个落盘处：
/// 倍速归 `AppSettings.defaultSpeed`，本类只记连播/循环/乱序。
class PlaybackPrefs {
  /// 循环/连播联动状态（含「打开循环前的连播」记忆值）。
  final LoopLink link;

  /// 是否乱序播放。
  final bool shuffle;

  const PlaybackPrefs({
    this.link = const LoopLink(),
    this.shuffle = false,
  });

  static const PlaybackPrefs defaults = PlaybackPrefs();

  Map<String, dynamic> toJson() => {
        // 版本只写在**键名**（`playback_prefs_v1`）里。此前这里还多写一份
        // `'v': 1`，但 `fromJson` 从不读它——两份版本号，改结构时改一处
        // 就漂移。键名已经承担了迁移职责，payload 里不再重复。
        'loopOne': link.loopOne,
        'autoplay': link.autoplay,
        'restoreAutoplay': link.restoreAutoplay,
        'shuffle': shuffle,
      };

  /// 容错解析：任何字段坏了只影响它自己，其余照常恢复。
  static PlaybackPrefs fromJson(dynamic raw) {
    if (raw is! Map) return defaults;
    // 旧版本在本文件里也存过 `speed`：这里**不读**它（倍速已归
    // `AppSettings.defaultSpeed`），但坏/旧字段一律忽略而不是抛异常，
    // 升级后的第一进页面不会因为旧 payload 失败而丢掉连播/乱序。
    // 本地 prefs 与「服务端字段」是两件事：prefs 是本机自己写的（永远是
    // bool），严格只认 bool 才是对的；`"yes"` 这种服务端形态不进 prefs。
    // 服务端字段的兼容规则不走这里。
    final loopOne = _boolPref(raw['loopOne'], false);
    final autoplay = _boolPref(raw['autoplay'], true);
    final restore = _boolPref(raw['restoreAutoplay'], autoplay);
    return PlaybackPrefs(
      link: LoopLink(
        loopOne: loopOne,
        autoplay: autoplay,
        restoreAutoplay: restore,
      ),
      shuffle: _boolPref(raw['shuffle'], false),
    );
  }

  /// 本机 prefs 只认 bool：类型不对就用默认值（不把服务端兼容规则带进来）。
  static bool _boolPref(dynamic v, bool d) => v is bool ? v : d;

  @override
  bool operator ==(Object other) =>
      other is PlaybackPrefs && other.link == link && other.shuffle == shuffle;

  @override
  int get hashCode => Object.hash(link, shuffle);
}

/// 落盘键（版本化，日后改结构可换键名平滑迁移）。
const String kPlaybackPrefsKey = 'playback_prefs_v1';

/// 读回上次的播放设置；无记录或坏数据返回 [PlaybackPrefs.defaults]。
Future<PlaybackPrefs> loadPlaybackPrefs() async {
  // 读盘判定只有 `readPrefJson` 一处；`fromJson` 不吃 null/非对象（回落默认）。
  return PlaybackPrefs.fromJson(await readPrefJson(kPlaybackPrefsKey));
}

/// 保存播放设置；写失败不影响播放（下次进页面回落默认值）。
Future<void> savePlaybackPrefs(PlaybackPrefs p) async {
  try {
    await savePrefString(kPlaybackPrefsKey, jsonEncode(p.toJson()));
  } catch (_) {
    // 编码失败也不阻塞播放。
  }
}

/// 播放器支持的倍速区间（**唯一一份**）。
///
/// 0.9.361：`0.5` / `3.0` 这对边界此前写了三遍：`speedLabel`（显示层夹紧）、
/// 播放页 `setSpeed`（写入层夹紧）、`AppSettings.applyJson`（读盘夹紧）。
/// 三处各自硬编码数字，改一处就漂——读盘那处漏改时，坏配置会被显示层
/// 默默夹到另一个区间，用户看到的值与存下的值不一样。
const double kSpeedMin = 0.5;
const double kSpeedMax = 3.0;

/// 倍速夹到 [kSpeedMin]..[kSpeedMax]。
///
/// 无法代表倍速的输入一律回到默认 1.0（不是夹到上限）：`NaN`、无穷、
/// 非正数。这些值只可能来自坏配置或未初始化状态，夹到 3.0 会把
/// 「这里的数据坏了」显示成一个像样的倍速。与 `speedLabel` 同一条判定，
/// 所以界面文案与存盘值不会给出两个答案。
double clampSpeed(double value) {
  if (!value.isFinite || value <= 0) return 1.0;
  return value.clamp(kSpeedMin, kSpeedMax).toDouble();
}

/// 界面上可选倍速的唯一清单（设置页「默认播放倍速」与播放页倍速菜单共用）。
///
/// 此前两份字面量都是 `[0.75, 1.0, 1.25, 1.5, 2.0]`，改一处就会出现
/// 「设置页能选 2.5、播放页没有」这类两个入口给两套选项的问题。
const List<double> kPlaybackSpeeds = <double>[0.75, 1.0, 1.25, 1.5, 2.0];
