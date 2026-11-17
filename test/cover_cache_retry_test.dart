import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/cover_cache.dart';

class _Resp implements FileServiceResponse {
  _Resp(this.contentLength);
  @override
  final int? contentLength;
  @override
  int get statusCode => 200;
  @override
  Stream<List<int>> get content => Stream<List<int>>.value(<int>[1, 2, 3]);
  @override
  DateTime get validTill => DateTime.now().add(const Duration(days: 1));
  @override
  String? get eTag => null;
  @override
  String get fileExtension => '.jpg';
}

class _FakeService extends FileService {
  _FakeService(this.lengths);
  final List<int?> lengths;
  int calls = 0;

  @override
  Future<FileServiceResponse> get(String url,
      {Map<String, String>? headers}) async {
    final i = calls < lengths.length ? calls : lengths.length - 1;
    calls++;
    return _Resp(lengths[i]);
  }
}

void main() {
  test('oversizedResizeResponse 按目标宽度判定', () {
    expect(oversizedResizeResponse('/media/a.jpg?w=480', 700000), isTrue);
    expect(oversizedResizeResponse('/media/a.jpg?w=480', 60000), isFalse);
    expect(oversizedResizeResponse('/media/a.jpg', 700000), isFalse);
    expect(oversizedResizeResponse('/media/a.jpg?w=480', null), isFalse);
    expect(oversizedResizeResponse('/media/a.jpg?w=480', 0), isFalse);
    // w=200 下限 150 KB：缩图正常 20–40 KB，原图通常远超 150 KB。
    expect(oversizedResizeResponse('/media/a.jpg?w=200', 140000), isFalse);
    expect(oversizedResizeResponse('/media/a.jpg?w=200', 400000), isTrue);
    // 参数不在末尾也要认。
    expect(oversizedResizeResponse('/media/a.jpg?w=480&x=1', 900000), isTrue);
  });

  test('未命中缩图：丢弃原图并重取一次', () async {
    final fake = _FakeService(<int?>[900000, 48000]);
    final svc = ResizeAwareFileService(fake,
        retryDelay: const Duration(milliseconds: 1));
    final r = await svc.get('/media/a.jpg?w=480');
    expect(fake.calls, 2);
    expect(r.contentLength, 48000);
  });

  test('正常尺寸只请求一次', () async {
    final fake = _FakeService(<int?>[48000]);
    final svc = ResizeAwareFileService(fake,
        retryDelay: const Duration(milliseconds: 1));
    final r = await svc.get('/media/a.jpg?w=480');
    expect(fake.calls, 1);
    expect(r.contentLength, 48000);
  });

  test('同一 URL 只重试一次', () async {
    final fake = _FakeService(<int?>[900000]);
    final svc = ResizeAwareFileService(fake,
        retryDelay: const Duration(milliseconds: 1));
    await svc.get('/media/a.jpg?w=480');
    await svc.get('/media/a.jpg?w=480');
    expect(fake.calls, 3); // 首次 2 次（原图 + 重取），第二次不再重试
  });
}
