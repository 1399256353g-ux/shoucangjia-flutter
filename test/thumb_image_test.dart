import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/thumb_image.dart';

Future<Object> _keyOf(ImageProvider provider) async =>
    await provider.obtainKey(ImageConfiguration.empty);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('thumbImageProvider', () {
    test('按宽度包装 ResizeImage（与 CachedNetworkImage 内部一致）', () {
      final p = thumbImageProvider('/media/a/b.jpg', decodeWidth: 440);
      expect(p, isA<ResizeImage>());
      final r = p as ResizeImage;
      expect(r.width, 440);
      expect(r.height, isNull);
      expect(r.imageProvider, isA<CachedNetworkImageProvider>());
    });

    test('同 URL + 同宽度 → 缓存键相等（命中，不再二次解码）', () async {
      final a = thumbImageProvider('/media/a/b.jpg', decodeWidth: 440);
      final b = thumbImageProvider('/media/a/b.jpg', decodeWidth: 440);
      expect(await _keyOf(a), await _keyOf(b));
    });

    test('同 URL + 不同宽度 → 缓存键不相等（正是不统一时的二次解码）', () async {
      final a = thumbImageProvider('/media/a/b.jpg', decodeWidth: 440);
      final b = thumbImageProvider('/media/a/b.jpg', decodeWidth: 480);
      expect(await _keyOf(a), isNot(await _keyOf(b)));
    });

    test('不同 URL 缓存键不相等', () async {
      final a = thumbImageProvider('/media/a/b.jpg', decodeWidth: 440);
      final b = thumbImageProvider('/media/a/c.jpg', decodeWidth: 440);
      expect(await _keyOf(a), isNot(await _keyOf(b)));
    });

    test('decodeWidth <= 0 时不缩放，直接返回原 provider', () async {
      final p = thumbImageProvider('/media/a/b.jpg', decodeWidth: 0);
      expect(p, isA<CachedNetworkImageProvider>());
      final q = thumbImageProvider('/media/a/b.jpg', decodeWidth: 0);
      expect(await _keyOf(p), await _keyOf(q));
    });
  });
}
