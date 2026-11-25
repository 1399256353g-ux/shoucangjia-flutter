// T4：封面/缩略图缓存（不落 C 盘，可限额、可自动清理）。
//
// 背景：`flutter_cache_manager` 默认用 `getTemporaryDirectory()`，Windows 上
// 即 `C:\Users\<用户>\AppData\Local\Temp`，长期播放会把 C 盘写满。
//
// 规则（owner 2026-11-16）：
//  - Windows 固定落 `E:\Dizi\cache\covers`；其它平台落临时目录下的 `dizi_covers`。
//  - 默认上限 512 MB，可选 128/256/512/1024/2048；超限按「最久未使用」淘汰。
//  - 启动清理一次（过期 + 超容量）；运行中每 30 分钟或累计新增 64 MB 再清理；
//    退到后台/退出前再清理一次（不阻塞退出）。
//  - 只清理本 App 的缓存目录，绝不触碰其它临时文件。
import 'dart:async';
import 'dart:io';

import 'package:file/file.dart' as pkgfile;
import 'package:file/local.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'byte_size.dart';
import 'json_num.dart';
import 'media_resize.dart';

// `formatBytes` 的唯一定义在 `byte_size.dart`（第十二批收口）；
// 这里 re-export，使既有 import 'cover_cache.dart' 的调用点与测试不必改。
export 'byte_size.dart' show formatBytes;

/// Windows 缓存根目录（E 盘；严禁 C 盘）。
const String kWindowsCacheDir = r'E:\Dizi\cache\covers';

/// 超容量淘汰顺序（**唯一定义**）：最久未使用（mtime 最早）的排在前面。
///
/// **同一毫秒必须按路径兜底**。首次打开网格、批量预取时几十张封面会在同一
/// 毫秒内落盘，`List.sort` 又不保证稳定——只按时间比较等于「淘汰哪几张
/// 取决于排序内部结果」：同一个缓存目录清两次，留下的文件不一样，命中率
/// 读数也跟着抖，而用户看到的只是「有些封面又变糊了」。同时间按路径升序，
/// 结果与目录遍历顺序无关，清两次留下的是同一批。
List<MapEntry<File, DateTime>> coverSweepOrder(
    List<MapEntry<File, DateTime>> entries) {
  final out = List<MapEntry<File, DateTime>>.of(entries);
  out.sort((a, b) {
    final c = a.value.compareTo(b.value);
    return c != 0 ? c : a.key.path.compareTo(b.key.path);
  });
  return out;
}

/// 缓存占用统计。
class CacheUsage {
  final int bytes;
  final int files;
  const CacheUsage(this.bytes, this.files);

  static const CacheUsage empty = CacheUsage(0, 0);

  String get human => formatBytes(bytes);
}

/// 自定义缓存目录：缓存文件只写在这里。
class DiziCacheFileSystem implements FileSystem {
  final Future<pkgfile.Directory> _dir;
  DiziCacheFileSystem(String path) : _dir = _ensure(path);

  static Future<pkgfile.Directory> _ensure(String path) async {
    const fs = LocalFileSystem();
    final dir = fs.directory(path);
    try {
      if (!(await dir.exists())) await dir.create(recursive: true);
    } catch (_) {
      // 缓存是尽力而为：目标盘不存在/无权限（如 CI 的 Windows runner 没有 E 盘）
      // 时不能把构造期的 Future 变成未捕获异常——那会让整个调用方判定失败。
      // 后续真正写文件时再自然失败，由调用方静默跳过即可。
    }
    return dir;
  }

  @override
  Future<pkgfile.File> createFile(String name) async {
    final d = await _dir;
    if (!(await d.exists())) await d.create(recursive: true);
    return d.childFile(name);
  }
}

/// `?w=` 请求的「超尺寸响应」判定（纯函数，便于测试）。
///
/// 服务端缩图首次请求时要现场 ffmpeg 生成，本次只能回原图（带 24h 缓存头）。
/// 而 flutter_cache_manager 不看服务端缓存头、按 stalePeriod（默认 14 天）存盘，
/// 于是这张卡在缓存过期前一直下载/解码原图——「封面加载慢」的主因之一。
/// 判定阈值按目标宽度给足余量：正常缩图远小于 `w * 1200` 字节。
bool oversizedResizeResponse(String url, int? contentLength) {
  if (contentLength == null || contentLength <= 0) return false;
  // 读 `w=` 走 [requestedImageWidth]（与 `withImageWidth` 写侧同一规则）：
  // 旧实现在这里又写了一个 `RegExp(r'[?&]w=(\d{2,4})(?:&|$)')`，
  // 只认半角小写 `w=` + 2–4 位数字 + `&`/结尾。实测 `?W=480`、
  // `?w=480#x`、`?w=12000` 三种真实地址都读不到宽度，于是一张**超大原图**
  // 被当成正常响应缓存 14 天 —— 那几张卡在缓存过期前永远拉原图。
  final w = requestedImageWidth(url);
  if (w == null) return false;
  final limit = mulSat(w, 1200);
  return contentLength > (limit < 150 * 1024 ? 150 * 1024 : limit);
}

/// 0.9.54：`?w=` 首次未命中时丢弃原图响应，等缩图生成后重取一次。
/// 只有同一 URL 第一次会重试；重试失败仍返回第一次的响应，不影响显示。
class ResizeAwareFileService extends FileService {
  ResizeAwareFileService(this._inner, {Duration? retryDelay})
      : retryDelay = retryDelay ?? const Duration(milliseconds: 700);

  final FileService _inner;
  final Duration retryDelay;
  final Set<String> _retried = <String>{};

  @override
  int get concurrentFetches => _inner.concurrentFetches;

  @override
  set concurrentFetches(int v) => _inner.concurrentFetches = v;

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    final first = await _inner.get(url, headers: headers);
    if (!oversizedResizeResponse(url, first.contentLength)) return first;
    if (!_retried.add(url)) return first;
    await Future<void>.delayed(retryDelay);
    FileServiceResponse second;
    try {
      second = await _inner.get(url, headers: headers);
    } catch (_) {
      return first;
    }
    // 第一次的大图响应不读取，直接取消订阅释放连接，避免白下几百 KB。
    try {
      await first.content.listen(null).cancel();
    } catch (_) {}
    return second;
  }
}

/// 统计下载字节数的文件服务：累计新增 64 MB 触发一次轻量清理。
class _CountingFileService extends FileService {
  final FileService _inner;
  final void Function(int bytes) _note;
  _CountingFileService(this._inner, this._note);

  @override
  int get concurrentFetches => _inner.concurrentFetches;

  @override
  set concurrentFetches(int v) => _inner.concurrentFetches = v;

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    final r = await _inner.get(url, headers: headers);
    final len = r.contentLength;
    if (len != null && len > 0) _note(len);
    return r;
  }
}

class DiziCache {
  static const String prefMaxMb = 'cache_max_mb';
  static const String prefKeepDays = 'cache_keep_days';
  static const String prefAutoClean = 'cache_auto_clean';

  static const int defaultMaxMb = 512;
  static const int defaultKeepDays = 14;
  static const bool defaultAutoClean = true;

  static const List<int> maxMbOptions = <int>[128, 256, 512, 1024, 2048];
  static const List<int> keepDayOptions = <int>[7, 14, 30];

  /// 累计新增多少字节后触发一次轻量清理（64 MB）。
  static const int sweepTriggerBytes = 64 * 1024 * 1024;

  static int maxMb = defaultMaxMb;
  static int keepDays = defaultKeepDays;
  static bool autoClean = defaultAutoClean;

  static String rootDir = '';
  static CacheManager? _manager;
  static Timer? _timer;
  static int _unsweptBytes = 0;
  static bool _sweeping = false;

  /// 缓存管理器；未调用 [init] 时用默认值惰性创建（测试/预览安全）。
  static CacheManager get manager => _manager ??= _build();

  static int get maxBytes => maxMb * 1024 * 1024;

  /// 条目上限由容量推导（按单张封面约 256 KB 估算），仅作兜底。
  static int get objectLimit {
    final n = maxBytes ~/ (256 * 1024);
    return n.clamp(100, 100000);
  }

  static CacheManager _build() {
    final dir = rootDir.isNotEmpty ? rootDir : _fallbackDirSync();
    return CacheManager(Config(
      'dizi_covers',
      stalePeriod: Duration(days: keepDays),
      maxNrOfCacheObjects: objectLimit,
      fileSystem: DiziCacheFileSystem(dir),
      fileService: _CountingFileService(
          ResizeAwareFileService(HttpFileService()), _noteBytes),
    ));
  }

  /// 非 Windows 且尚未初始化时的同步兜底目录。
  static String _fallbackDirSync() =>
      Platform.isWindows ? kWindowsCacheDir : p.join(
          Directory.systemTemp.path, 'dizi_covers');

  /// 解析缓存根目录：Windows 固定 E 盘；其它平台临时目录/App 缓存目录。
  static Future<String> resolveRoot() async {
    if (Platform.isWindows) return kWindowsCacheDir;
    try {
      final d = await getTemporaryDirectory();
      return p.join(d.path, 'dizi_covers');
    } catch (_) {
      return _fallbackDirSync();
    }
  }

  /// 启动初始化：读设置 → 建目录/管理器 → 清旧临时缓存 → 首次清理 → 定时器。
  ///
  /// [sweepOnStart] 为 false 时跳过首次全目录清理（仍启动定时器），
  /// 供 App 冷启动使用：清理遍历每个缓存文件做一次 stat，移动端缓存
  /// 上万条时会把首帧推迟到几秒后；调用方可在首帧后自行 `sweep()`。
  static Future<void> init({bool sweepOnStart = true}) async {
    await _loadPrefs();
    rootDir = await resolveRoot();
    _manager = _build();
    await _cleanLegacyTempDirs();
    if (sweepOnStart) await sweep();
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 30), (_) => unawaited(sweep(light: true)));
  }

  static Future<void> _loadPrefs() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final m = sp.getInt(prefMaxMb);
      if (m != null && maxMbOptions.contains(m)) maxMb = m;
      final d = sp.getInt(prefKeepDays);
      if (d != null && keepDayOptions.contains(d)) keepDays = d;
      final a = sp.getBool(prefAutoClean);
      if (a != null) autoClean = a;
    } catch (_) {}
  }

  static Future<void> setMaxMb(int v) async {
    if (!maxMbOptions.contains(v)) return;
    maxMb = v;
    await _persist();
    await sweep(light: true);
  }

  static Future<void> setKeepDays(int v) async {
    if (!keepDayOptions.contains(v)) return;
    keepDays = v;
    await _persist();
    await sweep(light: true);
  }

  static Future<void> setAutoClean(bool v) async {
    autoClean = v;
    await _persist();
    if (v) await sweep(light: true);
  }

  static Future<void> _persist() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(prefMaxMb, maxMb);
      await sp.setInt(prefKeepDays, keepDays);
      await sp.setBool(prefAutoClean, autoClean);
    } catch (_) {}
  }

  /// 删除旧版本默认落到 `%TEMP%` 的缓存目录（只这两个，不碰其它临时文件）。
  static Future<void> _cleanLegacyTempDirs() async {
    if (!Platform.isWindows) return;
    final temp = Platform.environment['TEMP'];
    if (temp == null || temp.isEmpty) return;
    for (final name in const ['libCachedImageData', 'dizi_covers']) {
      final path = p.join(temp, name);
      if (rootDir.isNotEmpty && p.equals(path, rootDir)) continue;
      try {
        final d = Directory(path);
        if (await d.exists()) await d.delete(recursive: true);
      } catch (_) {}
    }
  }

  static void _noteBytes(int bytes) {
    _unsweptBytes += bytes;
    if (_unsweptBytes >= sweepTriggerBytes) {
      _unsweptBytes = 0;
      unawaited(sweep(light: true));
    }
  }

  /// 统计缓存目录占用（字节 + 文件数）。
  static Future<CacheUsage> measure() async {
    final dir = Directory(rootDir);
    if (!await dir.exists()) return CacheUsage.empty;
    var bytes = 0;
    var files = 0;
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            bytes += await e.length();
            files++;
          } catch (_) {}
        }
      }
    } catch (_) {}
    return CacheUsage(bytes, files);
  }

  /// 清理：过期（保留天数）+ 超容量（LRU）。返回释放字节数。
  ///
  /// [light] 为真时只做超容量检查（运行中调用，便宜）。
  static Future<int> sweep({bool light = false}) async {
    if (_sweeping) return 0;
    if (!autoClean) return 0;
    if (rootDir.isEmpty) return 0;
    _sweeping = true;
    try {
      final dir = Directory(rootDir);
      if (!await dir.exists()) return 0;
      final entries = <MapEntry<File, DateTime>>[];
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        try {
          final st = await e.stat();
          entries.add(MapEntry(e, st.modified));
        } catch (_) {}
      }
      var freed = 0;
      var total = 0;
      for (final en in entries) {
        try {
          total += await en.key.length();
        } catch (_) {}
      }

      final cutoff = DateTime.now().subtract(Duration(days: keepDays));
      final removed = <File>{};
      if (!light) {
        for (final en in entries) {
          if (en.value.isBefore(cutoff)) {
            try {
              final len = await en.key.length();
              await en.key.delete();
              freed += len;
              total -= len;
              removed.add(en.key);
            } catch (_) {}
          }
        }
      }
      if (total > maxBytes) {
        final rest = coverSweepOrder([
          for (final en in entries)
            if (!removed.contains(en.key)) en
        ]);
        for (final en in rest) {
          if (total <= maxBytes) break;
          try {
            final len = await en.key.length();
            await en.key.delete();
            freed += len;
            total -= len;
          } catch (_) {}
        }
      }
      _unsweptBytes = 0;
      return freed;
    } finally {
      _sweeping = false;
    }
  }

  /// 立即清空（设置页按钮）。返回释放字节数。
  static Future<int> clearAll() async {
    final before = await measure();
    try {
      await manager.emptyCache();
    } catch (_) {}
    final dir = Directory(rootDir);
    if (await dir.exists()) {
      try {
        await for (final e in dir.list(followLinks: false)) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      } catch (_) {}
    }
    _unsweptBytes = 0;
    return before.bytes;
  }

  /// 备份用：退出/退后台时调用（不阻塞）。
  static void sweepOnExit() {
    unawaited(sweep(light: true));
  }

  // ---------------------------------------------------------------------
  // 按库淘汰（owner 2026-11-22「卡片快速刷新」第 3 步）。
  //
  // flutter_cache_manager 只按 URL 存取、没有「这个库有哪些 URL」的反向索引，
  // 所以由渲染端在请求封面时登记 `url → lib`，刷新时按库精确删除。
  // 只登记本进程见过的 URL（内存，不落盘、不联网），上限 [_kUrlIndexCap]。
  // ---------------------------------------------------------------------

  static const int _kUrlIndexCap = 4000;
  static final Map<String, Set<String>> _urlsByLib = <String, Set<String>>{};
  static final Map<String, String> _libByUrl = <String, String>{};

  /// 渲染封面时登记：这个 URL 属于哪个库。空 lib/url 直接忽略。
  static void noteUrl(String libId, String url) {
    final l = libId.trim();
    final u = url.trim();
    if (l.isEmpty || u.isEmpty) return;
    final prev = _libByUrl[u];
    if (prev == l) return;
    if (prev != null) _urlsByLib[prev]?.remove(u);
    _libByUrl[u] = l;
    (_urlsByLib[l] ??= <String>{}).add(u);
    if (_libByUrl.length > _kUrlIndexCap) {
      // 超上限就整体清空重建，避免无界增长（只影响淘汰精度，不影响功能）。
      _libByUrl.clear();
      _urlsByLib.clear();
      _libByUrl[u] = l;
      (_urlsByLib[l] ??= <String>{}).add(u);
    }
  }

  /// 清掉某库已知的全部封面缓存（磁盘 + 内存图片缓存）。返回删除条数。
  static Future<int> evictLib(String libId) async {
    final l = libId.trim();
    if (l.isEmpty) return 0;
    final urls = _urlsByLib.remove(l)?.toList() ?? const <String>[];
    var n = 0;
    for (final u in urls) {
      _libByUrl.remove(u);
      try {
        await manager.removeFile(u);
        n++;
      } catch (_) {}
    }
    try {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
    } catch (_) {}
    return n;
  }
}
