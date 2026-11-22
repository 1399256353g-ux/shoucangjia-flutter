import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shoucangjia/author_avatar_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AuthorAvatarStore.instance.debugSeed({});
  });

  test('作者名做键：去首尾空白，同名即同一作者', () {
    expect(authorAvatarKey(' 一等锦鲤 '), '一等锦鲤');
    expect(authorAvatarKey(''), '');
  });

  test('解析覆盖表：坏 JSON/非映射按空处理，非法值丢弃', () {
    expect(parseAuthorAvatarOverrides(null), isEmpty);
    expect(parseAuthorAvatarOverrides('  '), isEmpty);
    expect(parseAuthorAvatarOverrides('不是 json'), isEmpty);
    expect(parseAuthorAvatarOverrides('[1,2,3]'), isEmpty);

    final m = parseAuthorAvatarOverrides(
        '{" A ":"/media/lib-001/a/x.jpg","b":"ftp://nope","c":"","d":123}');
    expect(m.keys, ['A']);
    expect(m['A'], '/media/lib-001/a/x.jpg');
  });

  test('序列化：键排序且丢弃非法值（便于持久化与测试）', () {
    final s = encodeAuthorAvatarOverrides({
      'b': '/media/lib-002/b/2.jpg',
      'a': '/media/lib-001/a/1.jpg',
      'bad': 'not-a-path',
    });
    expect(s.indexOf('/media/lib-001/a/1.jpg'), lessThan(s.indexOf('/media/lib-002/b/2.jpg')));
    expect(s.contains('bad'), isFalse);
    final back = parseAuthorAvatarOverrides(s);
    expect(back, {
      'a': '/media/lib-001/a/1.jpg',
      'b': '/media/lib-002/b/2.jpg',
    });
  });

  test('设置/清除：即时生效并通知监听者', () async {
    var notified = 0;
    void listener() => notified++;
    AuthorAvatarStore.instance.addListener(listener);

    expect(AuthorAvatarStore.instance.pathFor('作者A'), isNull);
    final ok = await AuthorAvatarStore.instance
        .setPath('作者A', '/media/lib-001/作者A/1.jpg');
    expect(ok, isTrue);
    expect(AuthorAvatarStore.instance.pathFor(' 作者A '),
        '/media/lib-001/作者A/1.jpg');
    expect(AuthorAvatarStore.instance.has('作者A'), isTrue);
    expect(notified, 1);

    await AuthorAvatarStore.instance.clear('作者A');
    expect(AuthorAvatarStore.instance.pathFor('作者A'), isNull);
    expect(notified, 2);
    // 再清一次不重复通知
    await AuthorAvatarStore.instance.clear('作者A');
    expect(notified, 2);

    AuthorAvatarStore.instance.removeListener(listener);
  });

  test('非法路径不写入', () async {
    expect(await AuthorAvatarStore.instance.setPath('作者B', ''), isFalse);
    expect(await AuthorAvatarStore.instance.setPath('作者B', 'abc.jpg'), isFalse);
    expect(await AuthorAvatarStore.instance.setPath('', '/media/x.jpg'), isFalse);
    expect(AuthorAvatarStore.instance.count, 0);
  });

  test('服务端自定义头像路径识别（/@manual-avatar/ 前缀）', () {
    expect(isManualAvatarPath('/media/lib-001/@manual-avatar/x/_avatar/a.jpg'),
        isTrue);
    expect(isManualAvatarPath('/media/lib-001/x/_avatar/a.jpg'), isFalse);
    expect(isManualAvatarPath(null), isFalse);
    expect(isManualAvatarPath(''), isFalse);
  });

  test('写入本机偏好，重新读取后仍在', () async {
    await AuthorAvatarStore.instance
        .setPath('作者C', '/media/lib-003/作者C/av.jpg');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString(kAuthorAvatarPrefsKey), isNotNull);

    AuthorAvatarStore.instance.debugSeed({});
    expect(AuthorAvatarStore.instance.pathFor('作者C'), isNull);

    await AuthorAvatarStore.instance.load();
    expect(AuthorAvatarStore.instance.pathFor('作者C'),
        '/media/lib-003/作者C/av.jpg');
    expect(AuthorAvatarStore.instance.ready, isTrue);
  });
}
