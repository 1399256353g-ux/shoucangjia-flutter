import 'media_path.dart';
import 'rel_path.dart';
import 'stable_order.dart';

import 'basic_lib.dart';
import 'lib_names.dart' show libDisplayName;

/// 作者来源词条（J9）的纯逻辑：
/// 从作品/头像的媒体路径反查所属「基础库」，词条显示基础库名称而不是大库名。
/// 媒体路径形如 `/media/(1)%20%E5%85%B6%E4%BB%96/@作者/_avatar/x.jpg`，
/// 基础库形如 `lib-008`，其相对库根的路径为 `(1) 其他`。
///
/// 0.9.284：本文件曾经自己定义 `BasicLibRef`——一个只装 7 个字段的「基础库」。
/// 同一份服务端记录于是有两个模型，转换点 `basicLibFromRef` 装不下 `cover`
/// 指针与 `cv` 爬虫封面，单元库页的基础库卡片就比首页少两级封面来源
/// （`_cover/` 与 `cv`），常常是灰卡。两个模型已合并为
/// `basic_lib.BasicLib`，转换点随之消失：`basicsUnderBase` 直接返回同一个模型。
/// 迁移期保留 `BasicLibRef` 这个名字作为别名，避免调用点一次性改名。
///
/// 把媒体 URL 解码为相对库根的路径（去掉 `/media/` 前缀）。
/// 非法百分号编码时退化为原串，避免抛异常。
String decodeMediaRel(String mediaPath) {
  // 剥 `?` / `#` 走 [stripMediaSuffix]（唯一实现）。
  //
  // 旧写法只 `indexOf('?')` 截查询串，`#fragment` **原样留下**：实测
  // `decodeMediaRel('/media/lib/@a/x.jpg#poster')` 返回 `lib/@a/x.jpg#poster`。
  // 后果是这条 rel 永远匹配不上磁盘上的目录（基础库归属、作者前缀都算废），
  // 而 `isCoverImagePath` / `isVideoMediaPath` 早已把片段剥掉——同一份路径
  // 在两处判定里是两个不同的名字。
  // 前缀判定与切片走同一条 `mediaRelOrNull`：旧写法 `isMediaPath(p)` 判的是
  // trim 后的串、`p.substring(7)` 切的是原串，带前导空白时库段少一个字符。
  final p = mediaRelOrNull(stripMediaSuffix(mediaPath)) ??
      stripMediaSuffix(mediaPath);
  // 逐段解码再做归一：整串先解码会把文件名里的 `%2F` 变成真分隔符，
  // 一条作品路径凭空多出一层目录。
  final segs = relSegments(p).map(decodeComponentOrRaw);
  return relJoin(segs);
}

/// 把基础库的绝对路径换算成相对注册库根目录的路径；不在此根下返回空串。
///
/// 拆分/归一交给 [relUnder]（`rel_path.dart` 唯一实现）：此前这里手写
/// 「掐尾斜杠 + `startsWith('$b/')`」，只认半角 `/`——实测
/// `relUnderBase('/vol1/m', r'/vol1/m\A')` 返回 **空串**，那个基础库随后被
/// `basicsUnderBase` 直接 `continue` 跳过，首页整条消失（不报错、不提示）。
/// `'/vol1/m/./A'` → `'./A'`、`'/vol1/m//A'` → `'/A'` 同理：算出的 rel 带着
/// 点段和多余分隔符，`basicLibForMedia` 永远匹配不上，封面/作者也一起错位。
String relUnderBase(String basePath, String basicPath) =>
    relUnder(basePath, basicPath);

/// 解析 `/api/libraries.json` 的基础库列表，只保留注册库根下的基础库。
///
/// 返回 `BasicLib`（与首页 `LibraryTree.parse` 同一个模型）：此前返回
/// `BasicLibRef`，转换点 `basicLibFromRef` 装不下 `cover` 指针与 `cv`，
/// 单元库页的基础库卡片少两级封面来源。解析本体在
/// `basic_lib.basicLibFromJson`，本函数只负责「取坐标系 + 过滤 + 稳定排序」。
List<BasicLib> basicsUnderBase(
    Map<String, dynamic> librariesJson, String basePath) {
  final out = <BasicLib>[];
  final raw = librariesJson['basicLibraries'];
  if (raw is! List) return out;
  for (final e in raw) {
    if (e is! Map) continue;
    final id = '${e['id'] ?? ''}';
    if (id.isEmpty) continue;
    final rel = relUnderBase(basePath, '${e['path'] ?? ''}');
    if (rel.isEmpty) continue;
    out.add(basicLibFromJson(e, id: id, rel: rel, fallbackName: '${e['name'] ?? ''}'));
  }
  // 同一个 rel 下可能有两条基础库记录（服务端重复注册、或两台服务端都
  // 下发了同一个 rel 且都没带连接标识）。同名之间没有次序依据，`List.sort`
  // 不稳定 → 首页卡片与作者词条偶尔换位置，而数据一个都没变。稳定排序保持
  // 服务端下发顺序。
  stableSort(out, (a, b) => a.rel.compareTo(b.rel));
  return out;
}

/// 按媒体路径匹配基础库：取相对路径前缀最长者，避免父目录误匹配。
BasicLib? basicLibForMedia(
    List<BasicLib> basics, String mediaPath) {
  if (basics.isEmpty) return null;
  final rel = decodeMediaRel(mediaPath);
  if (rel.isEmpty) return null;
  BasicLib? best;
  var bestLen = -1;
  for (final b in basics) {
    final r = b.rel;
    if (r.isEmpty) continue;
    if (rel == r || rel.startsWith('$r/')) {
      if (r.length > bestLen) {
        best = b;
        bestLen = r.length;
      }
    }
  }
  return best;
}

/// 从媒体路径反查基础库 id。
///
/// 基础库作者列表的 `av` 有两种写法：
///  1. 库内相对路径：`/media/(1)%20其他/@作者/_avatar/x.jpg`
///  2. 库作用域路径：`/media/lib-015/@作者/_avatar/x.jpg`
/// 第二种无法按目录前缀匹配，直接取前缀里的基础库 id（且该库确实存在）。
String basicIdForMedia(List<BasicLib> basics, String mediaPath) {
  if (basics.isEmpty || mediaPath.trim().isEmpty) return '';
  final rel = decodeMediaRel(mediaPath);
  final m = RegExp(r'^(lib-\d+)(?:/|$)').firstMatch(rel);
  if (m != null) {
    final id = m.group(1)!;
    for (final b in basics) {
      if (b.id == id) return id;
    }
  }
  return basicLibForMedia(basics, mediaPath)?.id ?? '';
}

/// 词条显示名：基础库名去掉编号前缀，例如「(8) 🦶」→「🦶」。
///
/// 0.9.354：这里原来自调 `normalizeLibLabel`（无条件去序号），于是「省略编号」
/// 开关关掉后，同一份名字在卡片标题上带 `(1) `、在筛选面板/作者词条上去掉
/// ——两个入口对同一份数据给出两个名字。去序号只有一个判断点（读开关的
/// `LibraryBadge.stripIndex`），经由 [libDisplayName] 转发。
String basicLibLabel(BasicLib? lib, String fallback) {
  if (lib == null) return fallback;
  final n = libDisplayName(lib.name);
  return n.isEmpty ? fallback : n;
}
