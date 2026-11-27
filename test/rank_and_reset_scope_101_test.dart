// 第一百零一批契约（owner 规则逐条对照）：
//
// 1. 「数值类型统一在数字前面」（PROJECT_RULES §十）
//    排行榜明细行三项里，前两项是「类型 + 数字」，第三项却是 `3 作品`——
//    同一条明细行两种语序，读起来像两套排版。
//
// 2. 「只改被要求的那一处」+「单页按钮只碰自己那一半」（§十四.1 / 既有判据）
//    「播放设置 → 恢复默认」把首层设置页的「词条省略序号」也一起重置了：
//    那一页从头到尾没有出现过这个开关，用户在别处关掉它，点一次播放设置的
//    重置就自己打开——与 0.9.343 修掉的「resetPlayback 清按键绑定」同一族。
//
// 3. 媒体库根 id 的拼装与识别只有一处（结构收口）
//    `media:<连接>` 此前在 `buildUnitTree` 与 `crawler_sections.unitScopeKey`
//    各拼一遍，`UnitLibrary.isMediaRoot` 又自己写 `startsWith('media:')`。
//    前缀改名时漏一处，「这一层是不是媒体库」会静默变成 false：首页不再贴
//    媒体库词条、爬虫分节里所有单元库掉进「其它」，而两边都不报错。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/app_settings.dart';
import 'package:shoucangjia/crawler_sections.dart';
import 'package:shoucangjia/rank_metric.dart';
import 'package:shoucangjia/unit_library.dart';

String codeOf(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('1. 排行榜明细行：数值类型统一在数字前面', () {
    test('三项都是「类型 数字」，没有一项把类型放在数字后', () {
      final line = rankDetailLine(plays: 2000, drops: 4, works: 3);
      expect(line, '播放 2000 · 水滴 4 · 作品 3');
      // 旧写法 `$works 作品` 会把类型放到数字后面。
      expect(line.contains('3 作品'), isFalse,
          reason: '第三条与前两条必须同一语序');
    });

    test('不给 works 时不输出第三项（各库榜没有这一项）', () {
      expect(rankDetailLine(plays: 12, drops: 0), '播放 12 · 水滴 0');
    });

    test('源码里没有第二处「数字在类型前」的拼法', () {
      final metric = codeOf('lib/rank_metric.dart');
      expect(RegExp(r"'\$\w+ 作品'").hasMatch(metric), isFalse,
          reason: '明细行的作品数必须走同一语序');
      // 明细行仍是唯一出口。
      expect(RegExp(r'String rankDetailLine\(').allMatches(metric).length, 1);
    });
  });

  group('2. 「播放设置 → 恢复默认」不再连带重置词条显示开关', () {
    setUp(AppSettings.resetDefaults);

    test('resetPlayback 不动 stripLibIndex', () {
      AppSettings.stripLibIndex = false;
      AppSettings.defaultSpeed = 2.0;
      AppSettings.resetPlayback();
      expect(AppSettings.stripLibIndex, isFalse,
          reason: '该开关不在播放设置页上，不能被这一页的按钮改掉');
      expect(AppSettings.defaultSpeed, 1.0);
    });

    test('resetLabelPrefs 只恢复词条显示开关，不碰播放参数与按键', () {
      AppSettings.stripLibIndex = false;
      AppSettings.defaultSpeed = 1.75;
      AppSettings.hideUiSec = 9;
      AppSettings.resetLabelPrefs();
      expect(AppSettings.stripLibIndex, isTrue);
      expect(AppSettings.defaultSpeed, 1.75);
      expect(AppSettings.hideUiSec, 9);
    });

    test('resetDefaults 仍覆盖三项（全量入口没有漏）', () {
      AppSettings.stripLibIndex = false;
      AppSettings.defaultSpeed = 2.5;
      AppSettings.resetDefaults();
      expect(AppSettings.stripLibIndex, isTrue);
      expect(AppSettings.defaultSpeed, 1.0);
    });

    test('resetDefaults 只调三个分项，不出现第二份字段赋值', () {
      final src = codeOf('lib/app_settings.dart');
      final start = src.indexOf('static void resetDefaults()');
      expect(start, greaterThan(0));
      final body = src.substring(start, src.indexOf('}', start));
      expect(body.contains('resetPlayback()'), isTrue);
      expect(body.contains('resetKeys()'), isTrue);
      expect(body.contains('resetLabelPrefs()'), isTrue);
      // 任何一个具体字段都不该在这一层再写一遍。
      for (final f in ['defaultSpeed', 'stripLibIndex', 'keyBindings']) {
        expect(body.contains(f), isFalse, reason: '$f 被写了两份');
      }
    });
  });

  group('3. 媒体库根 id 的拼装与识别只有一处', () {
    test('拼装口与判定口都在 unit_library，且空连接统一写 local', () {
      expect(mediaRootId('s1'), 'media:s1');
      expect(mediaRootId('  s1  '), 'media:s1');
      expect(mediaRootId(''), 'media:local');
      expect(orphanRootId(''), 'top:local');
      expect(orphanRootId('s2'), 'top:s2');
      // 两个前缀不能相同：分组根与媒体库根按 id 索引，撞了会互相顶掉。
      expect(kMediaRootIdPrefix, isNot(kOrphanRootIdPrefix));
    });

    test('isMediaRootId 只认前缀，不看目录名文本', () {
      expect(isMediaRootId('media:s1'), isTrue);
      expect(isMediaRootId('top:s1'), isFalse);
      expect(isMediaRootId('secret'), isFalse);
      expect(isMediaRootId(''), isFalse);
    });

    test('UnitLibrary.isMediaRoot 走同一个判定（rel 为空 + 媒体库前缀）', () {
      UnitLibrary u(String id, String rel) => UnitLibrary(
          node: LibNode(id: id, rel: rel, name: 'x'),
          basics: const [],
          children: const []);
      expect(u('media:s1', '').isMediaRoot, isTrue);
      // rel 非空的永远不是媒体库根，哪怕 id 带前缀（防手写脏数据）。
      expect(u('media:s1', 'A').isMediaRoot, isFalse);
      expect(u('top:s1', '').isMediaRoot, isFalse);
    });

    test('两个文件都不再自己拼前缀字面量', () {
      for (final f in ['lib/unit_library.dart', 'lib/crawler_sections.dart']) {
        final src = codeOf(f);
        expect(RegExp(r"'media:\\\$").hasMatch(src), isFalse,
            reason: '$f 又出现一处 media: 拼装');
        expect(src.contains("startsWith('media:')"), isFalse,
            reason: '$f 又出现一处前缀判定');
      }
    });

    test('crawler_sections 的媒体库分节键与树节点 id 逐字相同', () {
      final top = UnitLibrary(
        node: const LibNode(id: 'media:s1', rel: '', name: 'NAS', serverId: 's1'),
        basics: const [],
        children: const [],
      );
      // 同一张卡片在两个页面按同一个键折叠；两处各拼一次就会漂。
      expect(unitScopeKey(top), top.id);
      expect(unitScopeKey(top), mediaRootId('s1'));
    });
  });
}
