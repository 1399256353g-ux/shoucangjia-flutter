import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_grade.dart';

void main() {
  setUp(() {
    AuthorGrade.reset();
    AuthorGrade.remoteManaged = false;
    AuthorGrade.remoteAt = 0;
  });

  test('默认权重与门槛', () {
    expect(AuthorGrade.score(), 0);
    expect(AuthorGrade.gradeFor(), 'D');
    // 100 分 → C
    expect(AuthorGrade.gradeFor(plays: 100), 'C');
    expect(AuthorGrade.gradeFor(plays: 499), 'C');
    expect(AuthorGrade.gradeFor(plays: 500), 'B');
    expect(AuthorGrade.gradeFor(plays: 2000), 'A');
    expect(AuthorGrade.gradeFor(plays: 8000), 'S');
  });

  test('水滴与作品加权计入', () {
    expect(AuthorGrade.score(plays: 10, drops: 2, works: 5), 10 + 20 + 10);
    // 9 颗水滴 = 90 分（D），10 颗 = 100 分（C 起点）
    expect(AuthorGrade.gradeFor(drops: 9), 'D');
    expect(AuthorGrade.gradeFor(drops: 10), 'C');
    expect(AuthorGrade.gradeFor(drops: 80), 'B'); // 800 分
    expect(AuthorGrade.gradeFor(drops: 800), 'S'); // 8000 分
  });

  test('负数与空数据按 0 处理', () {
    expect(AuthorGrade.score(plays: -5, drops: -1, works: -3), 0);
  });

  test('自定义门槛与权重生效', () {
    AuthorGrade.applyJson({
      'play': 2,
      'drop': 5,
      'work': 0,
      't': [10, 20, 30, 40],
    });
    expect(AuthorGrade.gradeFor(plays: 5), 'C'); // 10 分 → 第一档
    expect(AuthorGrade.gradeFor(plays: 15), 'A'); // 30 分 → 第三档
    expect(AuthorGrade.gradeFor(plays: 4), 'D');
    expect(AuthorGrade.gradeFor(drops: 8), 'S'); // 40 分
  });

  test('坏数据回落默认值', () {
    AuthorGrade.applyJson({
      'play': -1,
      'drop': 'abc',
      'work': 3,
      't': [100, 50, 2000, 8000], // 非递增
    });
    expect(AuthorGrade.playWeight, 0);
    expect(AuthorGrade.dropWeight, AuthorGrade.defaultDropWeight);
    expect(AuthorGrade.workWeight, 3);
    expect(AuthorGrade.thresholds, AuthorGrade.defaultThresholds);
  });

  test('序列化往返与颜色', () {
    AuthorGrade.applyJson({
      'play': 1,
      'drop': 10,
      'work': 2,
      't': [1, 2, 3, 4],
    });
    final json = AuthorGrade.parse(AuthorGrade.encode());
    expect(json['t'], [1, 2, 3, 4]);
    expect(AuthorGrade.colorForGrade('S'), AuthorGrade.colors.last);
    expect(AuthorGrade.colorForGrade('D'), AuthorGrade.colors.first);
    expect(AuthorGrade.grades.length, AuthorGrade.colors.length);
  });

  // P6：服务端下发（App 端只读）
  test('applyRemote 套用服务端配置并标记 remoteManaged', () {
    final ok = AuthorGrade.applyRemote({
      'ok': true,
      'grade': {'play': 2, 'drop': 20, 'work': 3, 't': [200, 1000, 4000, 16000]},
      'at': 1795421256,
    });
    expect(ok, isTrue);
    expect(AuthorGrade.playWeight, 2);
    expect(AuthorGrade.dropWeight, 20);
    expect(AuthorGrade.workWeight, 3);
    expect(AuthorGrade.thresholds, [200, 1000, 4000, 16000]);
    expect(AuthorGrade.remoteManaged, isTrue);
    expect(AuthorGrade.gradeFor(plays: 200), 'C');
  });

  test('applyRemote 接受裸对象（无 grade 包裹）', () {
    final ok = AuthorGrade.applyRemote(
        <String, dynamic>{'play': 1, 'drop': 10, 'work': 2, 't': [1, 2, 3, 4]});
    expect(ok, isTrue);
    expect(AuthorGrade.thresholds, [1, 2, 3, 4]);
  });

  test('applyRemote 拒绝非法数据且不改动现有配置', () {
    AuthorGrade.applyRemote(
        <String, dynamic>{'play': 2, 'drop': 20, 'work': 3, 't': [1, 2, 3, 4]});
    final before = AuthorGrade.thresholds;
    // 非递增
    expect(
        AuthorGrade.applyRemote(<String, dynamic>{
          'play': 5,
          'drop': 5,
          'work': 5,
          't': [100, 50, 200, 300]
        }),
        isFalse);
    // 门槛数量不对
    expect(
        AuthorGrade.applyRemote(
            <String, dynamic>{'play': 1, 'drop': 1, 'work': 1, 't': [1, 2, 3]}),
        isFalse);
    // 负权重
    expect(
        AuthorGrade.applyRemote(
            <String, dynamic>{'play': -1, 'drop': 1, 'work': 1, 't': [1, 2, 3, 4]}),
        isFalse);
    // null
    expect(AuthorGrade.applyRemote(null), isFalse);
    expect(AuthorGrade.thresholds, before);
    expect(AuthorGrade.playWeight, 2);
  });
}
