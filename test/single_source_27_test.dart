import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/continue_watching.dart';
import 'package:shoucangjia/time_labels.dart';
import 'package:shoucangjia/unit_author_groups.dart';
import 'package:shoucangjia/work_forms.dart';

// 第四十三批（0.9.257）契约：四条「不改就静默出错」的读数。
//
// 判据全部是纯函数输出，不涉及任何媒体内容、文件名或界面截图。

const int _maxInt = 9223372036854775807;
const int _minInt = -9223372036854775808;

ContinueItem _item({
  String id = 'i',
  int pos = 30000,
  int dur = 60000,
  String collection = '',
}) =>
    ContinueItem(
      lib: 'l',
      id: id,
      positionMs: pos,
      durationMs: dur,
      collection: collection,
      updatedAt: 1,
    );

void main() {
  group('播放时长文案：不可信的 du 不再打印二十几位数字', () {
    test('int 上限不再显示 `2562047788015215:30:07`', () {
      final s = formatClockSeconds(_maxInt);
      expect(s, kUnknownClock);
      expect(s.contains(':'), isTrue, reason: '仍然是「时间」的形状，不是空白');
      expect(s.length, lessThan(8), reason: '实际：$s');
    });

    test('1e15 秒不再是十七位小时的读数', () {
      expect(formatClockSeconds(1000000000000000), kUnknownClock);
    });

    test('毫秒版同样收口（进度行两个数同一个出口）', () {
      expect(formatClockMs(_maxInt), kUnknownClock);
      expect(formatClockMs(1000000000000000), kUnknownClock);
    });

    test('Duration 版跟随毫秒版（超出上限即占位）', () {
      // 注意：`Duration(milliseconds: int 上限)` 在**构造时**就溢出了
      // （内部以微秒存储），那条路径与时长文案无关；这里用合法可构造的
      // 超长 Duration 验证同一个出口。
      expect(formatClock(const Duration(hours: 101)), kUnknownClock);
      expect(formatClock(const Duration(hours: 100)), '100:00:00');
    });

    test('100 小时仍在可信区间内，按既有进位写法显示', () {
      expect(formatClockSeconds(kMaxClockSeconds), '100:00:00');
      expect(formatClockSeconds(65 * 60), '1:05:00');
      expect(formatClockSeconds(59), '00:59');
      expect(formatClockSeconds(0), '00:00');
    });

    test('上限只多 1 秒就换占位（边界不重叠、不四舍五入跨档）', () {
      expect(formatClockSeconds(kMaxClockSeconds + 1), kUnknownClock);
    });

    test('负数仍按 0 处理（未起播不是「不可信时长」）', () {
      expect(formatClockSeconds(-1), '00:00');
      expect(formatClockMs(-5000), '00:00');
    });
  });

  group('章节名：越界索引不再渲染成「第 -4 集」', () {
    test('负数索引按第 1 集', () {
      expect(chapterLabel(const {}, -1), '第 1 集');
      expect(chapterLabel(const {}, -5), '第 1 集');
      expect(chapterLabel(const {}, 0), '第 1 集');
    });

    test('有标题时标题优先（越界与否都不编序号）', () {
      expect(chapterLabel({'ti': '开场'}, -3), '开场');
    });

    test('正常序号的写法一个字都没变', () {
      expect(chapterLabel(const {}, 1), '第 2 集');
      expect(chapterLabel(const {}, 11), '第 12 集');
    });
  });

  group('继续观看写盘节流：差值溢出不再把真实跳转当成「没动」', () {
    test('跨越整个 int 区间的位次变化必须写盘（旧写法 abs 后是 1）', () {
      expect(
        shouldSkipContinueRecord(
            _item(pos: _maxInt), _item(pos: _minInt)),
        isFalse,
      );
    });

    test('同一作品小位移仍节流（既有行为不变）', () {
      final prev = _item(pos: 30000);
      expect(shouldSkipContinueRecord(prev, _item(pos: 30500)), isTrue);
      expect(
        shouldSkipContinueRecord(prev, _item(pos: 30000 + kContinueThrottleMs)),
        isFalse,
      );
    });

    test('换收藏夹/换作品一律立即记录', () {
      final prev = _item(pos: 30000);
      expect(
        shouldSkipContinueRecord(prev, _item(pos: 30200, collection: '别的')),
        isFalse,
      );
      expect(shouldSkipContinueRecord(prev, _item(id: '2', pos: 30200)), isFalse);
    });

    test('禁止回到「先相减再 abs」的写法（回绕方向不可预测）', () {
      // 这条是给 review 的护栏：差值必须在 double 里算。
      expect(
        shouldSkipContinueRecord(_item(pos: _maxInt), _item(pos: 0)),
        isFalse,
        reason: 'int 相减后再 abs 会把 max-0 也当成小数',
      );
    });
  });

  group('作者挂载项：坏 works 不再抛异常', () {
    test('1e999（JSON 解析成 infinity）以前抛 Unsupported operation', () {
      final it = AuthorMountItem.fromJson(
          {'lib': 'l', 'authorDir': '@a', 'works': 1e999});
      expect(it, isNotNull);
      expect(it!.works, 0);
    });

    test('数字字符串按数值读（与其它计数同一个解析器）', () {
      expect(
        AuthorMountItem.fromJson(
                {'lib': 'l', 'authorDir': '@a', 'works': '12'})!
            .works,
        12,
      );
    });

    test('缺字段/非数值一律 0，{lib, authorDir} 仍必须两段非空', () {
      expect(
        AuthorMountItem.fromJson({'lib': 'l', 'authorDir': '@a'})!.works,
        0,
      );
      expect(
        AuthorMountItem.fromJson({'lib': 'l', 'authorDir': '@a', 'works': 'x'})!
            .works,
        0,
      );
      expect(AuthorMountItem.fromJson({'lib': '', 'authorDir': '@a'}), isNull);
    });

    test('实现唯一性：挂载项不再自己写 `as num).toInt()`', () {
      // 同一个解析规则在本文件里出现了两次就会再分叉一次，所以钉住。
      expect(
          AuthorMountItem.fromJson(
                  {'lib': 'l', 'authorDir': '@a', 'works': 2.9})!
              .works,
          2,
          reason: '截断口径（json_num.intOf）而不是四舍五入');
    });
  });
}
