import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/basic_lib.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/server_origin.dart';
import 'package:shoucangjia/top_node.dart';
import 'package:shoucangjia/unit_library.dart';

/// 0.9.324 第八十八批：
///
/// 1. **单元库页面按地址字符串找连接** —— 连接表里的 base 已 `normalizeBase`
///    （补协议、去尾斜杠、全角折叠），节点字段却可能带 `/` 或大写协议。
///    比不中时页面拿绑定表的账号去敲另一台服务器（401 / 串库），两处页面
///    各写一遍同一段判定。
/// 2. **顶级节点名是一个进程级单值** —— 设置页逐台加载元数据时，后一台的
///    库根名把前一台覆盖掉，两张媒体库卡片同名。
/// 3. **两处页面级请求没有超时**（封面恢复/作者编辑等），断网时 Future
///    永不结束，界面一直停在「上传中…」。
///
/// 本文件只用合成的 `s1` / `s2` / `http://a:8090` 与合成目录名，不涉任何
/// 真实目录或媒体内容。
String _code(String p) => File(p).readAsStringSync();

/// 去掉整行注释：注释里提到某个写法不算「用了它」。
String _codeNoComments(String p) => _code(p)
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('1. 单元库所属连接：按 id 找，地址回落要归一', () {
    const s1 = ServerConn(
        id: 's1',
        label: 'A',
        base: 'http://a:8090',
        user: 'u1',
        pass: 'p1');
    const s2 = ServerConn(
        id: 's2',
        label: 'B',
        base: 'http://b:8090',
        user: 'u2',
        pass: 'p2');

    test('记录带连接 id：直接按 id 命中，不受地址写法影响', () {
      final hit = serverOfOrigin(
        const [s1, s2],
        const ServerOrigin(id: 's2', base: 'HTTP://B:8090/'),
      );
      expect(hit?.id, 's2');
      expect(hit?.pass, 'p2');
    });

    test('没有连接 id 时按归一化地址回落（尾斜杠 / 大写协议 / 补协议都等价）', () {
      for (final raw in const [
        'http://a:8090',
        'http://a:8090/',
        'HTTP://A:8090',
        'a:8090',
      ]) {
        final hit = serverOfOrigin(
          const [s1, s2],
          ServerOrigin(base: raw),
        );
        expect(hit?.id, 's1', reason: '地址写法 "$raw" 应归一到同一条连接');
      }
    });

    test('地址不匹配时返回 null（调用方回落绑定表，不猜别的连接）', () {
      expect(
        serverOfOrigin(const [s1], const ServerOrigin(base: 'http://c:8090')),
        isNull,
      );
      expect(serverOfOrigin(const [], ServerOrigin.empty), isNull);
    });

    test('记录里的 fallbackBase 也参与匹配（节点没带 base 时用库地址）', () {
      final hit = serverOfOrigin(
        const [s1, s2],
        ServerOrigin.empty,
        fallbackBase: 'http://b:8090/',
      );
      expect(hit?.id, 's2');
    });

    test('契约：两个单元库入口共用一份判定，页面里不再比地址字符串', () {
      final main = _codeNoComments('lib/main.dart');
      final start = main.indexOf('({String base, Map<String, String> headers, String libId}) _unitConn(');
      expect(start, greaterThan(0), reason: '_unitConn 是唯一出口');
      final end = main.indexOf('void _showBasicOn(', start);
      final body = main.substring(start, end);
      expect(body.contains('serverOfOrigin('), isTrue);
      // 旧写法：遍历 servers 用 `s.base == base` 比字符串。
      expect(RegExp(r'if \(s\.base == base\)').hasMatch(main), isFalse,
          reason: '地址字符串比对不归一，必须走 serverOfOrigin');
      expect(RegExp(r's\.base == base').allMatches(main).length, 0);
      // 两个入口都必须走同一份（不再各写一遍 base/headers/匹配循环）。
      expect('_unitConn(u)'.allMatches(main).length, 2,
          reason: '作者挂载 + 爬虫配置各调用一次，且都只有一次');
    });

    test('契约：multi_server 里只有一个 serverOfOrigin 实现，带 id 与地址两级', () {
      final ms = _code('lib/multi_server.dart');
      expect('ServerConn? serverOfOrigin('.allMatches(ms).length, 1);
      final body = ms.substring(
          ms.indexOf('ServerConn? serverOfOrigin('),
          ms.indexOf('String nextServerId('));
      expect(body.contains('if (s.id == sid) return s;'), isTrue,
          reason: '先按连接 id');
      expect(body.contains('sameBase(s.base, want)'), isTrue,
          reason: '再按归一化地址（主机名大小写也要折）');
    });
  });

  group('2. 顶级节点名必须属于各自的服务器', () {
    BasicLib basic(String id, String rel, {String sid = '', String base = ''}) =>
        BasicLib(
          id: id,
          name: id,
          rel: rel,
          bigId: '',
          authors: 1,
          works: 1,
          serverId: sid,
          serverBase: base,
        );

    setUp(TopNodeName.reset);

    test('两台服务器各自的根名进入各自的卡片，不再同名', () {
      TopNodeName.setFromRoot('/vol1/甲库');
      final tree = buildUnitTree(
        nodes: const [
          LibNode(id: 'node:A', rel: 'A', name: 'A', serverId: 's1'),
          LibNode(id: 'node:B', rel: 'B', name: 'B', serverId: 's2'),
        ],
        basics: [
          basic('b1', 'A/one', sid: 's1'),
          basic('b2', 'B/two', sid: 's2'),
        ],
        topName: TopNodeName.current,
        topNameOf: (sid) => sid == 's1' ? '甲库' : '乙库',
      );
      expect(tree, isNotNull);
      final media = {
        for (final c in tree!.children) c.node.serverId: c.name,
      };
      expect(media['s1'], '甲库');
      expect(media['s2'], '乙库',
          reason: '全局名只服务没有 meta 的旧页面，不能覆盖另一台');
    });

    test('拿不到该连接的根名时回落连接标签，再回落全局名', () {
      TopNodeName.setFromRoot('/vol1/兜底库');
      final tree = buildUnitTree(
        nodes: const [
          LibNode(
              id: 'node:A',
              rel: 'A',
              name: 'A',
              serverId: 's1',
              serverLabel: '家里'),
          LibNode(id: 'node:B', rel: 'B', name: 'B', serverId: 's2'),
        ],
        basics: [
          basic('b1', 'A/one', sid: 's1'),
          basic('b2', 'B/two', sid: 's2'),
        ],
        topName: TopNodeName.current,
        topNameOf: (_) => '',
      );
      final media = {
        for (final c in tree!.children) c.node.serverId: c.name,
      };
      expect(media['s1'], '家里', reason: '有连接标签就用标签');
      expect(media['s2'], '兜底库', reason: '都没有才回落全局名');
    });

    test('单个连接的孤儿根同样用该连接自己的根名', () {
      final tree = buildUnitTree(
        nodes: const [],
        basics: [basic('b1', 'one', sid: 's1')],
        topName: '全局',
        topNameOf: (sid) => sid == 's1' ? '甲库' : '',
      );
      expect(tree!.children.single.name, '甲库');
    });

    test('LibMeta 把根名存在自己的元数据里（不再只写全局）', () {
      final main = _codeNoComments('lib/main.dart');
      expect(main.contains('final String topName;'), isTrue);
      final start = main.indexOf('String unitNameOf(String id) {');
      final body = main.substring(start, start + 400);
      expect(body.contains('topName.trim()'), isTrue,
          reason: 'secret 这一层先读本份 meta 的根名');
      expect(body.contains('TopNodeName.current'), isTrue,
          reason: '没有本份根名时才回落全局（旧页面/旧缓存）');
    });

    test('契约：buildUnitTree 的根名按连接取，别处不得拿全局名画多连接卡片', () {
      final ul = _code('lib/unit_library.dart');
      expect(ul.contains('String Function(String serverId)? topNameOf'), isTrue);
      expect(ul.contains('rootNameOf(sid)'), isTrue,
          reason: '媒体库/孤儿根取名都要过这一层');
      expect(ul.contains('label.isEmpty ? top : label'), isFalse,
          reason: '全局名直接当卡片名就是这次的缺陷');
    });
  });

  group('2b. 删除监测的第三条读取路径不得跨服务器猜库', () {
    test('只在这条连接确实拥有 `cfg.lib` 时才追加该尝试，且地址比较归一', () {
      final main = _codeNoComments('lib/main.dart');
      final start = main.indexOf('Future<void> load() async {', main.indexOf('class _DeletedMonitorPageState'));
      final end = main.indexOf('DeletedReport best = DeletedReport.empty;', start);
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));
      final body = main.substring(start, end);
      // 旧写法：`if (cfg.lib.isNotEmpty && cfg.lib != widget.libId)` 后直接加。
      expect(body.contains('sameBase(cfg.baseFor(cfg.lib), _base)'), isTrue,
          reason: '默认库可能属于另一台服务器，拿它去问这一台只会 404');
      expect(RegExp(r'cfg\.lib\.isNotEmpty && cfg\.lib != widget\.libId\)\s*\{')
          .hasMatch(body), isFalse,
          reason: '不加来源校验就追加尝试会把「请求发错了」显示成「没有记录」');
    });
  });

  group('3. 页面级请求必须有超时（断网时不悬停）', () {
    /// 找出所有 `http.get/post(...)` 调用，检查调用链后面跟着 timeout。
    List<String> missingTimeout(String path) {
      final src = _code(path);
      final out = <String>[];
      for (final m in RegExp(r'http\s*\.\s*(get|post|put|delete)\s*\(')
          .allMatches(src)) {
        var i = m.end;
        var depth = 1;
        while (i < src.length && depth > 0) {
          final c = src[i];
          if (c == '(') depth++;
          if (c == ')') depth--;
          i++;
        }
        final seg = src.substring(m.start, i);
        final after = src.substring(i, (i + 120).clamp(0, src.length));
        if (seg.contains('.timeout') || after.contains('.timeout')) continue;
        // 允许两种已知的「故意不超时」：fire-and-forget 的统计上报，
        // 与 `Future.wait([...])` 里由**外层**统一 timeout 的批量请求。
        if (after.contains('.ignore()')) continue;
        final waitAt = src.lastIndexOf('Future.wait([', m.start);
        if (waitAt >= 0) {
          final close = src.indexOf('])', i);
          if (close >= 0) {
            final tail = src.substring(close, (close + 120).clamp(0, src.length));
            if (tail.contains('.timeout')) continue;
          }
        }
        final line = src.substring(0, m.start).split('\n').length;
        out.add('$path:$line');
      }
      return out;
    }

    test('lib/ 内所有请求都有超时（除批量/上报两个显式例外）', () {
      final files = Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path)
          .toList();
      final all = <String>[];
      for (final f in files) {
        all.addAll(missingTimeout(f));
      }
      expect(all, isEmpty,
          reason: '这些请求没有超时：断网时 Future 永不结束：\n${all.join('\n')}');
    });

    test('下载整条作品文件按分钟级放宽，不是无限等', () {
      final main = _code('lib/main.dart');
      final at = main.indexOf("_toast('正在保存…')");
      expect(at, greaterThan(0));
      final body = main.substring(at, at + 1200);
      expect(body.contains('Duration(minutes: 5)'), isTrue,
          reason: '大文件要有上限，否则断网永远不会结束');
    });
  });
}
