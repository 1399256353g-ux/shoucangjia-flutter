/// 「从合并组里拆出哪几个基础库」对话框（**唯一实现**）。
///
/// 0.9.376：这段对话框此前在 `author_mount_sheet` 与 `unit_author_mount_page`
/// 各写一份，逐字相同——同样的三行提示、同样「至少 1 个、不能全选」的禁用
/// 条件、同样的 `CheckboxListTile` 列表。两份的差别只有 Key 前缀（`ams-` /
/// `uag-`），而 Key 只服务于测试定位，不改变交互。
///
/// 为什么必须合成一处：这个对话框里的**判定**（不能全选、至少一个，
/// 否则「全拆走」等于解散——那是另一个动作）与服务端 `split` 的前置校验
/// 是同一条规则。两份实现意味着将来其中一处改判定时，另一处会静默地放行
/// 一个必然 400 的请求。
///
/// 拆分逻辑归调用方：作者页的卡可能是还没落盘的自动组，要先 `merge` 拿
/// 到组 id；单元库页拿的是已落盘的组。本文件只负责**问用户要哪几个**。
library;

import 'package:flutter/material.dart';

import 'text_styles.dart';

/// 弹出「拆出基础库」对话框，返回用户勾选的基础库 id 集合。
///
/// 取消（含点外部关闭）返回 null——调用方据此直接返回，不做任何请求。
/// 返回值保证非空且不等于全集（确认键在这两种情况下是禁用的）。
///
/// [keyPrefix] 只影响控件 Key（`<前缀>-split-lib-<lib>` / `<前缀>-split-ok`），
/// 两个入口各用一套，测试定位互不串台。
Future<Set<String>?> pickLibsToSplit(
  BuildContext context, {
  required List<String> libs,
  required String Function(String lib) labelOf,
  required String keyPrefix,
}) async {
  final picked = <String>{};
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: const Text('拆出基础库'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  '勾选要分出去的基础库（至少 1 个，不能全选——全部分开请用「解散」）。'
                  '只改分组，不动任何作者目录与作品文件。',
                  style: kHintTextStyle),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final lib in libs)
                    CheckboxListTile(
                      key: ValueKey('$keyPrefix-split-lib-$lib'),
                      dense: true,
                      value: picked.contains(lib),
                      title: Text(labelOf(lib),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setD(() {
                        if (v == true) {
                          picked.add(lib);
                        } else {
                          picked.remove(lib);
                        }
                      }),
                    ),
                ]),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            key: ValueKey('$keyPrefix-split-ok'),
            onPressed: (picked.isEmpty || picked.length >= libs.length)
                ? null
                : () => Navigator.pop(ctx, true),
            child: const Text('拆出'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  return picked;
}
