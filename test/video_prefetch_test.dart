import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/video_prefetch.dart';

void main() {
  group('videoPrefetchTargets', () {
    test('前后相邻视频各取一条，最多 2 条，方向优先', () {
      final out = videoPrefetchTargets(
        index: 3,
        count: 8,
        isVideo: (_) => true,
        mediaPath: (i) => 'v$i.mp4',
      );
      expect(out.map((e) => e.index).toList(), <int>[4, 2]);
      expect(out.map((e) => e.path).toList(), <String>['v4.mp4', 'v2.mp4']);
    });

    test('向上滑动时先取上一条', () {
      final out = videoPrefetchTargets(
        index: 3,
        count: 8,
        isVideo: (_) => true,
        mediaPath: (i) => 'v$i.mp4',
        direction: -1,
      );
      expect(out.map((e) => e.index).toList(), <int>[2, 4]);
    });

    test('跳过图片/图文/空路径，并继续向外找', () {
      final v = <int>{1, 5, 7};
      final out = videoPrefetchTargets(
        index: 3,
        count: 10,
        isVideo: (i) => v.contains(i),
        mediaPath: (i) => v.contains(i) ? 'v$i.mp4' : 'p$i.jpg',
        perSide: 4,
      );
      expect(out.map((e) => e.index).toList(), <int>[5, 1]);
    });

    test('空路径不算目标', () {
      final out = videoPrefetchTargets(
        index: 2,
        count: 5,
        isVideo: (_) => true,
        mediaPath: (i) => i == 1 ? '' : 'v$i.mp4',
      );
      // 距离 1 的 1 为空被跳过；距离 2 先取方向侧 4（3 已在距离 1 拿到）。
      expect(out.map((e) => e.index).toList(), <int>[3, 4]);
    });

    test('边界与单条列表返回空', () {
      expect(
        videoPrefetchTargets(
          index: 0,
          count: 1,
          isVideo: (_) => true,
          mediaPath: (i) => 'v$i.mp4',
        ),
        isEmpty,
      );
      expect(
        videoPrefetchTargets(
          index: -1,
          count: 5,
          isVideo: (_) => true,
          mediaPath: (i) => 'v$i.mp4',
        ),
        isEmpty,
      );
      expect(
        videoPrefetchTargets(
          index: 9,
          count: 5,
          isVideo: (_) => true,
          mediaPath: (i) => 'v$i.mp4',
        ),
        isEmpty,
      );
    });

    test('maxTargets 可限制为 1 条', () {
      final out = videoPrefetchTargets(
        index: 3,
        count: 8,
        isVideo: (_) => true,
        mediaPath: (i) => 'v$i.mp4',
        maxTargets: 1,
      );
      expect(out.length, 1);
      expect(out.first.index, 4);
    });

    test('perSide=0 不预取', () {
      expect(
        videoPrefetchTargets(
          index: 3,
          count: 8,
          isVideo: (_) => true,
          mediaPath: (i) => 'v$i.mp4',
          perSide: 0,
        ),
        isEmpty,
      );
    });
  });

  group('shouldRunVideoPrefetch', () {
    test('视频且不缓冲、不加载、非弱网时运行', () {
      expect(
        shouldRunVideoPrefetch(
          isVideo: true,
          buffering: false,
          slowBuffer: false,
          loading: false,
          enabled: true,
          count: 3,
        ),
        isTrue,
      );
    });

    test('非视频/缓冲/弱网/加载中/关闭/单条都跳过', () {
      bool run({
        bool isVideo = true,
        bool buffering = false,
        bool slowBuffer = false,
        bool loading = false,
        bool enabled = true,
        int count = 3,
      }) =>
          shouldRunVideoPrefetch(
            isVideo: isVideo,
            buffering: buffering,
            slowBuffer: slowBuffer,
            loading: loading,
            enabled: enabled,
            count: count,
          );
      expect(run(isVideo: false), isFalse);
      expect(run(buffering: true), isFalse);
      expect(run(slowBuffer: true), isFalse);
      expect(run(loading: true), isFalse);
      expect(run(enabled: false), isFalse);
      expect(run(count: 1), isFalse);
    });
  });

  group('VideoPrefetcher', () {
    test('串行执行，并发不超过 1，成功计数', () async {
      var active = 0;
      var maxActive = 0;
      final order = <String>[];
      final fetcher = VideoPrefetcher(
        fetch: (t) async {
          active++;
          maxActive = maxActive < active ? active : maxActive;
          order.add(t.key);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          active--;
          return true;
        },
      );
      fetcher.start(<VideoPrefetchTask>[
        VideoPrefetchTask(url: 'http://nas/1.mp4', key: '1'),
        VideoPrefetchTask(url: 'http://nas/2.mp4', key: '2'),
        VideoPrefetchTask(url: 'http://nas/3.mp4', key: '3'),
      ]);
      for (var i = 0; i < 100 && fetcher.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(fetcher.busy, isFalse);
      expect(maxActive, 1);
      expect(order, <String>['1', '2', '3']);
      expect(fetcher.stats.started, 3);
      expect(fetcher.stats.loaded, 3);
      expect(fetcher.stats.failed, 0);
      fetcher.dispose();
    });

    test('失败静默且继续下一条', () async {
      final seen = <String>[];
      final fetcher = VideoPrefetcher(
        fetch: (t) async {
          seen.add(t.key);
          return t.key != 'bad';
        },
      );
      fetcher.start(<VideoPrefetchTask>[
        VideoPrefetchTask(url: 'http://nas/bad.mp4', key: 'bad'),
        VideoPrefetchTask(url: 'http://nas/ok.mp4', key: 'ok'),
      ]);
      for (var i = 0; i < 100 && fetcher.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(seen, <String>['bad', 'ok']);
      expect(fetcher.stats.failed, 1);
      expect(fetcher.stats.loaded, 1);
      fetcher.dispose();
    });

    test('cancel 清空队列并丢弃在途结果', () async {
      final gate = Completer<void>();
      final started = <String>[];
      final fetcher = VideoPrefetcher(
        fetch: (t) async {
          started.add(t.key);
          await gate.future;
          return true;
        },
      );
      fetcher.start(<VideoPrefetchTask>[
        VideoPrefetchTask(url: 'http://nas/1.mp4', key: '1'),
        VideoPrefetchTask(url: 'http://nas/2.mp4', key: '2'),
        VideoPrefetchTask(url: 'http://nas/3.mp4', key: '3'),
      ]);
      while (started.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(fetcher.pending, 2);
      fetcher.cancel();
      expect(fetcher.pending, 0);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(started, <String>['1']);
      expect(fetcher.stats.loaded, 0);
      expect(fetcher.stats.canceled, greaterThanOrEqualTo(1));
      fetcher.dispose();
    });

    test('新一批任务替换旧批次，旧结果不再计数', () async {
      final first = Completer<void>();
      final started = <String>[];
      final fetcher = VideoPrefetcher(
        fetch: (t) async {
          started.add(t.key);
          if (t.key == 'old') await first.future;
          return true;
        },
      );
      fetcher.start(<VideoPrefetchTask>[
        VideoPrefetchTask(url: 'http://nas/old.mp4', key: 'old'),
      ]);
      while (started.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fetcher.start(<VideoPrefetchTask>[
        VideoPrefetchTask(url: 'http://nas/new.mp4', key: 'new'),
      ]);
      first.complete();
      for (var i = 0; i < 100 && fetcher.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(started, <String>['old', 'new']);
      expect(fetcher.stats.loaded, 1);
      expect(fetcher.stats.canceled, greaterThanOrEqualTo(1));
      fetcher.dispose();
    });

    test('默认实现发送 Range 与鉴权头，读完窗口后停止', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      String? range;
      String? auth;
      final got = Completer<void>();
      server.listen((req) {
        range = req.headers.value(HttpHeaders.rangeHeader);
        auth = req.headers.value(HttpHeaders.authorizationHeader);
        req.response.statusCode = HttpStatus.partialContent;
        req.response.add(List<int>.filled(64, 7));
        req.response.close();
        if (!got.isCompleted) got.complete();
      });
      final fetcher = VideoPrefetcher(rangeBytes: 16);
      fetcher.start(<VideoPrefetchTask>[
        VideoPrefetchTask(
          url: 'http://127.0.0.1:${server.port}/a.mp4',
          headers: <String, String>{'Authorization': 'Basic dGVzdDp0ZXN0'},
        ),
      ]);
      for (var i = 0; i < 200 && fetcher.busy; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await got.future.timeout(const Duration(seconds: 2));
      expect(range, 'bytes=0-15');
      expect(auth, 'Basic dGVzdDp0ZXN0');
      expect(fetcher.stats.loaded, 1);
      fetcher.dispose();
      await server.close(force: true);
    });
  });
}
