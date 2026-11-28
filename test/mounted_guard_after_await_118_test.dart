// 第 118 批：`await` 之后改状态前必须确认宿主还在。
//
// 上一批记录里列的「已识别未修」头一条就是这类：
//   `main._delete` / `main._disconnect` / 设置页三处角标回调
//   都是 `await …; setState((){})`，对话框关掉后页面已被 pop 时触发，
//   抛的是 `setState() called after dispose()`。
//
// 这不是「加个 try/catch 兜住」能解决的——那是补丁。正确做法是
// **每个 await 之后、写状态之前**先判 `mounted`，与文件里其它几十处一致。
// 本契约把这条规则钉在源码文本上：只检查这几个已知的会话型回调，
// 不搞全文件正则泛判（会误伤 `if (mounted) setState(...)` 与
// `=>` 表达式体）。
//
// 只读源码文本，不构建页面、不碰任何媒体内容。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _lib(String name) => File('lib/$name').readAsStringSync();

void main() {
  group('await 之后的 setState 都守 mounted', () {
    test('连接设置：删除 / 断开 / 重连 / 保存地址', () {
      final s = _lib('main.dart');
      // 四个函数各自「await 对话框 → 判 mounted → setState」。
      for (final fn in const [
        'Future<void> _delete(ServerConn s) async {',
        'Future<void> _disconnect(ServerConn s) async {',
      ]) {
        final i = s.indexOf(fn);
        expect(i, greaterThan(-1), reason: '找不到 $fn');
        final body = s.substring(i, i + 1400);
        final setIdx = body.indexOf('setState(() {');
        expect(setIdx, greaterThan(-1), reason: '$fn 里没有 setState');
        final before = body.substring(0, setIdx);
        expect(before.contains('if (!mounted) return;'), isTrue,
            reason: '$fn 在 setState 前没守 mounted');
      }
    });

    test('重连密码框与地址表单同一条规则', () {
      final s = _lib('main.dart');
      // 重连：`reconnectServer(s, pw)` 之后、setState 之前。
      final rc = s.indexOf('final next = reconnectServer(s, pw);');
      expect(rc, greaterThan(-1));
      final after = s.substring(rc, rc + 220);
      expect(after.contains('if (!mounted) return;'), isTrue,
          reason: '重连回来没守 mounted');

      // 保存地址：`old.copyWith(...)` 之后、setState 之前。
      final sv = s.indexOf('pass: pass.text,\n          );\n    // 地址/账号对话框');
      expect(sv, greaterThan(-1));
      final afterSave = s.substring(sv, sv + 200);
      expect(afterSave.contains('if (!mounted) return;'), isTrue,
          reason: '保存地址回来没守 mounted');
    });

    test('角标设置页三处回调（图案 / 颜色 / 恢复默认）', () {
      final s = _lib('main.dart');
      for (final call in const [
        'await LibraryCornerBadge.resetKind(kind);',
        'await LibraryCornerBadge.setPattern(kind, i);',
        'await LibraryCornerBadge.setColor(kind, c);',
      ]) {
        final i = s.indexOf(call);
        expect(i, greaterThan(-1), reason: '找不到 $call');
        final after = s.substring(i, i + 160);
        expect(after.contains('if (!mounted) return;'), isTrue,
            reason: '$call 之后没守 mounted');
      }
    });

    test('角标静态方法自身不抛（否则回调会连 setState 都走不到）', () {
      // 三个静态写方法都只做 clamp/赋值/save，save 内部走 savePrefString
      // （已 catch）。这里只钉「不 rethrow」这条：调用方守住 mounted 才有意义。
      final s = _lib('library_corner_badge.dart');
      for (final fn in const [
        'static Future<void> setPattern(',
        'static Future<void> setColor(',
        'static Future<void> resetKind(',
      ]) {
        expect(s.contains(fn), isTrue, reason: '找不到 $fn');
      }
      // 写盘出口只有一个。
      expect(
          RegExp(r'static Future<void> save\(\)').allMatches(s).length, 1);
    });
  });
}
