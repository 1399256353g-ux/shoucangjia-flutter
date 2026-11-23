/// 作品唯一键：`库/作品 id`。
///
/// 只用于本机内存映射与本地偏好（播放比例、已隐藏集合等），不参与任何
/// 内容判断。作品 id 为空时返回空串，调用方应跳过。
///
/// 原先放在 `likes.dart`（双击点赞），2026-11-23 去点赞后抽成独立模块：
/// 键本身与「喜欢/点赞」语义无关，只是「哪一条作品」的稳定标识。
library;

/// 生成作品键；作品 id 为空时返回空串。
String workKey({required String lib, required String id}) {
  final i = id.trim();
  if (i.isEmpty) return '';
  final l = lib.trim();
  return l.isEmpty ? i : '$l/$i';
}
