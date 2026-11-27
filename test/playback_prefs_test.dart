import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/loop_link.dart';
import 'package:shoucangjia/playback_prefs.dart';

/// 播放设置记忆（owner 2026-11-24）。
///
/// 需求原文：「添加设置记忆功能，重进播放界面记住沿用上次的播放设置」。
///
/// 之前 speed / LoopLink / shuffle 只存在播放页内存里，退出就回默认值。
/// 这些测试钉住序列化/反序列化的容错契约。
void main() {
  group('默认值', () {
    test('无记录时是 1.0x / 连播开 / 循环关 / 乱序关', () {
      const d = PlaybackPrefs.defaults;
      expect(d.speed, 1.0);
      expect(d.link.autoplay, isTrue);
      expect(d.link.loopOne, isFalse);
      expect(d.shuffle, isFalse);
    });
  });

  group('序列化往返', () {
    test('自定义设置存下再读回，逐字段一致', () {
      const p = PlaybackPrefs(
        speed: 1.5,
        link: LoopLink(loopOne: true, autoplay: false, restoreAutoplay: true),
        shuffle: true,
      );
      final back = PlaybackPrefs.fromJson(p.toJson());
      expect(back, p);
      expect(back.speed, 1.5);
      expect(back.link.loopOne, isTrue);
      expect(back.link.autoplay, isFalse);
      expect(back.link.restoreAutoplay, isTrue);
      expect(back.shuffle, isTrue);
    });

    test('默认值往返不变', () {
      expect(PlaybackPrefs.fromJson(PlaybackPrefs.defaults.toJson()),
          PlaybackPrefs.defaults);
    });
  });

  group('容错：坏数据只影响自己，不整体失效', () {
    test('非 Map 输入回落默认值', () {
      expect(PlaybackPrefs.fromJson(null), PlaybackPrefs.defaults);
      expect(PlaybackPrefs.fromJson('x'), PlaybackPrefs.defaults);
      expect(PlaybackPrefs.fromJson(<int>[1, 2]), PlaybackPrefs.defaults);
    });

    test('倍速超范围被夹到 0.5–3.0', () {
      expect(PlaybackPrefs.fromJson({'speed': 99.0}).speed, 3.0);
      expect(PlaybackPrefs.fromJson({'speed': 0.01}).speed, 0.5);
      expect(PlaybackPrefs.fromJson({'speed': -5}).speed, 0.5);
    });

    test('倍速是非法值（NaN/字符串）时回落 1.0，其它字段照常恢复', () {
      final p = PlaybackPrefs.fromJson({
        'speed': 'fast',
        'shuffle': true,
      });
      expect(p.speed, 1.0);
      expect(p.shuffle, isTrue, reason: '坏倍速不该连累乱序开关');
    });

    test('布尔字段类型不对时用默认值', () {
      final p = PlaybackPrefs.fromJson({
        'loopOne': 'yes',
        'autoplay': 1,
        'shuffle': null,
      });
      expect(p.link.loopOne, isFalse);
      expect(p.link.autoplay, isTrue);
      expect(p.shuffle, isFalse);
    });

    test('restoreAutoplay 缺失时跟随 autoplay（不猜成 false）', () {
      final p = PlaybackPrefs.fromJson({'autoplay': false});
      expect(p.link.autoplay, isFalse);
      expect(p.link.restoreAutoplay, isFalse,
          reason: '缺失的记忆值应等于当前连播状态');
    });
  });

  group('与播放页语义对齐', () {
    test('循环开启时连播实际不调度下一条', () {
      const p = PlaybackPrefs(
        link: LoopLink(loopOne: true, autoplay: true),
      );
      expect(p.link.nextEnabled, isFalse);
    });

    test('循环关闭且连播开启时才调度下一条', () {
      const p = PlaybackPrefs(link: LoopLink(autoplay: true));
      expect(p.link.nextEnabled, isTrue);
    });
  });

  // owner 2026-11-26：「每次退出播放或退出软件后播放设置要沿用上次退出时的啊，
  // 为什么没有记忆功能」。
  //
  // 排查结论：`PlaybackPrefs` 本身是对的，坏在两条链路上——
  //   1. 只有「用户点了某个开关」才落盘，**退出播放页时不保存**。没动过的
  //      值从来没被记下，退出软件后自然回到默认。
  //   2. 恢复是 `unawaited(...)`，与 postFrame 里的 `open()` 赛跑；恢复晚到
  //      时播放器已按默认倍速起播，看起来就是「没记住」。
  group('契约：退出落盘 + 起播前等恢复（0.9.303）', () {
    String code() {
      final src = File('lib/main.dart').readAsStringSync().replaceAll('\r\n', '\n');
      final start = src.indexOf('class _PlayerPageState');
      expect(start, greaterThan(0), reason: '找不到 _PlayerPageState');
      return src.substring(start);
    }

    test('退出播放页时必须落盘播放设置', () {
      final body = code();
      final disp = body.indexOf('void dispose()');
      expect(disp, greaterThan(0), reason: '找不到播放页 dispose');
      // 取 dispose 之后的一段（足够覆盖落盘调用）。
      final tail = body.substring(disp, disp + 2500);
      expect(tail.contains('_persistPlaybackPrefs()'), isTrue,
          reason: '退出播放页不落盘设置 → 没动过的值永远记不住');
    });

    test('起播前必须等设置读回（不能与 open 赛跑）', () {
      final body = code();
      expect(body.contains('_prefsReady'), isTrue,
          reason: '缺少读盘完成信号，open 会抢在恢复之前起播');
      // open 必须包在 ready.then 里
      final idx = body.indexOf('_prefsReady');
      expect(idx, greaterThan(0));
      expect(body.contains('ready.then('), isTrue,
          reason: 'open() 必须在设置读回之后再执行');
    });
  });
}
