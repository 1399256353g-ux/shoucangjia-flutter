import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/work_forms.dart';

Map<String, dynamic> _ch(int i, String path) => {
      'ti': '第 $i 集',
      'm': [path],
      'du': 10.0 + i,
    };

void main() {
  group('workChapters', () {
    test('解析章节列表并忽略坏数据', () {
      final w = {
        'ch': [
          {'ti': 'a', 'm': ['/a.mp4']},
          'bad',
          {'ti': 'b', 'm': ['/b.mp4']},
        ],
      };
      final chs = workChapters(w);
      expect(chs.length, 2);
      expect(chs[1]['ti'], 'b');
      expect(workChapterCount(w), 2);
      expect(workChapters(null), isEmpty);
      expect(workChapters({'ch': 'x'}), isEmpty);
    });
  });

  group('workKind / workTypeLabel', () {
    test('按 kind 字段优先', () {
      expect(workKind({'kind': 'chapters', 't': 'v'}), 'chapters');
      expect(workKind({'kind': 'album', 't': 'p'}), 'album');
    });

    test('旧数据缺 kind 时按 t 与数量推断', () {
      expect(workKind({'t': 'v', 'm': ['/1.mp4']}), 'single');
      expect(
          workKind({
            't': 'v',
            'ch': [_ch(0, '/0.mp4'), _ch(1, '/1.mp4')]
          }),
          'chapters');
      expect(workKind({'t': 'p', 'm': ['/1.jpg']}), 'single');
      expect(workKind({'t': 'p', 'm': ['/1.jpg', '/2.jpg']}), 'post');
    });

    test('标签覆盖四类形态', () {
      expect(workTypeLabel({'kind': 'chapters', 't': 'v'}), '合集');
      expect(workTypeLabel({'kind': 'album', 't': 'p'}), '图片');
      expect(workTypeLabel({'kind': 'post', 't': 'p'}), '图文');
      expect(workTypeLabel({'kind': 'single', 't': 'v'}), '视频');
      expect(workTypeLabel({'kind': 'single', 't': 'p'}), '图片');
    });
  });

  group('chapterLabel', () {
    test('优先标题，缺失回退集号', () {
      expect(chapterLabel({'ti': '正片'}, 0), '正片');
      expect(chapterLabel({'ti': ''}, 2), '第 3 集');
      expect(chapterLabel(null, 1), '第 2 集');
    });
  });

  group('workWithChapter', () {
    test('切换章节替换 m/du 并标记 c', () {
      final w = {
        'id': 'g1',
        't': 'v',
        'kind': 'chapters',
        'm': ['/0.mp4'],
        'du': 10,
        'ch': [_ch(0, '/0.mp4'), _ch(1, '/1.mp4'), _ch(2, '/2.mp4')],
      };
      final w2 = workWithChapter(w, 1);
      expect(w2['m'], ['/1.mp4']);
      expect(w2['du'], 11.0);
      expect(w2['c'], 1);
      expect(w['m'], ['/0.mp4'], reason: '不得修改原 Map');
      final w9 = workWithChapter(w, 9);
      expect(w9['c'], 2, reason: '越界夹紧');
    });

    test('非合集原样返回', () {
      final w = {'t': 'v', 'm': ['/x.mp4'], 'id': 'x'};
      expect(workWithChapter(w, 3)['m'], ['/x.mp4']);
    });
  });

  group('workWatchKeyFor', () {
    test('合集按章节区分，单条保持原键', () {
      final chs = {
        'id': 'g1',
        'ch': [_ch(0, '/0.mp4'), _ch(1, '/1.mp4')]
      };
      expect(workWatchKeyFor(chs, 0), 'g1#c1');
      expect(workWatchKeyFor(chs, 1), 'g1#c2');
      expect(workWatchKeyFor({'id': 'g2'}, 0), 'g2');
      expect(workWatchKeyFor({'id': 'g3', 'ch': [_ch(0, '/0.mp4')]}, 0), 'g3');
    });
  });

  group('workTotalDuration', () {
    test('合集累加章节时长，单条读 du', () {
      final w = {
        't': 'v',
        'ch': [_ch(0, '/0.mp4'), _ch(1, '/1.mp4')],
      };
      expect(workTotalDuration(w), 21.0);
      expect(workTotalDuration({'t': 'v', 'du': 8.5}), 8.5);
      expect(workTotalDuration({'t': 'v'}), 0);
    });
  });
}
