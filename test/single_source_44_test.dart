/// 第六十四批契约：**「什么时候用哪个值」的判断散在调用点上**。
///
/// 前三批抓的是同一段代码抄多份（第六十三批）、同一条记录两个模型
/// （第六十二批）、同一条记录的身份字段读六遍（第六十一批）。这一批抓的是
/// 更难看见的一类：**数字和语义在调用点被各选一次**。
///
/// 1. `_cover/` 目录归属：`resolveCover(rel: ...)` 的 `rel` 到底传节点 rel
///    还是空串，此前由四个调用点各写一遍并在注释里解释。同一个基础库在
///    `main._basicCoverUrl` 里传 `''`、在 `pickBasicCover(rel: ...)` 里传 rel，
///    同一张封面就是两个路径（一个 200、一个 404）。
/// 2. 网格数字：`grid_spec` 上一批只覆盖库卡片。作者网格的三个数字与作品
///    网格的三个数字仍「页面 delegate 写一遍、预热再写一遍」——重复的正是
///    上一批已经收口的那类缺陷，只是换了个网格。
/// 3. 首屏预热：`算张数 → 拼 URL → 去重 → 建 provider` 在四个页面各写一遍，
///    去重键一份用原地址、一份用带参地址，`run` 与 `runWith` 两种调用各一半。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/decode_plan.dart';
import 'package:shoucangjia/grid_spec.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/thumb_prefetch.dart';
import 'package:shoucangjia/work_card.dart';

/// 去掉整行注释后再做「有没有第二个实现」的扫描。
String _code(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

List<File> _libFiles() => Directory('lib')
    .listSync()
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String _fileName(File f) => f.path.split(Platform.pathSeparator).last;

void main() {
  group('封面作用域只有一个入口（0.9.287）', () {
    test('基础库封面在库根，单元库在节点目录', () {
      expect(kLibRootCoverRel, '');
      expect(coverScopeRel(CoverScopeDir.basic), '');
      // 基础库作用域忽略 unitRel：基础库的 `_cover/` 永远在库根。
      expect(coverScopeRel(CoverScopeDir.basic, unitRel: 'A/B'), '');
      expect(coverScopeRel(CoverScopeDir.unit, unitRel: 'A/B'), 'A/B');
      // 空 rel 的节点就是库根。
      expect(coverScopeRel(CoverScopeDir.unit), '');
      expect(coverScopeRel(CoverScopeDir.unit, unitRel: '/'), '');
      // 服务端可能下发 `\`；归一化走 rel_path（唯一实现）。
      expect(coverScopeRel(CoverScopeDir.unit, unitRel: r'A\B'), 'A/B');
    });

    test('作用域目录拼上 `_cover/` 才是封面目录，不会叠两层', () {
      // 早期把「封面目录」当 `rel` 传给 resolveCover，实测拼出
      // `A/_cover/_cover/v1.jpg` —— 服务端必然 404，而界面只是默认图。
      final hit = resolveUnitCover(unitRel: 'A', version: 'v1');
      expect(hit.path, 'A/_cover/v1.jpg');
      expect(hit.path.contains('_cover/_cover'), isFalse);
    });

    test('两个作用域共享同一条优先级链', () {
      // 手动 > 自定义 > 爬虫 > 最高播放 > 首张：作用域只影响自定义封面路径。
      final b = resolveBasicCover(
        manualUrl: '/media/l/m.jpg',
        version: 'v1',
        crawlerThumb: '/media/l/cv.jpg',
      );
      expect(b.source, CoverSource.manual);
      final u = resolveUnitCover(
        unitRel: 'A',
        manualUrl: '/media/l/m.jpg',
        version: 'v1',
      );
      expect(u.source, CoverSource.manual);

      // 关掉手动与自定义后，剩下三级在两个作用域下逐字相同。
      final b2 = resolveBasicCover(
        manualUrl: '/media/l/m.jpg',
        version: 'v1',
        crawlerThumb: '/media/l/cv.jpg',
        ignoreManual: true,
        ignoreCustom: true,
      );
      final u2 = resolveUnitCover(
        unitRel: 'A',
        manualUrl: '/media/l/m.jpg',
        version: 'v1',
        crawlerThumb: '/media/l/cv.jpg',
        ignoreManual: true,
        ignoreCustom: true,
      );
      expect(b2.path, '/media/l/cv.jpg');
      expect(b2.path, u2.path);
      expect(b2.source, u2.source);
    });

    test('CoverPick.of 把「全部落空」判成无图，而不是自定义封面', () {
      // resolveCover 全部落空时仍返回 source: first；直接看 source 会把
      // 一张不存在的图当成有封面。
      final empty = resolveBasicCover();
      expect(empty.path, '');
      expect(CoverPick.of(empty).isEmpty, isTrue);
      expect(CoverPick.of(empty).custom, isFalse);
      final custom = resolveBasicCover(version: 'v3');
      expect(CoverPick.of(custom).custom, isTrue);
      expect(CoverPick.of(custom).path, '_cover/v3.jpg');
    });

    test('契约：页面不得自己给 resolveCover 传 rel', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final name = _fileName(f);
        if (name == 'lib_cover.dart') continue;
        final src = _code(f.path);
        if (src.contains('resolveCover(')) offenders.add(f.path);
        // 旧三件套的签名就是「传 rel」本身，不得复活。
        for (final dead in <String>[
          'pickBasicCover(',
          'pickUnitCover(',
          '_pickLibCover(',
        ]) {
          if (src.contains(dead)) offenders.add('$name → $dead');
        }
      }
      expect(offenders, isEmpty, reason: '又绕过了封面作用域入口：$offenders');
      // 两个作用域入口都必须在 lib_cover 里可用。
      final lib = _code('lib/lib_cover.dart');
      expect(lib.contains('CoverHit resolveBasicCover('), isTrue);
      expect(lib.contains('CoverHit resolveUnitCover('), isTrue);
      expect(lib.contains('String coverScopeRel('), isTrue);
    });
  });

  group('手动封面指针的解析只有一个入口', () {
    test('非媒体路径 / 空串都当没设过', () {
      String build(String p, String? lib) => 'B|$p|${lib ?? '-'}';
      expect(manualCoverUrl('', build: build), '');
      expect(manualCoverUrl('   ', build: build), '');
      // 旧写法只判非空：半截路径会被当封面请求（404，卡片只剩默认图）。
      expect(manualCoverUrl('_cover/v1.jpg', build: build), '');
      expect(manualCoverUrl('http://cdn/x.jpg', build: build), '');
    });

    test('媒体路径：去掉首尾空白、把库段解出来交给调用方', () {
      String build(String p, String? lib) => '${lib ?? '-'}::$p';
      expect(manualCoverUrl(' /media/lib-008/a/b.jpg ', build: build),
          'lib-008::/media/lib-008/a/b.jpg');
      // 库段解码：中文库名在路径里是百分号编码，取出来的 id 必须能查绑定表。
      expect(manualCoverUrl('/media/%E4%B8%AD/c.jpg', build: build),
          '中::/media/%E4%B8%AD/c.jpg');
      // 没有库段（`/media/` 后面直接是文件）时传 null，由调用方选默认连接。
      expect(manualCoverUrl('/media/x.jpg', build: build), '-::/media/x.jpg');
    });

    test('调用方拼不出地址（返回空）时当作不可用', () {
      expect(manualCoverUrl('/media/l/a.jpg', build: (_, __) => '  '), '');
    });

    test('契约：三处手动封面读取全部转发', () {
      final main = _code('lib/main.dart');
      final view = _code('lib/unit_library_view.dart');
      expect(RegExp(r'manualCoverUrl\(').allMatches(main).length, 2,
          reason: '顶级卡片与单元库卡片两处');
      expect(RegExp(r'manualCoverUrl\(').allMatches(view).length, 1);
      // 旧写法特征：`libOfMediaPath(pick)` 紧跟 `cfg.mediaUrl(pick, lib:`。
      for (final src in <String>[main, view]) {
        expect(
            RegExp(r'final ownLib = libOfMediaPath\(pick\)').hasMatch(src),
            isFalse,
            reason: '又在自己手拆手动封面指针');
      }
    });
  });

  group('网格规格覆盖四类网格（0.9.287）', () {
    test('作者与作品网格的几何也在表里，且 delegate 与预热同源', () {
      // 作者总览：150 / 10 / 固定行高 170。
      expect(kAuthorGrid.maxCrossAxisExtent, 150);
      expect(kAuthorGrid.spacing, 10);
      expect(kAuthorGrid.mainAxisExtent, kAuthorCardExtent);
      expect(kAuthorCardExtent, 170);
      final d = kAuthorGrid.delegate;
      expect(d.maxCrossAxisExtent, kAuthorGrid.maxCrossAxisExtent);
      expect(d.mainAxisSpacing, kAuthorGrid.spacing);
      expect(d.crossAxisSpacing, kAuthorGrid.spacing);
      expect(d.mainAxisExtent, kAuthorGrid.mainAxisExtent);

      // 作品网格：180 / 2 / 3:4；不带固定行高（高度由宽度算）。
      expect(kWorkGrid.maxCrossAxisExtent, 180);
      expect(kWorkGrid.spacing, 2);
      expect(kWorkGrid.aspectRatio, 3 / 4);
      expect(kWorkGrid.mainAxisExtent, isNull);
      expect(kWorkGrid.delegate.mainAxisExtent, isNull);

      // 基础库页作品网格：150 / 8 / 0.72。
      expect(kBasicWorkGrid.maxCrossAxisExtent, 150);
      expect(kBasicWorkGrid.spacing, 8);
      expect(kBasicWorkGrid.aspectRatio, 0.72);

      // 基础库页作者网格：180 / 10 / 0.86（与作者总览是两个不同网格）。
      expect(kBasicAuthorGrid.maxCrossAxisExtent, 180);
      expect(kBasicAuthorGrid.spacing, 10);
      expect(kBasicAuthorGrid.aspectRatio, 0.86);
      expect(kBasicAuthorGrid.mainAxisExtent, isNull);
    });

    test('固定行高的网格：预热按行高算，不按宽 / 比例估', () {
      // 作者卡片固定 170：300 宽、上下内边距合计 20 → 可用 480。
      // cols = ceil(300/160) = 2；列宽 (300-10)/2 = 145。
      // 行高固定 170（不是 145 / aspectRatio），步长 180；
      // 2 屏 = ceil(960/180) = 6 行 → 12 张。
      expect(
          kAuthorGrid.prefetchCount(
            const Size(300, 500),
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 10),
          ),
          12);
      // 同一组参数若按「宽 / 比例」估行高（145）会多算一行（14 张）——
      // 这里钉住固定行高真的生效。
      expect(
          firstScreenThumbCount(
            viewportWidth: 300,
            viewportHeight: 500,
            maxCrossAxisExtent: 150,
            paddingX: 0,
            paddingY: 10,
            crossSpacing: 10,
            mainSpacing: 10,
            aspectRatio: 1,
            screens: 2,
            maxItems: 24,
          ),
          14);
    });

    test('规格自带的预热屏数生效（库卡片 1 屏、作者/作品 2 屏）', () {
      expect(kUnitLibGrid.prefetchScreens, 1);
      expect(kBasicLibGrid.prefetchScreens, 1);
      expect(kAuthorGrid.prefetchScreens, 2);
      expect(kWorkGrid.prefetchScreens, 2);
      expect(kBasicWorkGrid.prefetchScreens, 2);
    });

    test('四个页面都不得再手写 delegate 字面量', () {
      for (final pair in <List<String>>[
        ['lib/main.dart', 'gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent('],
        ['lib/basic_lib_page.dart', 'gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent('],
      ]) {
        expect(_code(pair[0]).contains(pair[1]), isFalse,
            reason: '${pair[0]} 又手写了 delegate，数字会与预热各写一份');
      }
      // 作者页 / 作品网格 / 骨架屏都必须转发规格表。
      final main = _code('lib/main.dart');
      expect(RegExp(r'kAuthorGrid\.delegate').hasMatch(main), isTrue);
      expect(RegExp(r'padding: workGridPadding\(context\)').hasMatch(main),
          isTrue,
          reason: '作品网格与骨架屏都读同一个内边距出口');
      // 0.9.300：骨架屏不再写死 `kWorkGrid`——它改成收一个网格规格
      // （默认作品网格），因为作者总览页的骨架必须模仿 `kAuthorGrid`，
      // 否则加载完成时列数与行高一起变。
      expect(RegExp(r'this\.grid = kWorkGrid').hasMatch(main), isTrue,
          reason: '骨架屏默认仍转发 kWorkGrid');
      expect(RegExp(r'gridDelegate: grid\.delegate').hasMatch(main), isTrue,
          reason: '骨架屏必须转发传入的网格规格');
      // 骨架屏内部不得再写死内边距：`padding: padding ?? workGridPadding(context)`
      // 是唯一写法（其它页面自己的 `EdgeInsets.all(12)` 与骨架屏无关）。
      final skeleton = main.substring(main.indexOf('class WorkGridSkeleton'));
      final skeletonBody = skeleton.substring(0, skeleton.indexOf('class _AuthorPageSkeleton'));
      expect(skeletonBody.contains('EdgeInsets.all('), isFalse,
          reason: '骨架屏不得自己挑内边距（会与真实网格跳一下）');      final page = _code('lib/basic_lib_page.dart');
      expect(RegExp(r'kBasicWorkGrid\.delegate').hasMatch(page), isTrue);
      expect(RegExp(r'kBasicAuthorGrid\.delegate').hasMatch(page), isTrue);
      // 作者卡片与作品卡片的宽高比也不得再次写死。
      expect(_code('lib/work_card.dart').contains('3 / 4'), isFalse);
      // `main.dart` 里「180 + 3/4 + 2」那组字面量的 delegate 参数不得复活。
      expect(
          RegExp(r'maxCrossAxisExtent:\s*180,\s*childAspectRatio:\s*3\s*/\s*4')
              .hasMatch(main),
          isFalse);
    });

    test('recommendVisibleCount 的默认几何来自规格表', () {
      final src = _code('lib/recommend_grid.dart');
      expect(src.contains('kWorkGrid.maxCrossAxisExtent'), isTrue);
      expect(src.contains('kWorkGrid.aspectRatio'), isTrue);
      expect(src.contains('kWorkGrid.spacing'), isTrue);
      // 旧默认值（180 / 3/4 / 2）不得再写在函数签名里。
      expect(RegExp(r'double maxCrossAxisExtent = 180').hasMatch(src), isFalse);
    });
  });

  group('首屏预热只有一个排队入口（0.9.287）', () {
    test('prefetchThumbItems 去重、限量、空图跳过', () {
      // 只验证纯逻辑部分：真实请求由 ThumbPrefetch 的全局实例发出，
      // 这里给一个已到上限之外的 limit，确认入口自己会收手。
      expect(
          prefetchThumbItems(
            const <ThumbPrefetchItem>[],
            limit: 5,
            decodeWidth: 100,
          ),
          0);
      expect(
          prefetchThumbItems(
            const <ThumbPrefetchItem>[(
              url: ' /a.jpg ',
              headers: <String, String>{},
            )],
            limit: 0,
            decodeWidth: 100,
          ),
          0);
      // 空串（库没有封面）不占额度。
      expect(
          prefetchThumbItems(
            const <ThumbPrefetchItem>[
              (url: '   ', headers: <String, String>{}),
              (url: '', headers: <String, String>{}),
            ],
            limit: 4,
            decodeWidth: 100,
          ),
          0);
    });

    test('契约：四个页面不再各自维护 urls + headers 表', () {
      for (final name in <String>[
        'lib/basic_lib_page.dart',
        'lib/main.dart',
      ]) {
        final src = _code(name);
        // 旧写法的特征：一个局部 `final urls = <String>[];` 紧跟着手动
        // 构造 provider 并调用 ThumbPrefetch。预热的四个入口已全部转发，
        // 页面上不该再有第二份。
        expect(src.contains('ThumbPrefetch.instance.run('), isFalse,
            reason: '$name 又自己调 run：去重/限量逻辑会出现第二份');
        expect(src.contains('ThumbPrefetch.instance.runWith('), isFalse,
            reason: '$name 又自己调 runWith：同上');
        expect(RegExp(r'final urls = <String>\[\];').hasMatch(src), isFalse,
            reason: '$name 又自己排 URL 列表');
      }
      // 唯一实现必须在 thumb_prefetch 里。
      expect(_code('lib/thumb_prefetch.dart').contains('int prefetchThumbItems('),
          isTrue);
      // 库卡片预热也走同一个「去重 + provider」实现。
      final libPrefetch = _code('lib/lib_card_prefetch.dart');
      expect(libPrefetch.contains('ThumbPrefetch.instance.run('), isTrue,
          reason: '库卡片预热是唯一允许直接排队的模块（几何来自 LibGridSpec）');
    });

    test('预热入口的返回张数与 limit 一致（不超发）', () {
      // limit 为负视为 0 张，不抛。
      expect(
          prefetchThumbItems(
            const <ThumbPrefetchItem>[(
              url: '/a.jpg',
              headers: <String, String>{},
            )],
            limit: -3,
            decodeWidth: 0,
          ),
          0);
    });
  });

  group('作品卡宽高比只有一处', () {
    test('WorkCard.aspect 转发 kWorkGrid', () {
      expect(WorkCard.aspect, kWorkGrid.aspectRatio);
      // 解码宽度也必须与卡片一致（缓存键 = 地址 + 解码宽度）。
      expect(workCardDecodeWidth(1), kWorkCardDisplayWidth);
    });
  });
}
