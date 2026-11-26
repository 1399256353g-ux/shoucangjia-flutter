/// 服务端「来源连接」字段的唯一读写口。
///
/// 聚合多个连接时，服务端下发的每条库/节点都会被打上五个私有字段：
/// `_serverId` / `_serverBase` / `_serverLabel` / `_serverUser` / `_serverPass`。
/// 此前这五个键名的字面量在 1 处写入（`multi_server._tag`）与 5 处读取
/// （`source_lib`、`library_tree` ×2、`unit_library`、`main` ×4）各写一遍：
/// 任何一处改名或补一个 `.trim()`，同一条记录在不同页面就会「有连接」与
/// 「无连接」两种身份——路由打到另一台服务器、封面 404，而界面各处都自洽。
///
/// 与封面首图字段 `fc` 同理：`'${raw['fc'] ?? ''}'.trim()` 也写了两遍。
library;

/// 五个字段名（唯一定义）。
const String kServerIdKey = '_serverId';
const String kServerBaseKey = '_serverBase';
const String kServerLabelKey = '_serverLabel';
const String kServerUserKey = '_serverUser';
const String kServerPassKey = '_serverPass';

/// 一条记录的来源连接。
///
/// [id] 是连接 id（不是地址、不是标签）：`buildUnitTree` 按它分组，
/// `cfg.headersFor` 按它取鉴权，写错整组会消失或串到另一台机器。
class ServerOrigin {
  final String id;
  final String base;
  final String label;
  final String user;
  final String pass;

  /// 账号/密码字段**是否存在于原始记录里**。
  ///
  /// `user` 无法区分「没写这个键」（旧格式，应用当前连接的账号）与
  /// 「写了但是空串」（这条连接本来就不需要鉴权）。`_switchTo` 以前靠
  /// `l['_serverUser'] ?? cfg.user` 区分这两件事，收口时不能把区别丢掉。
  final bool hasUser;
  final bool hasPass;

  const ServerOrigin({
    this.id = '',
    this.base = '',
    this.label = '',
    this.user = '',
    this.pass = '',
    this.hasUser = false,
    this.hasPass = false,
  });

  static const ServerOrigin empty = ServerOrigin();

  /// 没有任何来源信息（旧格式 / 离线快照 / 单连接）。
  bool get isEmpty => id.isEmpty && base.isEmpty && label.isEmpty;

  /// 卡片底部展示用的主机标注（`192.168.2.4:8090`）来源字段。
  String get displayLabel => label.trim();
}

/// 读取来源字段：所有五个键都 trim 一次，缺失即空串。
ServerOrigin serverOriginOf(dynamic raw) {
  if (raw is! Map) return ServerOrigin.empty;
  String s(String k) => '${raw[k] ?? ''}'.trim();
  return ServerOrigin(
    id: s(kServerIdKey),
    base: s(kServerBaseKey),
    label: s(kServerLabelKey),
    user: s(kServerUserKey),
    pass: s(kServerPassKey),
    hasUser: raw.containsKey(kServerUserKey),
    hasPass: raw.containsKey(kServerPassKey),
  );
}

/// 写入来源字段：服务端原始 map + 五个键（唯一写入口）。
Map<String, dynamic> withServerOrigin(
  Map raw, {
  required String id,
  required String base,
  required String label,
  String user = '',
  String pass = '',
}) =>
    <String, dynamic>{
      ...Map<String, dynamic>.from(raw),
      kServerIdKey: id.trim(),
      kServerBaseKey: base.trim(),
      kServerLabelKey: label.trim(),
      kServerUserKey: user,
      kServerPassKey: pass,
    };

/// 服务端下发的「首张作品封面」字段 `fc`（已是 `/media/<lib>/...` 的图片路径）。
///
/// 此前这段解析在 `source_lib`（基础库 ref）与 `library_tree`（基础库模型）
/// 各写一遍；两处一旦对「空串 / 空白 / 非字符串」处理不同，同一张库在
/// 单元库树与首页就一个有封面、一个灰。
String firstWorkCoverOf(dynamic raw) =>
    raw is Map ? '${raw['fc'] ?? ''}'.trim() : '';
