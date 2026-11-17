import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_upload.dart';

List<int> jpeg() => [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0];
List<int> png() => [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0];
List<int> webp() => [
      ...'RIFF'.codeUnits,
      0, 0, 0, 0,
      ...'WEBP'.codeUnits,
      0, 0, 0, 0,
    ];

void main() {
  test('只放行 JPG/PNG/WebP 魔数', () {
    expect(isSupportedCoverBytes(jpeg()), isTrue);
    expect(isSupportedCoverBytes(png()), isTrue);
    expect(isSupportedCoverBytes(webp()), isTrue);
    expect(isSupportedCoverBytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])),
        isFalse);
    expect(isSupportedCoverBytes(<int>[]), isFalse);
    expect(isSupportedCoverBytes(Uint8List.fromList('GIF89a~~~~~~'.codeUnits)),
        isFalse);
  });

  test('截断的 RIFF 不算 WebP', () {
    expect(isSupportedCoverBytes('RIFF____WEB'.codeUnits), isFalse);
  });

  test('上限常量与服务端一致（12MB）', () {
    expect(kCoverUploadMaxBytes, 12 * 1024 * 1024);
  });

  test('取消结果不当作失败提示', () {
    const r = CoverUploadResult.cancelled();
    expect(r.ok, isFalse);
    expect(r.cancelled, isTrue);
    expect(r.message, isNotEmpty);
  });
  test('打开失败的文案不暴露原始异常', () {
    expect(coverPickErrorText(Exception('PlatformException(photo_access_denied, ...)')),
        contains('权限'));
    expect(coverPickErrorText(Exception('cancelled by user')), '已取消');
    expect(coverPickErrorText(Exception('boom 0xdeadbeef')),
        isNot(contains('boom')));
    expect(coverPickErrorText(Exception('boom')), contains('重试'));
  });
}
