/// 基础库（basic library）的**唯一模型与唯一解析**。
///
/// 0.9.284（第六十二批）：这里原先有**两个模型描述同一条记录**——
/// `library_tree.BasicLib`（9 个字段，含 `coverVersion` / `coverExt` /
/// `crawlerCover` / 统计）与 `source_lib.BasicLibRef`（7 个字段，缺上面
/// 那四个）。两套字段名相同的部分（`id/name/rel/bigId/firstCover/
/// serverId/serverBase/serverLabel`）各存一份，`basicLibFromRef` 是唯一的
/// 转换点。
///
/// 后果不是「少显示一个字段」，而是**同一张卡在两个页面取到不同的封面**：
/// 单元库树里的基础库由 `basicsUnderBase` → `basicLibFromRef` 构造，而
/// `BasicLibRef` 根本装不下服务端的 `cover` 指针与 `cv` 爬虫封面，
/// 转换后 `coverVersion` 为空、`crawlerCover` 为空。于是同一个基础库：
///
/// ```
/// 首页（LibraryTree.parse，全字段）      → 自定义 _cover/ 或 cv 封面
/// 单元库页（BasicLibRef → basicLibFromRef）→ 只剩 fc / 播放量，常常是灰卡
/// ```
///
/// 两处各自都「算对了」——问题只在于转换点丢字段。修法是把模型和解析都
/// 收成一份：`basicLibFromJson` 是服务端条目 → 模型的**唯一**入口，
/// `LibraryTree.parse` 与 `basicsUnderBase` 都转发它。
library;

import 'disk_name.dart';
import 'json_num.dart';
import 'lib_cover.dart';
import 'server_origin.dart';

/// 一个基础库（服务端 `/api/libraries.json` 的 `basicLibraries` 条目）。
class BasicLib {
  final String id;
  final String name;
  final String rel;
  final String bigId;
  final int authors;
  final int works;

  /// 自定义封面版本（`_cover/<version>.<ext>`）；空串表示无自定义封面。
  final String coverVersion;
  final String coverExt;

  /// 爬虫脚本抓到的封面（作品目录 `cover.jpg`，服务端索引 `cv` 下发）；
  /// 空串表示没有。优先级介于手动封面与自动封面之间。
  final String crawlerCover;

  /// 服务端 `/api/libraries.json` 下发的「首张作品封面」（`fc`，已带
  /// `/media/<lib>/` 前缀，且保证是图片）。只在手动/爬虫/播放量都拿不到
  /// 图时兜底。
  final String firstCover;

  /// 来源连接（多 IP 聚合时用于路由与去重展示）。
  final String serverId;
  final String serverBase;
  final String serverLabel;

  /// 基础库的绝对路径（服务端 `path` 字段）。只有「反算相对路径」需要它，
  /// 展示与取图一律用 [rel]。
  final String path;

  const BasicLib({
    required this.id,
    required this.name,
    required this.rel,
    required this.bigId,
    required this.authors,
    required this.works,
    this.coverVersion = '',
    this.coverExt = 'jpg',
    this.crawlerCover = '',
    this.firstCover = '',
    this.serverId = '',
    this.serverBase = '',
    this.serverLabel = '',
    this.path = '',
  });

  // 0.9.229：不提供 `toJson()`。它只在测试里被断言过，`lib/` 没有任何调用点
  // ——库树从不回写本地快照（重启是重拉 `/api/libraries.json`）。
}

/// 服务端条目 → [BasicLib]（**唯一解析**）。
///
/// [rel] 是「相对注册库根」的路径，由调用方按自己的坐标系算好传入
/// （注册库 base 或媒体库根），本函数不猜坐标系——同一份 JSON 在两种
/// 坐标系下会得到不同的 rel，那是调用方的选择，不是解析的分歧。
///
/// [fallbackName] 只在 `rel` 为空（无法从目录名取显示名）时使用。
BasicLib basicLibFromJson(
  Map raw, {
  required String id,
  required String rel,
  String fallbackName = '',
}) {
  final pointer = coverPointerOf(raw['cover']);
  final origin = serverOriginOf(raw);
  return BasicLib(
    id: id,
    name: diskNameOf(rel, fallbackName.isEmpty ? id : fallbackName,
        where: 'BasicLib'),
    rel: rel,
    bigId: '${raw['big_id'] ?? ''}'.trim(),
    authors: intOf(raw['authors']),
    works: intOf(raw['works']),
    coverVersion: pointer.version,
    coverExt: pointer.ext,
    crawlerCover: '${raw['cv'] ?? ''}'.trim(),
    firstCover: firstWorkCoverOf(raw),
    serverId: origin.id,
    serverBase: origin.base,
    serverLabel: origin.label,
    path: '${raw['path'] ?? ''}'.trim(),
  );
}
