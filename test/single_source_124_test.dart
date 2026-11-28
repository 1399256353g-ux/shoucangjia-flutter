/// 0.9.379（第一百二十四批）契约：「读一个键 → 判能不能用」只剩一处。
///
///  1. 第一百二十三批只收了六张**表**（连接/绑定/进度/继续观看/播放量/头像
///     覆盖），**设置类**七处仍是自己那套：空串判 `isNotEmpty`（纯空格放行）、
///     `try { jsonDecode } catch` 有的写有的不写、`is Map` 之后是否再转
///     `Map<String, dynamic>` 各不相同。加第八个设置项时没人知道抄哪份。
///     现在只有 `prefs_json.readPrefJson(key)`：读不到 / 坏 JSON 一律 null，
///     结构判断留给调用方。
///  2. 本机三处**列表**偏好（星标 / 文件结构解锁 / 不感兴趣）各写一遍
///     `SharedPreferences.getInstance()` + `getStringList` + 自己的 catch，
///     现在只有 `readPrefStringList` / `savePrefStringList`。
///
/// 判据是源码结构与真实读盘行为，不涉及任何作者名 / 文件内容。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shoucangjia/author_grade.dart';
import 'package:shoucangjia/http_error_text.dart';
import 'package:shoucangjia/library_badge.dart';
import 'package:shoucangjia/playback_prefs.dart';
import 'package:shoucangjia/prefs_json.dart';

/// 去掉整行注释后的源码（用于「第二份实现」扫描）。
String _code(String path) => File(path)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

Iterable<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. readPrefJson：读盘 + 解析一件东西', () {
    test('没有这个键 / 空串 / 纯空格 / 坏 JSON 都是 null', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await readPrefJson('missing_v1'), isNull);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'empty_v1': '',
        'spaces_v1': '   ',
        'bad_v1': '{oops',
      });
      expect(await readPrefJson('empty_v1'), isNull);
      expect(await readPrefJson('spaces_v1'), isNull,
          reason: '纯空格与空串必须是同一个答案（旧实现一处 isEmpty 一处 trim）');
      expect(await readPrefJson('bad_v1'), isNull);
    });

    test('对象 / 数组 / 标量原样返回，由调用方判结构', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'obj_v1': '{"a":1}',
        'arr_v1': '[1,2]',
        'num_v1': '3',
      });
      expect(await readPrefJson('obj_v1'), {'a': 1});
      expect(await readPrefJson('arr_v1'), [1, 2]);
      expect(await readPrefJson('num_v1'), 3,
          reason: '是不是表由调用方判（那才是各表真正的差异）');
    });

    test('唯一实现：lib/ 内 jsonDecode( 只出现在 prefs_json', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final p = f.path.replaceAll('\\', '/');
        if (p == 'lib/prefs_json.dart') continue;
        if (p == 'lib/http_json.dart' || p == 'lib/json_isolate.dart') continue;
        if (_code(p).contains('jsonDecode(')) offenders.add(p);
      }
      expect(offenders, isEmpty,
          reason: '这些文件又自己解了一遍 JSON（读盘判定应只有 readPrefJson）：'
              '$offenders');
    });
  });

  group('2. 设置类读盘全部转发，行为不变', () {
    test('五个设置文件不再直接读 prefs / 解 JSON', () {
      for (final f in const [
        'lib/app_settings.dart',
        'lib/library_badge.dart',
        'lib/library_corner_badge.dart',
        'lib/author_grade.dart',
        'lib/playback_prefs.dart',
      ]) {
        final src = _code(f);
        expect(src.contains('jsonDecode('), isFalse, reason: f);
        // 允许留 `getInstance()`：AppSettings 还要读一个 bool 迁移标记
        // （`lowload_migrated_v1`），那是布尔不是 JSON 表。但**字符串**
        // 设置不许再自己 `sp.getString`——那正是读盘判定要收的东西。
        expect(src.contains('getString('), isFalse,
            reason: '$f 不该再自己 sp.getString 读设置（读盘入口只有 prefs_json）');
      }
      // LibraryBadge 仍要读多个键：它允许用 `readPrefString` 逐个读。
      expect(_code('lib/library_badge.dart').contains('decodePrefJson('), isTrue);
      expect(_code('lib/app_settings.dart').contains('readPrefJson('), isTrue);
      expect(_code('lib/author_grade.dart').contains('readPrefJson('), isTrue);
      expect(
          _code('lib/library_corner_badge.dart').contains('readPrefJson('), isTrue);
      expect(_code('lib/playback_prefs.dart').contains('readPrefJson('), isTrue);
    });

    test('坏数据仍退化为空 / 默认值（回归而不是放宽）', () async {
      // 解析层（纯函数）不受读盘改动影响。
      expect(LibraryBadge.parse('not json'), isEmpty);
      expect(LibraryBadge.parse('   '), isEmpty);
      expect(LibraryBadge.parseEmoji('{"a": 3}'), isEmpty);
      expect(AuthorGrade.parse('{oops'), isEmpty);

      // 真读盘：坏值 / 纯空格都回落到默认，不抛。
      SharedPreferences.setMockInitialValues(<String, Object>{
        kPlaybackPrefsKey: '   ',
      });
      final p = await loadPlaybackPrefs();
      expect(p, PlaybackPrefs.defaults);

      SharedPreferences.setMockInitialValues(<String, Object>{
        kPlaybackPrefsKey: '{"loopOne":true,"autoplay":false}',
      });
      final p2 = await loadPlaybackPrefs();
      expect(p2.link.loopOne, isTrue);
      expect(p2.link.autoplay, isFalse);
    });

    test('纯空格配置不再走一次「抛异常再吞掉」', () async {
      // 旧写法 `if (raw != null && raw.isNotEmpty) jsonDecode(raw)`：
      // 纯空格能过 isNotEmpty，随后 jsonDecode('   ') 抛异常被 catch 吞掉。
      // 结果对，但「能不能用」这条规则有两个说法。现在在 decodePrefJson 里
      // 先 trim，超时/异常路径都走不到。
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppSettingsKeyForTest.prefsKey: '   ',
      });
      expect(await readPrefJson(AppSettingsKeyForTest.prefsKey), isNull);
    });
  });

  group('3. 列表偏好只有一个读写入口', () {
    test('读取：没有键 / 存的不是列表 → 空列表', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      expect(await readPrefStringList('nothing_v1'), isEmpty);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'wrong_type_v1': 'not a list',
      });
      expect(await readPrefStringList('wrong_type_v1'), isEmpty);
    });

    test('写入后能原样读回（保持顺序）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await savePrefStringList('list_v1', <String>['b', 'a', 'c']);
      expect(await readPrefStringList('list_v1'), ['b', 'a', 'c']);
    });

    test('lib/ 内 getStringList / setStringList 只剩 prefs_json 一处', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final p = f.path.replaceAll('\\', '/');
        if (p == 'lib/prefs_json.dart') continue;
        final src = _code(p);
        if (src.contains('getStringList(') || src.contains('setStringList(')) {
          offenders.add(p);
        }
      }
      expect(offenders, isEmpty, reason: '列表偏好的读盘又各自写了一遍：$offenders');
    });

    test('三个调用点都转发到列表入口', () {
      expect(_code('lib/star_store.dart').contains('readPrefStringList('), isTrue);
      expect(_code('lib/star_store.dart').contains('savePrefStringList('), isTrue);
      expect(_code('lib/folder_structure_page.dart')
          .contains('readPrefStringList('), isTrue);
      expect(_code('lib/folder_structure_page.dart')
          .contains('savePrefStringList('), isTrue);
      final main = _code('lib/main.dart');
      expect(main.contains('readPrefStringList('), isTrue);
      expect(main.contains('savePrefStringList('), isTrue);
    });
  });

  group('4. 「不感兴趣」的键只定义一次', () {
    test('lib/ 内 hidden_works_v1 字面量只出现在常量定义处', () {
      var literals = 0;
      for (final f in _libFiles()) {
        final src = _code(f.path.replaceAll('\\', '/'));
        literals += "'hidden_works_v1'".allMatches(src).length;
      }
      expect(literals, 1,
          reason: '键名有两份就会有一天「写进 A、读的是 B」');
      // 0.9.381：三把本机偏好键（含这一把）搬到了 `lib/pref_keys.dart` 的
      // 同一处，`main` 只 import 转发——「只有一份」的判定从「只写在 main」
      // 改为「只写在 pref_keys」，仍然只有一份。
      expect(_code('lib/main.dart').contains('kHiddenWorksPrefsKey'), isTrue);
      expect(_code('lib/pref_keys.dart')
          .contains('const String kHiddenWorksPrefsKey = \'hidden_works_v1\''), isTrue);
    });

    test('隐藏一条作品真的落盘（读-改-写走列表入口）', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'hidden_works_v1': <String>['old'],
      });
      final list = <String>{...await readPrefStringList('hidden_works_v1')}
        ..add('new');
      await savePrefStringList('hidden_works_v1', list.toList());
      expect(await readPrefStringList('hidden_works_v1'), contains('new'));
      expect(await readPrefStringList('hidden_works_v1'), contains('old'),
          reason: '读-改-写不能把旧记录冲掉');
    });
  });

  group('5. 读接口的「状态码 → 抛出」只有一处', () {
    test('200 通过；其余抛出已翻译好的原因', () {
      expect(() => throwIfHttpFailed(200), returnsNormally);
      expect(() => throwIfHttpFailed(404), throwsA(predicate((e) =>
          '$e' == 'Exception: HTTP 404')));
      // 400/500 走同一张翻译表，页面不该再各拼一次。
      expect(() => throwIfHttpFailed(400), throwsA(predicate((e) =>
          '$e'.contains('请求格式不对'))));
      expect(() => throwIfHttpFailed(500), throwsA(predicate((e) =>
          '$e'.contains('服务端写入失败'))));
      // 业务特指文案仍可从外部传入。
      expect(() => throwIfHttpFailed(404, overrides: const {404: '该库不存在'}),
          throwsA(predicate((e) => '$e'.contains('该库不存在'))));
    });

    test('lib/ 内不再手写 if (… != 200) throw Exception(httpErrorText(…))', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final p = f.path.replaceAll('\\', '/');
        if (p == 'lib/http_error_text.dart') continue;
        if (_code(p).contains('throw Exception(httpErrorText(')) {
          offenders.add(p);
        }
      }
      expect(offenders, isEmpty,
          reason: '这行有 15 份拷贝时，改一份漏一份就是两种说法：$offenders');
    });

    test('调用点确实转发了（不是把实现写出来没人用）', () {
      var uses = 0;
      for (final f in _libFiles()) {
        final p = f.path.replaceAll('\\', '/');
        if (p == 'lib/http_error_text.dart') continue;
        uses += 'throwIfHttpFailed('.allMatches(_code(p)).length;
      }
      expect(uses, greaterThanOrEqualTo(10),
          reason: '转发点掉到 $uses 处，说明又有页面绕开了唯一出口');
    });
  });
}

/// 只为上面的断言拿到 AppSettings 的落盘键（不读它的内部实现）。
class AppSettingsKeyForTest {
  static const String prefsKey = 'app_settings_v1';
}
