/// 自定义封面（`_cover/`）的请求体与文案（纯函数，便于单测）。
///
/// 服务端 `/api/cover/set` 支持两种操作：
///  - 设置：`{lib, work, at?, index?}` → 由服务端取图并压成 720px 宽 jpg，
///    写入 `<库>/_cover/<version>.jpg` 并更新 `_cover/current` 指针；
///    视频带 `at`（当前播放秒数）截当前帧，图文/单图带 `index` 取当前图；
///  - 清除：`{lib, clear:true}` → 只删 `_cover/current` 指针，
///    已生成的封面文件全部保留（回滚只需把指针指回旧版本）。
///
/// 服务端只新增/改指针，不动作品原图。本文件不碰网络与文件系统。
library;

/// 封面作用域：基础库封面（`_cover/`）与单元库封面（`unit-covers.json` 指针）。
///
/// 两者请求体形状一致（`{lib, work}` / `{lib, clear:true}`），只是接口与文案不同：
/// 单元库封面接口会自己从基础库路径反推单元库 rel，客户端只传基础库与作品。
enum CoverScope {
  basic('/api/cover/set'),
  unit('/api/cover/unit');

  const CoverScope(this.path);

  /// 接口路径（POST）。
  final String path;
}

/// 封面操作类型。
enum CoverOp { set, clear }

/// 一次封面操作（设置 / 清除）。
class CoverRequest {
  final String lib;
  final String work;
  final CoverOp op;
  final CoverScope scope;

  /// 视频截帧时间点（秒）。null 表示交给服务端选图（旧调用方）。
  final double? at;

  /// 图文/单图取第几张（0 基）。null 表示取第 1 张。
  final int? index;

  const CoverRequest.set({
    required this.lib,
    required this.work,
    this.scope = CoverScope.basic,
    this.at,
    this.index,
  }) : op = CoverOp.set;

  const CoverRequest.clear({required this.lib, this.scope = CoverScope.basic})
      : work = '',
        op = CoverOp.clear,
        at = null,
        index = null;

  /// 请求体：清除只带 `clear:true`；设置带作品 id，并按需带截帧时间/图片序号。
  Map<String, dynamic> toBody() {
    if (op == CoverOp.clear) return <String, dynamic>{'lib': lib, 'clear': true};
    final body = <String, dynamic>{'lib': lib, 'work': work};
    if (at != null) body['at'] = at;
    if (index != null) body['index'] = index;
    return body;
  }

  /// 参数是否够用（缺库或设置时缺作品 id 都不发请求）。
  bool get valid =>
      lib.trim().isNotEmpty && (op == CoverOp.clear || work.trim().isNotEmpty);

  /// 成功后的提示文案。
  String get doneText {
    if (scope == CoverScope.unit) {
      return op == CoverOp.clear
          ? '已清除该单元库封面，恢复自动封面'
          : '已设为该单元库封面（返回主页刷新即可看到）';
    }
    return op == CoverOp.clear
        ? '已清除自定义封面，恢复自动封面'
        : '已设为该库封面（返回主页刷新即可看到）';
  }

  /// 失败提示前缀。
  String get failText {
    if (scope == CoverScope.unit) {
      return op == CoverOp.clear ? '清除单元库封面失败' : '设置单元库封面失败';
    }
    return op == CoverOp.clear ? '清除封面失败' : '设置封面失败';
  }
}

/// 把 HTTP 状态码翻成可读原因；未知状态码只报数字。
String coverErrorText(int status) {
  switch (status) {
    case 404:
      return '该库不存在或作品里没有可用图片';
    case 400:
      return '请求格式不对';
    case 500:
      return '服务端写入失败';
    default:
      return 'HTTP $status';
  }
}
