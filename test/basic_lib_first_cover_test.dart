// 0.9.162：服务端下发的首张作品封面（`fc`）成为 `BasicLib` 的字段。
//
// 背景：`fc` 原来只存在主页状态里的 `_fcByLib` 映射，单元库页的基础库卡片
// 拿不到 → 索引里「有 thumb/cover 但无媒体」的库卡片一直空白。现在统一由
// `BasicLib.firstCover` 携带，卡片解析链路（`basicCoverUrl`）直接使用。
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shoucangjia/library_tree.dart';
import 'package:shoucangjia/source_lib.dart';
import 'package:shoucangjia/unit_library_view.dart';
import 'package:shoucangjia/work_plays.dart';

Map<String, dynamic> _treeJson({String fc = ''}) => {
      'bigLibraries': [
        {'id': 'big-01', 'name': 'A', 'path': '/root/A'},
      ],
      'basicLibraries': [
        {
          'id': 'lib-029',
          'name': 'Rape & Date Rape',
          'rel': '(1) A/(5) Rape & Date Rape',
          'big_id': 'big-01',
          'authors': 1,
          'works': 1,
          'fc': fc,
          '_serverBase': 'http://nas:8090',
        },
      ],
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WorkPlaysStore.resetForTest(items: const {});
  });
  tearDown(() => WorkPlaysStore.resetForTest(items: const {}));

  test('解析：服务端 fc 落到 BasicLib.firstCover', () {
    final t = LibraryTree.parse(
      _treeJson(fc: '/media/lib-029/%40a/VID/cover.jpg'),
    )!;
    expect(t.allBasics.single.firstCover, '/media/lib-029/%40a/VID/cover.jpg');
  });

  test('解析：没有 fc 时为空串（不伪造地址）', () {
    final t = LibraryTree.parse(_treeJson())!;
    expect(t.allBasics.single.firstCover, isEmpty);
  });

  test('库树不再有「写了没人读」的本地序列化', () {
    // 此前 BasicLib.toJson 只被本文件断言：库树从不回写本地快照，
    // 重启是重拉 /api/libraries.json。留着它会让人误以为存在缓存。
    final src = File('lib/library_tree.dart').readAsStringSync().replaceAll('\r\n', '\n');
    expect(RegExp(r'Map<String, dynamic> toJson\(').hasMatch(src), isFalse,
        reason: 'BasicLib.toJson 又回来了（没有产品调用方）');
  });

  test('卡片封面：无手动/爬虫/播放记录时用 fc；fc 是视频则判无图', () {
    final t = LibraryTree.parse(_treeJson())!;
    final base = t.allBasics.single;
    final withFc = BasicLib(
      id: base.id,
      name: base.name,
      rel: base.rel,
      bigId: base.bigId,
      authors: base.authors,
      works: base.works,
      serverBase: base.serverBase,
      firstCover: '/media/lib-029/%40a/VID/cover.jpg',
    );
    expect(basicCoverUrl(withFc), 'http://nas:8090/media/lib-029/%40a/VID/cover.jpg');

    final videoFc = BasicLib(
      id: base.id,
      name: base.name,
      rel: base.rel,
      bigId: base.bigId,
      authors: base.authors,
      works: base.works,
      serverBase: base.serverBase,
      firstCover: '/media/lib-029/a/VID/clip.mp4',
    );
    expect(basicCoverUrl(videoFc), isEmpty);
  });

  testWidgets('单元库页基础库卡片：请求的封面就是 fc', (t) async {
    final b = BasicLib(
      id: 'lib-029',
      name: 'Rape & Date Rape',
      rel: '(1) A/(5) Rape & Date Rape',
      bigId: 'big-01',
      authors: 1,
      works: 1,
      serverBase: 'http://nas:8090',
      firstCover: '/media/lib-029/%40a/VID/cover.jpg',
    );
    await t.pumpWidget(
        MaterialApp(home: Scaffold(body: BasicLibCard(basic: b, onTap: () {}))));
    await t.pump();
    final img = t.widget<CachedNetworkImage>(find.byType(CachedNetworkImage));
    expect(img.imageUrl, contains('/media/lib-029/%40a/VID/cover.jpg'));
  });

  test('basicsUnderBase 直接产出 BasicLib（不再有转换点，字段一个不丢）', () {
    final libs = basicsUnderBase(<String, dynamic>{
      'basicLibraries': <dynamic>[
        <String, dynamic>{
          'id': 'lib-029',
          'name': '(5) 强奸',
          'path': '/root/(5) 强奸',
          'big_id': 'big-01',
          'authors': 7,
          'works': 9,
          'cover': <String, dynamic>{'v': 'c2026', 'e': 'png'},
          'cv': ' /media/lib-029/a/cv.jpg ',
          'fc': '/media/lib-029/x/cover.jpg',
        },
      ],
    }, '/root');
    final b = libs.single;
    expect(b.id, 'lib-029');
    expect(b.firstCover, '/media/lib-029/x/cover.jpg');
    expect(b.authors, 7, reason: '统计字段不再由调用方补 0');
    expect(b.works, 9);
    expect(b.coverVersion, 'c2026',
        reason: '自定义 _cover/ 指针必须在单元库这条构建路径上活下来');
    expect(b.coverExt, 'png');
    expect(b.crawlerCover, '/media/lib-029/a/cv.jpg',
        reason: 'cv 爬虫封面必须在单元库这条构建路径上活下来');
  });

  test('basicsUnderBase 与 LibraryTree.parse 对同一条记录给出同一个模型', () {
    final raw = <String, dynamic>{
      'id': 'lib-029',
      'name': 'X',
      'rel': 'A/X',
      'path': '/root/A/X',
      'big_id': 'big-01',
      'cover': <String, dynamic>{'v': 'v9', 'e': 'webp'},
      'cv': '/media/lib-029/a/cv.jpg',
      'fc': '/media/lib-029/a/fc.jpg',
    };
    final fromTree = LibraryTree.parse(<String, dynamic>{
      'bigLibraries': <dynamic>[
        <String, dynamic>{'id': 'big-01', 'name': 'A', 'path': '/root/A'},
      ],
      'basicLibraries': <dynamic>[raw],
    })!
        .allBasics
        .single;
    final fromRef = basicsUnderBase(
        <String, dynamic>{'basicLibraries': <dynamic>[raw]}, '/root').single;
    for (final pair in <List<String>>[
      <String>[fromTree.coverVersion, fromRef.coverVersion],
      <String>[fromTree.coverExt, fromRef.coverExt],
      <String>[fromTree.crawlerCover, fromRef.crawlerCover],
      <String>[fromTree.firstCover, fromRef.firstCover],
      <String>[fromTree.rel, fromRef.rel],
      <String>[fromTree.bigId, fromRef.bigId],
    ]) {
      expect(pair[0], pair[1], reason: '两个入口必须解析成同一份数据');
    }
  });

  test('basicsUnderBase/basicLibFromRef 保留来源连接（卡片自己拼地址要靠它）', () {
    final refs = basicsUnderBase({
      'basicLibraries': [
        {
          'id': 'lib-029',
          'name': 'Rape & Date Rape',
          'path': '/root/A',
          'big_id': 'big-01',
          'fc': '/media/lib-029/a/cover.jpg',
          '_serverId': 's1',
          '_serverBase': 'http://nas:8090',
          '_serverLabel': 'NAS',
        },
      ],
    }, '/root');
    expect(refs, hasLength(1));
    expect(refs.single.serverBase, 'http://nas:8090');
    expect(refs.single.serverLabel, 'NAS');
    expect(refs.single.serverId, 's1');
    // 缺 base 时 `basicCoverUrl` 只能返回空串 → 灰卡；这里断言整条链能拼出地址。
    final b = refs.single;
    expect(b.serverBase, 'http://nas:8090');
    expect(basicCoverUrl(b), 'http://nas:8090/media/lib-029/a/cover.jpg');
  });
}
