import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 崩溃前现场记录。
///
/// 原生崩溃（OOM、纹理、窗口线程）不会进 Dart 的 `FlutterError`，所以过去
/// 每次闪退都只剩“又崩了”这一条信息。这里把关键动作按行追加到本地文件，
/// 崩溃后下次启动能读出最后几行——至少知道是哪个按钮、哪一步。
class Breadcrumb {
  Breadcrumb._();

  static IOSink? _sink;
  static bool _ready = false;

  /// 上一次运行的最后动作（本次启动时读取，用于展示与排查）。
  static List<String> lastSessionTail = const <String>[];

  /// 上一次运行是否正常退出（没有正常标记即视为疑似崩溃）。
  static bool lastSessionCrashed = false;

  static Future<void> init() async {
    if (_ready) return;
    _ready = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/breadcrumb.log');
      // 读上一轮：以最后一行是否为 clean_exit 判断是否异常结束。
      if (await f.exists()) {
        final lines = await f.readAsLines();
        if (lines.isNotEmpty) {
          final tail = lines.length > 40 ? lines.sublist(lines.length - 40) : lines;
          lastSessionTail = List<String>.unmodifiable(tail);
          lastSessionCrashed =
              !(tail.last.contains('clean_exit'));
        }
      }
      // 新一轮：清空重写，避免无限增长。
      await f.writeAsString('', flush: true);
      _sink = f.openWrite(mode: FileMode.append);
    } catch (e) {
      debugPrint('[breadcrumb] init failed: $e');
    }
  }

  /// 记录一步动作。同步写盘由 IOSink 缓冲，崩溃时最多丢最后一行。
  static void mark(String tag, [Object? detail]) {
    try {
      final ts = DateTime.now().toIso8601String();
      final d = detail == null ? '' : ' | $detail';
      _sink?.writeln('$ts | $tag$d');
    } catch (_) {}
  }

  /// 把缓冲刷到磁盘，供诊断页读取当前会话记录。
  static Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {}
  }

  /// 读取当前会话最后 N 行（诊断页用）。
  static Future<List<String>> readTail({int lines = 40}) async {
    try {
      await flush();
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/breadcrumb.log');
      if (!await f.exists()) return const <String>[];
      final all = await f.readAsLines();
      if (all.isEmpty) return const <String>[];
      return all.length > lines ? all.sublist(all.length - lines) : all;
    } catch (_) {
      return const <String>[];
    }
  }

  /// 正常退出标记。
  static Future<void> cleanExit() async {
    try {
      _sink?.writeln('${DateTime.now().toIso8601String()} | clean_exit');
      await _sink?.flush();
    } catch (_) {}
  }

  static Future<void> dispose() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }
}
