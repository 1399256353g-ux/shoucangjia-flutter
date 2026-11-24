import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/api_url.dart';
import 'package:shoucangjia/index_prefix.dart';
import 'package:shoucangjia/color_codec.dart';
import 'package:shoucangjia/sync_ledger.dart';
import 'package:shoucangjia/unit_crawler.dart';
import 'package:shoucangjia/deleted_monitor.dart';
import 'package:shoucangjia/source_lib.dart';
import 'package:shoucangjia/collection_sync.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/library_corner_badge.dart';
import 'package:shoucangjia/app_settings.dart';

/// 第十四批：四组「同规则多份实现」收口的契约。
///
/// 每一组都先证明旧实现的缺口是真的（旧写法在这条用例上必然失败），
/// 再断言新实现的结果。这样契约不是「抄一遍现在的行为」，而是钉住缺口。
void main() {
  group('序号前缀：三处曾各写一份，其中一份只认半角 (1)', () {
    test('括号式四种写法与点号式都去掉', () {
      expect(stripIndexPrefix('(1) 名称'), '名称');
      expect(stripIndexPrefix('（12）名称'), '名称');
      expect(stripIndexPrefix('[3] 名称'), '名称');
      expect(stripIndexPrefix('【4】名称'), '名称');
      expect(stripIndexPrefix('01. 名称'), '名称');
      expect(stripIndexPrefix('02、名称'), '名称');
      expect(stripIndexPrefix('名称'), '名称');
    });

    test('旧 normalizeLibLabel 只认 (1)：[3] / （2） / 01. 会漏', () {
      // 旧实现的判据就是这条正则；新实现必须 Coverage 它覆盖不到的三类。
      final oldStyle = RegExp(r'^\(\s*\d+\s*\)\s*');
      expect(oldStyle.hasMatch('[3] 名称'), isFalse, reason: '旧写法确实漏方括号');
      expect(oldStyle.hasMatch('（2）名称'), isFalse, reason: '旧写法确实漏全角');
      expect(oldStyle.hasMatch('01. 名称'), isFalse, reason: '旧写法确实漏点号');
      // 新实现在这三类上都生效，并与其他两个调用点结果一致。
      expect(normalizeLibLabel('[3] 名称'), '名称');
      expect(normalizeLibLabel('（2）名称'), '名称');
      expect(normalizeLibLabel('01. 名称'), '名称');
      expect(syncUnitKey('[3] 名称'), '名称');
      expect(syncUnitKey('@（2）名称'), '名称');
    });

    test('三个调用点对同一个名字给出同一结果（此前会不一致）', () {
      for (final raw in const [
        '(1) 丝',
        '（02）丝',
        '[3] 丝',
        '【4】丝',
        '01. 丝',
        '01、丝',
        '( 14 )  擦边',
      ]) {
        AppSettings.stripLibIndex = true;
        final a = LibraryBadge.stripIndex(raw);
        final b = normalizeLibLabel(raw);
        final c = syncUnitKey(raw);
        expect(a, b, reason: '词条显示与基础库匹配对不上：$raw');
        expect(b.toLowerCase(), c, reason: '基础库匹配与同步源匹配对不上：$raw');
      }
    });

    test('不吞掉真实名字：日期与序号本身不剥空', () {
      expect(stripIndexPrefix('2026.11.24 相册'), '2026.11.24 相册');
      expect(stripIndexPrefix('18+'), '18+');
      expect(stripIndexPrefix('(1)'), '(1)', reason: '只有序号时保留原串，词条不能变空');
      expect(stripIndexPrefix('  '), '');
      // 反向判断曾被单独导出、却只有测试在调用；要判断「带了序号」时
      // 直接比较 stripIndexPrefix 的返回值即可（单一规则、单一入口）。
      const raw = '(1) 名称';
      expect(stripIndexPrefix(raw), isNot(raw));
    });

    test('括号前缀可叠加，点号前缀只剥一层', () {
      expect(stripIndexPrefix('(1)(2) 名称'), '名称');
      expect(stripIndexPrefix('01. 02. 名称'), '02. 名称');
    });
  });

  group('颜色读写：曾「写 8 位、读只认 6 位」并丢 alpha', () {
    test('六位、三位、八位都能读', () {
      expect(argbFromHex('#1b3f5f'), 0xFF1B3F5F);
      expect(argbFromHex('1b3f5f'), 0xFF1B3F5F);
      expect(argbFromHex('FF1B3F5F'), 0xFF1B3F5F);
      expect(argbFromHex('#abc'), 0xFFAABBCC, reason: '三位简写要展开，旧实现给的是 0xFF000ABC');
      expect(argbFromHex('0xff1b3f5f'), 0xFF1B3F5F);
    });

    test('非法输入返回 null（调用方保留旧值，不写半截）', () {
      expect(argbFromHex(''), isNull);
      expect(argbFromHex('zzz'), isNull);
      expect(argbFromHex('#12345'), isNull);
    });

    test('写入是 8 位，读回与写入逐位相等（不再抹掉 alpha）', () {
      const argb = 0x801B3F5F; // 半透明
      final hex = argbToHex(argb);
      expect(hex.length, 8);
      expect(argbFromHex(hex), argb);

      final encoded = LibraryBadge.encodeBasic(source: {'lib-001': argb});
      expect(LibraryBadge.parse(encoded)['lib-001'], argb);

      final top = LibraryBadge.encodeTop(source: {'node:rel': argb});
      expect(LibraryBadge.parse(top)['node:rel'], argb);
    });

    test('角标与词条对同一份 JSON 读出同一个颜色', () {
      // 两份实现曾各自解析；现在共用 argbFromJson，读到的必须完全一致。
      const json = {'top': '#abc', 'basic': 'ff1b3f5f', 'unit': 0xFF00FF00};
      expect(argbFromJson(json['top']), argbFromHex('#abc'));
      expect(argbFromJson(json['top']), 0xFFAABBCC);
      expect(argbFromJson(json['basic']), 0xFF1B3F5F);
      expect(argbFromJson(json['unit']), 0xFF00FF00);
      expect(argbFromJson(null), isNull);
      expect(argbFromJson(true), isNull);
      expect(argbFromJson(-1), isNull);
      expect(argbFromJson(0x1FFFFFFFF), isNull);
    });

    test('角标 toJson → applyJson 往返不丢值', () {
      LibraryCornerBadge.resetDefaults();
      final before = {
        for (final k in LibBadgeKind.values) k: LibraryCornerBadge.color[k],
      };
      LibraryCornerBadge.applyJson(LibraryCornerBadge.toJson());
      for (final k in LibBadgeKind.values) {
        expect(LibraryCornerBadge.color[k], before[k], reason: '层级 $k 往返后变色');
      }
    });
  });

  group('接口地址：六种拼接写法缺少补协议与多斜杠归一', () {
    test('base 补协议、去尾部所有斜杠、path 缺前导斜杠也能拼', () {
      expect(joinApiUrl('192.168.2.4:8090', '/api/x'), 'http://192.168.2.4:8090/api/x');
      expect(joinApiUrl(' 192.168.2.4:8090/ ', '/api/x'), 'http://192.168.2.4:8090/api/x');
      expect(joinApiUrl('http://h:8090//', '/api/x'), 'http://h:8090/api/x');
      expect(joinApiUrl('http://h:8090', 'api/x'), 'http://h:8090/api/x');
    });

    test('旧写法「endsWith 斜杠」对双斜杠只去一个，会拼出 //api', () {
      const base = 'http://h:8090//';
      final sep = base.endsWith('/') ? '' : '/';
      expect('$base${sep}api/sync/logs', 'http://h:8090//api/sync/logs');
      expect(joinApiUrl(base, '/api/sync/logs'), 'http://h:8090/api/sync/logs');
    });

    test('旧写法「Uri.parse(base + path)」在无协议时直接抛 FormatException', () {
      expect(
        () => Uri.parse('192.168.2.4:8090/api/x'),
        throwsA(isA<FormatException>()),
        reason: '这正是不补协议时真机上会静默/抛错的位置',
      );
      expect(apiUri('192.168.2.4:8090', '/api/x').toString(),
          'http://192.168.2.4:8090/api/x');
    });

    test('base 为空时 apiUri 返回 null；joinApiUrl 只留相对路径', () {
      expect(apiUri('', '/api/x'), isNull);
      expect(apiUri('   ', '/api/x'), isNull);
      expect(joinApiUrl('', '/api/x'), '/api/x');
    });

    test('query 值按查询组件编码（空格→+，括号→%28%29）', () {
      final u = joinApiUrl('http://h:8090', '/api/unit/crawler',
          query: {'unit': 'big-01', 'rel': '(1) A'});
      expect(u, 'http://h:8090/api/unit/crawler?unit=big-01&rel=%281%29+A');
    });

    test('path 自带查询时接 `&`，不出现两个问号', () {
      expect(joinApiUrl('http://h:8090', '/api/x?a=1', query: {'lib': 'l'}),
          'http://h:8090/api/x?a=1&lib=l');
      expect(withQueryFlag('http://h:8090/api/m', 'deep=1'),
          'http://h:8090/api/m?deep=1');
      expect(withQueryFlag('http://h:8090/api/m?a=1', 'deep=1'),
          'http://h:8090/api/m?a=1&deep=1');
      expect(withQueryFlag('http://h:8090/api/m', ''), 'http://h:8090/api/m');
    });

    test('libApiUrl：lib 为空则不带 lib 参数', () {
      expect(libApiUrl('http://h:8090', '/api/x', ''), 'http://h:8090/api/x');
      expect(libApiUrl('http://h:8090', '/api/x', ' a b '),
          'http://h:8090/api/x?lib=a+b');
    });

    test('四个既有调用点全部走同一出口并保持原有语义', () {
      final logs = syncLogsUri('http://nas:8090/', lib: 'douyin', limit: 30);
      expect(logs.path, '/api/sync/logs');
      expect(logs.queryParameters['lib'], 'douyin');
      expect(logs.queryParameters['limit'], '30');
      expect(syncLogsUri('http://nas:8090/', limit: 5).toString(),
          'http://nas:8090/api/sync/logs?limit=5');
      expect(syncRetryUri('http://nas:8090').path, '/api/sync/retry');

      final crawler = unitCrawlerUrl('http://nas:8090/', '/api/unit/crawler',
          unitId: 'big-01', rel: '(1) A');
      expect(crawler, startsWith('http://nas:8090/api/unit/crawler?'));
      expect(crawler, contains('rel=%281%29+A'));

      const e = DeletedEntry(
        at: '',
        author: '',
        date: '',
        title: 'T',
        workId: '7300',
        collection: '',
        link: '',
        cover: '',
        libId: 'lib-008',
      );
      final work = deletedWorkUri('http://nas:8090//', e)!;
      expect(work.toString(), startsWith('http://nas:8090/api/work.json?'));
      expect(work.queryParameters['lib'], 'lib-008');
      expect(deletedWorkUri('', e), isNull);
    });
  });
}
