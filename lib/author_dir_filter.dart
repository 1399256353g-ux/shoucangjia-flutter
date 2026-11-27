/// 作者页「按挂载的作者文件夹筛选」（纯逻辑，无 UI、无网络）。
///
/// 背景（owner 2026-11-27，任务清单待做项）：
/// > 「作者页可按挂载的作者文件夹筛选显示」
///
/// 同名作者可能分布在多个基础库、多个 `@作者` 目录里（挂载面板把这些目录
/// 列出来并可合并成一张卡）。合并之后，作者页把各目录的作品并成一列；
/// 但「这些作品到底来自哪一个目录」在界面上没有任何出口——只能靠来源库
/// 粗筛，同一个库里挂了两处目录时仍然分不开。
///
/// 这里只做两件可单测的事：
///  1. 从作品媒体路径里取出**作者目录段**（`@xxx`）；
///  2. 按「库 + 作者目录」筛选作品。
///
/// 目录名判定只有一处（[authorDirSegmentOfPath]）：服务端 `authorDirNameOf`
/// 规定作者目录必须以 `@` 开头，客户端 `authorDirError` 也是同一条规则，
/// 这里再多写一份「以 @ 开头」的判断就会出现第三个来源。
library;

import 'rel_path.dart';
import 'node_key.dart' show scopedKey;
import 'tally_order.dart';
import 'work_lib.dart';
import 'work_safety.dart';

/// 作品是否属于某个作者目录（按媒体路径里的路径段判定）。
///
/// [authorDir] 为空表示不限制；路径里没有任何 `@` 段时返回 false——那是
/// 「这条作品不在作者目录下」，不能当成「匹配所有目录」。
bool workInAuthorDir(dynamic work, String authorDir) {
  final want = authorDir.trim();
  if (want.isEmpty) return true;
  for (final p in workMediaPaths(work)) {
    for (final seg in relSegments(p)) {
      if (seg == want) return true;
    }
  }
  return false;
}

/// 按「库 + 作者目录」筛选作品。
///
/// 两个条件同时生效：库决定「哪台服务器/哪个基础库」，目录决定「库里的
/// 哪一个 `@作者` 文件夹」。任何一个为空表示该维度不限制。
List<Map<String, dynamic>> filterWorksByAuthorDir(
  Iterable<dynamic> works, {
  String lib = '',
  String authorDir = '',
  String fallbackLib = '',
}) {
  final wantLib = lib.trim();
  final wantDir = authorDir.trim();
  if (wantLib.isEmpty && wantDir.isEmpty) {
    return [
      for (final w in works)
        if (w is Map) Map<String, dynamic>.from(w)
    ];
  }
  final out = <Map<String, dynamic>>[];
  for (final w in works) {
    if (w is! Map) continue;
    if (wantLib.isNotEmpty && workLibOf(w, fallback: fallbackLib) != wantLib) {
      continue;
    }
    if (!workInAuthorDir(w, wantDir)) continue;
    out.add(Map<String, dynamic>.from(w));
  }
  return out;
}

/// 一个「库 + 作者目录」筛选选项。
class AuthorDirOption {
  final String lib;
  final String authorDir;
  const AuthorDirOption({required this.lib, required this.authorDir});

  String get key => scopedKey(lib, authorDir);
}

/// 作品媒体路径里的**第一个** `@` 目录段；没有则空串。
///
/// 服务端约定作者目录以 `@` 开头（`authorDirNameOf` / `authorDirError`）。
/// 这里不再重复校验整条目录名规则，只看首字符与「取哪一段」。
String authorDirOfWork(dynamic work) {
  for (final p in workMediaPaths(work)) {
    for (final seg in relSegments(p)) {
      if (seg.startsWith('@')) return seg;
    }
  }
  return '';
}

/// 由一批作品反推「库 + 作者目录」筛选项（按首次出现顺序，只收 ≥1 条作品）。
///
/// 为什么从作品反推而不是读 `/api/author/mounts`：作者页要筛的是**当前这一列
/// 作品**来自哪些目录。挂载接口给的是「磁盘上有哪些目录」，里面可能全是
/// 没有作品的空目录——那种选项点下去结果是空列表。两者不一致时以作品为准。
List<({AuthorDirOption option, int count})> authorDirOptionsOfWorks(
  Iterable<dynamic> works, {
  String fallbackLib = '',
}) {
  final byKey = <String, AuthorDirOption>{};
  final tally = tallyInOrder<Map>(
    works.whereType<Map>(),
    (w) {
      final dir = authorDirOfWork(w);
      if (dir.isEmpty) return '';
      final lib = workLibOf(w, fallback: fallbackLib);
      final o = AuthorDirOption(lib: lib, authorDir: dir);
      // 同一个键只建一个选项；计数仍由 [tallyInOrder] 统一做。
      byKey.putIfAbsent(o.key, () => o);
      return o.key;
    },
  );
  return [
    for (final e in tally) (option: byKey[e.key]!, count: e.value),
  ];
}
