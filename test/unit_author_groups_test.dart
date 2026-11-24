import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/unit_author_groups.dart';

// A1：单元库作者文件夹挂载——协议层与规则层（纯逻辑）。
// 判据全部是结构事实（字段、计数、错误文案），不涉及任何真实作者名/目录名。

AuthorGroupFile f(String lib, String dir) =>
    AuthorGroupFile(lib: lib, authorDir: dir);

Map<String, dynamic> groupJson({
  String id = 'mg_1',
  String name = 'A',
  List<Map<String, dynamic>> files = const [],
  bool split = false,
  bool auto = false,
  int works = 0,
}) =>
    <String, dynamic>{
      'id': id,
      'name': name,
      'names': [name],
      'files': files,
      'split': split,
      'auto': auto,
      'works': works,
      'av': '',
      'bio': '',
    };

void main() {
  group('AuthorGroupFile', () {
    test('两段都必须非空，否则视为无效成员', () {
      expect(AuthorGroupFile.fromJson({'lib': 'l1', 'authorDir': '@a'}),
          isNotNull);
      expect(AuthorGroupFile.fromJson({'lib': '', 'authorDir': '@a'}), isNull);
      expect(
          AuthorGroupFile.fromJson({'lib': 'l1', 'authorDir': '  '}), isNull);
      expect(AuthorGroupFile.fromJson('l1/@a'), isNull);
    });

    test('身份键与服务端同一写法 lib|authorDir', () {
      expect(f('l1', '@a').key, 'l1|@a');
      expect(f('l1', '@a'), f('l1', '@a'));
      expect(f('l1', '@a').hashCode, f('l1', '@a').hashCode);
    });
  });

  group('UnitAuthorGroup / State 解析', () {
    test('GET 响应：groups 与 auto 分别解析，坏条目丢弃不抛异常', () {
      final st = UnitAuthorGroupsState.fromJson({
        'ok': true,
        'unit': '(1) A',
        'groups': [
          groupJson(files: [
            {'lib': 'l1', 'authorDir': '@a'},
            {'lib': 'l2', 'authorDir': '@a'},
          ]),
          {'id': ''},
          'garbage',
        ],
        'auto': [
          groupJson(id: 'ag_1', auto: true, files: [
            {'lib': 'l1', 'authorDir': '@b'},
            {'lib': 'l2', 'authorDir': '@b'},
          ]),
        ],
      });
      expect(st.unit, '(1) A');
      expect(st.groups.length, 1);
      expect(st.auto.length, 1);
      expect(st.groups.first.isMerge, isTrue);
      expect(st.auto.first.auto, isTrue);
    });

    test('claimedKeys 把手动组成员摊平，派生组据此排重', () {
      final st = UnitAuthorGroupsState.fromJson({
        'groups': [
          groupJson(files: [
            {'lib': 'l1', 'authorDir': '@a'},
            {'lib': 'l2', 'authorDir': '@a'},
          ]),
        ],
      });
      expect(st.claimedKeys, {'l1|@a', 'l2|@a'});
    });

    test('空/非 Map 响应得到空状态，不炸', () {
      expect(UnitAuthorGroupsState.fromJson(null).isEmpty, isTrue);
      expect(UnitAuthorGroupsState.fromJson('x').isEmpty, isTrue);
      expect(UnitAuthorGroupsState.fromJson({}).isEmpty, isTrue);
    });

    test('单成员组不算合并（isMerge 只看成员数）', () {
      final g = UnitAuthorGroup.fromJson(groupJson(files: [
        {'lib': 'l1', 'authorDir': '@a'},
      ]))!;
      expect(g.isMerge, isFalse);
    });
  });

  group('请求体', () {
    test('merge：带 unit/action/files，不带 groupId', () {
      final r = UnitAuthorRequest(
        unit: '(1) A',
        action: UnitAuthorAction.merge,
        name: '合并名',
        files: [f('l1', '@a'), f('l2', '@a')],
      );
      expect(r.toBody(), {
        'unit': '(1) A',
        'action': 'merge',
        'name': '合并名',
        'files': [
          {'lib': 'l1', 'authorDir': '@a'},
          {'lib': 'l2', 'authorDir': '@a'},
        ],
      });
    });

    test('split / setFiles / delete：带 groupId；delete 不带 files', () {
      final split = UnitAuthorRequest(
        unit: 'A',
        action: UnitAuthorAction.split,
        groupId: 'mg_1',
        files: [f('l1', '@a')],
      );
      expect(split.toBody()['groupId'], 'mg_1');
      expect(split.toBody()['action'], 'split');
      expect(split.toBody()['files'], [
        {'lib': 'l1', 'authorDir': '@a'}
      ]);

      final del = UnitAuthorRequest(
        unit: 'A',
        action: UnitAuthorAction.delete,
        groupId: 'mg_1',
        files: [f('l1', '@a')],
      );
      final body = del.toBody();
      expect(body['action'], 'delete');
      expect(body.containsKey('files'), isFalse,
          reason: '删除只需要 groupId，多余 files 会让人以为要按成员删');
    });

    test('action 取值就是服务端字符串，改名即改协议', () {
      expect(UnitAuthorAction.merge.wire, 'merge');
      expect(UnitAuthorAction.split.wire, 'split');
      expect(UnitAuthorAction.setFiles.wire, 'setFiles');
      expect(UnitAuthorAction.delete.wire, 'delete');
    });
  });

  group('前置校验（与服务端规则同口径）', () {
    test('缺单元库一律拒绝', () {
      for (final a in UnitAuthorAction.values) {
        expect(
            unitAuthorRequestError(
                action: a, unit: '  ', groupId: 'g', files: [f('l1', '@a')]),
            '缺少单元库');
      }
    });

    test('merge：至少 1 个成员；重复成员先去重再计数', () {
      expect(
          unitAuthorRequestError(
              action: UnitAuthorAction.merge, unit: 'A', files: const []),
          '至少要挂载 1 个作者文件夹');
      expect(
          unitAuthorRequestError(
              action: UnitAuthorAction.merge,
              unit: 'A',
              files: [
                f('l1', '@a'),
                f('l1', '@a'),
              ]),
          isNull,
          reason: '同一个文件夹点两次不该被判成 0 个');
      expect(
          unitAuthorRequestError(
              action: UnitAuthorAction.merge, unit: 'A', files: [f('', '@a')]),
          '至少要挂载 1 个作者文件夹',
          reason: '缺 lib 的成员不算有效成员');
    });

    test('split：拆走全部成员要挡下（那是 delete 的语义）', () {
      final original = [f('l1', '@a'), f('l2', '@a')];
      expect(
          unitAuthorRequestError(
              action: UnitAuthorAction.split,
              unit: 'A',
              groupId: 'g',
              files: original,
              groupFiles: original),
          '不能把整组都拆走（用删除解散）');
      expect(
          unitAuthorRequestError(
              action: UnitAuthorAction.split,
              unit: 'A',
              groupId: 'g',
              files: [f('l1', '@a')],
              groupFiles: original),
          isNull);
    });

    test('split：还不知道原组时不误拦（GET 之前）', () {
      expect(
          unitAuthorRequestError(
              action: UnitAuthorAction.split,
              unit: 'A',
              groupId: 'g',
              files: [f('l1', '@a')]),
          isNull);
    });

    test('delete / setFiles 缺 groupId 拒绝', () {
      expect(unitAuthorRequestError(action: UnitAuthorAction.delete, unit: 'A'),
          '缺少组 id');
      expect(
          unitAuthorRequestError(
              action: UnitAuthorAction.setFiles,
              unit: 'A',
              files: [f('l1', '@a')]),
          '缺少组 id');
    });

    test('请求对象自带的 error 与函数口径一致', () {
      const bad = UnitAuthorRequest(unit: '', action: UnitAuthorAction.merge);
      expect(bad.error, '缺少单元库');
      final ok = UnitAuthorRequest(
          unit: 'A', action: UnitAuthorAction.merge, files: [f('l1', '@a')]);
      expect(ok.error, isNull);
    });
  });

  group('作者目录名规则（服务端 authorDirNameOf / sanitizeAuthorDir 镜像）', () {
    test('name_raw 优先，否则 @name', () {
      expect(authorDirForName('名字'), '@名字');
      expect(authorDirForName('名字', nameRaw: '原始名'), '原始名');
      expect(authorDirForName('  '), '');
    });

    test('必须 @ 开头、不含分隔符/..、不含非法字符', () {
      expect(authorDirError('@a'), isNull);
      expect(authorDirError('a'), '作者目录必须以 @ 开头');
      expect(authorDirError('@a/b'), '作者目录不能包含路径分隔符');
      expect(authorDirError(r'@a\b'), '作者目录不能包含路径分隔符');
      expect(authorDirError('@..'), '作者目录不能包含 ..');
      expect(authorDirError('@a:b'), '作者目录不能包含 : * ? " < > |');
      expect(authorDirError(''), '作者目录不能为空');
    });
  });

  group('UnitAuthorCards（/api/unit/authors.json）', () {
    test('卡片按成员数区分合并组与独立作者', () {
      final st = UnitAuthorCards.fromJson({
        'ok': true,
        'unit': 'A',
        'cards': [
          {
            'groupId': 'mg_1',
            'name': 'x',
            'files': [
              {'lib': 'l1', 'authorDir': '@x'},
              {'lib': 'l2', 'authorDir': '@x'},
            ],
            'works': 12,
          },
          {
            'groupId': '',
            'name': 'y',
            'files': [
              {'lib': 'l1', 'authorDir': '@y'},
            ],
            'works': 3,
          },
        ],
      });
      expect(st.cards.length, 2);
      expect(st.cards[0].merged, isTrue);
      expect(st.cards[1].merged, isFalse);
      expect(st.cards[1].files.single.lib, 'l1');
    });

    test('名字与成员都空的条目被丢掉（面板不出现空行）', () {
      final st = UnitAuthorCards.fromJson({
        'cards': [
          {'groupId': '', 'name': '', 'files': <dynamic>[]},
          {'groupId': '', 'name': 'ok', 'files': <dynamic>[]},
        ],
      });
      expect(st.cards.length, 1);
      expect(st.cards.single.name, 'ok');
    });

    test('摘要只拼结构信息（成员数/作品数/标记）', () {
      const merged = UnitAuthorCard(
        groupId: 'g',
        name: 'n',
        files: [
          AuthorGroupFile(lib: 'l1', authorDir: '@a'),
          AuthorGroupFile(lib: 'l2', authorDir: '@a'),
        ],
        works: 7,
        split: true,
      );
      final s = unitAuthorCardSummary(merged);
      expect(s, contains('合并 2 个文件夹'));
      expect(s, contains('7 作品'));
      expect(s, contains('已拆分'));
    });
  });

  group('mergeableFiles', () {
    test('排除已在组内的成员，并按身份键去重', () {
      final out = mergeableFiles(
        [f('l1', '@a'), f('l2', '@a'), f('l2', '@a'), f('l3', '@b')],
        alreadyIn: ['l1|@a'],
      );
      expect(out.map((e) => e.key).toList(), ['l2|@a', 'l3|@b']);
    });
  });

  group('地址拼接', () {
    test('作者组接口带 unit 查询参数并补齐协议', () {
      expect(unitAuthorGroupsUrl('192.168.2.4:8090', '(1) A'),
          'http://192.168.2.4:8090/api/unit-author-groups.json?unit=%281%29+A');
      expect(unitAuthorGroupsUrl('http://nas:8090/', ''),
          'http://nas:8090/api/unit-author-groups.json');
      expect(unitAuthorsUrl('nas:8091', 'A'),
          'http://nas:8091/api/unit/authors.json?unit=A');
      expect(unitAuthorCreateUrl('http://nas:8090'),
          'http://nas:8090/api/unit/authors/create');
    });
  });
}
