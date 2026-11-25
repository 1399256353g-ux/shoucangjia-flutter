// 第三十八批契约：默认键码 / 刷新结果自相矛盾 / 地址空白与端口 / 评论面板 NaN。
//
// 四条都是「跑得出错误结果、界面上看不出来」的口径问题：
//   1. 默认快捷键写的是**大写** ASCII（`'F' == 70`），而 Flutter 的字母键是
//      **小写**码（`keyF == 102`）→ 静音/全屏/图文前后四个默认键从未生效。
//   2. `parseReindexResponse` 把成功拆成两个条件算：`201 + ok:true` 得到
//      `ok == false` 但 `error == ''`、`message` 却报「已刷新 · N 个作品」；
//      `runLibRefresh` 在第一步就 return，后面三件事一件没做。
//   3. `normalizeBase` 用空白分隔主机时产出一个语法合法、永远连不上的地址
//      （`host == '%20nas'`）；端口 0 / 65536 同样只是「看起来是地址」。
//   4. `commentPanelSnap` 里 `NaN.clamp(0,1) == 1.0` → 「比例未知」被当成
//      「已展开到全屏」，与 `commentPanelHeight`（非有限 → 0 = 关闭）相反。
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/library_refresh.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/player_controls.dart';

void main() {
  setUp(() => AppSettings.resetDefaults());

  group('默认键码：只认 LogicalKeyboardKey，不能写数字字面量', () {
    test('每个动作的默认键都是「按下能发出来」的真实键码', () {
      for (final action in PlayerAction.values) {
        final c = AppSettings.keyBindings[action]!;
        expect(c.isBound, isTrue, reason: '$action 必须有默认键');
        expect(LogicalKeyboardKey.findKeyByKeyId(c.keyId), isNotNull,
            reason: '$action 的默认键码 ${c.keyId} 不是任何真实按键');
        expect(AppSettings.bindComboError(c), isNull,
            reason: '$action 的默认键过不了准入');
      }
    });

    test('字母默认键必须是**小写**码（大写 ASCII 是历史缺陷）', () {
      // 实测：keyF.keyId == 102（'f'），而 'F' == 70。
      expect(LogicalKeyboardKey.keyF.keyId, 102);
      expect(AppSettings.keyBindings[PlayerAction.fullscreen]!.keyId,
          LogicalKeyboardKey.keyF.keyId);
      expect(AppSettings.keyBindings[PlayerAction.mute]!.keyId,
          LogicalKeyboardKey.keyM.keyId);
      expect(AppSettings.keyBindings[PlayerAction.forward]!.keyId,
          LogicalKeyboardKey.keyL.keyId);
      expect(AppSettings.keyBindings[PlayerAction.back]!.keyId,
          LogicalKeyboardKey.keyH.keyId);
      // 大写码 70/76/72/77 不该再出现在绑定表里。
      final ids = AppSettings.keyBindings.values.map((c) => c.keyId).toSet();
      for (final dead in <int>[70, 76, 72, 77]) {
        expect(ids.contains(dead), isFalse, reason: '大写码 $dead 出现在绑定表');
      }
    });

    test('按 F 真的能匹配到全屏动作（端到端）', () {
      expect(AppSettings.actionForCombo(LogicalKeyboardKey.keyF.keyId, 0),
          PlayerAction.fullscreen);
      expect(AppSettings.actionForCombo(LogicalKeyboardKey.keyM.keyId, 0),
          PlayerAction.mute);
      // Ctrl+F 与单键 F 互不干扰。
      expect(
          AppSettings.actionForCombo(
              LogicalKeyboardKey.keyF.keyId, KeyCombo.modCtrl),
          isNull);
    });

    test('默认键的显示文案不再是「未绑定」', () {
      for (final action in PlayerAction.values) {
        expect(AppSettings.keyLabel(action), isNot('未绑定'),
            reason: '$action 显示了「未绑定」');
      }
    });

    test('无法识别的键码被准入规则拒绝（历史配置不会永久占用绑定）', () {
      expect(AppSettings.bindComboError(const KeyCombo(70)), isNotNull);
      expect(AppSettings.bindCombo(PlayerAction.mute, const KeyCombo(70)),
          isFalse);
      // 读盘同一条规则：坏条目回落默认，不会留在表里。
      AppSettings.applyJson({
        'keys': {'mute': KeyCombo(70).toJson()},
      });
      expect(AppSettings.keyBindings[PlayerAction.mute]!.keyId,
          LogicalKeyboardKey.keyM.keyId);
    });

    test('叫不出名字的键码显示键码本身，不冒充「未绑定」', () {
      // 真实硬件上会冒出媒体键/厂商自定义键，它们的 keyLabel 可能是空。
      // 显示「未绑定」会让用户以为这一项没设置，进而反复重按。
      const odd = 99999999;
      expect(LogicalKeyboardKey.findKeyByKeyId(odd), isNull);
      expect(AppSettings.keyLabelById(odd), contains('$odd'));
      expect(AppSettings.keyLabelById(odd), isNot('未绑定'));
    });
  });

  group('快速刷新：成功判定不能自相矛盾', () {
    test('201 + ok:true 是成功，且真的会继续走后面三步', () async {
      final out = parseReindexResponse(
        201,
        {
          'libs': [
            {'lib': 'lib-1', 'ok': true, 'works': 3}
          ]
        },
        lib: 'lib-1',
      );
      expect(out.ok, isTrue);
      expect(out.reindexed, isTrue);
      expect(out.error, isEmpty);
      expect(out.message, '已刷新 · 3 个作品');
    });

    test('ok == false 时 error 必须非空（界面不能既说失败又不给原因）', () {
      for (final status in <int>[200, 201, 207, 400, 500]) {
        final out = parseReindexResponse(
          status,
          {
            'libs': [
              {'lib': 'lib-1', 'ok': false}
            ]
          },
          lib: 'lib-1',
        );
        expect(out.ok, isFalse, reason: 'status=$status');
        expect(out.error, isNotEmpty, reason: 'status=$status 没有失败原因');
        expect(out.message.startsWith('刷新失败：'), isTrue,
            reason: 'status=$status 的提示不是失败');
      }
    });

    test('非 2xx 即使行里写了 ok:true 也不算成功', () {
      final out = parseReindexResponse(
        500,
        {
          'libs': [
            {'lib': 'lib-1', 'ok': true, 'works': 9}
          ]
        },
        lib: 'lib-1',
      );
      expect(out.ok, isFalse);
      expect(out.works, isNull);
      expect(out.error, '服务端写入失败');
    });

    test('编排层：失败时不再执行重拉/清缓存/广播', () async {
      final calls = <String>[];
      final out = await runLibRefresh(
        lib: 'lib-1',
        reindex: (_) async =>
            (status: 201, body: <String, dynamic>{'oops': true}),
        reloadLibraries: () async => calls.add('reload'),
        clearLibCovers: () async => calls.add('clear'),
        onBumpRevision: () => calls.add('bump'),
      );
      expect(out.ok, isFalse);
      expect(calls, isEmpty, reason: '第一步失败后不该继续');
    });

    test('编排层：2xx 成功时才继续，且顺序固定', () async {
      final calls = <String>[];
      final out = await runLibRefresh(
        lib: 'lib-1',
        reindex: (_) async => (status: 201, body: <String, dynamic>{
          'libs': [
            {'lib': 'lib-1', 'ok': true, 'works': 2}
          ]
        }),
        reloadLibraries: () async => calls.add('reload'),
        clearLibCovers: () async => calls.add('clear'),
        onBumpRevision: () => calls.add('bump'),
      );
      expect(out.ok, isTrue);
      expect(calls, <String>['reload', 'clear', 'bump']);
    });
  });

  group('normalizeBase：不产出「看起来是地址、其实连不上」的串', () {
    test('主机段里的空白被去掉（手输/复制的多余空格）', () {
      // 旧实现：`Uri.tryParse('http:// nas:8090')` 不报错，host 变成 '%20nas'。
      expect(normalizeBase('http:// nas:8090'), 'http://nas:8090');
      expect(normalizeBase('http://nas :8090'), 'http://nas:8090');
      expect(normalizeBase('http:// nas '), 'http://nas');
      expect(normalizeBase('http://\tnas'), 'http://nas');
    });

    test('去掉空白后主机为空则不猜', () {
      expect(normalizeBase('http://  '), '');
      expect(normalizeBase('http:// /'), '');
    });

    test('端口越界（0 / >65535）判为无效地址', () {
      expect(normalizeBase('http://nas:0'), '');
      expect(normalizeBase('http://nas:65536'), '');
      expect(normalizeBase('http://nas:-1'), '');
      // 边界内照常。
      expect(normalizeBase('http://nas:1'), 'http://nas:1');
      expect(normalizeBase('http://nas:65535'), 'http://nas:65535');
    });

    test('路径里的空白不受影响（只清洗主机段）', () {
      expect(normalizeBase('http://nas:8090/a b'), 'http://nas:8090/a b');
      expect(normalizeBase('http://nas:8090/a/b/'), 'http://nas:8090/a/b');
    });

    test('归一结果必须真能解析出主机', () {
      for (final raw in <String>[
        'http:// nas:8090',
        'HTTP://NAS:8090',
        '192.168.2.4:8090',
        '  https://nas:8443/ ',
      ]) {
        final b = normalizeBase(raw);
        expect(b, isNotEmpty, reason: raw);
        expect(Uri.parse(b).host, isNotEmpty, reason: raw);
      }
    });
  });

  group('评论面板 snap：非有限比例不能当成「已展开」', () {
    test('NaN / Infinity 比例按关闭处理（与 commentPanelHeight 同口径）', () {
      expect(commentPanelSnap(fraction: double.nan, velocity: 0),
          kCommentPanelClosedFraction);
      expect(commentPanelSnap(fraction: double.infinity, velocity: 0),
          kCommentPanelClosedFraction);
      expect(commentPanelSnap(fraction: double.negativeInfinity, velocity: 0),
          kCommentPanelClosedFraction);
    });

    test('非有限速度不参与方向判定', () {
      // NaN 速度：两种 `>= / <=` 判定都是 false，只能按比例走。
      expect(commentPanelSnap(fraction: 0.6, velocity: double.nan),
          kCommentPanelInitialFraction);
      // 比例未知 + 速度未知 → 关闭，不会吸到全屏。
      expect(commentPanelSnap(fraction: double.nan, velocity: double.nan),
          kCommentPanelClosedFraction);
    });

    test('非有限初值回落默认档，不把 NaN 传进动画', () {
      final t = commentPanelSnap(
          fraction: 0.0, velocity: 0, initial: double.nan);
      expect(t.isFinite, isTrue);
      expect(t, kCommentPanelClosedFraction);
    });

    test('正常档位语义不变', () {
      expect(commentPanelSnap(fraction: 0.0, velocity: 0),
          kCommentPanelClosedFraction);
      expect(commentPanelSnap(fraction: 0.45, velocity: 0),
          kCommentPanelInitialFraction);
      expect(commentPanelSnap(fraction: 0.92, velocity: 0),
          kCommentPanelFullFraction);
      expect(commentPanelSnap(fraction: 0.6, velocity: -900),
          kCommentPanelFullFraction);
      expect(commentPanelSnap(fraction: 0.4, velocity: 900),
          kCommentPanelClosedFraction);
    });
  });

  group('契约扫描：旧写法不得复活', () {
    final lib = Directory('lib')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => (f.path.split(RegExp(r'[\\/]')).last, f.readAsStringSync()));

    test('app_settings 里不再有裸数字默认键码', () {
      final src = lib.firstWhere((e) => e.$1 == 'app_settings.dart').$2;
      expect(RegExp(r'PlayerAction\.\w+:\s*\d+\s*,').hasMatch(src), isFalse,
          reason: '默认键位又写成数字字面量了');
    });

    test('library_refresh 不再把成功拆成两个条件', () {
      final src = lib.firstWhere((e) => e.$1 == 'library_refresh.dart').$2;
      expect(src.contains('reindexed: okRow && status == 200'), isFalse);
      expect(src.contains('final success = okRow'), isTrue);
    });

    test('commentPanelSnap 里比例必须走唯一归一（含非有限处理）', () {
      final src = lib.firstWhere((e) => e.$1 == 'player_controls.dart').$2;
      final start = src.indexOf('double commentPanelSnap(');
      // 注意：函数签名多行，`}) {` 本身以 `\n}` 开头——不能拿 `'\n}'` 找结尾，
      // 否则切出来只有参数列表。这里按固定窗口取整段实现。
      final body = src.substring(start, start + 1600);
      // 2026-11-26：比例归一下沉到 `unit_fraction.dart` 的唯一实现
      // （`unitFraction` 内部处理 NaN/±Infinity）。这条契约改为盯「有没有走
      // 那个唯一出口」，而不是逼调用点各写一遍 isFinite——否则每统一一处
      // 都要来改这条断言，等于把「第二份实现」制度化。
      expect(body.contains('unitFraction(fraction'), isTrue,
          reason: '比例必须过唯一归一（非有限值的口径只能有一处）');
      // 速度不是 0–1 比例，不进 unitFraction，必须自己挡非有限。
      expect(body.contains('velocity.isFinite'), isTrue,
          reason: '速度非有限会让方向判定恒真/恒假');
    });

    test('normalizeBase 校验主机段空白与端口范围', () {
      final src = lib.firstWhere((e) => e.$1 == 'multi_server.dart').$2;
      final start = src.indexOf('String normalizeBase(');
      final body = src.substring(start, start + 2400);
      expect(body.contains(r'\s+'), isTrue, reason: '缺主机段空白清洗');
      expect(body.contains("uri.port < 1"), isTrue, reason: '缺端口越界校验');
      expect(body.contains('65535'), isTrue);
    });
  });
}
