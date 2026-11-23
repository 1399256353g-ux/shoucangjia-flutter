import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

/// C2：库卡片「本地选图上传封面」的结果。
class CoverUploadResult {
  final bool ok;
  final bool cancelled;
  final String message;

  /// owner 2026-11-23：服务端返回的新封面相对媒体路径
  /// （`/media/<lib>/_cover/<version>.<ext>`）；卡片据此立即换图。
  final String url;

  const CoverUploadResult(this.ok, this.message,
      {this.cancelled = false, this.url = ''});

  const CoverUploadResult.cancelled()
      : ok = false,
        cancelled = true,
        message = '已取消',
        url = '';
}

/// 由宿主页面注入的上传入口：负责拼 URL/鉴权，并在成功后触发封面刷新。
typedef CoverUploader = Future<CoverUploadResult> Function({
  required String libId,
  String unitRel,
});

/// 与服务端 `/api/cover/upload` 保持一致的单图上限。
const int kCoverUploadMaxBytes = 12 * 1024 * 1024;

/// 只放行服务端支持的三种图片魔数（JPG/PNG/WebP）。
bool isSupportedCoverBytes(List<int> b) {
  if (b.length < 12) return false;
  if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return true;
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return true;
  }
  final riff = String.fromCharCodes(b.sublist(0, 4)) == 'RIFF';
  final webp = String.fromCharCodes(b.sublist(8, 12)) == 'WEBP';
  return riff && webp;
}

/// 打开选图失败时的可读文案：不把原始异常字符串暴露给用户。
String coverPickErrorText(Object e) {
  final s = '$e'.toLowerCase();
  if (s.contains('cancelled') || s.contains('canceled') || s.contains('cancel')) {
    return '已取消';
  }
  if (s.contains('denied') ||
      s.contains('permission') ||
      s.contains('not authorized')) {
    return '没有照片访问权限：请在系统设置里允许访问照片后重试';
  }
  if (s.contains('notsupported') || s.contains('unsupported')) {
    return '当前系统不支持选择图片';
  }
  return '无法打开图片选择器，请稍后重试';
}

/// 打开本地文件选择器挑一张图片，base64 POST 到 `/api/cover/upload`。
///
/// 只上传图片字节，不改作品原图与已有封面文件；`unitRel` 非空时表示
/// 该单元库的自定义封面（服务端写 unit-covers.json 指针）。
Future<CoverUploadResult> pickAndUploadCover({
  required String url,
  required Map<String, String> headers,
  required String libId,
  String unitRel = '',
}) async {
  XFile? picked;
  try {
    // iOS：file_selector 在部分系统上打不开，改用系统照片选择器（image_picker），
    // 需要 Info.plist 的 NSPhotoLibraryUsageDescription（CI 里注入）。
    if (Platform.isIOS) {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        imageQuality: 95,
      );
    } else {
      picked = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: '图片', extensions: ['jpg', 'jpeg', 'png', 'webp']),
      ]);
    }
  } catch (e) {
    return CoverUploadResult(false, coverPickErrorText(e));
  }
  if (picked == null) return const CoverUploadResult.cancelled();

  List<int> bytes;
  try {
    bytes = await picked.readAsBytes();
  } catch (e) {
    return const CoverUploadResult(false, '读取图片失败，请重试');
  }
  if (bytes.isEmpty) return const CoverUploadResult(false, '图片为空');
  if (bytes.length > kCoverUploadMaxBytes) {
    return const CoverUploadResult(false, '图片超过 12MB，请先压缩');
  }
  if (!isSupportedCoverBytes(bytes)) {
    return const CoverUploadResult(false, '只支持 JPG/PNG/WebP 图片');
  }

  return uploadCoverBytes(
    bytes: bytes,
    url: url,
    headers: headers,
    libId: libId,
    unitRel: unitRel,
  );
}

/// 直接用已有图片字节上传封面（播放页「设置封面」截帧/取当前图时用）。
Future<CoverUploadResult> uploadCoverBytes({
  required List<int> bytes,
  required String url,
  required Map<String, String> headers,
  required String libId,
  String unitRel = '',
}) async {
  if (bytes.isEmpty) return const CoverUploadResult(false, '图片为空');
  if (bytes.length > kCoverUploadMaxBytes) {
    return const CoverUploadResult(false, '图片超过 12MB，请先压缩');
  }
  if (!isSupportedCoverBytes(bytes)) {
    return const CoverUploadResult(false, '只支持 JPG/PNG/WebP 图片');
  }
  http.Response r;
  try {
    r = await http.post(
      Uri.parse(url),
      headers: {...headers, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'lib': libId,
        if (unitRel.isNotEmpty) 'unitRel': unitRel,
        'data': base64Encode(bytes),
      }),
    );
  } catch (e) {
    return const CoverUploadResult(false, '上传失败：网络异常，请检查连接后重试');
  }
  if (r.statusCode != 200) {
    var msg = 'HTTP ${r.statusCode}';
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['error'] is String) msg = j['error'] as String;
    } catch (_) {}
    return CoverUploadResult(false, '上传失败：$msg');
  }
  var coverPath = '';
  try {
    final j = jsonDecode(r.body);
    if (j is Map) coverPath = '${j['u'] ?? ''}'.trim();
  } catch (_) {}
  return CoverUploadResult(
      true, unitRel.isEmpty ? '封面已更新' : '单元库封面已更新',
      url: coverPath.startsWith('/media/') ? coverPath : '');
}
