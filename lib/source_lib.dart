import 'disk_name.dart';

/// 作者来源词条（J9）的纯逻辑：
/// 从作品/头像的媒体路径反查所属「基础库」，词条显示基础库名称而不是大库名。
/// 媒体路径形如 `/media/(1)%20%E5%85%B6%E4%BB%96/@作者/_avatar/x.jpg`，
/// 基础库形如 `lib-008`，其相对库根的路径为 `(1) 其他`。
class BasicLibRef {
  final String id;
  final String name;
  final String rel;
  /// 所属大库 id（J10 作者筛选用）；旧数据/缺失时为空。
  final String bigId;
  /// 基础库绝对路径；用于换算到其它坐标系（如库根 rel）。
  final String path;

  const BasicLibRef({
    required this.id,
    required this.name,
    required this.rel,
    this.bigId = '',
    this.path = '',
  });

  @override
  String toString() => 'BasicLibRef($id,$name,$rel)';
}

/// 去掉名称前的编号前缀「(12) 」并折叠空白，用于容错匹配。
String normalizeLibLabel(String raw) {
  var s = raw.trim();
  while (true) {
    final m = RegExp(r'^\(\s*\d+\s*\)\s*').firstMatch(s);
    if (m == null) break;
    s = s.substring(m.end).trim();
  }
  return s.replaceAll(RegExp(r'\s+'), ' ');
}

/// 把媒体 URL 解码为相对库根的路径（去掉 `/media/` 前缀）。
/// 非法百分号编码时退化为原串，避免抛异常。
String decodeMediaRel(String mediaPath) {
  var p = mediaPath.trim();
  final q = p.indexOf('?');
  if (q >= 0) p = p.substring(0, q);
  if (p.startsWith('/media/')) p = p.substring(7);
  try {
    p = Uri.decodeComponent(p);
  } catch (_) {}
  while (p.startsWith('/')) {
    p = p.substring(1);
  }
  return p;
}

/// 把基础库的绝对路径换算成相对注册库根目录的路径；不在此根下返回空串。
String relUnderBase(String basePath, String basicPath) {
  var b = basePath.trim();
  var p = basicPath.trim();
  if (b.isEmpty || p.isEmpty) return '';
  while (b.endsWith('/')) {
    b = b.substring(0, b.length - 1);
  }
  while (p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  if (p == b) return '';
  if (!p.startsWith('$b/')) return '';
  return p.substring(b.length + 1);
}

/// 解析 `/api/libraries.json` 的基础库列表，只保留注册库根下的基础库。
List<BasicLibRef> basicsUnderBase(
    Map<String, dynamic> librariesJson, String basePath) {
  final out = <BasicLibRef>[];
  final raw = librariesJson['basicLibraries'];
  if (raw is! List) return out;
  for (final e in raw) {
    if (e is! Map) continue;
    final id = '${e['id'] ?? ''}';
    final rawName = '${e['name'] ?? ''}';
    final path = '${e['path'] ?? ''}';
    final bigId = '${e['big_id'] ?? ''}';
    if (id.isEmpty) continue;
    final rel = relUnderBase(basePath, path);
    if (rel.isEmpty) continue;
    final name = diskNameOf(rel, rawName, where: 'BasicLibRef');
    out.add(
        BasicLibRef(id: id, name: name, rel: rel, bigId: bigId, path: path));
  }
  out.sort((a, b) => a.rel.compareTo(b.rel));
  return out;
}

/// 按媒体路径匹配基础库：取相对路径前缀最长者，避免父目录误匹配。
BasicLibRef? basicLibForMedia(
    List<BasicLibRef> basics, String mediaPath) {
  if (basics.isEmpty) return null;
  final rel = decodeMediaRel(mediaPath);
  if (rel.isEmpty) return null;
  BasicLibRef? best;
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
String basicIdForMedia(List<BasicLibRef> basics, String mediaPath) {
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
String basicLibLabel(BasicLibRef? lib, String fallback) {
  if (lib == null) return fallback;
  final n = normalizeLibLabel(lib.name);
  return n.isEmpty ? fallback : n;
}
