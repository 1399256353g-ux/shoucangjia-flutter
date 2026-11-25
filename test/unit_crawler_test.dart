import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/unit_crawler.dart';

void main() {
  test('配置默认值与解析', () {
    const def = UnitCrawlerConfig();
    expect(def.enabled, isFalse);
    expect(def.quickCheck, isTrue);
    expect(def.quickMin, 5);
    expect(def.fullMin, 60);
    expect(def.cooldownMin, 15);
    expect(def.script, 'sync.sh');
    // 脚本列表为空 → 未就绪。
    expect(def.scriptReadyIn(const <UnitCrawlerScript>[]), isFalse);

    final c = UnitCrawlerConfig.fromJson({
      'enabled': true,
      'schedule': '7:05',
      'intervalMin': 9999,
      'note': '  hello  ',
      'script': 'run.sh',
    });
    expect(c.enabled, isTrue);
    expect(c.fullMin, 60);
    expect(c.note, 'hello');
    expect(c.script, 'run.sh');
    // 关键：配置里写着 run.sh 但磁盘上没有这个脚本 → 不算就绪。
    // 旧实现只判 `script.isNotEmpty`，这里会给出相反（更宽松）的答案。
    expect(c.scriptReadyIn(const <UnitCrawlerScript>[]), isFalse);
    const real = [UnitCrawlerScript(name: 'run.sh')];
    expect(c.scriptReadyIn(real), isTrue);
    // 就绪只看脚本是否存在，不看开关：否则关掉同步后开关再也打不开。
    expect(c.copyWith(enabled: false).scriptReadyIn(real), isTrue);
    // 不可运行的扩展名不算就绪。
    const bad = [UnitCrawlerScript(name: 'run.sh.bak')];
    expect(c.scriptReadyIn(bad), isFalse);
  });

  test('备注归一化', () {
    expect(clipNote('  x  '), 'x');
    expect(clipNote('a' * 250).length, 200);
  });

  test('脚本名只允许纯文件名', () {
    expect(normalizeScriptName('sync.sh'), 'sync.sh');
    expect(normalizeScriptName('a/b/run.py'), 'run.py');
    expect(normalizeScriptName('../evil.sh'), 'evil.sh');
    expect(normalizeScriptName('..'), 'sync.sh');
    expect(normalizeScriptName('.hidden'), 'sync.sh');
    expect(normalizeScriptName('a b.sh'), 'sync.sh');
    expect(normalizeScriptName(''), 'sync.sh');
  });

  test('脚本列表解析与可运行判断', () {
    final list = UnitCrawlerScript.listFrom([
      {'name': 'b.py', 'size': 2},
      {'name': 'a.sh', 'size': 1, 'mtime': 123},
      {'name': 'config.json', 'size': 9},
      {'name': ''},
      'bad',
    ]);
    expect(list.map((s) => s.name).toList(), ['a.sh', 'b.py', 'config.json']);
    expect(list.first.size, 1);
    expect(list.first.mtimeMs, 123);
    expect(list.first.looksRunnable, isTrue);
    expect(list.last.looksRunnable, isFalse);
    expect(UnitCrawlerScript.listFrom(null), isEmpty);
  });

  test('接口 URL 同时带 unit 与 rel 且正确编码', () {
    final u = unitCrawlerUrl('http://nas:8090/', '/api/unit/crawler',
        unitId: 'big-01', rel: '(1) A');
    expect(u, startsWith('http://nas:8090/api/unit/crawler?'));
    expect(u, contains('unit=big-01'));
    expect(u, contains('rel=%281%29+A'));
    expect(unitCrawlerRunLabel(false), '运行单元库同步');
    expect(unitCrawlerRunLabel(true), '运行中…');
  });

  test('同步频率：快检/全量/冷却取值收敛并兼容旧字段', () {
    final c = UnitCrawlerConfig.fromJson({
      'enabled': true,
      'quickCheck': false,
      'quickMin': 15,
      'fullMin': 180,
      'cooldownMin': 60,
      'intervalMin': 30,
      'script': 'sync.sh',
    });
    expect(c.quickCheck, isFalse);
    expect(c.quickMin, 15);
    expect(c.fullMin, 180);
    expect(c.cooldownMin, 60);
    expect(c.toJson()['intervalMin'], 180, reason: '旧服务端读 intervalMin');

    final bad = UnitCrawlerConfig.fromJson(
        {'quickMin': 7, 'fullMin': 33, 'cooldownMin': 9});
    expect(bad.quickMin, 5);
    expect(bad.fullMin, 60);
    expect(bad.cooldownMin, 15);
    expect(bad.quickCheck, isTrue);
    expect(bad.intervalLabel, contains('快检'));
  });
  test('旧字段 intervalMin 不能丢掉（旧配置的全量间隔要能读回来）', () {
    // 0.9.228 实缺陷：`m['intervalMin'] != null ? 60 : 60` 两支相同，
    // 老配置里的 30/180 全被读成默认 60，界面「当前：…」与真实调度不符。
    expect(UnitCrawlerConfig.fromJson({'intervalMin': 30}).fullMin, 30);
    expect(UnitCrawlerConfig.fromJson({'intervalMin': 180}).fullMin, 180);
    // 新字段优先于旧字段。
    expect(
        UnitCrawlerConfig.fromJson({'fullMin': 720, 'intervalMin': 30}).fullMin,
        720);
    // 两个都没有时才是默认值。
    expect(UnitCrawlerConfig.fromJson(const {}).fullMin, 60);
    // 非法值仍夹回默认（与 normalizeFullMin 同一判定）。
    expect(UnitCrawlerConfig.fromJson({'intervalMin': 7}).fullMin, 60);
  });

  test('H：/api/nodes 的 crawler 映射解析（缺字段一律按无脚本）', () {
    expect(unitCrawlerFlags({'crawler': {'(1) A': true, '(2) B': false}}),
        {'(1) A': true, '(2) B': false});
    expect(unitCrawlerFlags({'nodes': ['x']}), isEmpty);
    expect(unitCrawlerFlags(null), isEmpty);
    // 0.9.235：`1` / `"true"` 也算已配置（此前 `== true` 把它们当未启用，
    // 与设置页的显示相反）。真正的脏数据（对象/任意串）仍按无脚本。
    expect(unitCrawlerFlags({'crawler': {'x': 1}}), {'x': true});
    expect(unitCrawlerFlags({'crawler': {'y': 'oops'}}), {'y': false});
  });
}
