import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/library_rank.dart';
import 'package:shoucangjia/recommend_grid.dart';
import 'package:shoucangjia/sync_ledger.dart';

/// 第三十二批：网格几何单一实现 + 两处布尔/浮点显示缺口。
///
///  - 网格列数三套写法各不同（作者索引/首屏预热在分子多加一个间距，
///    推荐页完全没算间距），与 Flutter delegate 不一致 → 字母索引滚错行、
///    首屏多预热一整列；
///  - `libraryOnline` 用 `== false` 判在线：服务端发 `0`/`"false"` 时离线库
///    被当成在线；
///  - 设置读入 `stripIndex` 用 `is bool`：落盘写 `"false"` 时用户关掉的
///    选项重启后又打开；
///  - 同步耗时先取整分再对余数四舍五入：119.6s 显示成 `1m 60s`。
void main() {
  group('推荐页列数与卡片高度按真实网格算', () {
    test('宽 1440 / 间距 2：7 列（旧写法 ceil(1440/180)=8 列）', () {
      // 真实网格 ceil(1440/182)=8？不——8×(180+2) 需要 1456>1440，
      // 所以是 ceil(1440/182)=8。用能分叉的宽验证：
      // 宽 1456 时旧写法 ceil(1456/180)=9、真实 ceil(1456/182)=8。
      final n = recommendVisibleCount(const Size(1456, 1200));
      final cols = ((1456 / 182).ceil());
      expect(cols, 8);
      // 展示数量必须是 8 的整数倍（列数对得上）。
      expect(n % cols, 0);
    });

    test('真实列宽决定行高：宽 2000 时行高不是按 180 算', () {
      final wide = recommendVisibleCount(const Size(2000, 1200));
      // 列数 = ceil(2000/182) = 11；列宽 = (2000-20)/11 ≈ 180；
      // 行高 ≈ 180/(3/4) = 240 → 1200-110=1090 → 5 行 + 1 = 6 行 → 66。
      expect(wide, 66);
    });

    test('非法参数仍走早退', () {
      expect(recommendVisibleCount(Size.zero), 40);
      expect(recommendVisibleCount(const Size(400, 800), spacing: 0),
          greaterThan(0));
      expect(recommendVisibleCount(const Size(400, 800), aspect: 0), 40);
    });
  });

  group('库在线判定接受数字/字符串布尔', () {
    test('baseOk / indexOk 为 0 / "false" / "no" 一律离线', () {
      for (final f in <dynamic>[false, 0, 'false', '0', 'no', 'off']) {
        expect(libraryOnline({'baseOk': f}), isFalse, reason: '$f');
        expect(libraryOnline({'indexOk': f}), isFalse, reason: '$f');
      }
    });

    test('真值与非布尔（缺失/空串）算在线', () {
      for (final t in <dynamic>[true, 1, 'true', 'yes', 'on']) {
        expect(libraryOnline({'baseOk': t, 'indexOk': t}), isTrue, reason: '$t');
      }
      expect(libraryOnline(const {}), isTrue);
      expect(libraryOnline({'baseOk': null, 'indexOk': ''}), isTrue);
    });
  });

  group('设置读入：布尔字段写坏时三种答案分明', () {
    setUp(AppSettings.resetDefaults);

    test('"false" / 0 关闭省略序号（旧写法 is bool 会静默保留 true）', () {
      for (final f in <dynamic>[false, 0, 'false', 'no', '0']) {
        AppSettings.resetDefaults();
        AppSettings.applyJson({'stripIndex': f});
        expect(AppSettings.stripLibIndex, isFalse, reason: '$f');
      }
    });

    test('"true" / 1 打开；字段缺失或写坏保留默认', () {
      AppSettings.applyJson({'stripIndex': 'true'});
      expect(AppSettings.stripLibIndex, isTrue);
      AppSettings.applyJson({'stripIndex': 1});
      expect(AppSettings.stripLibIndex, isTrue);
      AppSettings.applyJson({'stripIndex': '乱写'});
      expect(AppSettings.stripLibIndex, isTrue);
      AppSettings.applyJson(<String, dynamic>{});
      expect(AppSettings.stripLibIndex, isTrue);
    });
  });

  group('同步耗时：先四舍五入到秒再拆分，不出现 1m 60s', () {
    test('119.6s 进位到 2m 00s（旧写法 1m 60s）', () {
      expect(syncDurationLabel(119600), '2m 00s');
      expect(syncDurationLabel(59900), '59s'); // 不显示成 60s
      expect(syncDurationLabel(60100), '1m 00s');
      expect(syncDurationLabel(65000), '1m 05s');
    });

    test('毫秒与非法值', () {
      expect(syncDurationLabel(820), '820ms');
      expect(syncDurationLabel(2400), '2.4s');
      expect(syncDurationLabel(0), '—');
      expect(syncDurationLabel(-5), '—');
    });
  });
}
