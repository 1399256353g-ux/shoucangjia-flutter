import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_grade.dart';

/// P6：作者等级**配色也是服务端配置**。
///
/// 0.9.191 之前只有权重与门槛走 `/api/author-grade.json`，配色仍是客户端
/// 写死的 `const colors`。后果：owner 在服务端调等级观感时，权重生效、
/// 颜色不生效，同一份配置在两种来源之间分裂——这就是「一轮改一半」的典型。
///
/// 现在配色与权重同源：服务端下发 `c`（5 个 ARGB 整数），客户端只读；
/// 缺省或非法时整组回落默认色，绝不逐项修补。
void main() {
  setUp(() {
    AuthorGrade.reset();
    AuthorGrade.remoteManaged = false;
    AuthorGrade.remoteAt = 0;
  });

  test('默认配色与等级数量一致，且为可变表（不是 const 字面量）', () {
    expect(AuthorGrade.colors.length, AuthorGrade.grades.length);
    expect(AuthorGrade.colors, AuthorGrade.defaultColors);
    // 可变：服务端下发后能整组替换，这正是 0.9.191 之前的缺陷所在。
    AuthorGrade.colors = const <int>[1, 2, 3, 4, 5];
    expect(AuthorGrade.colors, <int>[1, 2, 3, 4, 5]);
  });

  test('服务端下发 c → 生效；colorForGrade 跟着变', () {
    final custom = <int>[
      0xFFFF0000,
      0xFF00FF00,
      0xFF0000FF,
      0xFFFFFF00,
      0xFF000000,
    ];
    final ok = AuthorGrade.applyRemote(<String, dynamic>{
      'ok': true,
      'grade': <String, dynamic>{
        'play': 1,
        'drop': 10,
        'work': 2,
        't': <int>[100, 500, 2000, 8000],
        'c': custom,
      },
    });
    expect(ok, isTrue);
    expect(AuthorGrade.colors, custom);
    expect(AuthorGrade.colorForGrade('D'), 0xFFFF0000);
    expect(AuthorGrade.colorForGrade('S'), 0xFF000000);
    expect(AuthorGrade.remoteManaged, isTrue);
  });

  test('服务端没下发 c（旧版服务端）→ 保留默认色，不算失败', () {
    final ok = AuthorGrade.applyRemote(<String, dynamic>{
      'grade': <String, dynamic>{
        'play': 3,
        'drop': 20,
        'work': 1,
        't': <int>[10, 20, 30, 40],
      },
    });
    expect(ok, isTrue, reason: '权重/门槛合法就是一次成功的同步');
    expect(AuthorGrade.playWeight, 3);
    expect(AuthorGrade.colors, AuthorGrade.defaultColors,
        reason: '缺 c 时不能把配色清空或改成半截');
  });

  test('c 数量不对 → 整组回落默认（不逐项修补）', () {
    final ok = AuthorGrade.applyRemote(<String, dynamic>{
      'grade': <String, dynamic>{
        'play': 1,
        'drop': 10,
        'work': 2,
        't': <int>[100, 500, 2000, 8000],
        'c': <int>[0xFFFF0000, 0xFF00FF00],
      },
    });
    // 配色非法不阻断整次同步：权重仍应生效，但颜色必须是默认值。
    expect(ok, isTrue);
    expect(AuthorGrade.colors, AuthorGrade.defaultColors);
  });

  test('c 含非法值（负数 / 超出 32 位 / 非数字）→ 整组回落默认', () {
    for (final bad in <List<Object>>[
      <Object>[1, 2, 3, 4, -1],
      <Object>[1, 2, 3, 4, 4294967296],
      <Object>[1, 2, 3, 4, 'oops'],
    ]) {
      AuthorGrade.reset();
      final ok = AuthorGrade.applyRemote(<String, dynamic>{
        'grade': <String, dynamic>{
          'play': 1,
          'drop': 10,
          'work': 2,
          't': <int>[100, 500, 2000, 8000],
          'c': bad,
        },
      });
      expect(ok, isTrue, reason: '$bad');
      expect(AuthorGrade.colors, AuthorGrade.defaultColors, reason: '$bad');
    }
  });

  test('toJson 带上 c，可被 applyJson 读回（本机只读缓存往返）', () {
    AuthorGrade.colors = <int>[
      0xFF111111,
      0xFF222222,
      0xFF333333,
      0xFF444444,
      0xFF555555,
    ];
    final j = AuthorGrade.toJson();
    expect(j['c'], AuthorGrade.colors);

    AuthorGrade.reset();
    AuthorGrade.applyJson(Map<String, dynamic>.from(j));
    expect(AuthorGrade.colors, <int>[
      0xFF111111,
      0xFF222222,
      0xFF333333,
      0xFF444444,
      0xFF555555,
    ]);
  });

  test('reset 把配色一起还原（不会残留上一份服务端配色）', () {
    AuthorGrade.colors = <int>[9, 9, 9, 9, 9];
    AuthorGrade.reset();
    expect(AuthorGrade.colors, AuthorGrade.defaultColors);
  });

  test('配色不影响定级：只换颜色，分数与等级仍按权重门槛算', () {
    AuthorGrade.colors = <int>[1, 2, 3, 4, 5];
    expect(AuthorGrade.gradeFor(plays: 100), 'C');
    expect(AuthorGrade.gradeFor(plays: 8000), 'S');
    expect(AuthorGrade.colorForGrade('C'), 2);
  });
}
