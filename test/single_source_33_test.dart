/// 第五十三批契约：**同一条规则，两个实现，其中一半只做了半件事**。
///
/// 前几批收口的是「同一个读数两种算法」「同一个数据两种排列」。这一批是
/// 更隐蔽的一种：规则**本身**是对的、也确实被收口过，但**同一个读写对**里
/// 只有一半走到了那条规则，另一半自己又写了一遍，而且写得更窄。
///
/// 五处实测后果：
///
///  1. `relUnderBase` 手写「掐尾斜杠 + `startsWith('$b/')`」，只认 `/`——
///     `relUnderBase('/vol1/m', r'/vol1/m\A')` 返回 **空串**，那条基础库随即被
///     `basicsUnderBase` 跳过，**整个基础库从首页消失**（不报错、不提示）。
///  2. `SyncRun.unitLabel` 与作者挂载面板都写 `split('/').last`：服务端下发
///     `A\B` 时同步日志/分组标题把整条路径当库名。
///  3. `isCoverImagePath` 只剥 `?query` 不剥 `#fragment`：`/a.jpg#poster`
///     判成「不是图片」，`pickCoverPath` 把唯一候选剔除，卡片只剩空白底。
///  4. `oversizedResizeResponse` 自己写了个 `[?&]w=(\d{2,4})(?:&|$)`，而写侧
///     (`withImageWidth`) 认大小写、认更长宽度、认 fragment：`?W=480`、
///     `?w=12000`、`?w=480#x` 三种真实地址读不到宽度 → 超大原图被当正常响应
///     缓存 14 天，那几张卡在缓存过期前永远拉原图。
///  5. `parseRecommendCount` 的 `num` 分支 `round()`、字符串分支「剔除非数字
///     字符再 parse」：同一个 `1.5` 传数字是 **2**、传字符串是 **15**——
///     推荐页一批拉十倍作品。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/collection_sync.dart';
import 'package:shoucangjia/cover_cache.dart';
import 'package:shoucangjia/cover_ext.dart';
import 'package:shoucangjia/main.dart';
import 'package:shoucangjia/media_path.dart';
import 'package:shoucangjia/media_resize.dart';
import 'package:shoucangjia/rel_path.dart';
import 'package:shoucangjia/source_lib.dart';
import 'package:shoucangjia/sync_ledger.dart';
import 'package:shoucangjia/top_node.dart';

/// 只保留非注释行，避免文档里的「旧写法」被契约扫描当成现役代码。
String _lib(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('路径归一只有一套规则（rel_path 唯一实现）', () {
    test('relUnder：分隔符/点段/重复分隔符都是同一个根', () {
      expect(relUnder('/vol1/m', '/vol1/m/A'), 'A');
      expect(relUnder('/vol1/m', r'/vol1/m\A'), 'A',
          reason: '反斜杠路径此前算出空串，整条基础库从首页消失');
      expect(relUnder(r'/vol1/m', r'\vol1\m\A'), 'A',
          reason: '根目录本身用反斜杠时同样要认得');
      expect(relUnder('/vol1/m', '/vol1/m/./A'), 'A',
          reason: '点段此前被算进 rel（`./A`），后续前缀匹配永远失败');
      expect(relUnder('/vol1/m', '/vol1/m//A'), 'A',
          reason: '重复分隔符此前算出前导 `/`');
      expect(relUnder('/vol1/m/', '/vol1/m/A/'), 'A');
      expect(relUnder(r'E:\media', r'E:\media\A\B'), 'A/B',
          reason: 'Windows 根目录也要算出多级 rel');
    });

    test('relUnder：不在根下/等于根/空输入都返回空串', () {
      expect(relUnder('/vol1/m', '/vol1/m'), '');
      expect(relUnder('/vol1/m', '/vol1/other/A'), '');
      expect(relUnder('/vol1/m', '/vol1/mA'), '', reason: '同前缀但不是子目录');
      expect(relUnder('', '/vol1/m/A'), '');
      expect(relUnder('/vol1/m', ''), '');
    });

    test('relUnderBase 只是 relUnder 的转发（不再有第二套实现）', () {
      for (final pair in <List<String>>[
        ['/vol1/m', '/vol1/m/A'],
        ['/vol1/m', r'/vol1/m\A'],
        ['/vol1/m', '/vol1/m/./A'],
        ['/vol1/m', '/vol1/m//A'],
        ['/vol1/m', '/vol1/other/A'],
      ]) {
        expect(relUnderBase(pair[0], pair[1]), relUnder(pair[0], pair[1]),
            reason: 'relUnderBase 与 relUnder 对 ${pair} 给出不同结果');
      }
    });

    test('basicsUnderBase 不因分隔符丢掉基础库', () {
      final libs = <String, dynamic>{
        'basicLibraries': <dynamic>[
          <String, dynamic>{'id': 'lib-1', 'name': 'A', 'path': r'/vol1/m\A'},
          <String, dynamic>{'id': 'lib-2', 'name': 'B', 'path': '/vol1/m/B'},
          <String, dynamic>{
            'id': 'lib-3',
            'name': 'C',
            'path': '/vol1/m/./C',
          },
        ],
      };
      final ids = basicsUnderBase(libs, '/vol1/m').map((e) => e.id).toList();
      expect(ids, ['lib-1', 'lib-2', 'lib-3'],
          reason: '三条都在根下，一条都不能因为写法不同被跳过（按 rel 升序）');
    });

    test('normalizeRelPath / lastRelName 与 relSegments 同一条规则', () {
      expect(normalizeRelPath(r' A\B //C/. '), 'A/B/C');
      expect(normalizeRelPath('/a//b/'), 'a/b');
      expect(lastRelName(r'A\B/C'), 'C');
      expect(lastRelName('A/B/'), 'B');
      expect(lastRelName(''), '');
      expect(lastRelName('/'), '');
      expect(relSegments('../x'), <String>['..', 'x'],
          reason: '`..` 必须保留给校验层，不能在这里被静默吃掉');
    });

    test('顶级节点名从同一套拆分取最后一段', () {
      expect(TopNodeName.nameFromRoot('/vol1/SECRET/.'), 'SECRET',
          reason: '此前返回 `.`，顶级节点词条上就是个点号');
      expect(TopNodeName.nameFromRoot('/vol1/./SECRET'), 'SECRET');
      expect(TopNodeName.nameFromRoot(r'E:\media\SECRET'), 'SECRET');
      // `/vol1/.` 归一后就是 `/vol1`，名字应当是 `vol1`（不是 `.`）。
      expect(TopNodeName.nameFromRoot('/vol1/.'), 'vol1');
      expect(TopNodeName.nameFromRoot('E:'), '');
    });

    test('同步日志的单元库列只显示最后一段', () {
      expect(const SyncRun(id: 'r', unit: 'A/B', at: 0).unitLabel, 'B');
      expect(const SyncRun(id: 'r', unit: r'A\B', at: 0).unitLabel, 'B',
          reason: '此前把整条 `A\\B` 原样贴在同步日志里');
      expect(const SyncRun(id: 'r', unit: 'A/./B', at: 0).unitLabel, 'B');
      expect(const SyncRun(id: 'r', unit: '(1) 抖音/子目录/更深', at: 0).unitLabel,
          '更深');
      // 空的 unit 仍回落到 lib（既有行为不变）。
      expect(const SyncRun(id: 'r', lib: 'douyin', at: 0).unitLabel, 'douyin');
    });

    test('同步源匹配对同一 rel 的两种写法给出同一结果', () {
      const rows = <CollectionSyncInfo>[
        CollectionSyncInfo(
            idx: 0,
            name: 'A',
            count: 1,
            sync: true,
            inIndex: true,
            account: false,
            customName: false),
      ];
      final slash = syncCollectionsForUnit(rows, unitName: 'x', unitRel: 'A/B');
      final back =
          syncCollectionsForUnit(rows, unitName: 'x', unitRel: r'A\B');
      expect(back.length, slash.length);
      expect(back.map((e) => e.idx), slash.map((e) => e.idx));
    });
  });

  group('封面后缀判定：`?` 与 `#` 都要剥', () {
    test('带 fragment 的图片仍是图片', () {
      for (final p in <String>[
        '/a.jpg#poster',
        '/a.JPG#x',
        '/a.jpg?v=2#x',
        '/a.webp#t=1',
      ]) {
        expect(isCoverImagePath(p), isTrue, reason: '$p 应可作封面');
      }
    });

    test('视频永远不是封面（两个后缀都要剥才判得对）', () {
      for (final p in <String>[
        '/a.mp4',
        '/a.mp4#t=1',
        '/a.mp4?x=1#y',
        '/a.mkv',
      ]) {
        expect(isCoverImagePath(p), isFalse, reason: '$p 不能当封面');
        expect(isVideoMediaPath(p), isTrue, reason: '$p 应判为视频');
      }
    });

    test('stripMediaSuffix 是 `?`/`#` 的唯一剥除口', () {
      expect(stripMediaSuffix('/a.jpg?v=1#x'), '/a.jpg');
      expect(stripMediaSuffix('/a.jpg#x?v=1'), '/a.jpg');
      expect(stripMediaSuffix('  /a.jpg  '), '/a.jpg');
      expect(stripMediaSuffix(''), '');
      final src = _lib('lib/media_path.dart');
      final ext = _lib('lib/cover_ext.dart');
      // 两份都不得再自己剥后缀：`split('?')` 与 indexOf 链只允许出现在
      // media_path.dart 的那一个函数里。
      expect(ext.contains("split('?')"), isFalse,
          reason: 'cover_ext 不得再写一份只剥 `?` 的判定');
      expect(RegExp(r'indexOf\(.#.\)').hasMatch(ext), isFalse);
      expect(src.contains('String stripMediaSuffix'), isTrue);
    });
  });

  group('`w=` 读写同一条规则', () {
    test('读侧认大小写、认长宽度、认 fragment', () {
      expect(requestedImageWidth('/a.jpg?w=480'), 480);
      expect(requestedImageWidth('/a.jpg?W=480'), 480,
          reason: '写侧认大小写、读侧此前不认');
      expect(requestedImageWidth('/a.jpg?w=480#x'), 480,
          reason: '片段粘在末尾，旧正则要求 w= 后面直接跟 & 或结尾');
      expect(requestedImageWidth('/a.jpg?w=12000'), 12000,
          reason: '旧正则只允许 2–4 位');
      expect(requestedImageWidth('/a.jpg?v=1&w=440&x=2'), 440);
      expect(requestedImageWidth('/a.jpg?w='), isNull);
      expect(requestedImageWidth('/a.jpg?w=0'), isNull);
      expect(requestedImageWidth('/a.jpg?w=-5'), isNull);
      expect(requestedImageWidth('/a.jpg'), isNull);
      expect(requestedImageWidth(''), isNull);
    });

    test('读写对同一地址给出对应结果（写进去能读回来）', () {
      for (final base in <String>['/a.jpg', '/a.jpg?v=1', '/a.jpg?w=0']) {
        final u = withImageWidth(base, 480);
        expect(requestedImageWidth(u), isNotNull,
            reason: '写进 `w=` 之后读不到：$base -> $u');
      }
    });

    test('超尺寸判定用到读到的宽度（三种真实地址都生效）', () {
      for (final u in <String>[
        '/a.jpg?w=480',
        '/a.jpg?W=480',
        '/a.jpg?w=480#x',
        '/a.jpg?w=12000',
      ]) {
        expect(oversizedResizeResponse(u, 50 * 1024 * 1024), isTrue,
            reason: '$u 的大图响应应判为超尺寸');
      }
      // 正常小图不误判，没有宽度的地址也不判。
      expect(oversizedResizeResponse('/a.jpg?w=480', 60 * 1024), isFalse);
      expect(oversizedResizeResponse('/a.jpg', 50 * 1024 * 1024), isFalse);
      expect(oversizedResizeResponse('/a.jpg?w=480', null), isFalse);
    });

    test('`w=` 解析只有一处实现', () {
      final cache = _lib('lib/cover_cache.dart');
      expect(RegExp(r'RegExp\(r.\[\?&\]w=').hasMatch(cache), isFalse,
          reason: 'cover_cache 不得再自己写一份 `w=` 正则');
      expect(cache.contains('requestedImageWidth(url)'), isTrue);
    });
  });

  group('推荐数量：数字与字符串同一结果', () {
    test('小数两种写法一致（此前 1.5 → 2 vs 15）', () {
      expect(parseRecommendCount(1.5), 2);
      expect(parseRecommendCount('1.5'), 2,
          reason: '小数点被剔掉会变成 15，一批拉十倍作品');
      expect(parseRecommendCount('1.5 倍'), 2);
      expect(parseRecommendCount(40.6), 41);
      expect(parseRecommendCount('40.6'), 41);
    });

    test('单位、千分位、全角都归一到同一个数', () {
      expect(parseRecommendCount('20条'), 20);
      expect(parseRecommendCount(' 20 '), 20);
      expect(parseRecommendCount('1,000'), 500);
      expect(parseRecommendCount('１００'), 100,
          reason: '全角数字此前被剔成空串 → 回落 40');
      expect(parseRecommendCount('２０个'), 20);
    });

    test('上限与默认值不变', () {
      expect(parseRecommendCount(null), 40);
      expect(parseRecommendCount(''), 40);
      expect(parseRecommendCount('abc'), 40);
      expect(parseRecommendCount('0'), 0);
      expect(parseRecommendCount('-12'), 0);
      expect(parseRecommendCount('999'), 500);
      expect(parseRecommendCount(double.nan), 40);
      expect(parseRecommendCount(double.infinity), 40);
    });

    test('解析不得再出现「剔除非数字字符再 parse」那一支', () {
      final src = _lib('lib/main.dart');
      expect(RegExp(r"replaceAll\(RegExp\(r'\[\^0-9-\]'\)").hasMatch(src),
          isFalse,
          reason: '剔除非数字会把小数点和千分位一起吃掉');
      expect(src.contains('int parseRecommendCount'), isTrue);
    });
  });

  group('契约扫描：这几条规则各自只有一处实现', () {
    test('路径统一拆分入口只有 rel_path', () {
      for (final f in <String>[
        'lib/source_lib.dart',
        'lib/top_node.dart',
        'lib/folder_structure_page.dart',
        'lib/collection_sync.dart',
        'lib/sync_ledger.dart',
        'lib/author_mount_sheet.dart',
      ]) {
        final src = _lib(f);
        expect(src.contains(r"replaceAll('\\', '/')"), isFalse,
            reason: '$f 仍在手写分隔符归一');
      }
    });

    test('`split(\'/\').last` 不再出现在 lib 下', () {
      final dir = Directory('lib');
      final hits = <String>[];
      for (final e in dir.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final src = _lib(e.path);
        if (src.contains("split('/').last")) hits.add(e.path);
      }
      expect(hits, isEmpty, reason: '这些文件还在用只认 `/` 的取末段写法：$hits');
    });

    test('库根/媒体路径的前缀比较集中在一处', () {
      final src = _lib('lib/rel_path.dart');
      expect(src.contains('String relUnder('), isTrue);
      expect(src.contains('String normalizeRelPath('), isTrue);
      expect(src.contains('String lastRelName('), isTrue);
      final sourceLib = _lib('lib/source_lib.dart');
      expect(
          RegExp(r'=>\s*\n?\s*relUnder\(basePath, basicPath\)')
              .hasMatch(sourceLib),
          isTrue,
          reason: 'relUnderBase 必须只是转发，不能自带实现');
    });
  });
}
