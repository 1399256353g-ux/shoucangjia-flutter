import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/unit_crawler.dart';

void main() {
  test('配置默认值与解析', () {
    const def = UnitCrawlerConfig();
    expect(def.enabled, isFalse);
    expect(def.schedule, '04:10');
    expect(def.intervalMin, 0);
    expect(def.script, 'sync.sh');
    expect(def.syncReady, isFalse);

    final c = UnitCrawlerConfig.fromJson({
      'enabled': true,
      'schedule': '7:05',
      'intervalMin': 9999,
      'note': '  hello  ',
      'script': 'run.sh',
    });
    expect(c.enabled, isTrue);
    expect(c.schedule, '07:05');
    expect(c.intervalMin, 1440);
    expect(c.note, 'hello');
    expect(c.script, 'run.sh');
    expect(c.syncReady, isTrue);
  });

  test('时间/间隔/备注归一化', () {
    expect(normalizeSchedule('04:10'), '04:10');
    expect(normalizeSchedule('4:09'), '04:09');
    expect(normalizeSchedule('24:00'), '04:10');
    expect(normalizeSchedule('12:60'), '04:10');
    expect(normalizeSchedule('bad'), '04:10');
    expect(normalizeInterval(-5), 0);
    expect(normalizeInterval(30), 30);
    expect(normalizeInterval(2000), 1440);
    expect(normalizeInterval('12'), 12);
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

  test('顶级单元库不可单独配置', () {
    expect(unitCrawlerConfigurable('(1) A'), isTrue);
    expect(unitCrawlerConfigurable('  '), isFalse);
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
}
