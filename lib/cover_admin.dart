/// 自定义封面（`_cover/`）的请求体与文案（纯函数，便于单测）。
///
/// 服务端 `/api/cover/set` 支持两种操作：
///  - 设置：`{lib, work}` → 把该作品的图片压成 720px 宽 jpg，写入
///    `<库>/_cover/<version>.jpg` 并更新 `_cover/current` 指针；
///  - 清除：`{lib, clear:true}` → 只删 `_cover/current` 指针，
///    已生成的封面文件全部保留（回滚只需把指针指回旧版本）。
///
/// 服务端只新增/改指针，不动作品原图。本文件不碰网络与文件系统。
library;

/// 封面操作类型。
enum CoverOp { set, clear }

/// 一次封面操作（设置 / 清除）。
class CoverRequest {
  final String lib;
  final String work;
  final CoverOp op;

  const CoverRequest.set({required this.lib, required this.work})
      : op = CoverOp.set;

  const CoverRequest.clear({required this.lib})
      : work = '',
        op = CoverOp.clear;

  /// 请求体：清除只带 `clear:true`，设置带作品 id。
  Map<String, dynamic> toBody() => op == CoverOp.clear
      ? <String, dynamic>{'lib': lib, 'clear': true}
      : <String, dynamic>{'lib': lib, 'work': work};

  /// 参数是否够用（缺库或设置时缺作品 id 都不发请求）。
  bool get valid =>
      lib.trim().isNotEmpty && (op == CoverOp.clear || work.trim().isNotEmpty);

  /// 成功后的提示文案。
  String get doneText => op == CoverOp.clear
      ? '已清除自定义封面，恢复自动封面'
      : '已设为该库封面（返回主页刷新即可看到）';

  /// 失败提示前缀。
  String get failText => op == CoverOp.clear ? '清除封面失败' : '设置封面失败';
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
