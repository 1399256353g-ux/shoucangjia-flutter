import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 死实现防回归契约（owner 2026-11-24）。
///
/// 0.9.193 删「右侧互动栏」、0.9.199 删「信息区面板」、0.9.200 删「亮度/边缘
/// 滑动」，本轮删掉第四批：**lib/ 里定义了、只有 test/ 在断言的公开符号**。
/// 它们共同的特征不是「没用了」，而是「测试为一块不存在的界面作证」——
/// 单测全绿，产品里却没有任何代码路径走到它，于是真正的那条路径没有任何
/// 测试拦得住。
///
/// 本文件钉住这一批，防止有人为了「补测试覆盖」把死代码又搬回来。
void main() {
  List<File> libDartFiles() {
    final dir = Directory('lib');
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  String libSourceAll() =>
      libDartFiles().map((f) => f.readAsStringSync()).join('\n');

  group('已删除的死实现在 lib/ 内不得复活', () {
    test('预载计划：shouldPreloadNext / preloadMatches 不得再定义', () {
      // 真实预载决策只走 preload_pool.dart 的 planPreloadPool。
      final src = libSourceAll();
      expect(src.contains('shouldPreloadNext'), isFalse);
      expect(src.contains('preloadMatches'), isFalse);
    });

    test('震动门控：SwitchHapticGate / hapticAllowedFor 不得再定义', () {
      // 真实翻页震动走 lib/haptics.dart 的 hapticTap()。
      final src = libSourceAll();
      expect(src.contains('SwitchHapticGate'), isFalse);
      expect(src.contains('hapticAllowedFor'), isFalse);
    });

    test('播放敕底：shouldForcePlay / shouldStartupReopen 不得再定义', () {
      // 真实自救只走 stallRecoveryAction + startupSignal。
      final src = libSourceAll();
      expect(src.contains('shouldForcePlay'), isFalse);
      expect(src.contains('shouldStartupReopen'), isFalse);
    });

    test('作者快捷条：AuthorQuickChips 不得再定义', () {
      // 真实作者筛选用 AuthorFilterBar（按钮 + 摘要 + 清空）。
      expect(libSourceAll().contains('AuthorQuickChips'), isFalse);
    });
  });

  group('第六批：删掉的替身不得复活（2026-11-24）', () {
    const gone = [
      'authorGridGeometry', // 真实：SliverGridDelegateWithMaxCrossAxisExtent(150)
      'AuthorGridStyle', // 9 个常量零引用，取值写在页面里
      'toggleExpanded', // 真实：category_tree_page 自己维护 _expanded
      'treeFromPaths', // 真实：服务端 /api/cat/tree 下发 parseCategoryTree
      'validateAuthorDirName', // 真实改名只走 validateCategoryName
      'firstWorkCoverPath', // 真实：BasicLib.firstCover（fc）单一来源
      'continueResumeMs', // 真实：watch_progress.resumeMs
      'formatContinueLabel', // 「继续观看」卡片不存在，只有菜单里一行
      'formatContinueDuration',
      'isManualWork', // 真实：widget.manualIds.contains
      'avatarCropNormalizedOffset', // 裁切只存像素偏移，从不归一化
      'avatarCropOffsetFromNormalized',
      'normalizeSchedule', // 服务端字段，客户端只回显 04:10
      'normalizeInterval',
      'unitCrawlerConfigurable', // 真实：unitCrawlerFlags
      'playbackLoadTimedOut', // 真实：Timer(playbackLoadTimeout)
      'hasBrokenText', // 真实：fixDisplayName / fixEmojiText
      'containsAstralChar',
      'coverPointerRel', // 真实：服务端拼 `_cover/current`
      'pickAutoCover', // 真实：work_plays.topPlayed
      'videoViewportHeight', // 真实：stageBottomInset
      'taskbarBottomInset', // 任务栏跟随视频已关闭，恒贴底
    ];

    test('22 个替身在 lib/ 内一个都不许回来', () {
      final src = libSourceAll();
      final alive = gone.where(src.contains).toList();
      expect(alive, isEmpty, reason: '这些符号已被删除，必须由真实路径承载');
    });

    test('真实路径仍在', () {
      final src = libSourceAll();
      expect(src.contains('SliverGridDelegateWithMaxCrossAxisExtent'), isTrue);
      expect(src.contains('topPlayed('), isTrue);
      expect(src.contains('int resumeMs('), isTrue);
      expect(src.contains('stageBottomInset('), isTrue);
      expect(src.contains('final String firstCover'), isTrue);
      expect(src.contains('Timer(playbackLoadTimeout'), isTrue);
    });
  });

  group('真实路径仍在（删的是替身，不是本体）', () {
    test('预载池计划、自救策略、启动判定、震动、作者筛选条都在', () {
      final src = libSourceAll();
      expect(src.contains('planPreloadPool'), isTrue);
      expect(src.contains('stallRecoveryAction'), isTrue);
      expect(src.contains('startupSignal'), isTrue);
      expect(src.contains('hapticTap'), isTrue);
      expect(src.contains('class AuthorFilterBar'), isTrue);
      expect(src.contains('preloadMediaPath'), isTrue);
      expect(src.contains('preloadKeyFor'), isTrue);
    });
  });

  group('第七批（0.9.205）：未接线抽象 / 孤儿模块 / 无消费 getter', () {
    test('player_backend 不得回到 lib/（播放页仍直接用 media_kit）', () {
      final files = libDartFiles().map((f) => f.path).toList();
      expect(files.any((p) => p.endsWith('player_backend.dart')), isFalse,
          reason: '该抽象零 import，骨架已移到 docs/skeletons/');
      final src = libSourceAll();
      expect(src.contains('selectPlayerBackendKind'), isFalse);
      expect(src.contains('MpvBackend'), isFalse);
    });

    test('cover_memo 孤儿模块不得复活', () {
      final files = libDartFiles().map((f) => f.path).toList();
      expect(files.any((p) => p.endsWith('cover_memo.dart')), isFalse);
      expect(libSourceAll().contains('CoverMemo'), isFalse);
    });

    test('videoContentRect 不得复活（真实排版走 media_kit 的 BoxFit）', () {
      expect(libSourceAll().contains('videoContentRect'), isFalse);
    });

    test('pickOnlyIn / countMatchingAuthors / needsAvatarPlaceholder 不得复活', () {
      final src = libSourceAll();
      expect(src.contains('pickOnlyIn'), isFalse);
      expect(src.contains('countMatchingAuthors'), isFalse);
      expect(src.contains('needsAvatarPlaceholder'), isFalse);
    });

    test('isActivelyPlaying 是唯一「正在播放」判定，且真实路径在用', () {
      final src = libSourceAll();
      expect(src.contains('bool get isActivelyPlaying'), isTrue);
      // 真实相位应用点必须走这个 getter，而不是再写一遍 == playing。
      expect(src.contains('next.isActivelyPlaying'), isTrue);
    });
  });

  group('第八批（0.9.206）：单源缺陷 + lib/test 双零的死符号', () {
    /// 只查「定义形状」，不查注释/文档里的历史叙述。
    bool defines(String src, String pattern) =>
        RegExp(pattern, multiLine: true).hasMatch(src);

    test('轻震动只有 haptics.dart 一处实现（页面不得再内联 HapticFeedback）', () {
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('haptics.dart'))
          .where((f) => f.readAsStringSync().contains('HapticFeedback.'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '这些文件各自写了一份震动实现：$offenders');
      final src = libSourceAll();
      expect(defines(src, r'^void hapticTap\(\)'), isTrue);
      expect(defines(src, r'^void hapticSelect\(\)'), isTrue);
      expect(File('lib/haptics.dart').existsSync(), isTrue);
    });

    test('预载启动延迟只有一个取值处（300ms 死常量不得复活）', () {
      final src = libSourceAll();
      expect(defines(src, r'const int poolPreloadCooldownMs'), isFalse);
      expect(defines(src, r'const int preloadKickoffDelayMs = 120;'), isTrue);
      // 真实路径必须引用该常量，而不是再写一个字面量 120。
      expect(
          src.contains(
              'Timer(const Duration(milliseconds: preloadKickoffDelayMs)'),
          isTrue);
    });

    test('crashLogPaths 不得复活（真实界面只读 CrashLog.logPath）', () {
      expect(
          defines(libSourceAll(), r'^List<String> crashLogPaths\('), isFalse);
    });

    test('翻页吸附只留 pageSwipeTarget 一套规则', () {
      final src = libSourceAll();
      expect(defines(src, r'^double snapTargetPage\('), isFalse);
      expect(defines(src, r'const Duration kPageSnapMaxDuration'), isFalse);
      // 弹簧参数从未参与落位（落位早就是固定 110ms 的曲线）。
      expect(defines(src, r'const double kSnapStiffness'), isFalse);
      expect(defines(src, r'const double kSnapDampingRatio'), isFalse);
      expect(defines(src, r'^\s+final double stiffness;'), isFalse);
      expect(defines(src, r'^\s+final double dampingRatio;'), isFalse);
      // 真实路径仍在：
      expect(src.contains('double pageSwipeTarget('), isTrue);
      expect(src.contains('class FastSettleSimulation'), isTrue);
    });

    test('topPlayedAny 不得复活（封面规则只有 topPlayed）', () {
      final src = libSourceAll();
      expect(defines(src, r'^WorkPlay\? topPlayedAny\('), isFalse);
      expect(src.contains('WorkPlay? topPlayed('), isTrue);
    });

    test('同步日志解码走 decodeSyncJson（面板不再手写 jsonDecode）', () {
      final panel = File('lib/sync_log_panel.dart').readAsStringSync();
      expect(panel.contains('decodeSyncJson('), isTrue);
      expect(panel.contains('jsonDecode(utf8.decode('), isFalse,
          reason: '两处响应体解码必须共用一个实现');
      expect(libSourceAll().contains('dynamic decodeSyncJson('), isTrue);
    });
  });

  group('第九批（0.9.207）：同规则多份实现 + 无人调用的成员', () {
    test('亮度→前景色只有 contrast.dart 一处（词条与角标不得各写一份）', () {
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('contrast.dart'))
          .where((f) => f.readAsStringSync().contains('0.299'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '这些文件又抄了一份亮度公式：$offenders');
      expect(libSourceAll().contains('int foregroundArgbOn(int argb)'), isTrue);
    });

    test('相对路径拆分/拼接只有 rel_path.dart 一处', () {
      // 此前 splitCatRel / splitRel / diskNameOf 内联链 是三份同规则实现。
      final quoted = RegExp(r"split\(RegExp\(r.\[\\\\\\\\/\]\+\.\)\)");
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('rel_path.dart'))
          .where((f) => quoted.hasMatch(f.readAsStringSync()))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '路径拆分又出现了内联拷贝：$offenders');
      final src = libSourceAll();
      expect(src.contains('List<String> relSegments(String rel)'), isTrue);
      // 旧名字保留为转调（调用点多，改名无收益），但不得再自带实现。
      expect(
          RegExp(r'^List<String> splitRel\(String rel\) => relSegments\(rel\);',
                  multiLine: true)
              .hasMatch(src),
          isTrue);
      expect(
          RegExp(r'^List<String> splitCatRel\(String rel\) => relSegments\(rel\);',
                  multiLine: true)
              .hasMatch(src),
          isTrue);
    });

    test('配置落盘只有 prefs_json.dart 一处（类里不得再写 try-catch 存盘）', () {
      final offenders = <String>[];
      for (final f in libDartFiles()) {
        if (f.path.endsWith('prefs_json.dart')) continue;
        final text = f.readAsStringSync();
        if (text.contains('await sp.setString(')) offenders.add(f.path);
      }
      expect(offenders, isEmpty, reason: '这些文件又手写了一份存盘：$offenders');
      expect(libSourceAll().contains('Future<void> savePrefString('), isTrue);
    });

    test('AuthorGrade 不再有两个名字做同一件事', () {
      final src = File('lib/author_grade.dart').readAsStringSync();
      expect(src.contains('static Future<void> save()'), isFalse,
          reason: 'save 与 cacheLocal 逐字相同，只保留 cacheLocal');
      expect(src.contains('static Future<void> cacheLocal()'), isTrue);
      expect(src.contains('savePrefString(prefsKey'), isTrue);
    });

    test('九批删掉的零引用成员不得复活', () {
      const gone = <String>[
        'bool get isLight',
        'static int unitColor(',
        'static String keyFor(String basicId)',
        'static double get closeFraction',
        'Map<String, String> get overrides',
        'static void invalidate(String lib)',
        'Set<String> typesFor(',
        'void cycleSpeed()',
        'bool legacyOpen',
        'static void updatePosition(',
      ];
      final src = libSourceAll();
      for (final g in gone) {
        expect(src.contains(g), isFalse, reason: '死成员复活：$g');
      }
    });

    test('崩溃判定的另一端已接线（clean_exit 必须有写入点）', () {
      // 这是本轮修的真 bug：写入函数一直存在，但没人调用，
      // 于是每次冷启动都把上一轮读成「疑似原生崩溃」。
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('Breadcrumb.cleanExit()'), isTrue,
          reason: 'cleanExit 必须被生命周期钩子调用');
      expect(main.contains('AppLifecycleState.paused'), isTrue);
      expect(
          File('lib/breadcrumb.dart')
              .readAsStringSync()
              .contains('static Future<void> cleanExit()'),
          isTrue);
    });
  });

  group('第十批（0.9.209）：同规则再收口 + 星标单一真相', () {
    test('「每 N 分钟/小时」只有 interval_label.dart 一处', () {
      // 此前 5 处各写一份 `>= 60 ? '每 N 小时' : '每 N 分钟'`：
      // main.dart 两处、unit_crawler_page.dart 两处、unit_crawler.dart 一处。
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('interval_label.dart'))
          .where((f) => f.readAsStringSync().contains("~/ 60} 小时"))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '间隔文案又出现了内联拷贝：$offenders');
      final src = libSourceAll();
      expect(src.contains('String everyMinutesLabel(int minutes)'), isTrue);
      // 真实调用点必须转调，不能只是留着一个没人用的函数。
      expect(
          File('lib/main.dart')
              .readAsStringSync()
              .contains('everyMinutesLabel('),
          isTrue);
      expect(
          File('lib/unit_crawler_page.dart')
              .readAsStringSync()
              .contains('everyMinutesLabel('),
          isTrue);
      expect(
          File('lib/unit_crawler.dart')
              .readAsStringSync()
              .contains('everyMinutesLabel('),
          isTrue);
    });

    test('状态码→文案只有 http_error_text.dart 一处', () {
      // 三个业务函数此前各自写了 400/500/default 三个相同分支。
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('http_error_text.dart'))
          .where((f) => f.readAsStringSync().contains("return '服务端写入失败';"))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '状态码文案又各写了一份：$offenders');
      expect(
          libSourceAll().contains('String httpErrorText(int status'), isTrue);
      // 三个业务包装必须仍在（业务 404 文案不同，不能一起删）。
      final src = libSourceAll();
      for (final fn in const [
        'String coverErrorText(int status)',
        'String coverActionErrorText(int status)',
        'String authorAvatarApiErrorText(int status)',
      ]) {
        expect(src.contains(fn), isTrue, reason: '业务入口被误删：$fn');
      }
    });

    test('星标只有 StarStore 一份状态（LibraryTree 不得再算 starred）', () {
      final tree = File('lib/library_tree.dart').readAsStringSync();
      expect(tree.contains('final List<BasicLib> starred;'), isFalse,
          reason: 'LibraryTree 又持有了第二份星标状态');
      expect(tree.contains('LibraryTree withStars('), isFalse);
      expect(tree.contains('List<BasicLib> visibleBasics('), isFalse);
      expect(tree.contains('orderStarred('), isFalse);
      // 真实星标入口仍在。
      expect(File('lib/star_store.dart').readAsStringSync(),
          contains('List<String> get ordered'));
      expect(libSourceAll().contains('List<String> toggleStar('), isTrue);
    });


    test('十批删掉的零引用成员不得复活', () {
      const gone = <String>[
        'AvatarCropBox', // 真实头像裁剪走 main.dart 的 avatarCropDisplaySize 一族
        'int get totalBasics',
      ];
      final src = libSourceAll();
      for (final g in gone) {
        expect(src.contains(g), isFalse, reason: '死成员复活：$g');
      }
    });
  });

  group('第十一批：同规则多份实现再收口（2026-11-24）', () {
    test('Basic 鉴权头只有 basic_auth.dart 一处格式', () {
      // 清理前 main.dart 里逐字手写了 7 份 base64(user:pass)。
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('basic_auth.dart'))
          .where((f) => f.readAsStringSync().contains("'Basic "))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '鉴权头格式又被手写了：$offenders');
      expect(
          File('lib/basic_auth.dart').readAsStringSync(),
          contains('String basicAuthHeader(String user, String pass)'));
      // 真实调用点必须还在（Cfg 的鉴权头仍从这一条出口出去）。
      expect(
          File('lib/main.dart')
              .readAsStringSync()
              .contains('basicAuthHeader(u, p)'),
          isTrue);
    });

    test('名次奖牌色只有 rank_medal.dart 一处', () {
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('rank_medal.dart'))
          .where((f) => f.readAsStringSync().contains('0xFFFFC107'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '奖牌色又复制了一份：$offenders');
      final src = libSourceAll();
      expect(src.contains('Color _rankColor('), isFalse,
          reason: '两个榜单各自的名次配色方法必须收成一个 rankColorFor');
      expect(src.contains('Color rankColorFor('), isTrue);
    });

    test('作者热区点击只有一个处理函数（三处热区共用）', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('void _authorTapOpen()'), isTrue);
      expect('onTap: _authorTapOpen'.allMatches(main).length, 3,
          reason: '头像 / 占位头像 / 作者名三处热区必须共用同一处理');
      // 真实打开动作只剩处理函数内部那一次调用。
      expect('openAuthor();'.allMatches(main).length, 1);
    });

    test('绑定表查字段只有 _bindingOf 一处算实际库 id', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('String _bindingOf('), isTrue);
      expect('libId ?? lib'.allMatches(main).length, 1,
          reason: '又有地方自己算 libId ?? lib 再查绑定表');
      for (final acc in const [
        'String serverIdFor([String? libId])',
        'String serverLabelFor([String? libId])',
        'Map<String, String> headersFor([String? libId])',
      ]) {
        expect(main.contains(acc), isTrue, reason: '访问器被误删：$acc');
      }
    });

    test('播放页不再重复 @override', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('@override\n  @override'), isFalse);
    });
  });

  group('第十二批：同规则多份实现收口', () {
    test('字节文案只有 formatBytes 一处（负数=0 B、四级含 GB）', () {
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('byte_size.dart'))
          .where((f) =>
              f.readAsStringSync().contains("toStringAsFixed(2)} GB") ||
              f.readAsStringSync().contains("toStringAsFixed(1)} KB"))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '字节分级又抄了一份：$offenders');
      final src = libSourceAll();
      expect(src.contains('String formatBytes(int n)'), isTrue);
      // 三处旧实现必须都是转调，不得各自再写一遍分级。
      expect(src.contains('String get human => formatBytes(bytes);'), isTrue);
      expect(src.contains('static String bytesText(int b) => formatBytes(b);'),
          isTrue);
    });

    test('封面扩展名两条规则各只有一处定义', () {
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('cover_ext.dart'))
          .where((f) => f.readAsStringSync().contains("'.heic'"))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '可显示图片白名单又抄了一份：$offenders');
      final src = libSourceAll();
      // 规则 A（能否渲染）与规则 B（能否存成版本）是两个不同集合，都必须只剩一处。
      expect(
          RegExp(r"const List<String> kCoverImageExts").allMatches(src).length, 1);
      expect(RegExp(r"const List<String> kCoverExts").allMatches(src).length, 1);
      expect(
          RegExp(r"bool isCoverImagePath\(String p\)").allMatches(src).length, 1);
      expect(src.contains('_isCoverImage('), isFalse,
          reason: 'media_priority 的私有副本必须删掉，改为转调 isCoverImagePath');
    });

    test('MM-dd HH:mm 时间文案只有一处（批次键 UTC 是唯一例外）', () {
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('time_labels.dart'))
          .where((f) => RegExp(r"padLeft\(2, '0'\)")
              .hasMatch(f.readAsStringSync()))
          .where((f) => RegExp(r"\{two\((d|l|t|u|at|l)\.month\)\}")
              .hasMatch(f.readAsStringSync()))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '时间两位补零又抄了一份：$offenders');
      final dm = File('lib/deleted_monitor.dart').readAsStringSync();
      // 批次键必须保持 UTC：跨时区时同一批不能被拆成两组。
      expect(dm.contains('yearMonthDayTimeUtc(t)'), isTrue,
          reason: 'syncKeyOf 的 UTC 是有意的，改成本地时区会让批次键随时区漂移');
      expect(dm.contains('syncKeyOf(String at)'), isTrue);
      expect(dm.contains('monthDayTimeOfIso(at, fallback: at)'), isTrue,
          reason: '展示用的 atLabel/syncLabel 必须走本地时区的统一实现');
    });

    test('播放位置时间进位：进度行与进度条不再各写一份', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main.contains('String fmt(Duration d) {'), isTrue);
      expect(main.contains('return formatClock(d);'), isTrue,
          reason: '播放页时间必须走统一进位实现（65 分钟要显示 1:05:03）');
      expect(main.contains('inMinutes.remainder(60)'), isFalse,
          reason: '不进位的旧写法又回来了');
      final pm = File('lib/playback_menu.dart').readAsStringSync();
      expect(pm.contains('String formatMenuPosition(int ms) => formatClockMs(ms);'),
          isTrue);
    });

    test('封面角标的 m:ss 不补零是有意的，不得并入播放器格式', () {
      final cb = File('lib/cover_badges.dart').readAsStringSync();
      expect(cb.contains('formatClockSeconds(total.round())'), isFalse,
          reason: '角标用 m:ss（0:05），播放器用 mm:ss（00:05）：并入会改掉角标显示');
      expect(cb.contains("h > 0 ? m.toString().padLeft(2, '0') : m.toString()"),
          isTrue);
    });
  });
}
