// 非用户暂停诊断（「播放中随机自动暂停」排查用）。
//
// 目标：每一条可能让播放停下来的路径（player.pause / 槽位 stop / 解码重建 /
// 生命周期切后台 / 卡顿自动恢复）都留一条带调用方与栈顶的本地记录，真机复现后
// 直接回看就能判断「这次暂停是谁按的」。
//
// 约定（隐私红线）：
//  - 只写本地日志文件（与崩溃日志同目录，Windows 落 E:\Dizi\logs），不联网；
//  - 只记录原因、时间、栈顶几行，不记录媒体路径/文件名；
//  - 内存里保留最近 [PauseTrace.maxEntries] 条供诊断页回看。
import 'dart:io';

import 'crash_guard.dart';
import 'time_labels.dart';

/// 一条暂停记录。
class PauseTraceEntry {
  final DateTime at;
  final String reason;

  /// 调用方栈（已裁剪为前几行，去掉框架噪声）。
  final String stack;

  const PauseTraceEntry({
    required this.at,
    required this.reason,
    required this.stack,
  });

  String get timeText => clockHmsMs(at);

  /// 一行文本：`HH:mm:ss.SSS  reason  <- 调用方`。
  String get line {
    final first = stack.isEmpty ? '' : stack.split('\n').first.trim();
    return '$timeText  $reason'
        '${first.isEmpty ? '' : '  <- $first'}';
  }

  @override
  String toString() => line;
}

/// 全局暂停轨迹（进程内单例）。
class PauseTrace {
  PauseTrace._();

  /// 内存里保留的条数上限。
  static const int maxEntries = 200;

  static final List<PauseTraceEntry> _entries = <PauseTraceEntry>[];

  /// 测试可覆盖日志目录；默认与崩溃日志同目录。
  static String? logDirOverride;

  static String get logDir => logDirOverride ?? CrashLog.logDir;

  static String get logPath => '$logDir/pause.log';

  /// 打一条暂停点。
  ///
  /// [reason] 用 `来源:动作` 的格式，便于 grep：
  ///  - `user:toggle` / `user:seek-drag` / `user:double-tap-restore`
  ///  - `lifecycle:hidden` / `lifecycle:paused`
  ///  - `failure:decode` / `failure:timeout`
  ///  - `open:stop-current` / `open:stop-old-slot` / `decode:rebuild`
  ///  - `preload:stop-idle`
  ///  - `stall:retryPlay#1` / `stall:reopen#2` / `stall:giveup`
  static void mark(String reason, {StackTrace? stack, int frames = 6}) {
    final raw = (stack ?? StackTrace.current).toString();
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(frames)
        .join('\n');
    final entry = PauseTraceEntry(
      at: DateTime.now(),
      reason: reason,
      stack: lines,
    );
    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
    _appendFile(entry);
  }

  /// 供真机回看：最近的暂停记录（默认全部，按时间正序）。
  static List<PauseTraceEntry> pauseTraces({int? limit}) {
    final list = List<PauseTraceEntry>.unmodifiable(_entries);
    if (limit == null || limit >= list.length) return list;
    return list.sublist(list.length - limit);
  }

  /// 多行文本，直接贴给诊断页/日志。
  static String dump({int limit = 60}) {
    final list = pauseTraces(limit: limit);
    if (list.isEmpty) return '(pause trace empty)';
    return list.map((e) => e.line).join('\n');
  }

  static void clear() => _entries.clear();

  static void _appendFile(PauseTraceEntry e) {
    try {
      final d = Directory(logDir);
      if (!d.existsSync()) d.createSync(recursive: true);
      final f = File(logPath);
      // 单文件超过 256KB 时轮换，避免真机长期运行写爆存储。
      if (f.existsSync() && f.lengthSync() > 256 * 1024) {
        final old = File('$logPath.1');
        if (old.existsSync()) old.deleteSync();
        f.renameSync(old.path);
      }
      f.writeAsStringSync(
        '${e.timeText}\t${e.reason}\t${e.stack.replaceAll('\n', ' | ')}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // 日志写入失败不影响播放。
    }
  }
}
