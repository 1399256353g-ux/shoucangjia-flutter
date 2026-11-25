/// 第五十五批契约：**规则本身对了，但调用点里还留着一份更窄的抄写**。
///
/// 第五十四批收口的是「后缀剥除只做了一半」；这一批是同一个模式再往下一层：
/// 公共出口已经存在、而且是对的，个别调用点却**自己又判了一遍**，判得比公共
/// 出口窄。窄的那一份在正常输入下永远看不出问题，只在「大写协议」「带查询
/// 串的扩展名」「解析不了的 URL」这类真实输入上翻车。
///
/// 本批修掉的四处（修复前实测）：
///
///  1. `isAbsoluteMediaUrl('HTTP://nas/x.jpg')` → **false**（配置层
///     `normalizeBase` 早已认大写协议）。后果：
///     `libraryMediaPath('lib', 'HTTP://nas/x.jpg')` →
///     `/media/lib/HTTP://nas/x.jpg`，服务端把 `HTTP:` 当库内子目录，封面 404。
///  2. `normalizeCoverExt('png?w=1')` → **`jpg`**（`cover_ext` 里没有归一函数，
///     `lib_cover` 与 `cover_history` 各写一份窄的，都不剥后缀、不取末段）。
///     请求 `v1.jpg`、磁盘是 `v1.png` → 封面 404。
///  3. `mediaSaveExtension(url: 'http://[::1/a.png#t=3')` → **`.jpg`**
///     （`Uri.tryParse` 返回 null 时回落到整串 URL，末段带 `#t=3`）。
///     一张 png 被存成 `.jpg`，双击打不开。
///  4. `ServerConn`/脚本名：`looksRunnable` 只 `endsWith('.sh')`，与
///     `normalizeScriptName` 的「先剥后缀再取末段」不是同一条规则。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_avatar_store.dart';
import 'package:shoucangjia/cover_history.dart';
import 'package:shoucangjia/lib_cover.dart';
import 'package:shoucangjia/media_path.dart';
import 'package:shoucangjia/media_resize.dart';
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/unit_crawler.dart';

/// 只保留非注释行，避免文档里的「旧写法」被契约扫描当成现役代码。
String _lib(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///');
    })
    .join('\n');

void main() {
  group('绝对地址判定：协议忽略大小写（唯一出口）', () {
    test('大写/混合大小写协议都算绝对地址', () {
      expect(isAbsoluteMediaUrl('http://nas/x.jpg'), isTrue);
      expect(isAbsoluteMediaUrl('https://nas/x.jpg'), isTrue);
      expect(isAbsoluteMediaUrl('HTTP://NAS/x.jpg'), isTrue);
      expect(isAbsoluteMediaUrl('Https://nas/x.jpg'), isTrue);
      expect(isAbsoluteMediaUrl('  HTTPS://nas/x.jpg  '), isTrue);
    });

    test('相对路径、接口地址、别的协议都不是绝对媒体地址', () {
      expect(isAbsoluteMediaUrl('/media/lib/a.jpg'), isFalse);
      expect(isAbsoluteMediaUrl('_cover/v1.jpg'), isFalse);
      expect(isAbsoluteMediaUrl('/api/thumb/lib/1'), isFalse);
      expect(isAbsoluteMediaUrl('ftp://nas/a.jpg'), isFalse);
      expect(isAbsoluteMediaUrl(''), isFalse);
    });

    test('库卡片封面套前缀时不再把大写绝地地址当相对路径', () {
      // 修复前：'/media/lib/HTTP://nas/x.jpg'（必然 404）
      expect(libraryMediaPath('lib', 'HTTP://nas/x.jpg'), 'HTTP://nas/x.jpg');
      expect(libraryMediaPath('lib', 'https://cdn/x.jpg'), 'https://cdn/x.jpg');
      // 相对路径的补前缀规则不变
      expect(libraryMediaPath('lib', 'a/b.jpg'), '/media/lib/a/b.jpg');
      // 绝对地址也不再被 encodeMediaPath 转义（`?` 保持是查询串）
      expect(
        absoluteMediaUrl('http://nas:8090', lib: 'lib', path: 'HTTP://nas/x.jpg?w=1'),
        'HTTP://nas/x.jpg?w=1',
      );
    });

    test('缩图参数：大写协议的图片也会被加上 w=', () {
      expect(withImageWidth('HTTP://nas/x.jpg', 480), 'HTTP://nas/x.jpg?w=480');
      expect(withImageWidth('HTTPS://nas/x.jpg', 480), 'HTTPS://nas/x.jpg?w=480');
      // 相对路径行为不变
      expect(withImageWidth('/media/a/b.jpg', 480), '/media/a/b.jpg?w=480');
      // 非图片 / 非 http 一律原样
      expect(withImageWidth('asset:x.jpg', 480), 'asset:x.jpg');
    });

    test('头像覆盖表不再静默丢弃大写协议的地址', () {
      // 修复前：encodeAuthorAvatarOverrides({'a': 'HTTP://nas/x.jpg'}) == {}
      final a = encodeAuthorAvatarOverrides({'a': 'HTTP://nas/x.jpg'});
      expect(a, contains('HTTP://nas/x.jpg'));
      expect(parseAuthorAvatarOverrides(a)['a'], 'HTTP://nas/x.jpg');
      // 非法值仍然拒绝
      expect(encodeAuthorAvatarOverrides({'a': 'nas/x.jpg'}), '{}');
      expect(encodeAuthorAvatarOverrides({'a': ''}), '{}');
    });

    test('契约扫描：不得再出现自己写的小写协议前缀判定', () {
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        // media_path.dart 是唯一定义本身
        if (f.path.endsWith('media_path.dart')) continue;
        final src = _lib(f.path);
        expect(src.contains("startsWith('http://') ||"), isFalse,
            reason: '${f.path} 自己又写了一遍绝对地址判定，应转发 isAbsoluteMediaUrl');
        expect(src.contains('startsWith(\'https://\')'), isFalse,
            reason: '${f.path} 自己又写了一遍绝对地址判定，应转发 isAbsoluteMediaUrl');
      }
    });
  });

  group('封面扩展名归一（唯一定义在 cover_ext）', () {
    test('剥查询串/片段、取末段、去点、小写', () {
      expect(normalizeCoverExt('png?w=1'), 'png');
      expect(normalizeCoverExt('png#x'), 'png');
      expect(normalizeCoverExt('.webp'), 'webp');
      expect(normalizeCoverExt('PNG'), 'png');
      expect(normalizeCoverExt('_cover/v3.PNG?w=480'), 'png');
      expect(normalizeCoverExt(r'_cover\v4.webp'), 'webp');
    });

    test('白名单外一律回落 jpg（不猜）', () {
      expect(normalizeCoverExt('gif'), 'jpg');
      expect(normalizeCoverExt('mp4'), 'jpg');
      expect(normalizeCoverExt(''), 'jpg');
      expect(normalizeCoverExt('mp4'), 'jpg');
      expect(normalizeCoverExt('png?w=abc.jpg'), 'png');
    });

    test('lib_cover 与 cover_history 是同一份规则', () {
      // 修复前：coverVersionFromJson({'e': 'png?w=1'}).ext == 'jpg'
      expect(coverVersionFromJson({'v': 'v1', 'e': 'png?w=1'})!.ext, 'png');
      expect(coverVersionFromJson({'v': 'v1', 'e': '.WEBP#x'})!.ext, 'webp');
      expect(normalizeCoverExt('png'), 'png');
      // 与封面指针同一串、同一个扩展名
      final p = coverPointerOf('v1.webp?w=480');
      expect(p.ext, 'webp');
      expect(p.version, 'v1');
    });

    test('契约扫描：扩展名归一只有一份实现', () {
      final ce = _lib('lib/cover_ext.dart');
      expect(ce.contains('String normalizeCoverExt('), isTrue);
      expect(ce.contains('contains(e) ? e : \'jpg\''), isTrue);
      // 另外两处只能转发
      final lc = _lib('lib/lib_cover.dart');
      expect(lc.contains('normalizeCoverExt'), isTrue);
      expect(lc.contains("export 'cover_ext.dart'"), isTrue);
      final ch = _lib('lib/cover_history.dart');
      expect(ch.contains('normalizeCoverExt('), isTrue);
      // 旧的两份窄写法不得复活
      expect(lc.contains("replaceFirst('.', '')"), isFalse);
      expect(ch.contains("if (e.startsWith('.'))"), isFalse);
      expect(ch.contains('_kCoverVersionName'), isFalse);
    });
  });

  group('封面版本名：写入截断 / 读取拒绝（同一份白名单）', () {
    test('写入侧沿用旧口径：超长截到 40', () {
      final long = 'a' * 45;
      expect(normalizeCoverVersion(long).length, 40);
      expect(normalizeCoverVersion('v1.png?w=200'), 'v1');
      expect(normalizeCoverVersion('..'), '');
      // 带目录的写法只取末段（`_cover/v1.png` 也是这么进来的），不整串拒绝
      expect(normalizeCoverVersion('_cover/v1.png'), 'v1');
    });

    test('读取侧不截断：超长版本名按非法处理，不指向不存在的文件', () {
      final long = 'a' * 45;
      expect(normalizeCoverVersionName(long, clip: false), '');
      expect(coverVersionFromJson({'v': long}), isNull);
      // 40 字仍合法
      expect(coverVersionFromJson({'v': 'a' * 40})!.version.length, 40);
    });
  });

  group('保存文件名：解析不了的地址也要保住真实扩展名', () {
    test('坏 URL 不再把 #t=3 当成扩展名而回落 .jpg', () {
      // Uri.tryParse 返回 null 的两种真实输入
      expect(mediaSaveExtension(url: 'http://[::1/a.png#t=3', video: false),
          '.png');
      expect(mediaSaveExtension(url: 'http://nas:port/a.webp'), '.webp');
      expect(mediaSaveFileName(base: 'x', url: 'http://[::1/a.png#t=3', video: false),
          'x.png');
    });

    test('正常地址与目录名带点的情况不变', () {
      expect(mediaSaveExtension(url: 'http://h/lib-1/2026.11/x'), '.mp4');
      expect(mediaSaveExtension(url: '/a/b.MP4#t=3'), '.mp4');
      expect(mediaSaveExtension(url: '/a/b.jpg?x=1', video: false), '.jpg');
      expect(mediaSaveExtension(url: '', video: false), '.jpg');
    });

    test('契约扫描：不许再用 Uri.tryParse(...)?.path ?? url', () {
      final pc = _lib('lib/player_controls.dart');
      expect(pc.contains('Uri.tryParse(url)?.path ?? url'), isFalse);
      expect(pc.contains('lastRelName(stripMediaSuffix(url))'), isTrue);
    });
  });

  group('脚本可运行判定与脚本名归一同一套规则', () {
    test('带查询串/反斜杠的名字仍能判出可运行', () {
      expect(UnitCrawlerScript(name: 'run.py').looksRunnable, isTrue);
      expect(UnitCrawlerScript(name: 'run.py?t=2').looksRunnable, isTrue);
      expect(UnitCrawlerScript(name: r'crawler\run.sh').looksRunnable, isTrue);
      expect(UnitCrawlerScript(name: 'readme.md').looksRunnable, isFalse);
      expect(UnitCrawlerScript(name: 'run.py.bak').looksRunnable, isFalse);
    });

    test('脚本名归一：先剥后缀再取末段', () {
      expect(normalizeScriptName('run.py?x=1'), 'run.py');
      expect(normalizeScriptName(r'crawler\run.py#frag'), 'run.py');
      // 目录穿越在取末段这一步被抹平（`../x.py` → `x.py`），不在末尾的 `..`
      // 也拦不住——与 `serverAvatarFileFromPath` 的路径结构校验同一条原则。
      expect(normalizeScriptName('../x.py'), 'x.py');
      expect(normalizeScriptName('crawler/'), 'sync.sh');
    });
  });
}
