/// 图片「按显示尺寸取图」参数（纯函数，便于单测）。
///
/// 背景（owner 2026-11-17「封面加载慢」）：卡片只有 150–220 逻辑像素宽，却
/// 去拉爬虫落盘的原始大图（常见 1080–4000px、几百 KB 到数 MB），局域网里也
/// 要等明显一下。服务端 `/media/...` 新增 `w=<像素>` 参数按需缩放并落盘缓存
/// （只对 jpg/jpeg 生效，其它格式原样返回），客户端在卡片类封面/头像上带
/// `w=`，播放页等大图场景不带，保持原画质。
library;

/// 库/单元库卡片封面宽度（卡片约 150–180dp，2x 屏 360px 足够）。
const int kCardImageWidth = 480;

/// 作品卡封面宽度（卡片约 110–180dp）。
const int kWorkImageWidth = 440;

/// 头像宽度（最大显示 64dp）。
const int kAvatarImageWidth = 200;

/// 播放页海报（全屏铺底）宽度：1080p 屏也够清晰，比动辄 2400px 的
/// 原图省一半以上流量与解码内存。
const int kPlayerImageWidth = 1080;

final RegExp _imageExt = RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false);
final RegExp _hasWidthParam = RegExp(r'(?:^|&)w=\d+(?:&|$)');

/// 只给「图片静态路径」加 `w=`：
///  - 绝对/根相对地址才处理，`asset:`/`data:`/空串原样返回；
///  - 路径必须以 jpg/jpeg/png/webp 结尾（视频、`/api/thumb/...` 这类接口
///    没有扩展名的地址不加，避免给抽帧接口塞无用参数）；
///  - 已有 `w=` 时不重复添加；
///  - 保留原有 query 与 `#fragment`。
String withImageWidth(String raw, int width) {
  final url = raw.trim();
  if (url.isEmpty || width <= 0) return raw;
  if (!(url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('/'))) {
    return raw;
  }
  var body = url;
  var fragment = '';
  final hash = url.indexOf('#');
  if (hash >= 0) {
    body = url.substring(0, hash);
    fragment = url.substring(hash);
  }
  final q = body.indexOf('?');
  final pathPart = q >= 0 ? body.substring(0, q) : body;
  final query = q >= 0 ? body.substring(q + 1) : '';
  if (!_imageExt.hasMatch(pathPart)) return raw;
  if (_hasWidthParam.hasMatch(query)) return raw;
  final sep = q >= 0 ? '&' : '?';
  return '$body${sep}w=$width$fragment';
}
