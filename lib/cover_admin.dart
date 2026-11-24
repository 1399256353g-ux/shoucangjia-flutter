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

import 'http_error_text.dart';

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

/// 截取框归一化的最小宽高（小于它说明用户没真正框选，按整帧处理）。
const double kCoverRectMin = 0.02;

/// 归一化封面截取框：`[x, y, w, h]`（0..1，相对源帧左上角）。
///
/// 越界值夹回画面内；宽高同时 ≥0.999、或不是 4 个有限数时返回 null，
/// 表示「整帧」，服务端维持原行为。与 `gallery_server.js` 的
/// `coverCropFilter()` 规则一致（两端各自夹一次，协议层不互相信任）。
List<double>? coverCropRect(List<double>? r) {
  if (r == null || r.length != 4) return null;
  if (r.any((v) => v.isNaN || v.isInfinite)) return null;
  final w = r[2].clamp(kCoverRectMin, 1.0);
  final h = r[3].clamp(kCoverRectMin, 1.0);
  if (w >= 0.999 && h >= 0.999) return null;
  final x = r[0].clamp(0.0, 1.0 - w);
  final y = r[1].clamp(0.0, 1.0 - h);
  return <double>[x, y, w, h];
}

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

  /// 封面截取框：`[x, y, w, h]` 归一化。null 表示整帧（旧行为）。
  final List<double>? rect;

  const CoverRequest.set({
    required this.lib,
    required this.work,
    this.scope = CoverScope.basic,
    this.at,
    this.index,
    this.rect,
  }) : op = CoverOp.set;

  const CoverRequest.clear({required this.lib, this.scope = CoverScope.basic})
      : work = '',
        op = CoverOp.clear,
        at = null,
        index = null,
        rect = null;

  /// 请求体：清除只带 `clear:true`；设置带作品 id，并按需带截帧时间/图片序号。
  Map<String, dynamic> toBody() {
    if (op == CoverOp.clear)
      return <String, dynamic>{'lib': lib, 'clear': true};
    final body = <String, dynamic>{'lib': lib, 'work': work};
    if (at != null) body['at'] = at;
    if (index != null) body['index'] = index;
    final rr = coverCropRect(rect);
    if (rr != null) body['rect'] = rr;
    return body;
  }

  /// 参数是否够用（缺库或设置时缺作品 id 都不发请求）。
  bool get valid =>
      lib.trim().isNotEmpty && (op == CoverOp.clear || work.trim().isNotEmpty);

  /// 成功后的提示文案。
  String get doneText {
    if (scope == CoverScope.unit) {
      return op == CoverOp.clear ? '已清除该单元库封面，恢复自动封面' : '已设为该单元库封面（返回主页刷新即可看到）';
    }
    return op == CoverOp.clear ? '已清除自定义封面，恢复自动封面' : '已设为该库封面（返回主页刷新即可看到）';
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
///
/// 只有 404 是本业务特指的（「库里/作品里没有可用图片」），其余走
/// [httpErrorText] 的通用归类，避免与另外两个封面/头像函数各写一份。
String coverErrorText(int status) => httpErrorText(status, overrides: const {
      404: '该库不存在或作品里没有可用图片',
    });
