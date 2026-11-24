/// 轻量性能诊断（0.9.55 · iOS 卡死定位）。
///
/// 只做本地记录，不联网、不上传：
///  - 首帧耗时（[markAppStart] → [markFirstFrame]）；
///  - 启动各阶段耗时（[step]）；
///  - 图片解码并发峰值/等待（由 `ThumbPrefetch` 调用 [recordDecode]）；
///  - 播放器槽位创建/释放计数与存活数（播放页调用 [slotCreated]/[slotsReleased]）；
///  - 页面进入耗时（[beginSpan]/[endSpan]）。
///
/// 日志落本地：Windows `E:\Dizi\logs\perf.log`，其它平台系统临时目录下的
/// `dizi_logs/perf.log`；写入前超过 1 MB 就先清空；任何失败静默。
/// 落盘用异步链（[_tail]）串行追加，避免在主 isolate 做同步文件 IO。
library;

import 'dart:async';
import 'dart:io';

import 'time_labels.dart';

/// 日志文件上限：超过就先截断（清空）再写。
const int kPerfLogMaxBytes = 1024 * 1024;

/// 日志文件名。
const String kPerfLogFileName = 'perf.log';

/// 内存中保留的最近日志行数（供诊断页/测试查看）。
const int kPerfTimelineLimit = 200;

/// 本地时间 → `2026-11-17T23:14:05.123`（带毫秒，便于对齐卡顿时间点）。
String perfIsoMs(DateTime at) => isoLikeLocalMs(at);

/// 一行日志：时间 + 标签 + `k=v` 字段（保持字段插入顺序）。
///
/// 值里的换行/回车替换成空格，避免一条记录被拆成多行；空值省略。
String perfLogLine(
  DateTime at,
  String tag, [
  Map<String, Object?> fields = const <String, Object?>{},
]) {
  final b = StringBuffer('${perfIsoMs(at)} $tag');
  fields.forEach((k, v) {
    if (v == null) return;
    final s = '$v'.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (s.isEmpty) return;
    b.write(' $k=$s');
  });
  return b.toString();
}

/// 落盘前是否需要截断：当前长度超过 [maxBytes]。
bool perfLogNeedsTruncate(int length, {int maxBytes = kPerfLogMaxBytes}) {
  if (maxBytes <= 0) return false;
  return length > maxBytes;
}

/// 默认日志目录（纯函数便于测试）：Windows 固定 E 盘，其它平台临时目录。
String perfLogDirDefault({
  bool? isWindows,
  String? tempDir,
  String? windowsDir,
}) {
  final win = isWindows ?? Platform.isWindows;
  if (win) return windowsDir ?? r'E:\Dizi\logs';
  final temp = tempDir ?? Directory.systemTemp.path;
  return '$temp/dizi_logs';
}

/// 全局诊断实例。所有入口都容错：任何异常都不影响业务。
class PerfDiagnostics {
  PerfDiagnostics({
    String? logDir,
    DateTime Function()? clock,
    this.maxBytes = kPerfLogMaxBytes,
    this.writeFile = true,
  })  : _logDir = logDir,
        _clock = clock ?? DateTime.now;

  static final PerfDiagnostics instance = PerfDiagnostics();

  final String? _logDir;
  final DateTime Function() _clock;
  final int maxBytes;

  /// 便于单测关闭落盘；App 内始终为 true。
  final bool writeFile;

  DateTime? _startedAt;
  Duration? firstFrameMs;

  int slotsAlive = 0;
  int slotsPeak = 0;
  int slotsCreated = 0;
  int slotsDisposed = 0;

  int decodePeakActive = 0;
  int decodePeakWaiting = 0;
  int decodeLimit = 0;
  int decodeSamples = 0;

  final List<String> _timeline = <String>[];
  final Map<String, DateTime> _spans = <String, DateTime>{};
  Future<void> _tail = Future<void>.value();
  Timer? _heartbeat;
  int _heartbeatTicks = 0;

  String get logDir => _logDir ?? perfLogDirDefault();
  String get logPath => '$logDir/$kPerfLogFileName';

  /// 最近日志（内存副本，最新在尾部）。
  List<String> get timeline => List<String>.unmodifiable(_timeline);

  /// 从启动到现在的毫秒数；未标记启动时返回 0。
  int get elapsedMs {
    final s = _startedAt;
    if (s == null) return 0;
    return _clock().difference(s).inMilliseconds;
  }

  /// 记下 App 启动时刻（`main()` 最开始调用一次）。
  void markAppStart([DateTime? at]) {
    _startedAt = at ?? _clock();
  }

  /// 启动阶段打点：`startup step=xxx ms=123`。
  void step(String name) {
    log('startup', <String, Object?>{'step': name, 'ms': elapsedMs});
  }

  /// 首帧出现（runApp 之后 post-frame 调用）：记录并开启 2 分钟心跳采样。
  void markFirstFrame([DateTime? at]) {
    final now = at ?? _clock();
    final start = _startedAt;
    final ms = start == null ? -1 : now.difference(start).inMilliseconds;
    if (ms >= 0) firstFrameMs = Duration(milliseconds: ms);
    log('first_frame', <String, Object?>{'ms': ms});
    _startHeartbeat();
  }

  /// 追加一条日志：先进内存，再异步落盘（串行，不阻塞调用方）。
  void log(
    String tag, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    final line = perfLogLine(_clock(), tag, fields);
    _timeline.add(line);
    if (_timeline.length > kPerfTimelineLimit) {
      _timeline.removeRange(0, _timeline.length - kPerfTimelineLimit);
    }
    if (!writeFile) return;
    _tail = _tail.then((_) => _append(line));
  }

  /// 等待所有已排队的落盘完成（测试用；App 内无需调用）。
  Future<void> flush() => _tail;

  Future<void> _append(String line) async {
    try {
      final d = Directory(logDir);
      if (!await d.exists()) await d.create(recursive: true);
      final f = File(logPath);
      final len = await f.exists() ? await f.length() : 0;
      if (perfLogNeedsTruncate(len, maxBytes: maxBytes)) {
        await f.writeAsString('', flush: false);
      }
      await f.writeAsString('$line\n', mode: FileMode.append, flush: false);
    } catch (_) {
      // 静默：诊断日志绝不能影响业务。
    }
  }

  /// 页面进入耗时：begin 记开始，end 记录毫秒数（未 begin 记 -1）。
  void beginSpan(String name) {
    if (name.isEmpty) return;
    _spans[name] = _clock();
  }

  void endSpan(
    String name, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    final start = _spans.remove(name);
    final ms = start == null ? -1 : _clock().difference(start).inMilliseconds;
    log('span', <String, Object?>{'name': name, 'ms': ms, ...fields});
  }

  /// 播放器槽位创建（含当前播放槽位与预加载槽位）。
  void slotCreated() {
    slotsAlive++;
    slotsCreated++;
    if (slotsAlive > slotsPeak) slotsPeak = slotsAlive;
    log('slot', <String, Object?>{
      'ev': 'create',
      'alive': slotsAlive,
      'created': slotsCreated,
      'disposed': slotsDisposed,
    });
  }

  /// 播放器槽位释放（[count] 个）。
  void slotsReleased([int count = 1]) {
    final n = count < 0 ? 0 : count;
    if (n == 0) return;
    slotsAlive -= n;
    if (slotsAlive < 0) slotsAlive = 0;
    slotsDisposed += n;
    log('slot', <String, Object?>{
      'ev': 'release',
      'alive': slotsAlive,
      'created': slotsCreated,
      'disposed': slotsDisposed,
    });
  }

  /// 图片解码并发采样（由 `ThumbPrefetch` 每次预取结束时上报）。
  void recordDecode({
    required int active,
    required int waiting,
    int limit = 0,
  }) {
    decodeSamples++;
    if (active > decodePeakActive) decodePeakActive = active;
    if (waiting > decodePeakWaiting) decodePeakWaiting = waiting;
    if (limit > 0) decodeLimit = limit;
  }

  /// 当前计数器快照。
  Map<String, Object?> snapshot() => <String, Object?>{
        'first_frame_ms': firstFrameMs?.inMilliseconds ?? -1,
        'slots_alive': slotsAlive,
        'slots_peak': slotsPeak,
        'slots_created': slotsCreated,
        'slots_disposed': slotsDisposed,
        'decode_peak_active': decodePeakActive,
        'decode_peak_waiting': decodePeakWaiting,
        'decode_limit': decodeLimit,
        'decode_samples': decodeSamples,
      };

  /// 清空内存计数（单测用）。
  void reset() {
    _startedAt = null;
    firstFrameMs = null;
    slotsAlive = 0;
    slotsPeak = 0;
    slotsCreated = 0;
    slotsDisposed = 0;
    decodePeakActive = 0;
    decodePeakWaiting = 0;
    decodeLimit = 0;
    decodeSamples = 0;
    _timeline.clear();
    _spans.clear();
  }

  /// 首帧后采样 2 分钟（每 5 秒一次），覆盖「进页面/播放后卡死」的时间窗。
  void _startHeartbeat() {
    if (!writeFile || _heartbeat != null) return;
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (t) {
      _heartbeatTicks++;
      log('sample', snapshot());
      if (_heartbeatTicks >= 24) {
        t.cancel();
        _heartbeat = null;
      }
    });
  }

  /// 停止心跳（页面退出/单测用）。
  void stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }
}
