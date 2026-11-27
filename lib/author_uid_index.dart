/// 作者名 → 平台 uid 的索引（**唯一实现**）。
///
/// 为什么需要它：`AuthorAvatarStore` 从 0.9.331 起在**有 uid 时按 `uid:` 键
/// 写**手动头像（作者在平台改名后仍能找到）。但读取侧只有作者主页传了 uid
/// ——作者总览卡、播放页、基础库页作者 tab 都只调 `pathFor(name)`：
///
/// ```
/// 写： uid:123  -> /media/.../x.jpg     （作者页设置头像，当时有 uid）
/// 读： pathFor('新名字')  -> null        （改名后，名字键早已不存在）
/// ```
///
/// 于是「在作者页设的头像，改过名之后只有作者页还认，卡片与播放页全退回
/// 爬虫图」。这不是显示问题，是**同一个读取规则在四个地方各写了一遍**，
/// 其中三处漏了 uid 这一级。
///
/// 这里把「名字 → uid」这张表与「按名字取手动头像」收成一处：
/// 数据来源与 [authorAvatarIndex] 同一次 `/api/authors.json` 响应（同一个
/// 作用域），所以生命周期也一起——连接一变就清空，不跨服务器串作者。
library;

import 'author_avatar_store.dart';

/// 作者名的等价写法：**去首尾空白**，以及**去掉前导 `@`**。
///
/// 服务端 `authors.json` 的作者键存在 `张三` 与 `@张三` 两种（同一个人），
/// 而本机覆盖表按调用方传进来的原样存。只拿一种去查，另一半永远查不到：
///
/// ```
/// 索引里:        '@那谁' -> uid:123
/// 作者页传进去:  '那谁'   -> 查不到 uid -> 读不到手动头像
/// ```
///
/// 所以查找一律跑「两种写法 × 两种键」。不在这里做全角折叠：那会改变
/// 「是不是同一个作者」的判定，属于 `author_index.authorMatchKey` 的职责，
/// 本文件只负责「同一个名字的两种写法」。
List<String> authorNameForms(String name) {
  final t = name.trim();
  if (t.isEmpty) return const <String>[];
  final bare = t.replaceFirst(RegExp(r'^@+'), '').trim();
  if (bare.isEmpty || bare == t) return <String>[t];
  return <String>[t, bare];
}

/// 作者名 → 平台 uid。键是**已归一**的作者名（见 [authorNameForms] 两种写法都存）。
///
/// 只由 [_putUid] 写入；不对外暴露可写视图，避免调用点各自 `map[name]=uid`。
final Map<String, String> _authorUidByName = <String, String>{};

/// 当前索引的作用域（`<base>␁<user>`）；空串＝尚未加载。
String _authorUidScope = '';

/// 这个作者名对应的平台 uid；没有则空串。
String authorUidFor(String name) {
  for (final f in authorNameForms(name)) {
    final hit = _authorUidByName[f];
    if (hit != null && hit.isNotEmpty) return hit;
  }
  return '';
}

/// 索引是否属于当前作用域。
bool authorUidIndexLoadedFor(String scopeKey) =>
    scopeKey.isNotEmpty && _authorUidScope == scopeKey;

/// 用一份 `authors.json`（或多个）重建索引。
///
/// [entries] 是 `作者名 → 索引条目`；条目里没有 `uid` 的作者不进表（旧服务端
/// 的 `authors.json` 不带这个字段，此时整张表为空，行为与改动前一致）。
///
/// [scopeKey] 是**发请求时**那一份作用域：请求途中用户可能又切了连接，
/// 拿当前值写入等于把旧服务器的 uid 记成新连接的。
void rebuildAuthorUidIndex(
    Iterable<MapEntry<dynamic, dynamic>> entries, String scopeKey) {
  if (scopeKey.isEmpty) return;
  _authorUidByName.clear();
  for (final e in entries) {
    final name = authorAvatarKey('${e.key}');
    if (name.isEmpty) continue;
    final v = e.value;
    if (v is! Map) continue;
    final uid = '${v['uid'] ?? ''}'.trim();
    if (uid.isEmpty) continue;
    // 两种写法都进表：作者页传来的名字可能是带 `@` 也可能不带。
    // `putIfAbsent` 保持「先到先得」，两条键指向同一个 uid 时不会互相覆盖。
    for (final form in authorNameForms(name)) {
      _authorUidByName.putIfAbsent(form, () => uid);
    }
  }
  _authorUidScope = scopeKey;
}

/// 作废索引（连接变化、手动刷新作者索引时调用）。
void clearAuthorUidIndex() {
  _authorUidByName.clear();
  _authorUidScope = '';
}

/// 按名字取手动头像：**先名字键、再 uid 键**（与 `pathFor` 同一优先级）。
///
/// 这是全 App 唯一的读法。四个入口（作者总览卡、播放页、基础库页作者 tab、
/// 作者主页）都必须走它，否则又会回到「有的地方认改名后的头像、有的地方不认」。
String manualAvatarFor(String name) {
  final store = AuthorAvatarStore.instance;
  final forms = authorNameForms(name);
  if (forms.isEmpty) return '';
  // 第一级：名字键（历史数据都在这，作者页设置头像时也是这样写的）。
  for (final f in forms) {
    final hit = store.pathFor(f);
    if (hit != null && hit.isNotEmpty) return hit;
  }
  // 第二级：`uid:` 键。uid 本身也两种写法都查（表里按两种写法存）。
  final uid = authorUidFor(name);
  if (uid.isEmpty) return '';
  for (final f in forms) {
    final hit = store.pathFor(f, uid: uid);
    if (hit != null && hit.isNotEmpty) return hit;
  }
  return '';
}
