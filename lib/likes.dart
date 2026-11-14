import 'dart:ui' show Offset;

/// G9：双击点赞的本地喜欢标记。
///
/// 只在本机保存「库/作品」键，不上报服务端、不修改收藏夹。
/// 键带库前缀，避免不同库里同 id 的作品互相串标记。
const String kLikedWorksPrefsKey = 'liked_works_v1';

/// 生成作品喜欢标记的存储键；作品 id 为空时返回空串（调用方应跳过）。
String workLikeKey({required String lib, required String id}) {
  final i = id.trim();
  if (i.isEmpty) return '';
  final l = lib.trim();
  return l.isEmpty ? i : '$l/$i';
}

/// 容错解析本地列表：去空白、去空项、去重。
Set<String> parseLikedKeys(List<String>? raw) {
  final out = <String>{};
  for (final e in raw ?? const <String>[]) {
    final v = e.trim();
    if (v.isNotEmpty) out.add(v);
  }
  return out;
}

/// 返回写入 SharedPreferences 的新列表（排序后稳定存储）。
List<String> updateLikedKeys(
  Iterable<String> keys,
  String key, {
  required bool liked,
}) {
  final out = keys.where((e) => e != key).toList();
  if (liked && key.isNotEmpty) out.add(key);
  out.sort();
  return out;
}

/// G9：判断舞台上的第二次点击是否构成双击（时间 320ms、位移 80px）。
bool isStageDoubleTap({
  required int nowMs,
  required int lastMs,
  required Offset? lastPos,
  required Offset? pos,
  int windowMs = 320,
  double maxDistance = 80,
}) {
  if (pos == null || lastPos == null || lastMs <= 0) return false;
  if (nowMs - lastMs >= windowMs) return false;
  return (pos - lastPos).distance < maxDistance;
}
