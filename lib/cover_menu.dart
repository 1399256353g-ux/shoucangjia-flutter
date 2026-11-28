/// owner 2026-11-23：库卡片封面入口整合。
///
/// 卡片右上角只留一个入口，弹出四项：
///  1. 本地选图作封面（复用 [CoverUploader]）
///  2. 使用过往封面（网格列最近 5 个缩略图）
///  3. 恢复自动封面（只删指针，回到自动封面链）
///  4. 清除自定义封面（二次确认，服务端删除版本文件）
///
/// 本文件只负责 UI 与菜单编排；具体请求由调用方通过 [CoverMenuActions]
/// 注入，保持与各页面的连接/鉴权一致。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'cover_cache.dart';
import 'cover_history.dart';
import 'cover_upload.dart';
import 'media_resize.dart';
import 'toast.dart';
import 'confirm_dialog.dart';
import 'loading_view.dart';

/// 菜单执行成功后告诉卡片该怎么显示：
/// - [url] 非空：直接换成这张封面；
/// - [auto] 为 true：按「自动封面」链重新求值。
class CoverMenuOutcome {
  final String url;
  final bool auto;

  const CoverMenuOutcome.forUrl(this.url) : auto = false;

  const CoverMenuOutcome.auto()
      : url = '',
        auto = true;
}

/// 卡片封面菜单所需的服务端动作（由宿主页面注入）。
class CoverMenuActions {
  final String libId;

  /// 空串表示基础库封面；非空表示单元库封面（指针在 unit-covers.json）。
  final String unitRel;

  /// 封面请求鉴权头（媒体接口需要 Basic 认证）。
  final Map<String, String> headers;

  /// 相对媒体路径 → 可直接加载的绝对地址。
  final String Function(String path) urlOf;

  final Future<CoverUploadResult> Function() pickLocal;
  final Future<CoverListResult> Function() listVersions;
  final Future<CoverActionResult> Function(CoverVersion version) restore;
  final Future<CoverActionResult> Function() restoreAuto;
  final Future<CoverActionResult> Function() clearAll;

  /// 封面变化后的刷新信号（主页/库页重新拉取索引）。
  final VoidCallback? onChanged;

  const CoverMenuActions({
    required this.libId,
    this.unitRel = '',
    this.headers = const <String, String>{},
    required this.urlOf,
    required this.pickLocal,
    required this.listVersions,
    required this.restore,
    required this.restoreAuto,
    required this.clearAll,
    this.onChanged,
  });
}

/// 卡片右上角入口 → 封面菜单。返回 null 表示没有改变封面。
Future<CoverMenuOutcome?> showCoverMenu(
  BuildContext context,
  CoverMenuActions actions,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(children: [
            const Icon(Icons.image_outlined, size: 18),
            const SizedBox(width: 8),
            Text(actions.unitRel.isEmpty ? '基础库封面' : '单元库封面',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
        ListTile(
          key: const ValueKey('cover-menu-local'),
          leading: const Icon(Icons.add_photo_alternate_outlined),
          title: const Text('本地选图作封面'),
          onTap: () => Navigator.of(ctx).pop('local'),
        ),
        ListTile(
          key: const ValueKey('cover-menu-history'),
          leading: const Icon(Icons.history),
          title: const Text('使用过往封面'),
          subtitle: const Text('最近用过的最多 5 个'),
          onTap: () => Navigator.of(ctx).pop('history'),
        ),
        ListTile(
          key: const ValueKey('cover-menu-auto'),
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('恢复自动封面'),
          subtitle: const Text('回到播放量最高的作品封面'),
          onTap: () => Navigator.of(ctx).pop('auto'),
        ),
        ListTile(
          key: const ValueKey('cover-menu-clear'),
          leading: Icon(Icons.delete_outline,
              color: Theme.of(ctx).colorScheme.error),
          title: Text('清除自定义封面',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          subtitle: const Text('删除封面文件，需二次确认'),
          onTap: () => Navigator.of(ctx).pop('clear'),
        ),
        const SizedBox(height: 8),
      ]),
      ),
    ),
  );
  if (action == null) return null;
  switch (action) {
    case 'local':
      final r = await actions.pickLocal();
      if (!context.mounted) return null;
      _toast(context, r.message);
      if (!r.ok) return null;
      actions.onChanged?.call();
      return r.url.isEmpty ? null : CoverMenuOutcome.forUrl(actions.urlOf(r.url));
    case 'history':
      return _pickHistory(context, actions);
    case 'auto':
      final r = await actions.restoreAuto();
      if (!context.mounted) return null;
      _toast(context, r.message);
      if (!r.ok) return null;
      actions.onChanged?.call();
      return const CoverMenuOutcome.auto();
    case 'clear':
      final ok = await _confirmClear(context);
      if (ok != true || !context.mounted) return null;
      final r = await actions.clearAll();
      if (!context.mounted) return null;
      _toast(context, r.message);
      if (!r.ok) return null;
      actions.onChanged?.call();
      return const CoverMenuOutcome.auto();
  }
  return null;
}

/// 过往封面网格：最多 5 个缩略图，当前封面打勾。
Future<CoverMenuOutcome?> _pickHistory(
  BuildContext context,
  CoverMenuActions actions,
) async {
  final picked = await showModalBottomSheet<CoverVersion>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      top: false,
      child: SizedBox(
        height: 340,
        child: FutureBuilder<CoverListResult>(
          future: actions.listVersions(),
          builder: (ctx2, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const LoadingView();
            }
            final res = snap.data;
            if (res == null || !res.ok) {
              return Center(
                  child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(res?.message ?? '读取封面历史失败',
                    textAlign: TextAlign.center),
              ));
            }
            if (res.versions.isEmpty) {
              return const Center(child: Text('还没有可用的历史封面'));
            }
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  const Icon(Icons.history, size: 18),
                  const SizedBox(width: 8),
                  Text('使用过往封面（${res.versions.length}）',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 140,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount: res.versions.length,
                  itemBuilder: (c, i) {
                    final v = res.versions[i];
                    return InkWell(
                      key: ValueKey('cover-version-${v.fileName}'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.of(c).pop(v),
                      child: Stack(fit: StackFit.expand, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            cacheManager: DiziCache.manager,
                            imageUrl: withImageWidth(actions.urlOf(v.url), 320),
                            httpHeaders: actions.headers,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.black12,
                              child: const Icon(Icons.broken_image_outlined,
                                  color: Colors.white38),
                            ),
                          ),
                        ),
                        if (v.current)
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.check,
                                  size: 14, color: Colors.lightGreenAccent),
                            ),
                          ),
                      ]),
                    );
                  },
                ),
              ),
            ]);
          },
        ),
      ),
    ),
  );
  if (picked == null) return null;
  final r = await actions.restore(picked);
  if (!context.mounted) return null;
  _toast(context, r.message);
  if (!r.ok) return null;
  actions.onChanged?.call();
  final u = r.url.isNotEmpty ? r.url : picked.url;
  return u.isEmpty ? const CoverMenuOutcome.auto() : CoverMenuOutcome.forUrl(actions.urlOf(u));
}

/// 清除自定义封面：不可撤销，必须二次确认。
///
/// 本函数原先自己拼了一遍 `showDialog<bool>`；那个弹框与其它页面完全同形，
/// 已收到 [confirmAction]。保留这层是因为调用点关心的是 `bool?`（null 与
/// false 都当取消，实际上没有第二个结果）。
Future<bool?> _confirmClear(BuildContext context) async =>
    (await confirmAction(
      context,
      title: '清除自定义封面？',
      message: '会删除该库/单元库的自定义封面文件，并恢复为自动封面。此操作不可撤销。',
      confirmLabel: '清除',
      destructive: true,
    ))
        ? true
        : false;

void _toast(BuildContext context, String text) =>
    showToastIn(context, text);
