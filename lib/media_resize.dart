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
/// 查询串 → 「带上本次宽度」的查询串（**唯一实现**）。
///
/// 旧写法是 `RegExp(r'(?:^|&)w=\d+(?:&|$)')`，只认「半角 `w=` + 至少一位数字」。
/// 四种真实输入都会被判成「没有宽度」，于是在已有参数后面**再追加一个**：
///
/// | 输入 | 旧输出 | 后果 |
/// |---|---|---|
/// | `/a.jpg?w=` | `/a.jpg?w=&w=480` | 两个同名参数，服务端取到空串，缩图失效 |
/// | `/a.jpg?w=0` | 原样保留 `w=0` | 宽度 0 = 不缩放，卡片又去拉原图 |
/// | `/a.jpg?w=-5` | `/a.jpg?w=-5&w=480` | 同名参数冲突 |
/// | `/a.jpg?W=100` | `/a.jpg?W=100&w=480` | 大小写不同 → 两个宽度 |
///
/// 判定只有一条规则：**按 `&` 切开、键名忽略大小写等于 `w`、值能解析成正整数**才算
/// 「已经有了」。已经可用就原样返回；存在但不可用（空/0/负/非数字）就把那一个
/// 换成新宽度，并且不再追加第二个。
String _queryWithWidth(String query, int width) {
  if (query.isEmpty) return 'w=$width';
  final parts = query.split('&');
  bool isWidthKey(String t) {
    final eq = t.indexOf('=');
    return (eq < 0 ? t : t.substring(0, eq)).trim().toLowerCase() == 'w';
  }

  bool usable(String t) {
    final eq = t.indexOf('=');
    if (eq < 0) return false;
    final n = int.tryParse(t.substring(eq + 1).trim());
    return n != null && n > 0;
  }

  final widthIdx = <int>[];
  for (var i = 0; i < parts.length; i++) {
    if (isWidthKey(parts[i])) widthIdx.add(i);
  }
  if (widthIdx.isEmpty) return '$query&w=$width';
  // 恰好一个且可用：就是它，原样返回（不重排用户的查询串）。
  if (widthIdx.length == 1 && usable(parts[widthIdx.first])) return query;

  // 其余情况一律重建：**只保留一个** `w`，且必须是可用宽度。
  // 有可用值就沿用第一个可用值（用户已经指定了宽度，不该被我们覆盖），
  // 否则把第一个位置换成新宽度、其余同名参数丢弃。
  final keepIdx =
      widthIdx.firstWhere((i) => usable(parts[i]), orElse: () => -1);
  final out = <String>[];
  for (var i = 0; i < parts.length; i++) {
    if (!isWidthKey(parts[i])) {
      out.add(parts[i]);
      continue;
    }
    if (i != (keepIdx >= 0 ? keepIdx : widthIdx.first)) continue;
    out.add(keepIdx >= 0 ? parts[i] : 'w=$width');
  }
  return out.join('&');
}

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
  final nextQuery = _queryWithWidth(query, width);
  // 值没变（已经有了可用宽度）时原样返回，不重排用户的查询串。
  if (nextQuery == query) return raw;
  return '$pathPart?$nextQuery$fragment';
}
