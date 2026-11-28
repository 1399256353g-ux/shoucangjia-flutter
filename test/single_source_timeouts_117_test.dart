import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/api_timeout.dart';
import 'package:shoucangjia/api_url.dart';

/// 第一百一十七批（0.9.364）：**同一个端点，各页各给一个超时**。
///
/// `timeout(const Duration(seconds: N))` 此前在 16 个文件里写了 92 遍，N 由每个
/// 页面自己定。看不见的后果不是「不统一」，而是「短的赢」：
///
/// - `/api/libraries` 有 8 / 10 / 12 / 15 四种上限，慢盘上 8s 的那几处先失败；
/// - `/api/authors.json` 有 12 / 20，大索引在 12s 的调用点永远读不出来；
/// - `/api/crawler` 有 8 / 10 / 15，同一份爬虫配置三个页面对「慢」容忍不同。
///
/// 收口方式是**按读到的体量分档**（不是按数字分档），每档取该档已有调用点的
/// **最大值**——只会放宽、绝不收紧。这条不变量是重点：收口不能把 20s 能读出来
/// 的东西变成 12s 超时。
String codeOf(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String codeOnly(String src) => [
      for (final l in src.split('\n'))
        if (!l.trimLeft().startsWith('//')) l,
    ].join('\n');

List<File> libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String relPath(File f) => f.path.replaceAll('\\', '/');

void main() {
  group('1. 档位本身：只放宽，不收紧', () {
    test('每一档的取值都不小于它取代的那些旧字面量', () {
      // 旧值集合（改造前实测）：2/5/6/8/10/12/15/20/30/60。
      // 其中 2s（Windows 全屏切换）、5min（整条作品下载）不是 HTTP 读，
      // 留在原处；其余的旧值必须被某一档「覆盖」——分档值 >= 旧值。
      const oldHttpValues = [6, 8, 10, 12, 15, 20, 30, 60];
      final buckets = <Duration>[
        kTimeoutProbe,
        kTimeoutRead,
        kTimeoutReadSlow,
        kTimeoutReadHeavy,
        kTimeoutWrite,
        kTimeoutHeavyWrite,
        kTimeoutUpload,
        kTimeoutDeepScan,
        kTimeoutBatch,
      ];
      for (final old in oldHttpValues) {
        expect(buckets.any((b) => b.inSeconds >= old), isTrue,
            reason: '旧上限 ${old}s 没有任何一档 >= 它，改成档位就收紧了这个端点');
      }
    });

    test('重读档不小于普通读档，读档不小于探测档', () {
      expect(kTimeoutReadHeavy >= kTimeoutReadSlow, isTrue);
      expect(kTimeoutReadSlow >= kTimeoutRead, isTrue);
      expect(kTimeoutRead >= kTimeoutProbe, isTrue,
          reason: '读一份 JSON 不该比只判活还急');
    });

    test('整批档保持 10s：它不是单条上限', () {
      expect(kTimeoutBatch, const Duration(seconds: 10));
      expect(kTimeoutBatch < kTimeoutReadSlow, isTrue,
          reason: '整批一起等，必须比单条读取更早放弃，否则掉线的服务器拖垮首屏');
    });

    test('深度扫描比重读更宽', () {
      expect(kTimeoutDeepScan > kTimeoutReadHeavy, isTrue);
    });
  });

  group('2. lib/ 内不再有裸的接口超时字面量', () {
    test('除 api_timeout.dart 外零 `.timeout(const Duration(...))` / `.timeout(Duration(...))`',
        () {
      final bad = <String>[];
      for (final f in libFiles()) {
        if (relPath(f) == 'lib/api_timeout.dart') continue;
        final src = codeOnly(codeOf(relPath(f)));
        // 三处非接口超时按字面量放行：手势 400ms、整条下载 5min、全屏 2s。
        final hits = [
          for (final l in src.split('\n'))
            if (RegExp(r'\.timeout\(\s*(?:const\s+)?Duration\(').hasMatch(l))
              if (!l.contains('milliseconds: 400') &&
                  !l.contains('minutes: 5') &&
                  !l.contains('seconds: 2'))
                l,
        ];
        if (hits.isNotEmpty) bad.add(relPath(f));
      }
      expect(bad, isEmpty, reason: '这些文件还留着裸的接口超时：$bad');
    });

    test('三处非 HTTP 超时留在原处（手势 400ms / 下载 5min / 全屏 2s）', () {
      expect(codeOf('lib/author_drag.dart')
          .contains('.timeout(const Duration(milliseconds: 400)'), isTrue);
      expect(codeOf('lib/main.dart')
          .contains('.timeout(const Duration(minutes: 5))'), isTrue);
      expect(codeOf('lib/main.dart')
          .contains('.timeout(const Duration(seconds: 2))'), isTrue);
    });
  });

  group('3. 一个端点只落一档', () {
    /// 只挑**纯读**端点做断言。
    ///
    /// 读写分开的端点（`/api/libraries` 的 GET 与 POST、`/api/crawler`、
    /// `/api/sync`）不在此表：同一条路径上的「读配置」与「写配置」允许不同
    /// 档，把它们塞进来只会让断言靠「猜这一行是读还是写」，反而不可靠。
    const expected = <String, String>{
      '/api/authors.json': 'kTimeoutReadHeavy', // 12/20 → 20（大索引一次读完）
      '/api/author_stats.json': 'kTimeoutRead', // 8/10 → 12
      '/api/cat/tree': 'kTimeoutReadHeavy', // 10/20 → 20
      '/api/drops': 'kTimeoutProbe', // 两次都是 8，探测档
      '/api/work/manual': 'kTimeoutRead',
    };

    /// 返回 `端点 -> 用到的档位集合`（只看读请求，跳过 `Future.wait` 整批上限）。
    Map<String, Set<String>> scan() {
      final found = <String, Set<String>>{};
      for (final f in libFiles()) {
        if (relPath(f) == 'lib/api_timeout.dart') continue;
        final lines = codeOf(relPath(f)).split('\n');
        for (var i = 0; i < lines.length; i++) {
          final m = RegExp(r'\.timeout\((k\w+)\)').firstMatch(lines[i]);
          if (m == null) continue;
          // 整批上限（`]).timeout(...)`）管的是「多条一起等」，不是某个端点。
          if (lines[i].contains(']).timeout(')) continue;
          final ctx = lines
              .sublist(i - 25 < 0 ? 0 : i - 25, i + 1)
              .join('\n');
          final paths = RegExp(r"'(/api/[^']*)'").allMatches(ctx).toList();
          if (paths.isEmpty) continue;
          final ep = paths.last.group(1)!.split('?').first;
          if (!expected.containsKey(ep)) continue;
          found.putIfAbsent(ep, () => <String>{}).add(m.group(1)!);
        }
      }
      return found;
    }

    test('表内端点的读取上限只剩一档', () {
      final found = scan();
      for (final ep in expected.keys) {
        final got = found[ep] ?? <String>{};
        expect(got, isNotEmpty, reason: '$ep 一个读取调用点都没找到');
        expect(got, {expected[ep]},
            reason: '$ep 应只落 ${expected[ep]}，实际 $got');
      }
    });

    test('连接测试整段走探测档（快告诉用户通不通）', () {
      final main = codeOf('lib/main.dart');
      final start = main.indexOf('  Future<void> _test(ServerConn s) async {');
      expect(start, greaterThan(0));
      final body = main.substring(start, start + 1400);
      expect('.timeout(kTimeoutProbe)'.allMatches(body).length, 2,
          reason: '探测请求两条（索引 + 注册表），都该是同一档');
    });

    test('作者索引这个「一处 12s、一处 20s」的缺口已堵上', () {
      // 12s 的调用点永远读不出大索引，20s 的读得出来 —— 同一份数据两种结局。
      final main = codeOnly(codeOf('lib/main.dart'));
      final basic = codeOnly(codeOf('lib/basic_lib_page.dart'));
      expect("/api/authors.json".allMatches(main + basic).length,
          greaterThanOrEqualTo(5));
      expect('kTimeoutRead'.allMatches(main).length,
          greaterThan(0), reason: '其它读取档仍在用，不是把所有读都改成 20s');
    });
  });

  group('4. 缓存穿透参数只有一个出口', () {
    test('cacheBusted 把 `t=` 接在已有查询串之后', () {
      final t = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      expect(cacheBusted('/api/libraries.json', now: t),
          '/api/libraries.json?t=1700000000000');
      expect(cacheBusted('/api/libraries.json?lib=a', now: t),
          '/api/libraries.json?lib=a&t=1700000000000',
          reason: 'base/path 已带查询时必须用 `&`，否则第二个 `?` 之后的都丢了');
    });

    test('lib/ 内不再手拼时间戳查询参数', () {
      final bad = <String>[];
      for (final f in libFiles()) {
        if (relPath(f) == 'lib/api_url.dart') continue;
        final src = codeOnly(codeOf(relPath(f)));
        if (src.contains('?t=\${DateTime.now().millisecondsSinceEpoch}')) {
          bad.add(relPath(f));
        }
      }
      expect(bad, isEmpty, reason: '时间戳还在和地址拼在同一行：$bad');
    });

    test('lib/ 内不再有「手拼 base + /api」的地址（base 带查询串时会拼坏）', () {
      final bad = <String>[];
      for (final f in libFiles()) {
        if (relPath(f) == 'lib/api_url.dart') continue;
        final src = codeOnly(codeOf(relPath(f)));
        if (RegExp(r"'\$\{s\.base\}/api").hasMatch(src)) bad.add(relPath(f));
      }
      expect(bad, isEmpty, reason: '这些文件还在手拼 base 地址：$bad');
    });

    test('六处 libraries.json 读取都走同一出口', () {
      final main = codeOnly(codeOf('lib/main.dart'));
      expect("cacheBusted('/api/libraries.json')".allMatches(main).length, 6);
      // 换行会让字面量跨行，先压成单行再数。
      final oneLine = main.replaceAll(RegExp(r'\s+'), ' ');
      expect('joinApiUrl( s.base, cacheBusted(\'/api/libraries.json\'))'
          .allMatches(oneLine).length, 3,
          reason: '跨连接读取必须同时走 base 归一与时间戳：连接测试、并发列表、单元库树');
    });
  });
}
