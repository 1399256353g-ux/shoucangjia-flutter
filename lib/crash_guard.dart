// 闪退兜底 + 崩溃日志（0.9.23 稳定性）。
//
// 目标：
//  - 单个部件构建失败时不再整页灰屏/红屏，只坏那一块（`CrashFallback`）；
//  - 未捕获的异步异常不再让界面「无声无息」停住，记下来继续跑；
//  - 记录只在内存里（最多 50 条，同名错误合并计数），供「设置 → 诊断信息」查看，
//    不写文件、不上传，符合 NAS 隐私红线。
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
    notifyListeners();
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
