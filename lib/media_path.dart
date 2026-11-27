/// 媒体路径转义（**单一实现**）。
///
/// NAS 上的文件名可能带 `#`、`?` 或空格（如 `1#花絮.mp4`），直接拼进 URL 后
/// `Uri.parse` 会把 `#` 之后当 fragment、`?` 之后当 query，请求到的是另一个
/// 路径，表现为封面 404 / 播放失败。
///
/// 规则：
/// - 已有合法 `%XX` 原样保留，避免二次编码（`%25`）；
/// - 孤立 `%`（后面不是两位十六进制）转成 `%25`；
/// - `#`、`?`、空格、控制字符转义成 `%XX`；
/// - 其余字符（含中文、`/` 分段符）不动，交给 Uri 自己编码。
///
/// 0.9.231：这条规则此前只被 `Cfg.mediaUrl`（main.dart）用，而
/// `lib_cover.absoluteMediaUrl`（单元库卡片 / 基础库卡片的封面主路径）
/// 直接 `'$base$path'` 拼——同一个带 `#` 的文件名，走作品列表能播，
/// 走库卡片就 404。两份实现只差「有没有转义」，所以转义本身单独成模块，
/// 任何拼媒体地址的地方都必须经过它。
library;

/// 绝对 `http(s)` 地址？是则调用方不应再补服务器前缀。
///
/// 协议**忽略大小写**：连接地址那条规则（`multi_server.normalizeBase`）早已
/// 认 `HTTP://NAS:8090`（owner 从浏览器地址栏复制的结果），媒体地址这一条却
/// 只认小写。于是同一条「绝对地址」判定在配置层为真、在媒体层为假：
///
/// ```
/// normalizeBase('HTTP://nas:8090')                     -> 'http://nas:8090'
/// isAbsoluteMediaUrl('HTTP://nas/x.jpg')               -> false  ← 实测
/// libraryMediaPath('lib', 'HTTP://nas/x.jpg')          -> '/media/lib/HTTP://nas/x.jpg'  ← 实测
/// absoluteMediaUrl('http://nas:8090', ...)             -> 'http://nas:8090/media/lib/HTTP://nas/x.jpg'
/// ```
///
/// 服务端把 `HTTP:` 当库内子目录，那张封面/头像永远 404，而地址本身完全可用。
/// 判定只写这一份，`media_resize.withImageWidth` 与
/// `author_avatar_store._validAvatarValue` 都转发到这里。
bool isAbsoluteMediaUrl(String path) {
  final p = path.trim().toLowerCase();
  return p.startsWith('http://') || p.startsWith('https://');
}

/// **协议相对**地址（`//cdn.example.com/x.jpg`）？
///
/// 浏览器地址栏与部分 CDN 会把同域不同协议的外链写成这样。它和
/// [isAbsoluteMediaUrl] 是**两件事**：前者没写协议、后者写了。此前只判了后者，
/// 于是协议相对地址被当成库内相对路径补齐：
///
/// ```
/// isAbsoluteMediaUrl('//cdn/x.jpg')            -> false        ← 实测
/// libraryMediaPath('lib', '//cdn/x.jpg')       -> '/media/lib/cdn/x.jpg'  ← 实测
/// ```
///
/// 服务端按这个路径找不到文件，爬虫封面永远 404、卡片只剩底色。判定单独一个
/// 出口，拼地址时统一由 [resolveProtocolRelative] 补协议——**不要**各处
/// `startsWith('//')`。
bool isProtocolRelativeUrl(String path) {
  final p = path.trim();
  return p.length > 2 && p.startsWith('//');
}

/// 网络地址（绝对 或 协议相对）：调用方不应再补 `/media/<lib>/` 前缀。
bool isNetworkMediaUrl(String path) =>
    isAbsoluteMediaUrl(path) || isProtocolRelativeUrl(path);

/// 把协议相对地址补成绝对地址：协议取自 [base]（解析不出时回落 `https`）。
///
/// `//cdn/x.jpg` + `http://nas:8090` → `http://cdn/x.jpg`。
/// 非协议相对地址原样返回（幂等），调用方可以无条件调用。
String resolveProtocolRelative(String base, String path) {
  final p = path.trim();
  if (!isProtocolRelativeUrl(p)) return p;
  // 只取协议名，而且**必须带 `://`**：`nas:8090` 里的 `nas:` 是主机名而不是
  // 协议（只判 `^([A-Za-z]+):` 会把它当成协议，拼出 `nas://cdn/x.jpg`——
  // 语法合法、永远连不上）。取不到就回落 `https`。
  final m = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://').firstMatch(base.trim());
  final scheme = (m?.group(1) ?? 'https').toLowerCase();
  return '$scheme:$p';
}

/// 服务端**接口**地址（`/api/thumb/<lib>/<id>` 等），不是媒体文件。
///
/// 扫描器会把这类地址写进作品的 `th`/`fc`，若再套 `/media/<lib>/` 就变成
/// `/media/<lib>/api/thumb/...`——服务端把 `api` 当库内子目录，必然 404。
/// 实测 2026-11-23：2288 条图文作品的 `th` 就是这种接口地址。
bool isApiMediaPath(String path) => path.trim().startsWith('/api/');

/// 已经是 `/media/` 起头的库内媒体路径？
///
/// **唯一定义**。此前这条判定在 6 处各写一遍
/// （`lib_cover.coverUrlOf` / `nodesFromMarks` / `cover_history` /
/// `unit_library` / `cover_upload` / `source_lib`），都是裸
/// `startsWith('/media/')`：哪天服务端把前缀改成 `/m/` 或加上域名，
/// 六处得同时改，漏一处就是「封面/头像/节点封面一半显示一半空」。
bool isMediaPath(String path) => mediaRelOrNull(path) != null;

/// `/media/` 之后的部分；不是媒体路径时返回 **null**（与「有前缀但后面为空」区分）。
///
/// 前缀长度 `7` 此前在四个文件里各写了一遍（`lib_cover.libOfMediaPath`、
/// `author_avatar_store.serverAvatarFileFromPath`、`source_lib.decodeMediaRel`、
/// `main.Cfg.media` / `main.authorPrefixOfMedia`），而且每一处都得**先自己
/// trim** 才安全：`isMediaPath` 是 trim 后比较的，`p.substring(7)` 用的却是
/// 原串，`'\t/media/lib-7/a.jpg'` 会切出 `ib-7/a.jpg`。哪一处忘了 trim，
/// 库段就少一个字符，绑定表查不到 → 请求打到默认服务器。
///
/// 现在前缀判定与切片在同一个函数里，调用方拿到的就是已经 trim 过的尾部。
String? mediaRelOrNull(String path) {
  final p = path.trim();
  if (!p.startsWith('/media/')) return null;
  return p.substring(7);
}

/// 把 `/media/<lib>/<相对路径>` 拆成「库段 + 其余」（**唯一实现**）。
///
/// 「取第一段当库 id」这件事此前写了三遍，每遍都自带一个 `indexOf('/')`
/// 和三行切片：
///
/// ```
/// lib_cover.libOfMediaPath         取库段（封面/删除记录/头像的路由依据）
/// main.Cfg.media                   判断「这条路径已经带了已知库段吗」
/// main.authorPrefixOfMedia         去掉库段后取作者目录前缀
/// ```
///
/// 三份里只要有一份对「没有第二段」的处理不同，同一份路径就会在封面解析里
/// 认得出库、在媒体拼接里认不出（于是被再前缀一次 → 404）。
///
/// 返回 null = 不是媒体路径；`rel` 为空 = 只有库段没有文件段。
({String lib, String rel})? mediaLibSplitOrNull(String path) {
  final rest = mediaRelOrNull(path);
  // `/media/` 后面什么都没有时不算「有库段」：与 `isMediaPath('/media/')`
  // 的旧口径保持一致（那里也返回 true，但取库段的调用方一律按未命中处理）。
  if (rest == null || rest.isEmpty) return null;
  final at = rest.indexOf('/');
  final seg = at < 0 ? rest : rest.substring(0, at);
  return (
    lib: decodeComponentOrRaw(seg),
    rel: at < 0 ? '' : rest.substring(at + 1),
  );
}


/// 相对路径 → `/media/<lib>/<rel>`（**唯一拼装口**）。
///
/// 「库前缀」这件事此前在三个文件里各拼一遍，而且各自的**判定集合不同**：
///
/// ```
/// lib_cover.libraryMediaPath  network/api/media 三种都判，不补前缀
/// main.Cfg.media              同上，但 `/media/` 已知库段时原样返回
/// main.Cfg.media（相对分支）   '/media/${Uri.encodeComponent(l)}/$rel'
/// ```
///
/// 编`Uri.encodeComponent(l)` 这一句就抄了两次：只要有一处改成不编码（或
/// 编码两次），中文/空格库名的封面在其中一个入口就是 `%25E4%25B8%25AD`
/// ——服务端按字面路径找不到目录，返回 404，卡片只剩底色。
///
/// [lib] 为空时返回 `/media/<rel>`（服务端接受无库段的形式）。
/// [rel] 前导斜杠会被吃掉：`'/cover/v1.jpg'` 不能拼成 `//cover`。
String libMediaPrefix(String lib, String rel) {
  final r = rel.trim().replaceFirst(RegExp(r'^/+'), '');
  final l = lib.trim();
  if (l.isEmpty) return '/media/$r';
  return '/media/${Uri.encodeComponent(l)}/$r';
}

/// 百分号解码，非法编码原样返回（**唯一实现**）。
///
/// 媒体路径的库段与 `.avatars` 文件名都可能是百分号编码的，而文件名本身
/// 可以含孤立 `%`（如 `100%成品.jpg` 被拼进路径后仍是裸 `%`）。
/// `Uri.decodeComponent` 遇到非法编码直接抛 `ArgumentError`：
/// `libOfMediaPath` 早有 try 保护，`serverAvatarFileFromPath` 没有——
/// 点一次这种头像就在 UI 回调里抛异常。规则只允许有一份。
String decodeComponentOrRaw(String s) {
  if (s.isEmpty || !s.contains('%')) return s;
  try {
    return Uri.decodeComponent(s);
  } catch (_) {
    return s;
  }
}

/// 媒体类型（**唯一分类表**）。
///
/// 服务端 `gen_lib_index.py` 只有三张表：`VIDEO_EXT` / `IMAGE_EXT` /
/// `AUDIO_EXT`，索引里一个文件算视频、图片还是音频都由它决定。客户端此前
/// 把同一件事写成了**四份互不相等的清单**：
///
/// ```
/// media_path.kVideoExts        6 种（缺 ts/wmv/3gp/flv）
/// playback_error._kRedactExts 视频 7 种（多 ts）、图片 8 种（多 avif）
/// cover_ext.kCoverImageExts    7 种（多 heic，缺 avif）
/// author_avatar.kAvatarImageExts 7 种（多 avif，缺 heic/heif）
/// ```
///
/// 后果不是「显示差一点」，而是**同一份文件在不同页面走不同分支**：
/// 服务端下发的 `.ts` 视频在网格里不算视频（进不了播放分支、只当封面候选
/// 再被剔除 → 卡片全是底色），`.avif` 头像能显示却不能当封面。
///
/// 三张表必须以服务端为准；各调用点只允许用下面的谓词，不得再列清单。
/// 「服务端能吃这个格式吗」（缩图/头像注册只收四种）是**另一条规则**，
/// 在 `cover_ext.kCoverExts`，别混进来。
const List<String> kVideoExts = <String>[
  '.mp4',
  '.mov',
  '.m4v',
  '.mkv',
  '.webm',
  '.avi',
  '.ts',
  '.wmv',
  '.3gp',
  '.flv',
];

/// 图片扩展名（与服务端 `IMAGE_EXT` 同源，含 heic/heif/avif）。
const List<String> kImageExts = <String>[
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.heic',
  '.heif',
  '.bmp',
  '.avif',
];

/// 音频扩展名（与服务端 `AUDIO_EXT` 同源）。
const List<String> kAudioExts = <String>[
  '.mp3',
  '.m4a',
  '.aac',
  '.wav',
  '.flac',
  '.ogg',
];

/// 媒体文件的类别。`other` 表示「不是服务端认识的媒体文件」（目录、txt…）。
enum MediaKind { video, image, audio, other }

/// 按扩展名给媒体分类（**唯一实现**，忽略 `?query` 与 `#fragment`）。
///
/// 判定顺序与三张表无关：先剥后缀、再比末段。用 `endsWith` 而不是
/// `split('.')`，因为文件名里可以有点（`a.b.mp4`）而目录名里可以有扩展名
/// （`x.mp4/` 只是名字，真正的文件另有后缀）。
MediaKind mediaKindOf(String path) {
  final l = stripMediaSuffix(path).toLowerCase();
  if (l.isEmpty) return MediaKind.other;
  bool has(List<String> exts) => exts.any(l.endsWith);
  if (has(kVideoExts)) return MediaKind.video;
  if (has(kImageExts)) return MediaKind.image;
  if (has(kAudioExts)) return MediaKind.audio;
  return MediaKind.other;
}

/// 是否服务端认识的媒体文件（视频 / 图片 / 音频任一）。
///
/// 播放失败日志的脱敏边界用它：这里判错一位，整段路径连同文件名就会留在
/// 日志里（AGENTS.md：文件名不上传、不进模型）。
bool isMediaFilePath(String path) => mediaKindOf(path) != MediaKind.other;

/// 是否图片（可渲染成封面/头像）。
bool isImageMediaPath(String path) => mediaKindOf(path) == MediaKind.image;

/// 去掉地址里的 `?query` 与 `#fragment`，只保留路径本体（**唯一实现**）。
///
/// 同一件事此前在两处各写一遍，而且**只剥了一半**：
///  - `isVideoMediaPath` 两段都剥（`\n` 与 `#`）；
///  - `cover_ext.isCoverImagePath` 只写 `split('?').first`。
///
/// 实测后果：`isCoverImagePath('/a.jpg#poster')` 返回 **false**
/// （`'a.jpg#poster'.endsWith('.jpg')` 为 false）——`pickCoverPath` 于是把
/// 这一张唯一的候选剔除，卡片渲染成一块空白底色，而地址本身完全能加载。
/// 扫器/服务端把 `#poster`、`#t=1` 这类片段写进 `cv`/`fc` 并不罕见。
String stripMediaSuffix(String p) {
  var s = p.trim();
  if (s.isEmpty) return s;
  final q = s.indexOf('?');
  if (q >= 0) s = s.substring(0, q);
  final h = s.indexOf('#');
  if (h >= 0) s = s.substring(0, h);
  return s;
}

/// 把地址切成 `路径 / 查询串 / 片段` 三段（**唯一实现**）。
///
/// [stripMediaSuffix] 是它的「丢掉后两段」特例；需要**保留**后缀再拼回去的
/// 调用方（缩图参数、绝对地址转义）用它，否则各自手写「先 find `#` 再 find
/// `?`」，顺序一错就切反：
///
/// ```
/// withImageWidth('/a.jpg#f?w=1', 640)  -> '/a.jpg?w=640#f?w=1'   ← 实测（片段里又长出参数）
/// ```
///
/// 片段本身可以包含 `?`（它只是片段内容），所以**必须先切 `?` 再切 `#`**：
/// 反过来时 `/a.jpg#f?w=1` 的 `#` 在前，`?` 会被判成「片段内的字符」，
/// 查询串整个丢掉。
({String path, String query, String fragment}) splitMediaSuffix(String p) {
  final s = p.trim();
  final q = s.indexOf('?');
  final h = s.indexOf('#');
  // 先算 `#`，再在 `#` 之前找 `?`：两者都能正确落在路径段内。
  if (h >= 0) {
    final head = s.substring(0, h);
    final q2 = head.indexOf('?');
    if (q2 >= 0) {
      return (
        path: head.substring(0, q2),
        query: head.substring(q2 + 1),
        fragment: s.substring(h),
      );
    }
    return (path: head, query: '', fragment: s.substring(h));
  }
  if (q >= 0) {
    return (
      path: s.substring(0, q),
      query: s.substring(q + 1),
      fragment: '',
    );
  }
  return (path: s, query: '', fragment: '');
}

bool isVideoMediaPath(String p) => mediaKindOf(p) == MediaKind.video;

/// 路径是否指向 GIF 动图（**唯一定义**，忽略 `?query` 与 `#fragment`）。
///
/// 此前这条判定有两个手写副本，都只处理了一半后缀：
///  - `main.isGifPath`：`low.endsWith('.gif') || low.contains('.gif?')`；
///  - `author_avatar.AvatarCandidate.isGif`：同一段代码再抄一遍。
///
/// 两处都靠 `contains('.gif?')` 认查询串，于是**片段**形式的地址全部漏判：
/// 实测 `isGifPath('/m/a.gif#poster')` 返回 **false**——`CachedNetworkImage`
/// 只取首帧，一张动图在网格里就变成静止的第一帧，看起来像「动图丢了」。
/// 同一份图像路径在别处（`isCoverImagePath` / `isVideoMediaPath`）已经认
/// 片段，只有动图这一条不认。
///
/// 后缀剥除统一走 [stripMediaSuffix]，判定只写一份。
bool isGifMediaPath(String p) {
  final l = stripMediaSuffix(p).toLowerCase();
  return l.endsWith('.gif');
}

String encodeMediaPath(String path) {
  if (path.isEmpty) return path;
  if (isAbsoluteMediaUrl(path)) return path;
  // 接口地址（`/api/thumb/<lib>/<id>`）不是媒体文件：它自带的 `?v=` 是
  // 抽帧版本参数，把 `?` 转义成 `%3F` 会让服务端收到一个不存在的路径。
  if (isApiMediaPath(path)) return path;
  final hex2 = RegExp(r'^[0-9A-Fa-f]{2}$');
  final out = StringBuffer();
  for (var i = 0; i < path.length; i++) {
    final ch = path[i];
    if (ch == '%') {
      final hex = i + 2 < path.length ? path.substring(i + 1, i + 3) : '';
      if (hex2.hasMatch(hex)) {
        out.write(path.substring(i, i + 3));
        i += 2;
      } else {
        out.write('%25');
      }
      continue;
    }
    final code = ch.codeUnitAt(0);
    if (ch == '#' || ch == '?' || ch == ' ' || ch == '\u007f' || code < 0x20) {
      out.write(Uri.encodeComponent(ch));
    } else {
      out.write(ch);
    }
  }
  return out.toString();
}
