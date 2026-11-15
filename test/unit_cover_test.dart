import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/unit_library.dart';
import 'package:shoucangjia/unit_library_view.dart';
import 'package:shoucangjia/work_plays.dart';

BasicLib basic(
  String id,
  String rel, {
  String serverBase = '',
  String coverVersion = '',
  String coverExt = 'jpg',
}) =>
    BasicLib(
      id: id,
      name: rel.split('/').last,
      rel: rel,
      bigId: '',
      authors: 1,
      works: 10,
      serverBase: serverBase,
      coverVersion: coverVersion,
      coverExt: coverExt,
    );

void main() {
  final playTree = buildUnitTree(
    nodes: const [
      LibNode(id: 'big-01', rel: '(1) A', name: '(1) A'),
      LibNode(id: 'big-01-sub', rel: '(1) A/sub', name: 'sub'),
    ],
    basics: [
      basic('l1', '(1) A/x', serverBase: 'http://nas:8090'),
      basic('l2', '(1) A/sub/y', serverBase: 'http://nas:8090'),
    ],
  )!;

  setUp(() => WorkPlaysStore.resetForTest(items: const {}));
  tearDown(() => WorkPlaysStore.resetForTest(items: const {}));

  group('单元库封面解析', () {
    test('自定义封面优先于播放量', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 9, thumb: '/media/l1/x/th.jpg'),
      });
      expect(
          unitCoverUrl(playTree,
              customUrl: 'http://nas:8090/media/l1/x/_cover/v1.jpg'),
          'http://nas:8090/media/l1/x/_cover/v1.jpg');
    });

    test('无自定义时取整棵子树内播放量最高的作品封面', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 2, thumb: '/media/l1/x/a.jpg'),
        'l2/w2': const WorkPlay(count: 7, thumb: '/media/l2/y/b.jpg'),
      });
      final top = topPlayedInUnit(playTree);
      expect(top?.basic.id, 'l2');
      expect(top?.thumb, '/media/l2/y/b.jpg');
      expect(unitCoverUrl(playTree), 'http://nas:8090/media/l2/y/b.jpg');
    });

    test('相对缩略图按基础库前缀补齐', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 4, thumb: 'x/th.jpg'),
      });
      expect(unitCoverUrl(playTree), 'http://nas:8090/media/l1/x/th.jpg');
    });

    test('播放记录只有空缩略图时回退默认图', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 6, thumb: ''),
      });
      expect(topPlayedInUnit(playTree), isNull);
      expect(unitCoverUrl(playTree), '');
    });

    test('thumbUrlOf 可替换 URL 拼装（交给 cfg 处理鉴权/路由）', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 4, thumb: '/media/l1/x/th.jpg'),
      });
      expect(
          unitCoverUrl(playTree,
              thumbUrlOf: (b, th) => 'custom:$th@${b.id}'),
          'custom:/media/l1/x/th.jpg@l1');
    });

    test('单元库卡片鉴权头取子树第一个基础库的连接', () {
      expect(unitHeadersOf(playTree, null), isEmpty);
      final h = unitHeadersOf(playTree, ([lib]) => {'X-Lib': lib ?? '-'});
      expect(h, {'X-Lib': 'l1'});
    });

    test('节点带版本指针时卡片自行拼自定义封面地址', () {
      final t = buildUnitTree(
        nodes: const [
          LibNode(
              id: 'big-09',
              rel: '(9) C',
              name: '(9) C',
              coverVersion: 'v3',
              coverExt: 'webp'),
        ],
        basics: [basic('l9', '(9) C/z', serverBase: 'http://nas:8090')],
      )!;
      expect(unitCoverUrl(t.children.first),
          'http://nas:8090/media/l9/(9) C/_cover/v3.webp');
      // 调用方已解析好的地址优先（鉴权/路由由调用方掌握）
      expect(unitCoverUrl(t.children.first, customUrl: 'http://nas:8090/x.jpg'),
          'http://nas:8090/x.jpg');
    });
  });

  group('基础库卡片封面解析', () {
    test('自定义 _cover 版本优先于播放量', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 9, thumb: '/media/l1/x/th.jpg'),
      });
      final b = basic('l1', '(1) A/x',
          serverBase: 'http://nas:8090', coverVersion: 'v2', coverExt: 'png');
      expect(
          basicCoverUrl(b), 'http://nas:8090/media/l1/(1) A/x/_cover/v2.png');
    });

    test('无自定义时用库内播放量最高的作品封面', () {
      WorkPlaysStore.resetForTest(items: {
        'l1/w1': const WorkPlay(count: 3, thumb: '/media/l1/x/a.jpg'),
        'l1/w2': const WorkPlay(count: 8, thumb: '/media/l1/x/b.jpg'),
      });
      expect(
          basicCoverUrl(basic('l1', '(1) A/x', serverBase: 'http://nas:8090')),
          'http://nas:8090/media/l1/x/b.jpg');
    });

    test('调用方给好的地址优先（自定义封面走鉴权路由）', () {
      final b = basic('l1', '(1) A/x', serverBase: 'http://nas:8090');
      expect(basicCoverUrl(b, preset: 'http://nas:8090/custom.jpg'),
          'http://nas:8090/custom.jpg');
    });

    test('都没有时为空（默认图标）', () {
      expect(basicCoverUrl(basic('l1', '(1) A/x')), '');
    });
  });
}
