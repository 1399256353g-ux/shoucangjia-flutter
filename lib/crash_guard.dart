// 闪退兜底 + 崩溃日志（0.9.23 稳定性）。
//
// 目标：
//  - 单个部件构建失败时不再整页灰屏/红屏，只坏那一块（`CrashFallback`）；
//  - 未捕获的异步异常不再让界面「无声无息」停住，记下来继续跑；
//  - 内存里保留最近 50 条（同名错误合并计数）供「设置 → 诊断信息」查看；
//  - 同时追加到本机日志文件（Windows 落 E 盘），诊断页可读取尾部并复制，
//    不上传、不发给任何服务，符合 NAS 隐私红线。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 一条错误记录（内存态，最多保留 [CrashLog.maxEntries] 条）。
class CrashEntry {
  final DateTime at;
  final String kind; // widget / async
  final String message;
  final String stack;
  final int hits;

  const CrashEntry({
    required this.at,
    required this.kind,
    required this.message,
    required this.stack,
    this.hits = 1,
  });

  CrashEntry bump(DateTime now) => CrashEntry(
        at: now,
        kind: kind,
        message: message,
        stack: stack,
        hits: hits + 1,
      );

  String get timeText {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  String get kindLabel => kind == 'widget' ? '界面' : '异步';
}

/// 错误记录表：单例 + `ChangeNotifier`，诊断页直接监听。
class CrashLog extends ChangeNotifier {
  CrashLog._();

  static final CrashLog instance = CrashLog._();
  static const int maxEntries = 50;

  final List<CrashEntry> _entries = <CrashEntry>[];

  List<CrashEntry> get entries => List<CrashEntry>.unmodifiable(_entries);
  int get count => _entries.length;

  /// 记录一条错误；同一条消息已存在时只更新时间并累加次数（按栈去重）。
  void record(Object error, {String kind = 'async', StackTrace? stack}) {
    final now = DateTime.now();
    final message = describeError(error);
    final st = (stack?.toString() ?? '').trim();
    final i = _entries.indexWhere(
        (e) => e.message == message && e.kind == kind && e.stack == st);
    if (i >= 0) {
      final e = _entries.removeAt(i);
      _entries.insert(0, e.bump(now));
    } else {
      _entries.insert(
        0,
        CrashEntry(at: now, kind: kind, message: message, stack: st),
      );
      if (_entries.length > maxEntries) {
        _entries.removeRange(maxEntries, _entries.length);
      }
    }
    _appendFile(_entries.first);
    notifyListeners();
  }

  /// 崩溃日志落盘路径：Windows 固定 E 盘（不写 C 盘），其它平台临时目录。
  static String get logDir =>
      Platform.isWindows ? r'E:\Dizi\logs' : '${Directory.systemTemp.path}/dizi_logs';
  static String get logPath => '$logDir/crash.log';

  /// 追加一条到本地日志文件；超过 2 MB 先截断，避免无限增长。
  void _appendFile(CrashEntry e) {
    try {
      final d = Directory(logDir);
      if (!d.existsSync()) d.createSync(recursive: true);
      final f = File(logPath);
      if (f.existsSync() && f.lengthSync() > 2 * 1024 * 1024) {
        f.writeAsStringSync('', mode: FileMode.write);
      }
      f.writeAsStringSync(
          '${e.at.toIso8601String()} [${e.kindLabel}]'
          '${e.hits > 1 ? ' x${e.hits}' : ''} ${e.message}\n'
          '${e.stack.trim().isEmpty ? '' : '${e.stack}\n'}',
          mode: FileMode.append);
    } catch (_) {}
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  /// 纯文本导出（复制到剪贴板用）。
  String dump() {
    if (_entries.isEmpty) return '';
    final b = StringBuffer();
    for (final e in _entries) {
      b.writeln('${e.timeText} [${e.kindLabel}]'
          '${e.hits > 1 ? ' ×${e.hits}' : ''} ${e.message}');
      if (e.stack.trim().isNotEmpty) b.writeln(e.stack);
      b.writeln();
    }
    return b.toString().trimRight();
  }
}

/// 落盘日志尾部截取（纯逻辑，便于单测）。
///
/// 文件可能很大（最多 2 MB），诊断页只展示最近的一段：先按行数限制，
/// 再按字符数限制；被截断时在开头加一行提示，并避免从半个 UTF-16
/// 代理对（emoji 等）中间开始。
String crashTailOf(
  String raw, {
  int maxChars = 20000,
  int maxLines = 400,
}) {
  if (raw.trim().isEmpty) return '';
  var text = raw;
  var cut = false;
  if (maxLines > 0) {
    final lines = text.split('\n');
    if (lines.length > maxLines) {
      text = lines.sublist(lines.length - maxLines).join('\n');
      cut = true;
    }
  }
  if (maxChars > 0 && text.length > maxChars) {
    text = text.substring(text.length - maxChars);
    cut = true;
    final c = text.codeUnitAt(0);
    // 低代理项开头说明切断了 emoji，丢掉这半个码元。
    if (c >= 0xDC00 && c <= 0xDFFF) text = text.substring(1);
  }
  return cut ? '…（已截断，仅显示最近的日志）\n$text' : text;
}

/// 落盘日志的可能路径（去重；只用于界面提示，不做操作）。
List<String> crashLogPaths() => <String>{
      CrashLog.logPath,
      if (Platform.isWindows) r'E:\Dizi\logs\crash.log',
    }.toList(growable: false);

/// 读取落盘崩溃日志的尾部；文件不存在或读失败返回空串。
///
/// 大文件只读最后 512 KB，避免把内存和 IO 拖住。
Future<String> readCrashLogTail({
  String? path,
  int maxChars = 20000,
  int maxLines = 400,
  int readBytes = 512 * 1024,
}) async {
  final p = path ?? CrashLog.logPath;
  try {
    final f = File(p);
    if (!f.existsSync()) return '';
    final len = f.lengthSync();
    if (len <= 0) return '';
    String raw;
    if (len > readBytes && readBytes > 0) {
      final raf = f.openSync();
      try {
        raf.setPositionSync(len - readBytes);
        final bytes = raf.readSync(readBytes);
        raw = utf8.decode(bytes, allowMalformed: true);
        // 从文件中间开始时，首行多半是半截，丢掉。
        final nl = raw.indexOf('\n');
        if (nl >= 0) raw = raw.substring(nl + 1);
      } finally {
        raf.closeSync();
      }
    } else {
      raw = f.readAsStringSync();
    }
    return crashTailOf(raw, maxChars: maxChars, maxLines: maxLines);
  } catch (_) {
    return '';
  }
}

/// 落盘日志的一句话状态：不存在时返回 null。
Future<String?> crashLogFileInfo({String? path}) async {
  final p = path ?? CrashLog.logPath;
  try {
    final f = File(p);
    if (!f.existsSync()) return null;
    final len = f.lengthSync();
    final at = f.statSync().modified;
    String two(int n) => n.toString().padLeft(2, '0');
    final size = len < 1024
        ? '$len B'
        : (len < 1024 * 1024
            ? '${(len / 1024).toStringAsFixed(1)} KB'
            : '${(len / (1024 * 1024)).toStringAsFixed(1)} MB');
    return '$size · 最近写入 '
        '${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}';
  } catch (_) {
    return null;
  }
}

/// 错误 → 一行可读文本（去换行、限长，避免把整段 JSON 塞进界面）。
String describeError(Object error) {
  var s = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) s = '未知错误';
  if (s.length > 600) s = '${s.substring(0, 600)}…';
  return s;
}

bool _installed = false;

/// 装全局兜底。幂等；只在 `main()` 里调用一次。
void installCrashGuard() {
  if (_installed) return;
  _installed = true;

  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    CrashLog.instance.record(details.exception,
        kind: 'widget', stack: details.stack);
    // 保留默认行为：debug 下仍然打印完整错误，方便开发定位。
    if (kDebugMode) (previous ?? FlutterError.presentError)(details);
  };

  // 未捕获的异步异常：记录下来，返回 true 表示已处理，App 继续运行。
  PlatformDispatcher.instance.onError = (error, stack) {
    CrashLog.instance.record(error, kind: 'async', stack: stack);
    return true;
  };

  // 单个部件构建失败时只坏一块，不再整页灰屏。
  ErrorWidget.builder = (details) => CrashFallback.fromDetails(details);
}

/// 构建失败时的占位块：深色底 + 一句提示 + 截断的错误摘要。
///
/// 注意：它会出现在任意位置（可能没有 Material/MediaQuery/Directionality），
/// 所以这里自带 `Directionality`，并且不读取任何 inherited widget。
class CrashFallback extends StatelessWidget {
  final String message;

  const CrashFallback({super.key, required this.message});

  factory CrashFallback.fromDetails(FlutterErrorDetails details) =>
      CrashFallback(message: describeError(details.exception));

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: const Color(0xFF1A1F24),
        padding: const EdgeInsets.all(10),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 22, color: Color(0xFFE0A030)),
            const SizedBox(height: 6),
            const Text(
              '此区域加载出错',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            if (message.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
