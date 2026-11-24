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
  group('第十三批：响应解码字符集单一出口', () {
    // 注释里提到旧写法是说明，不是实现；判断前先剥掉行注释。
    String codeOf(File f) => f
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('lib/ 内不得再出现 Response.body 直接解 JSON', () {
      // 旧写法 `jsonDecode(r.body)` 的字符集由响应的 Content-Type 决定：
      // 不是 application/json 就按 latin1 解，同一份 UTF-8 响应里的中文变乱码。
      // 现在唯一出口是 http_json.dart 的 jsonOfBytes（始终 UTF-8）。
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('http_json.dart'))
          .where((f) => RegExp(r'jsonDecode\([^)]*\.body\s*\)')
              .hasMatch(codeOf(f)))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '又有人直接用 .body 解 JSON：$offenders');
    });

    test('lib/ 内不得再手写 jsonDecode(utf8.decode(...))', () {
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('http_json.dart'))
          .where((f) => codeOf(f).contains('jsonDecode(utf8.decode('))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty,
          reason: '字符集规则必须只有一处实现，这里是重复：$offenders');
    });

    test('真实路径仍在：jsonOf 有实际调用方', () {
      final src = libDartFiles().map(codeOf).join('\n');
      expect(src.contains('dynamic jsonOfBytes(List<int> bytes)'), isTrue);
      expect(src.contains('dynamic jsonOf(http.Response r) =>'), isTrue);
      // 调用点数量是"真的接上了"的证据：少于 60 说明有人改回了 .body。
      final calls = RegExp(r'\bjsonOf\(').allMatches(src).length;
      expect(calls, greaterThanOrEqualTo(60),
          reason: 'jsonOf 调用点从 78 处掉到 $calls 处，说明有路径回退到 .body');
    });

    test('「加载失败」错误块只走 LoadErrorView（不再手写 11 份）', () {
      // 之前 main.dart 手写 11 次、另两个页面各手写一次，三种形态：
      // 有内边距/无内边距/无重试。同一句错误在不同页面字号不一。
      // 只认「把错误文本直接摆进 Text 里」这一种手写形态；
      // 页面上另有过「图片加载失败」这类媒体占位，不属于本契约。
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('load_error_view.dart'))
          .where((f) => RegExp(r"Text\('加载失败：(\$err|\$\{err\})'")
              .hasMatch(codeOf(f)))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '错误块又手写回来了：$offenders');
      // 真实路径仍在：控件被多处使用。
      final src = libDartFiles().map(codeOf).join('\n');
      final uses = RegExp(r'LoadErrorView\(').allMatches(src).length;
      expect(uses, greaterThanOrEqualTo(13),
          reason: 'LoadErrorView 使用点从 13 处掉到 $uses 处');
    });

    test('异常转文案只走 errorText（页面不得再写原始异常插值）', () {
      // `'$e'` 对 Exception 产出 `Exception: HTTP 500`，对 TimeoutException
      // 产出 `TimeoutException after 0:00:08.000000: Future not completed`
      // ——两个都会原样显示在界面上。
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('error_text.dart'))
          .where((f) => RegExp(r"err = \'\$e\'|err = \'\$\{?e\}?\'")
              .hasMatch(codeOf(f)))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '页面又把原始异常塞进界面：$offenders');
      final src = libDartFiles().map(codeOf).join('\n');
      expect(src.contains('String errorText(Object? e)'), isTrue);
      final uses = RegExp(r'errorText\(').allMatches(src).length;
      expect(uses, greaterThanOrEqualTo(25),
          reason: 'errorText 调用点从 30 处掉到 $uses 处');
    });

    test('isolate 模块与 sync_ledger 都转发到同一出口', () {
      final iso = codeOf(File('lib/json_isolate.dart'));
      expect(iso.contains('jsonOfBytes(bytes)'), isTrue);
      expect(iso.contains('jsonDecode(utf8.decode('), isFalse);
      final ledger = codeOf(File('lib/sync_ledger.dart'));
      expect(ledger.contains('=> jsonOfBytes(bytes);'), isTrue);
      expect(ledger.contains('jsonDecode(utf8.decode('), isFalse);
    });
  });

  group('第十四批：三处「写一份规则、抄一份实现」必须仍只有一个出口', () {
    String codeOf(File f) => f
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('序号前缀正则只许出现在 index_prefix.dart', () {
      // 三份实现（词条显示 / 基础库匹配 / 同步源匹配）已合并；任何再往页面
      // 里抄一份 `\d{1,4}` 前缀正则的行为都会让三者重新分叉。
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('index_prefix.dart'))
          .where((f) => codeOf(f).contains('d{1,4}'))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: '序号前缀规则被又抄了一份：$offenders');
      final src = libDartFiles().map(codeOf).join('\n');
      expect(src.contains('String stripIndexPrefix(String raw)'), isTrue);
      final uses = RegExp(r'stripIndexPrefix\(').allMatches(src).length;
      expect(uses, greaterThanOrEqualTo(3),
          reason: '三个调用点（词条/基础库/同步源）少了，实际 $uses 处');
    });

    test('颜色十六进制编解码只许出现在 color_codec.dart', () {
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('color_codec.dart'))
          .where((f) {
        final c = codeOf(f);
        return c.contains("replaceFirst('#', '')") ||
            c.contains('radix: 16') ||
            c.contains('0xFF000000 |');
      }).map((f) => f.path).toList();
      expect(offenders, isEmpty, reason: '颜色编解码被又抄了一份：$offenders');
      final src = libDartFiles().map(codeOf).join('\n');
      // 读入方仍然是两处（词条 / 角标），但都只调 argbFromJson。
      final reads = RegExp(r'argbFromJson\(').allMatches(src).length;
      expect(reads, greaterThanOrEqualTo(2),
          reason: '角标与词条没有共用同一解析入口，实际 $reads 处');
      final writes = RegExp(r'argbToHex\(').allMatches(src).length;
      expect(writes, greaterThanOrEqualTo(4),
          reason: '写入路径应覆盖词条三张表 + 角标一张表，实际 $writes 处');
    });

    test('接口地址拼接只许走 api_url.dart', () {
      final offenders = libDartFiles()
          .where((f) => !f.path.endsWith('api_url.dart'))
          .where((f) {
        final c = codeOf(f);
        return c.contains("endsWith('/') ? '' : '/'") ||
            c.contains(r"replaceFirst(RegExp(r'/+$'), '')");
      }).map((f) => f.path).toList();
      expect(offenders, isEmpty, reason: 'base 归一又写了一份：$offenders');
      final src = libDartFiles().map(codeOf).join('\n');
      expect(src.contains('String baseForJoin(String raw)'), isTrue);
      final joins = RegExp(r'joinApiUrl\(|libApiUrl\(|apiUri\(')
          .allMatches(src)
          .length;
      expect(joins, greaterThanOrEqualTo(10),
          reason: '拼接调用点从 13 处掉到 $joins 处，说明有路径绕开了 api_url');
    });
  });

  // owner 2026-11-24：「简化播放界面任务栏，你就保留个集成设置按钮就行了,
  // 重复把设置里有的按钮放外面干嘛呢」+「主页右上角设置点开没东西不好用」。
  // 两条需求同一个根：入口只能有一个，且必须真的能点开。
  group('第十五批：入口唯一且可见', () {
    String codeOf(File f) => f
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('播放任务栏不再有独立的连播/循环/乱序槽位', () {
      // 这三个开关都在「播放设置」弹窗里；任务栏再多摆一份就是重复入口。
      final enums = codeOf(File('lib/taskbar_layout.dart'));
      expect(enums.contains('autoplay,'), isFalse,
          reason: '任务栏又长出一个 autoplay 槽位');
      expect(enums.contains('shuffle,'), isFalse,
          reason: '任务栏又长出一个 shuffle 槽位');
      expect(RegExp(r'^\s*loop,', multiLine: true).hasMatch(enums), isFalse,
          reason: '任务栏又长出一个 loop 槽位');
      // 设置入口必须还在（删了就真的没有播放设置了）。
      expect(enums.contains('settings,'), isTrue);
    });

    test('三个播放开关只在播放设置弹窗里出现一次', () {
      final main = codeOf(File('lib/main.dart'));
      // key 是弹窗内的唯一锚点，每个只能有一个处置点。
      for (final k in ['setting-autoplay', 'setting-loop', 'setting-shuffle']) {
        final n = RegExp("'$k'").allMatches(main).length;
        expect(n, 1, reason: '$k 出现 $n 次，播放开关被写了多份 UI');
      }
    });

    test('播放设置弹窗里的三个开关都落到持久化入口', () {
      final main = codeOf(File('lib/main.dart'));
      // 四个会改变播放设置的地方：乱序、循环、连播、倍速。漏一处就变成
      // 「这次改了，重进没记住」。
      final persists = RegExp(r'_persistPlaybackPrefs\(\);')
          .allMatches(main)
          .length;
      expect(persists, greaterThanOrEqualTo(4),
          reason: '落盘点只有 $persists 处（应为乱序/循环/连播/倍速至少 4 处）');
      expect(main.contains('loadPlaybackPrefs()'), isTrue,
          reason: '进播放页没有读回上次设置');
    });

    test('主页设置是常驻尾位，不参与「⋯」溢出', () {
      final bar = codeOf(File('lib/home_top_bar.dart'));
      expect(bar.contains("id == 'settings'"), isTrue,
          reason: '设置固定尾位逻辑被删，设置会重新被挤进「⋯」');
      expect(bar.contains('pinned'), isTrue);
    });
  });

  // 第十六批（0.9.217）：组合键落地后留下的三处「单键兼容壳」。
  // `keyIds` / `bind()` / `actionFor()` 只被 test 引用，真实路径全部走
  // `keyBindings` / `bindCombo` / `actionForCombo`；壳还在，就等于给「只改壳
  // 不改真路径」留了一条静默分叉的路。
  group('第十六批：组合键只有一套 API', () {
    String codeOf(String path) => File(path)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('单键兼容壳不得复活', () {
      final s = codeOf('lib/app_settings.dart');
      expect(RegExp(r'^\s*(static )?Map<PlayerAction, int> get keyIds',
                      multiLine: true)
              .hasMatch(s),
          isFalse,
          reason: 'keyIds 只读视图又回来了：组合键会出现两条真相');
      expect(RegExp(r'^\s*static void bind\(', multiLine: true).hasMatch(s),
          isFalse,
          reason: 'bind() 单键壳又回来了');
      expect(RegExp(r'^\s*static PlayerAction\? actionFor\(', multiLine: true)
              .hasMatch(s),
          isFalse,
          reason: 'actionFor() 单键壳又回来了');
      // 真入口必须都在。
      for (final k in ['keyBindings', 'bindCombo(', 'actionForCombo(']) {
        expect(s.contains(k), isTrue, reason: '$k 不见了');
      }
    });

    test('响应体 → Map 只有 jsonMapOf 一个入口', () {
      // `jsonOf(r) as Map<String, dynamic>` 散在 11 处时，任何一处改成
      // `as Map`（丢掉类型）都不会有人发现；集中到 jsonMapOf 后只有一份。
      for (final f in ['lib/main.dart', 'lib/unit_crawler_page.dart',
                       'lib/collection_sync_panel.dart']) {
        final s = codeOf(f);
        expect(RegExp(r'jsonOf\(\w+\) as Map').hasMatch(s), isFalse,
            reason: '$f 又手写了一遍资源体转型');
      }
      final http = codeOf('lib/http_json.dart');
      expect(http.contains('Map<String, dynamic> jsonMapOf'), isTrue);
    });
  });

  // 第十七批（0.9.217）：单元库「同步就绪」只有一条判定。
  group('第十七批：同步就绪只有一条规则', () {
    String codeOf(String path) => File(path)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('页面不得自己再判一遍脚本就绪', () {
      final page = codeOf('lib/unit_crawler_page.dart');
      expect(RegExp(r'scripts\.any\(').hasMatch(page), isFalse,
          reason: '单元库页又自己扫了一遍脚本列表，与配置对象的判定分叉');
      expect(page.contains('config.scriptReadyIn(scripts)'), isTrue,
          reason: '页面没走单一判定口');
    });

    test('就绪判定必须区分「脚本存在」与「已启用」', () {
      final c = codeOf('lib/unit_crawler.dart');
      // scriptReadyIn 不得掺 enabled；syncReadyIn 才是 enabled && scriptReadyIn。
      final scriptReady = RegExp(
              r'bool scriptReadyIn\(Iterable<UnitCrawlerScript> scripts\) \{([\s\S]*?)\n  \}',
              multiLine: true)
          .firstMatch(c);
      expect(scriptReady, isNotNull, reason: 'scriptReadyIn 不见了');
      expect(scriptReady!.group(1)!.contains('enabled'), isFalse,
          reason: 'scriptReadyIn 掺进了 enabled：关掉同步后开关再也打不开');
      expect(c.contains('syncReadyIn'), isFalse,
          reason: '又出现了一个「enabled && 就绪」的第二判定口');
    });
  });

  // 第十八批（0.9.220）：`node:` 前缀归一曾写 14 遍。
  //
  // 危害不是「代码重复」这么抽象：`library_badge.dart` 10 处、`main.dart` 1 处、
  // `unit_library.dart` 2 处各自 `m[id] ?? m[rel] ?? m['node:$rel']`，其中一处
  // 顺序写反就会出现「设置页显示自定义、卡片上还是自动色」。归一到 lib_id.dart
  // 之后，任何调用点再手写这套链都会静默分叉，所以从代码层面禁掉。
  group('第十八批：库 id 归一只有一套规则', () {
    String codeOf(String path) => File(path)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('生产代码里不得再手剥 node: 前缀', () {
      final libs = Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final offenders = <String>[];
      for (final f in libs) {
        if (f.path.endsWith('lib_id.dart')) continue; // 规则本体
        final s = f.readAsStringSync();
        if (s.contains("substring(5)")) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: '这些文件又自己剥了 node: 前缀，改走 relOf/idFormsOf');
    });

    test('不得再手写「三种 id 形式」的查表链', () {
      for (final f in ['lib/library_badge.dart', 'lib/main.dart',
                       'lib/unit_library.dart']) {
        final s = codeOf(f);
        // 典型分叉写法：`x[id] ?? x[rel] ?? x['node:$rel']`。
        // 只禁「回退到另一种 id 形式」这一种链；构造 id（`id: 'node:$rel'`）
        // 与别的规则的 ?? 链（如 `covers[rel] ?? covers[raw]`）不在此列。
        expect(RegExp(r"\?\?\s*\w+\[\s*'node:").hasMatch(s), isFalse,
            reason: '$f 又手写了 node: 形式回退查表；用 lookupByLibId');
        expect(RegExp(r"\?\?\s*\w+\[\s*(rel|prefixed)\s*\]").hasMatch(s),
            isFalse,
            reason: '$f 又手写了一串 ?? 查表；用 lookupByLibId');
      }
    });

    test('lib_id 的四个入口都在，删除是幂等的', () {
      final s = codeOf('lib/lib_id.dart');
      for (final k in ['String relOf(', 'List<String> idFormsOf(',
                       'T? lookupByLibId<T>(', 'int removeByLibId<T>(']) {
        expect(s.contains(k), isTrue, reason: '$k 不见了');
      }
    });
  });

  // 第十九批（0.9.221）：A1 作者文件夹挂载——服务端早就有，客户端长期没有入口。
  //
  // 这一批的风险不是「写错」，而是**协议字符串被抄第二份**：
  // `unit-author-groups.json` 与四个 action 名（merge/split/setFiles/delete）
  // 一旦在页面里再拼一遍，服务端改字段时只会改到其中一处，表现是
  // 「有的操作生效、有的静默 400」。
  group('第十九批：作者挂载协议只有一处', () {
    String codeOf(String path) => File(path)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('接口路径只在 unit_author_groups.dart 出现', () {
      final libs = Directory('lib')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final offenders = <String>[];
      for (final f in libs) {
        if (f.path.endsWith('unit_author_groups.dart')) continue;
        final s = codeOf(f.path);
        for (final p in [
          '/api/unit-author-groups.json',
          '/api/unit/authors.json',
          '/api/unit/authors/create',
        ]) {
          if (s.contains(p)) offenders.add('${f.path} → $p');
        }
      }
      expect(offenders, isEmpty,
          reason: '这些文件又自己拼了一份作者挂载地址，改走 unit_author_groups.dart');
    });

    test('四个 action 名不得在页面里手写', () {
      final page = codeOf('lib/unit_author_mount_page.dart');
      for (final a in ['"merge"', "'merge'", '"split"', "'split'",
                       '"setFiles"', "'setFiles'", '"delete"', "'delete'"]) {
        expect(page.contains(a), isFalse,
            reason: '页面里手写了 action 字符串 $a；用 UnitAuthorAction');
      }
      final model = codeOf('lib/unit_author_groups.dart');
      for (final a in ["merge('merge')", "split('split')",
                       "setFiles('setFiles')", "delete('delete')"]) {
        expect(model.contains(a), isTrue, reason: 'UnitAuthorAction 少了 $a');
      }
    });

    test('作者目录 @ 规则只有一处入口', () {
      final model = codeOf('lib/unit_author_groups.dart');
      expect(model.contains('String? authorDirError('), isTrue);
      expect(model.contains('String authorDirForName('), isTrue);
      // 页面不得自己判 @ 前缀（否则改名规则要改两处）。
      final page = codeOf('lib/unit_author_mount_page.dart');
      expect(page.contains("startsWith('@')"), isFalse,
          reason: '页面自己判 @ 前缀；用 authorDirError');
    });

    test('挂载入口从单元库页接到主页（否则等于没做）', () {
      final view = codeOf('lib/unit_library_view.dart');
      expect(view.contains('onMountAuthors'), isTrue,
          reason: '单元库页没有挂载入口参数');
      final main = codeOf('lib/main.dart');
      expect(main.contains('_openUnitAuthorMount'), isTrue,
          reason: '主页没有把挂载面板接上');
      expect(
          RegExp(r'onMountAuthors:\s*_openUnitAuthorMount')
              .allMatches(main)
              .length,
          2,
          reason: '一级/下级单元库页的挂载入口数量不对');
      expect(main.contains('UnitAuthorMountPage'), isTrue);
    });
  });
}
