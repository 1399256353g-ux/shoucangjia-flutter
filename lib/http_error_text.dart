// HTTP 状态码 → 用户可读文案的唯一实现。
//
// 三个业务函数（封面设置 `coverErrorText`、封面历史 `coverActionErrorText`、
// 作者头像 `authorAvatarApiErrorText`）此前各自写了一份 4~5 分支的 switch，
// 其中 `400 → 请求格式不对`、`500 → 服务端写入失败`、`default → HTTP n`
// 三条在每个函数里逐字重复。文案分叉的风险很实际：改一处忘两处，同一个
// 错误在不同页面显示不同原因。
//
// 这里只保留「状态码归类」这一层规则，业务文案通过 [overrides] 传入——
// 因为 404 对「作品封面」「封面版本」「作者头像」确实是三件不同的事，
// 统一成一句话反而会让用户看不懂。

/// 状态码 → 文案。[overrides] 优先，未命中时用通用归类。
///
/// 通用归类只覆盖三个跨业务一致的语义：请求格式（400）、图片过大（413）、
/// 服务端写入失败（500）；其余一律 `HTTP <状态码>`，不猜。
///
/// `status <= 0` 表示**根本没有 HTTP 状态码**（内部错误码缺省、网络异常短路），
/// 这时说「HTTP 0」只会让人去找一个不存在的响应。
String httpErrorText(int status, {Map<int, String> overrides = const {}}) {
  final o = overrides[status];
  if (o != null) return o;
  if (status <= 0) return '服务端未确认';
  switch (status) {
    case 400:
      return '请求格式不对';
    case 413:
      return '图片过大';
    case 500:
      return '服务端写入失败';
    default:
      return 'HTTP $status';
  }
}
