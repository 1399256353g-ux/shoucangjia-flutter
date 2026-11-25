// 第三十七批契约：地址归一 / 时间年份 / 保存扩展名 / 整数饱和。
//
// 四条都是「实测能跑出错结果」的口径问题，不是风格问题：
//   1. `normalizeBase('http://')` -> `http://http:`，host 被解析成 `http`；
//      大写协议 `HTTP://NAS:8090` 同样被当成无协议再补一次。
//   2. `DateTime.tryParse('999999-01-01T00:00:00Z')` 不返回 null，而是
//      静默回绕成公元前 169110 年（毫秒 -5.4e15，仍在 kMaxEpochMs 内）。
//   3. `mediaSaveExtension` 取「最后一个点」，目录名带点时得到 `.11/x`。
//   4. int64 上 `max + max = -2`、`max * 10 = -10`，等级与排行直接变负。
import 'dart:io';
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/author_grade.dart';
import 'package:shoucangjia/deleted_monitor.dart';
import 'package:shoucangjia/json_num.dart';
import 'package:shoucangjia/library_rank.dart';
import 'package:shoucangjia/multi_server.dart';
import 'package:shoucangjia/pic_zoom.dart';
import 'package:shoucangjia/player_controls.dart';
import 'package:shoucangjia/resize_cache_api.dart';
import 'package:shoucangjia/start_fade.dart';
import 'package:shoucangjia/time_labels.dart';

const int _intMax = 9223372036854775807;

void main() {
  group('normalizeBase：不合格地址归一为空串，不产出假地址', () {
    test('正常输入', () {
      expect(normalizeBase('192.168.2.4:8090'), 'http://192.168.2.4:8090');
      expect(normalizeBase(' 192.168.2.4:8090/ '), 'http://192.168.2.4:8090');
      expect(normalizeBase('https://a.b/'), 'https://a.b');
      expect(normalizeBase('http://a.b//'), 'http://a.b');
      expect(normalizeBase('nas.local:8443'), 'http://nas.local:8443');
    });

    test('大写协议不再被当成「没有协议」', () {
      // 旧实现：'http://HTTP://NAS:8090'，host 解析成 'http'。
      expect(normalizeBase('HTTP://NAS:8090'), 'http://NAS:8090');
      expect(normalizeBase('Http://a.b'), 'http://a.b');
      expect(normalizeBase('HTTPS://nas:8443/'), 'https://nas:8443');
    });

    test('只有协议/斜杠时返回空串（旧实现给出 http://http:）', () {
      expect(normalizeBase('http://'), '');
      expect(normalizeBase('http:///'), '');
      expect(normalizeBase('https://'), '');
      expect(normalizeBase('   '), '');
      expect(normalizeBase(''), '');
    });

    test('非 http(s) 协议不猜着改写', () {
      expect(normalizeBase('ftp://a.b'), '');
      expect(normalizeBase('file:///x'), '');
    });

    test('归一结果一定能被 Uri 解析出 host', () {
      for (final raw in const [
        '192.168.2.4:8090',
        'HTTP://NAS:8090',
        'https://a.b/',
        '  nas:1  ',
      ]) {
        final b = normalizeBase(raw);
        expect(b, isNotEmpty, reason: raw);
        expect(Uri.parse(b).host, isNotEmpty, reason: raw);
      }
    });
  });

  group('时间：6 位年份越界不再静默回绕', () {
    test('dateTimeOfIso 挡住回绕值', () {
      // 实测 DateTime.tryParse 返回 -169110-11-25，而不是 null。
      expect(DateTime.tryParse('999999-01-01T00:00:00Z'), isNotNull);
      expect(dateTimeOfIso('999999-01-01T00:00:00Z'), isNull);
      expect(msFromIso('999999-01-01T00:00:00Z'), 0);
    });

    test('正常年份照常解析', () {
      expect(msFromIso('2026-11-25T00:00:00Z'),
          DateTime.utc(2026, 11, 25).millisecondsSinceEpoch);
      expect(monthDayTimeOfIso('2026-11-25T04:05:00Z', fallback: 'X'),
          isNot('X'));
      expect(monthDayTimeOfIso('garbage', fallback: 'X'), 'X');
    });

    test('删除记录的时间不再拿回绕值参与排序', () {
      DeletedEntry e(String at) => DeletedEntry(
            at: at,
            author: '',
            date: '',
            title: '',
            workId: 'w',
            collection: '',
            link: '',
            cover: '',
          );
      expect(e('999999-01-01T00:00:00Z').atMs, 0);
      expect(e('2026-11-25T00:00:00Z').atMs,
          DateTime.utc(2026, 11, 25).millisecondsSinceEpoch);
      // 批次键也必须按「解析不出」处理，不能让同一批被拆成赛博年份分组。
      expect(syncKeyOf('999999-01-01T00:00:00Z'), '999999-01-01T00:00:00Z');
    });

    test('契约扫描：lib/ 内不再有裸 DateTime.tryParse 取毫秒', () {
      const banned = 'millisecondsSinceEpoch ?? 0';
      // 允许出现的只剩 time_labels 自己的实现。
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final src = _read(f);
        for (final line in src.split('\n')) {
          if (!line.contains('DateTime.tryParse')) continue;
          if (line.contains(banned)) offenders.add(f);
        }
      }
      expect(offenders, isEmpty, reason: '走 dateTimeOfIso / msFromIso');
    });
  });

  group('保存文件名：目录名带点也不能拆出分隔符', () {
    test('扩展名只取最后一段文件名', () {
      // 旧实现：'.11/x' —— 文件名里出现 `/`。
      expect(mediaSaveExtension(url: 'http://h/media/lib-1/2026.11/x'),
          '.mp4');
      expect(mediaSaveExtension(url: 'http://h/media/lib-1/a.b/作品', video: false),
          '.jpg');
    });

    test('正常扩展名照旧', () {
      expect(mediaSaveExtension(url: 'http://h/a/b.mp4'), '.mp4');
      expect(mediaSaveExtension(url: 'http://h/a/b.MOV'), '.mov');
      expect(mediaSaveExtension(url: 'http://h/a/b.webp', video: false), '.webp');
    });

    test('任何输入得到的扩展名都不含分隔符', () {
      for (final u in const [
        'http://h/media/lib-1/2026.11/x',
        'http://h/a/b.',
        'http://h/a.b/c.d/e',
        'http://h/a/b. m p',
        'http://h/apithumb/lib/id',
      ]) {
        final ext = mediaSaveExtension(url: u);
        expect(ext, startsWith('.'));
        expect(ext.contains('/'), isFalse, reason: u);
        expect(ext.contains('.'), isTrue);
      }
    });
  });

  group('浮点 NaN 不把「未知」当成「最大」', () {
    test('淡入音量：NaN/Infinity 不再变成满音量', () {
      // `NaN.clamp(0,100)` 实测返回 100.0，旧实现直接淡入到最大声。
      expect(double.nan.clamp(0.0, 100.0), 100.0);
      expect(fadeInSteps(double.nan), isEmpty);
      expect(fadeInSteps(double.infinity), isEmpty);
      expect(fadeInSteps(double.negativeInfinity), isEmpty);
      expect(fadeInSteps(80, steps: 2), [40.0, 80.0]);
    });

    test('图片缩放：NaN 尺寸/锤点不产生 NaN 偏移', () {
      const z = PicZoom(scale: 2, offset: Offset(10, 10));
      final out = z.clamped(const Size(double.nan, double.nan));
      expect(out.scale, 2);
      expect(out.offset.dx.isFinite, isTrue);
      expect(out.offset.dy.isFinite, isTrue);
      expect(out.offset, Offset.zero);

      final out2 =
          z.scaleTo(2.5, const Offset(double.nan, 4), const Size(300, 200));
      expect(out2.offset.dx.isFinite, isTrue);
      expect(out2.offset.dy.isFinite, isTrue);

      final inf = z.clamped(const Size(double.infinity, 200));
      expect(inf.offset.dx.isFinite, isTrue);
    });

    test('缓存占用：坏 bytes 不再显示 0%', () {
      // 旧实现：max*100 -> -100 -> 0%。
      final s = ResizeCacheStats.fromJson({
        'bytes': _intMax,
        'maxBytes': _intMax,
      })!;
      expect(s.usedPercent, 100);

      final half = ResizeCacheStats.fromJson({'bytes': 50, 'maxBytes': 100})!;
      expect(half.usedPercent, 50);

      final neg = ResizeCacheStats.fromJson({'bytes': -5, 'maxBytes': 100})!;
      expect(neg.usedPercent, 0);
    });

    test('命中率：坏计数不让比例变负或超 100%', () {
      final s = ResizeCacheStats.fromJson({'hit': _intMax, 'miss': _intMax})!;
      expect(s.hitRate.isFinite, isTrue);
      expect(s.hitRate, inInclusiveRange(0.0, 1.0));
      expect(s.hitRate, closeTo(0.5, 1e-9));
    });
  });

  group('整数饱和：int64 回绕不再把计数变负', () {
    test('addSat 四周界', () {
      expect(addSat(1, 2), 3);
      expect(addSat(_intMax, 1), _intMax);
      expect(addSat(_intMax, _intMax), _intMax);
      expect(addSat(-_intMax, -_intMax), -9223372036854775808);
      expect(addSat(5, -3), 2);
    });

    test('mulSat 不溢出', () {
      expect(mulSat(3, 4), 12);
      expect(mulSat(_intMax, 10), _intMax);
      expect(mulSat(_intMax, _intMax), _intMax);
      expect(mulSat(0, _intMax), 0);
    });

    test('作者等级分数不因坏计数变负', () {
      // 旧实现：max * 10 -> -10，等级掉到 D。
      expect(AuthorGrade.score(plays: _intMax), greaterThanOrEqualTo(0));
      expect(AuthorGrade.gradeFor(plays: _intMax), 'S');
      expect(AuthorGrade.score(plays: _intMax, drops: _intMax), greaterThan(0));
    });

    test('库排行合计不因坏计数变负', () {
      final t = libraryTotals({
        'a': {'p': _intMax, 'dr': _intMax},
        'b': {'p': _intMax, 'dr': 1},
      });
      expect(t.plays, _intMax);
      expect(t.drops, _intMax);
      expect(t.plays < 0, isFalse);

      final rows = buildLibraryRank(
        libs: [
          {'id': 'x', 'name': 'X'},
          {'id': 'y', 'name': 'Y'},
        ],
        stats: {
          'x': {
            'a': {'p': _intMax, 'dr': 0},
          },
          'y': {
            'a': {'p': 10, 'dr': 0},
          },
        },
        metric: 'play',
      );
      expect(rows.first.id, 'x');
      expect(rows.every((r) => r.plays >= 0), isTrue);
    });
  });
}

// --- 契约扫描辅助（只读 lib/ 文本，不碰任何媒体数据） ---

List<String> _libFiles() {
  final dir = Directory('lib');
  if (!dir.existsSync()) return const <String>[];
  return <String>[
    for (final e in dir.listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e.path,
  ];
}

String _read(String path) => File(path).readAsStringSync();
