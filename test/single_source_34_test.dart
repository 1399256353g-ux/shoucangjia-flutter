/// 第五十四批契约：**同一个地址，后缀剥除只做了一半**。
///
/// 前几批收口的是「同一条规则两个实现」「同一个读数两种算法」「同一个数据
/// 两种排列」。这一批是同一件事的第三种形态：后缀剥除已经有一个公共出口
/// （`media_path.stripMediaSuffix`），也确实有一半调用点走到了它，但**另一半
/// 自己又写了一遍，而且只剥 `?` 不剥 `#`**。
///
/// 实测后果（修复前）：
///
///  1. `main.isGifPath('/m/a.gif#poster')` 与 `AvatarCandidate.isGif` → **false**
///     （两处都写 `endsWith('.gif') || contains('.gif?')`）。`CachedNetworkImage`
///     只取首帧，动图在网格里变成一张静止图。
///  2. `decodeMediaRel('/media/lib/@a/x.jpg#poster')` → `lib/@a/x.jpg#poster`：
///     rel 带着片段，基础库归属 / 作者前缀全都匹配不上。
///  3. `serverAvatarFileFromPath('/media/lib/.avatars/a.jpg?w=200')` → **null**：
///     「设置头像」静默退化成只存本机（跨设备不生效）。
///  4. `normalizeCoverVersion('_cover/v1.png?w=200')` → **空串**：
///     库封面指针作废，卡片退回默认图。
///  5. `coverPointerOf('v1.webp?w=480')` 的扩展名回落 `jpg`，而
///     `normalizeCoverVersion` 同一串剥完得到 `webp`——同一个指针两个扩展名，
///     请求 `v1.jpg`、磁盘是 `v1.webp`，封面 404。
///  6. `normalizeScriptName('run.py?x=1')` → `sync.sh`（一个不存在的默认名）。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_avatar.dart';
import 'package:shoucangjia/author_filter.dart';
import 'package:shoucangjia/library_rank.dart';
import 'package:shoucangjia/author_avatar_store.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/main.dart' show isGifPath;
import 'package:shoucangjia/source_lib.dart';
import 'package:shoucangjia/unit_crawler.dart';
import 'package:shoucangjia/work_forms.dart';

/// 只保留非注释行，避免文档里的「旧写法」被契约扫描当成现役代码。
String _lib(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('动图判定：后缀剥除与其它媒体判定同一条规则', () {
    test('片段形式的 GIF 地址也认（旧写法只认 `?`）', () {
      expect(isGifPath('/media/lib/PIC/a_01.gif'), isTrue);
      expect(isGifPath('/media/lib/PIC/a_01.gif?w=200'), isTrue);
      expect(isGifPath('/media/lib/PIC/a_01.gif#poster'), isTrue,
          reason: '旧写法 `contains(".gif?")` 漏片段，动图在网格里只播首帧');
      expect(isGifPath('/media/lib/PIC/a_01.gif?w=200#poster'), isTrue);
      expect(isGifPath('/media/lib/PIC/a_01.GIF#x'), isTrue);
      expect(isGifPath('/media/lib/PIC/a_01.webp'), isFalse);
      expect(isGifPath('/media/lib/PIC/agif_01.png'), isFalse);
      expect(isGifPath('/media/lib/VID/a.mp4'), isFalse);
    });

    test('头像候选的 isGif 与页面判定同源', () {
      expect(AvatarCandidate(path: '/m/a.gif#p').isGif, isTrue);
      expect(AvatarCandidate(path: '/m/a.gif?w=9').isGif, isTrue);
      expect(AvatarCandidate(path: '/m/a.png').isGif, isFalse);
    });

    test('契约扫描：`contains(".gif?")` 这种半截判定不得复活', () {
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = _lib(f.path);
        expect(src.contains(".gif?')"), isFalse, reason: '${f.path} 又写了一遍');
        expect(src.contains('.gif?")'), isFalse, reason: '${f.path} 又写了一遍');
      }
    });
  });

  group('媒体 rel：片段必须先剥掉再归一', () {
    test('`#fragment` 不再留在 rel 里', () {
      expect(decodeMediaRel('/media/lib/@a/x.jpg#poster'), 'lib/@a/x.jpg',
          reason: '旧写法只截 `?`，片段留在 rel 里，前缀匹配永远失败');
      expect(decodeMediaRel('/media/lib/@a/x.jpg?t=1#p'), 'lib/@a/x.jpg');
      expect(decodeMediaRel('/media/lib/@a/x.jpg'), 'lib/@a/x.jpg');
    });

    test('反斜杠路径与重复分隔符算同一条 rel（与基础库 rel 同一口径）', () {
      expect(decodeMediaRel(r'/media/lib\@a\VID\x.mp4'), 'lib/@a/VID/x.mp4');
      expect(decodeMediaRel('/media//lib//@a/x.jpg'), 'lib/@a/x.jpg');
      expect(decodeMediaRel('/media/lib/./@a/x.jpg'), 'lib/@a/x.jpg');
    });

    test('库内路径不再带前导斜杠（旧写法 while 循环剥过，保持）', () {
      expect(decodeMediaRel('/media//x.jpg'), 'x.jpg');
    });
  });

  group('头像注册：查询串不算文件名', () {
    test('带缓存参数/片段的 `.avatars` 地址仍能注册到服务端', () {
      final a = serverAvatarFileFromPath('/media/lib-001/.avatars/a.jpg?w=200');
      expect(a?.lib, 'lib-001',
          reason: '旧写法返回 null → 「设置头像」静默退化为只存本机');
      expect(a?.file, 'a.jpg');
      final b = serverAvatarFileFromPath('/media/lib-001/.avatars/a.jpg#v2');
      expect(b?.file, 'a.jpg');
    });

    test('结构不对的地址仍然拒绝（剥后缀不放松路径规则）', () {
      expect(serverAvatarFileFromPath('/media/lib-001/.avatars/a.txt?w=1'),
          isNull);
      expect(
          serverAvatarFileFromPath('/media/lib-001/other/a.jpg?w=1'), isNull);
      expect(serverAvatarFileFromPath('/media/lib-001/.avatars/a.jpg/x?w=1'),
          isNull);
    });
  });

  group('封面指针：版本名与扩展名剥的是同一个后缀', () {
    test('带查询串/片段的版本指针不再变成空串', () {
      expect(normalizeCoverVersion('_cover/v1.png?w=200'), 'v1',
          reason: '旧写法把 `png?w=200` 当扩展名 → 白名单拒绝 → 空串');
      expect(normalizeCoverVersion('_cover/v1.png#x'), 'v1');
      expect(normalizeCoverVersion('v2.webp?w=480'), 'v2');
    });

    test('Windows 风格分隔符仍取末段（走 lastRelName）', () {
      expect(normalizeCoverVersion(r'_cover\v3.png'), 'v3');
      expect(normalizeCoverVersion('_cover/sub/v4.jpg'), 'v4');
    });

    test('同一串在版本与扩展名两处得到同一个扩展名', () {
      expect(coverPointerOf('v1.webp?w=480').version, 'v1');
      expect(coverPointerOf('v1.webp?w=480').ext, 'webp',
          reason: '旧写法扩展名回落 jpg，请求 v1.jpg 而磁盘是 v1.webp，封面 404');
      expect(coverPointerOf('v1.png#p').ext, 'png');
      expect(coverPointerOf('v1').ext, 'jpg');
    });

    test('非法指针在后缀剥除后仍被拒（不放松白名单）', () {
      expect(normalizeCoverVersion('../etc/passwd?w=1'), '');
      expect(normalizeCoverVersion('a b?v=1'), '');
    });
  });

  group('爬虫脚本名：查询串不是文件名的一部分', () {
    test('带参/带片段的脚本名仍落到真实脚本上', () {
      expect(normalizeScriptName('run.py?x=1'), 'run.py',
          reason: '旧写法回落到 `sync.sh`，按钮打到一个不存在的脚本');
      expect(normalizeScriptName('a/b/run.js#f'), 'run.js');
      expect(normalizeScriptName(r'crawler\sync.sh?t=2'), 'sync.sh');
    });

    test('真正的非法名仍然回落默认', () {
      expect(normalizeScriptName(''), 'sync.sh');
      expect(normalizeScriptName('../run.py'), 'run.py');
      expect(normalizeScriptName('.hidden.py'), 'sync.sh');
      expect(normalizeScriptName('a b.py'), 'sync.sh');
    });
  });

  group('头像图片判定走同一条后缀剥除', () {
    test('片段形式的图片地址也认', () {
      expect(isAvatarImagePath('/a.PNG?w=64'), isTrue);
      expect(isAvatarImagePath('/a.jpg#poster'), isTrue);
      expect(isAvatarImagePath('/a.mp4'), isFalse);
      expect(isAvatarImagePath(''), isFalse);
    });
  });

  group('筛选摘要：四个库维度共用一条文案规则', () {
    test('每个维度都输出「标题 名字/名字」，且同名不换位', () {
      final st = AuthorFilterState(
        tops: {'t1', 't2'},
        units: {'u1'},
        basics: {'b1', 'b2'},
        bigs: {'g1'},
        grades: {'S', 'A'},
        types: {workFilterVideo},
      );
      final text = st.summary(
        topNames: {'t1': '甲', 't2': '乙'},
        unitNames: {'u1': '单元'},
        basicNames: {'b1': '库一', 'b2': '库二'},
        bigNames: {'g1': '媒体'},
      );
      // 0.9.313：一级（每个连接的库根）在界面上就叫「媒体库」，旧 `bigs`
      // 维度只剩「历史分组」，不再有「顶级节点」「媒体库（旧分组）」两个
      // 让用户分不清的说法。
      expect(text,
          '媒体库 乙/甲 · 单元库 单元 · 基础库 库一/库二 · 历史分组 媒体 · 等级 S/A · 视频');
      // 五次结果必须逐字相同（旧写法裸 sort，同名之间会换位）
      for (var i = 0; i < 5; i++) {
        expect(
            st.summary(
              topNames: {'t1': '甲', 't2': '乙'},
              unitNames: {'u1': '单元'},
              basicNames: {'b1': '库一', 'b2': '库二'},
              bigNames: {'g1': '媒体'},
            ),
            text);
      }
    });

    test('名字缺失回落 id，空筛选写「未筛选」', () {
      final st = AuthorFilterState(tops: {'zzz'}, units: {'aaa'});
      expect(st.summary(), '媒体库 zzz · 单元库 aaa');
      expect(AuthorFilterState().summary(), '未筛选');
    });
  });

  group('排行榜名次：等键记录不得靠不稳定排序', () {
    test('同一个库 id 出现两次只占一行，名次与入参顺序无关', () {
      final libs = [
        {'id': 'lib-1', 'name': '同名'},
        {'id': 'lib-1', 'name': '同名'},
        {'id': 'lib-2', 'name': '同名'},
      ];
      final stats = {
        'lib-1': {
          'a': {'p': 5},
        },
        'lib-2': {
          'a': {'p': 5},
        },
      };
      for (final list in [libs, libs.reversed.toList()]) {
        final rows =
            buildLibraryRank(libs: list, stats: stats, metric: 'play');
        expect(rows.map((e) => e.id).toList(), ['lib-1', 'lib-2']);
        expect(rows.map((e) => e.rank).toList(), [1, 2]);
      }
    });
  });

  group('契约扫描：后缀剥除只有一处实现', () {
    test('lib/ 内不再出现手写的 `indexOf("?")` + substring 截断', () {
      // 只剩 media_path.stripMediaSuffix 内部那一处（已在该文件里，扫描时跳过）
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('media_path.dart')) continue;
        if (f.path.endsWith('media_resize.dart')) continue; // 内部另有拆分
        final src = _lib(f.path);
        for (final line in src.split('\n')) {
          if (line.contains("indexOf('?')") && line.contains('substring')) {
            fail('${f.path} 手写了一遍查询串截断：${line.trim()}');
          }
        }
      }
    });

    test('isGifMediaPath 是动图判定的唯一定义', () {
      final mp = File('lib/media_path.dart').readAsStringSync();
      expect(RegExp(r'bool isGifMediaPath\(').allMatches(mp).length, 1);
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('media_path.dart')) continue;
        final src = _lib(f.path);
        // 允许转发（isGifPath / isGif getter 各一行），不允许另定义
        expect(RegExp(r'bool isGifMediaPath\(').allMatches(src).length, 0,
            reason: '${f.path} 又定义了一份动图判定');
      }
    });
  });
}
