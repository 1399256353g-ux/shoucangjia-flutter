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
      expect(offenders, isEmpty,
          reason: '这些文件各自写了一份震动实现：$offenders');
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
      expect(defines(libSourceAll(), r'^List<String> crashLogPaths\('), isFalse);
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
}
