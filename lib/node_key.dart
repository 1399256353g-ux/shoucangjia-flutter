/// 单元库节点的身份键：`<连接>\u0001<归一化 rel>`（**唯一拼装口**）。
///
/// 为什么必须存在这个文件（0.9.286）：
///
/// 同一根字符串此前在**四处各拼一遍**，而且有两处连分隔符都是自己写的字面量：
///
/// ```
/// unit_library._nodeKeyOf          '${serverId.trim()}\u0001$rel'   ← 树节点键
/// multi_server.unitCoverKey        '${serverId.trim()}\u0001${normalizeUnitRel(rel)}'
/// unit_cover_store._keyOf          '$ns:${scope.trim()}\u0001$id'    ← 另一套（带命名空间）
/// main.dart                        k.startsWith('$markedSid\u0001')  ← 反向**手拆**一次
/// ```
///
/// 前两者的输出必须逐字相同：封面表的键（服务端下发）与树节点的键
/// （`buildUnitTree` 去重/父子/归属三张表）对不上，表现就是「设了封面、
/// 返回界面又没了」——而两处各自都自洽。分隔符各写一份更危险：`\u0001`
/// 与 `\u0001 ` 之类肉眼看不见的差别，只在两台服务端同名目录时才炸。
///
/// 所以这里只放两件事：常量 + 拼装，反向解析也在这里（`main` 不再手拆）。
/// `unit_cover_store` 的键另有命名空间前缀，它自己再拼一层即可，但分隔符
/// 必须取自 [kNodeKeySep]。
library;

import 'rel_path.dart';

/// 连接标识与 rel 之间的分隔符。
///
/// rel 里可能出现 `|`、`:`、`/`，但不会是控制字符，因此 `\u0001` 拼接后
/// 不会被两个不同 (连接, rel) 组合撞成同一个键。
const String kNodeKeySep = '\u0001';

/// 节点键：连接标识（trim 后）+ 分隔符 + rel。
///
/// [rel] 必须已归一（`normalizeUnitRel` / `splitRel(...).join('/')`）。
/// 归一不做两次的理由：`..` 由校验层拒绝，这里再归一一次会把「写进去的键」
/// 与「读出来的键」变成两条不同的规则。
String nodeKey(String serverId, String rel) =>
    '${serverId.trim()}$kNodeKeySep$rel';

/// 节点键里的连接标识；格式不对返回空串。
String nodeKeyServerId(String key) {
  final at = key.indexOf(kNodeKeySep);
  if (at < 0) return '';
  return key.substring(0, at).trim();
}

/// 节点键里的 rel；格式不对返回空串。
String nodeKeyRel(String key) {
  final at = key.indexOf(kNodeKeySep);
  if (at < 0) return '';
  return key.substring(at + kNodeKeySep.length);
}

/// 该键是否属于连接 [serverId]（两侧空白等价，与 [nodeKey] 的 trim 口径一致）。
bool nodeKeyHasServer(String key, String serverId) =>
    nodeKeyServerId(key) == serverId.trim() && key.contains(kNodeKeySep);

/// 归一化 rel 后直接成键（服务端下发的节点只有原始 rel 时用）。
String nodeKeyNormalized(String serverId, String rel) =>
    nodeKey(serverId, normalizeRelPath(rel));

/// 两段作用域键的**中性**拼装：`<a>␁<b>`（两侧各 trim 一次）。
///
/// 输出与 [nodeKey] 逐字相同，但语义中性：`meta_source.metaCacheKey` 的键是
/// `<库>␁<连接>`——第一段是库、第二段才是作用域，与 `nodeKey(连接, rel)` 的
/// 字段顺序正好相反。共用拼装是为了让**分隔符只有一份**，而不是让两个
/// 不同语义的东西共用一个名字（名字错了比分隔符错了更难看出来）。
///
/// 0.9.334：此前 `author_dir_filter`、`crawler_sections`（两处）、
/// `meta_source`（两处）各自在字符串里写了一个 `\u0001` 字面量——五份肉眼
/// 分不出差别的控制字符，只在「某处被改成 `\u0001 `」时才炸，而那种时候
/// 表现是「这条筛选/配置/缓存读不出来」，四处都自洽。
String scopedKey(String a, String b) =>
    '${a.trim()}$kNodeKeySep${b.trim()}';
