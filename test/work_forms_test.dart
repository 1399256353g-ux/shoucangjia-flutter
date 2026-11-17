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

  group('J6 作品类型筛选', () {
    final works = <dynamic>[
      {'id': 'v1', 't': 'v', 'm': ['/v1.mp4']},
      {'id': 'c1', 't': 'v', 'ch': [_ch(0, '/0.mp4'), _ch(1, '/1.mp4')]},
      {'id': 'p1', 't': 'p', 'kind': 'post', 'm': ['/1.jpg', '/2.jpg']},
      {'id': 'a1', 't': 'p', 'kind': 'album', 'm': ['/1.jpg', '/2.jpg']},
      {'id': 's1', 't': 'p', 'm': ['/1.jpg']},
      'bad',
    ];

    test('分类映射', () {
      expect(workFilterType(works[0]), workFilterVideo);
      expect(workFilterType(works[1]), workFilterCollection);
      expect(workFilterType(works[2]), workFilterPost);
      expect(workFilterType(works[3]), workFilterCollection,
          reason: '图片合集归入合集');
      expect(workFilterType(works[4]), workFilterPicture);
      expect(workFilterType(works[5]), 'other', reason: '坏数据归为其他');
      expect(workFilterType(null), 'other', reason: '坏数据不抛异常');
      expect(workFilterLabel(workFilterPicture), '图片');
    });

    test('空筛选返回全部，多选并集命中', () {
      expect(filterWorksByType(works, {}).length, works.length);
      final video = filterWorksByType(works, {workFilterVideo});
      expect(video.map((w) => w['id']), ['v1']);
      final multi =
          filterWorksByType(works, {workFilterPost, workFilterPicture});
      expect(multi.map((w) => w['id']), ['p1', 's1']);
      expect(filterWorksByType(works, {workFilterCollection}).length, 2);
      expect(filterWorksByType(works, {workFilterVideo, workFilterPost,
          workFilterCollection, workFilterPicture}).length, 5,
          reason: '坏数据不混入四类筛选');
    });

    test('计数覆盖四类且含 0', () {
      final c = workTypeCounts(works);
      expect(c[workFilterVideo], 1);
      expect(c[workFilterCollection], 2);
      expect(c[workFilterPost], 1);
      expect(c[workFilterPicture], 1);
      expect(c['other'], 1, reason: '坏数据单独计数');
      expect(workTypeCounts([])[workFilterVideo], 0);
    });
  });

  test('混合合集：视频章节在前，图片章节排最后并切换播放类型', () {
    final w = {
      'id': 'x',
      't': 'v',
      'kind': 'chapters',
      'ch': [
        {'ti': '第1段', 'm': ['/media/lib-001/a/1.mp4']},
        {'ti': '图片A', 't': 'p', 'm': ['/media/lib-001/a/1.jpg']},
        {'ti': '第2段', 'm': ['/media/lib-001/a/2.mp4']},
        {'ti': '图片B', 't': 'p', 'm': ['/media/lib-001/a/2.jpg']},
      ],
    };
    final chs = workChapters(w);
    expect(chs.map((c) => c['ti']).toList(),
        ['第1段', '第2段', '图片A', '图片B']);
    expect(chapterIsImage(chs[2]), isTrue);
    final img = workWithChapter(w, 2);
    expect(img['t'], 'p');
    expect(img['m'], ['/media/lib-001/a/1.jpg']);
    final vid = workWithChapter(w, 0);
    expect(vid['t'], 'v');
  });

  test('章节没写 t 时按扩展名识别图片', () {
    expect(chapterIsImage({'m': ['/x/a.png']}), isTrue);
    expect(chapterIsImage({'m': ['/x/a.MP4']}), isFalse);
  });
}
