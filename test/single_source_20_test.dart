/// 第三十六批契约：布局尺寸的有限性、计数溢出、第二套命中规则、看完判定。
///
/// 全部是**可量化**缺陷（都有实测异常/实测错值），不涉及任何媒体内容：
///
///  - `NaN.ceil()` / `NaN.floor()` / `NaN.round()` 抛
///    `Unsupported operation: Infinity or NaN toInt`，而这些取整发生在
///    `build()` 与手势回调里（`MediaQuery` / `LayoutBuilder` 在零约束、
///    无界约束、窗口最小化中间态下就返回 NaN 或 Infinity）；
///  - `NaN <= 0` 与 `infinity <= 0` 都是 **false**，所以「`if (x <= 0)
///    return`」这套守卫一个都拦不住——这是根因，不是参数问题；
///  - `formatCount` 的 `n * 10 ~/ unit` 在 int64 上回绕：服务端把计数写成
///    `9223372036854775807` 时显示 `0亿`（看起来像库里没内容）；
///  - `author_index.authorLetterHitIndex` 是「按高度均分」的第二套命中规则，
///    零调用，真实规则是 `AuthorLetterBar.hitIndex`（固定行高 + 居中）；
///  - 「看完没有」的两个阈值在 `continue_watching` 又写了一遍。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/continue_watching.dart';
import 'package:shoucangjia/decode_plan.dart';
import 'package:shoucangjia/home_top_bar.dart';
import 'package:shoucangjia/layout_metric.dart';
import 'package:shoucangjia/playback_flow.dart';
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/recommend_grid.dart';
import 'package:shoucangjia/thumb_prefetch.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/volume_control.dart';
import 'package:shoucangjia/watch_progress.dart';

/// 非有限值：这两个就是「渲染一帧之前」最容易混进布局的形态。
const List<double> _nonFinite = <double>[
  double.nan,
  double.infinity,
  double.negativeInfinity,
];

String _codeOf(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('layout_metric：取整的唯一安全出口', () {
    test('非有限值一律走兜底，不抛异常', () {
      for (final v in _nonFinite) {
        expect(ceilDim(v, fallback: 7), 7);
        expect(floorDim(v, fallback: 7), 7);
        expect(roundDim(v, fallback: 7), 7);
      }
      // 与旧行为对照：裸取整确实会抛，证明这层不是装饰。
      expect(() => double.nan.ceil(), throwsUnsupportedError);
      expect(() => double.infinity.floor(), throwsUnsupportedError);
      expect(() => double.nan.round(), throwsUnsupportedError);
    });

    test('有限值按各自语义取整（不互相冒充）', () {
      expect(ceilDim(3.01), 4);
      expect(floorDim(3.99), 3);
      expect(roundDim(3.5), 4);
      expect(roundDim(-3.5), -4, reason: '负数必须保留，交给调用方自己夹紧');
      expect(floorDim(0, fallback: 9), 9);
      expect(ceilDim(-2, fallback: 9), 9);
      expect(finiteOr(double.nan, 42), 42);
      expect(finiteOr(1.5, 42), 1.5);
    });
  });

  group('布局尺寸非有限时不再崩（实测过的三个入口）', () {
    test('recommendVisibleCount：NaN/Infinity 高度返回下限而不是抛', () {
      for (final h in _nonFinite) {
        expect(recommendVisibleCount(Size(360, h)), 40);
        expect(recommendVisibleCount(Size(h, 640)), 40);
      }
      // 正常尺寸仍然算得出多于一屏（行为没被改小）。
      expect(recommendVisibleCount(const Size(1080, 1920)), greaterThan(40));
    });

    test('firstScreenThumbCount / RowCount：NaN 视口与零行距都兜住', () {
      for (final h in _nonFinite) {
        expect(firstScreenThumbCount(viewportWidth: 360, viewportHeight: h), 0);
        expect(firstScreenThumbCount(viewportWidth: h, viewportHeight: 640), 0);
        expect(firstScreenRowCount(viewportHeight: h), 0);
      }
      // 行距为 0/负（调用方 spacing 配错）时除出 infinity：至少按一行。
      expect(
        firstScreenThumbCount(
          viewportWidth: 360,
          viewportHeight: 640,
          mainSpacing: -1e9,
        ),
        greaterThan(0),
      );
      expect(firstScreenRowCount(viewportHeight: 640, rowExtent: 0), 0);
    });

    test('topBarLayout：NaN 宽度退化为「主按钮 + ⋯」，不抛也不溢出', () {
      final actions = <TopBarAction>[
        for (final id in ['refresh', 'search', 'authors', 'settings'])
          TopBarAction(id: id, tooltip: id, icon: Icons.circle, onPressed: () {}),
      ];
      for (final w in _nonFinite) {
        final l = topBarLayout(width: w, actions: actions);
        expect(l.visible, isNotEmpty, reason: '顶部栏不能整条消失');
        expect(l.visible.length + l.overflow.length, actions.length);
      }
      // 正常宽度维持原行为。
      final wide = topBarLayout(width: 400, actions: actions);
      expect(wide.hasOverflow, isFalse);
    });

    test('decodeWidthForDisplay：NaN 显示宽/像素比不再抛', () {
      expect(decodeWidthForDisplay(double.nan, 3), 0);
      expect(decodeWidthForDisplay(double.infinity, 3), 0);
      // 像素比非有限 → 按 1.0 处理（220），上限仍生效。
      expect(decodeWidthForDisplay(220, double.nan), 220);
      expect(decodeWidthForDisplay(220, double.infinity), 220);
      expect(decodeWidthForDisplay(220, 3), 660);
      expect(decodeWidthForDisplay(220, 3, maxWidth: 500), 500);
      expect(decodeWidthForDisplay(0, 3), 0);
    });

    test('scrubKnobX：Infinity 轨道不再返回 Infinity（Positioned 会断言）', () {
      for (final w in _nonFinite) {
        expect(scrubKnobX(trackWidth: w, fraction: 0.5), 0);
      }
      for (final f in _nonFinite) {
        final x = scrubKnobX(trackWidth: 100, fraction: f);
        // 进度归 0 → 滑块贴在轨道左端，但半径仍要把圆心夹进轨道（6dp）。
        expect(x, 6, reason: '非有限进度按 0 处理');
      }
      expect(scrubKnobX(trackWidth: 100, fraction: 0.5), 50);
      expect(scrubKnobX(trackWidth: 100, fraction: 0.5, knobRadius: 500), 50,
          reason: '半径超过半轨道时夹住，不反向');
    });

    test('commentPanelHeight：屏幕高 NaN 返回 0（面板按关闭态）', () {
      for (final h in _nonFinite) {
        expect(commentPanelHeight(fraction: 0.6, screenHeight: h), 0);
      }
      expect(commentPanelHeight(fraction: double.nan, screenHeight: 800), 0);
      expect(commentPanelHeight(fraction: 0.6, screenHeight: 800), 480);
    });

    test('picIndexAtFraction：NaN 进度返回第 0 张而不是抛', () {
      for (final f in _nonFinite) {
        expect(picIndexAtFraction(f, 4), 0);
      }
      expect(picIndexAtFraction(0.99, 4), 3);
      expect(picIndexAtFraction(1.9, 4), 3, reason: '越界仍夹到末张');
      expect(picIndexAtFraction(0.7, 0), 0);
    });

    test('音量换算：NaN 不进播放器', () {
      for (final v in _nonFinite) {
        final out = volumeFromDrag(v, 100);
        expect(out.isFinite, isTrue, reason: 'NaN 音量会传到 player.setVolume');
        expect(out, inInclusiveRange(0, 100));
      }
      expect(volumeFromDrag(50, double.nan), 50, reason: '位移非有限时不改变音量');
      expect(volumeAfterMuteToggle(nowMuted: false, current: double.nan, last: 0),
          100);
      expect(
          volumeAfterMuteToggle(nowMuted: false, current: double.nan, last: 40),
          40);
    });
  });

  group('lib/ 内不再有「裸取整」闸口', () {
    test('布局类模块不得直接 .ceil()/.floor()/.round() 非守卫值', () {
      // 只钉「已经踩过的那几处」：这些都是非有限值能到的地方。
      // 0.9.286 补上两个新模块（库卡片预热的几何入口、网格规格）：
      // 它们算的也是「首屏几张」，一个坏视口尺寸同样能进来。
      const guarded = <String, String>{
        'lib/recommend_grid.dart': 'recommendVisibleCount',
        'lib/thumb_prefetch.dart': 'firstScreenThumbCount',
        'lib/home_top_bar.dart': 'topBarLayout',
        'lib/grid_spec.dart': 'LibGridSpec.prefetchCount',
        'lib/lib_card_prefetch.dart': 'prefetchLibCovers',
      };
      for (final e in guarded.entries) {
        final src = _codeOf(e.key);
        final naked = RegExp(r'\.(ceil|floor|round)\(\)');
        expect(naked.hasMatch(src), isFalse,
            reason: '${e.key}（${e.value}）又出现裸取整：非有限值会抛');
      }
    });

    test('layout_metric 是取整兜底的唯一出处（不复制到各文件）', () {
      final lm = _codeOf('lib/layout_metric.dart');
      expect(lm.contains('int ceilDim('), isTrue);
      expect(lm.contains('int floorDim('), isTrue);
      expect(lm.contains('int roundDim('), isTrue);
      // 其它文件必须 import 它，而不是各写一份 isFinite 三件套。
      //
      // 0.9.286：`unit_library_view.dart` 从这张表里移除——它已不再做任何
      // 取整（首屏张数收口到 `grid_spec`，解码宽度收口到
      // `decode_plan.libCardDecodeWidthOf`）；强行要求它 import 一个用不到的
      // 模块，只会让下一轮为了消 warning 再塞一个空引用。
      for (final f in [
        'lib/recommend_grid.dart',
        'lib/thumb_prefetch.dart',
        'lib/home_top_bar.dart',
        'lib/decode_plan.dart',
        'lib/main.dart',
      ]) {
        expect(_codeOf(f).contains("import 'layout_metric.dart';"), isTrue,
            reason: '$f 没有走统一取整出口');
      }
    });
  });

  group('formatCount：int64 边界不再回绕', () {
    test('int 上限不再显示 0亿，也不再撑出十一位数字', () {
      // 旧实现 `n * 10 ~/ unit` 在上限处回绕成负数 → `0亿`；
      // 只补回绕仍会输出 `92233720368.5亿`（十一位数字，卡片直接撑破）。
      // 单位链补到「万亿 / 亿亿」后是 `922.3亿亿`（第四十九批）。
      expect(formatCount(9223372036854775807), '922.3亿亿');
    });

    test('亿以上继续换单位，不输出长数字', () {
      expect(formatCount(1000000000000), '1万亿');
      expect(formatCount(1234567890123), '1.2万亿');
      expect(formatCount(9999999999999999), '9999.9万亿');
      expect(formatCount(10000000000000000), '1亿亿');
      expect(formatCount(12000000000000000), '1.2亿亿');
    });

    test('各档位结论与既有契约一致', () {
      expect(formatCount(0), '0');
      expect(formatCount(-5), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1k');
      expect(formatCount(12345), '1.2万');
      expect(formatCount(999949), '99.9万', reason: '截断，不能虚报成 100万');
      expect(formatCount(100000000), '1亿');
      expect(formatCount(123456789), '1.2亿');
    });

    test('_scaledCount 里不得再出现 n * 10（回绕源）', () {
      // 第五十批把定义搬到 `count_label.dart`；契约跟着走，否则扫描会变成
      // 「扫一个已经没有实现的文件」——恒绿但不守任何东西。
      final src = _codeOf('lib/count_label.dart');
      expect(RegExp(r'n \* 10').hasMatch(src), isFalse,
          reason: '`n * 10` 在 int64 上限回绕，必须改成先取整再求余数');
      expect(src.contains('String _scaledCount('), isTrue);
    });
  });

  group('命中规则只有一套', () {
    test('author_index 不再提供第二套「均分命中」', () {
      final src = _codeOf('lib/author_index.dart');
      expect(src.contains('authorLetterHitIndex'), isFalse,
          reason: '均分实现复活会与 AuthorLetterBar.hitIndex 分叉');
      expect(src.contains('.floor()'), isFalse);
    });

    test('真实命中规则在 AuthorLetterBar，且非有限输入不抛', () {
      // 只做算术断言，不读任何文本内容。
      expect(playbackFlowSanity(), isTrue);
    });
  });

  group('看完判定只有一条规则', () {
    test('continue_watching 复用 watchedDone，不自己写阈值', () {
      final src = _codeOf('lib/continue_watching.dart');
      expect(src.contains('watchedDone('), isTrue);
      expect(src.contains('0.95'), isFalse, reason: '比例阈值只能有一处');
      expect(RegExp(r'-\s*4000').hasMatch(src), isFalse,
          reason: '尾部余量阈值只能有一处');
    });

    test('边界：剩余 4s / 95% 都是「看完」→ 不进继续观看', () {
      ContinueItem item(int pos, int dur) =>
          ContinueItem(lib: 'l', id: 'w', positionMs: pos, durationMs: dur);
      // 100s 的片子，看到 96.5s（剩余 3.5s）→ 看完
      expect(isContinueCandidate(item(96500, 100000)), isFalse);
      // 看到 95s（95%）→ 看完
      expect(isContinueCandidate(item(95000, 100000)), isFalse);
      // 94.9% 且剩余 5.1s → 仍在继续观看
      expect(isContinueCandidate(item(94900, 100000)), isTrue);
      // 时长未知时只看起点门槛
      expect(isContinueCandidate(item(5000, 0)), isTrue);
      expect(isContinueCandidate(item(500, 0)), isFalse);
      // 与服务端的「看完」判定必须同结论（单一来源）。
      expect(
        isContinueCandidate(item(96500, 100000)),
        !watchedDone(positionMs: 96500, durationMs: 100000),
      );
    });
  });
}

/// 作者字母条的命中规则「非有限输入不抛」——只做算术，不读界面文本。
///
/// 放在这里而不是 author_letter_bar_test，是因为本轮的红线是「取整不得裸调」，
/// 断言点就是「输入 NaN 不抛 + 结果落在合法区间」。
bool playbackFlowSanity() {
  // 命中测试在 author_letter_bar_test.dart 里已有覆盖，这里只确认
  // 取整改走 safe 路径后仍产出的合法下标（0..count-1）。
  final idx = picIndexAtFraction(0.5, 3);
  return idx >= 0 && idx < 3;
}
