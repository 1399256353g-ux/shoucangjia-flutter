import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/concurrency.dart';

void main() {
  test('并发上限生效，结果顺序与输入一致', () async {
    final items = List<int>.generate(12, (i) => i);
    var inFlight = 0;
    var peak = 0;
    final out = await mapConcurrent<int, int>(items, 3, (i) async {
      inFlight++;
      if (inFlight > peak) peak = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inFlight--;
      return i * 10;
    });
    expect(peak, 3, reason: '并发窗口不得超过 limit');
    expect(out, items.map((i) => i * 10).toList());
  });

  test('上限大于条数时按条数并发；空列表直接返回', () async {
    var peak = 0;
    var inFlight = 0;
    final out = await mapConcurrent<int, int>([1, 2], 9, (i) async {
      inFlight++;
      if (inFlight > peak) peak = inFlight;
      await Future<void>.delayed(const Duration(milliseconds: 2));
      inFlight--;
      return i;
    });
    expect(peak, 2);
    expect(out, [1, 2]);
    expect(await mapConcurrent<int, int>([], 4, (i) async => i), isEmpty);
  });

  test('进度回调按完成数递增，最后为 (总数, 总数)', () async {
    final seen = <String>[];
    await mapConcurrent<int, int>(List<int>.generate(5, (i) => i), 2, (i) async {
      await Future<void>.delayed(Duration(milliseconds: 1 + i));
      return i;
    }, onProgress: (done, total) => seen.add('$done/$total'));
    expect(seen.length, 5);
    expect(seen.last, '5/5');
    expect(seen.first.startsWith('1/'), isTrue);
  });

  test('run 抛出的异常向上传递', () async {
    expect(
      () => mapConcurrent<int, int>([1, 2, 3], 2, (i) async {
        if (i == 2) throw StateError('boom');
        return i;
      }),
      throwsA(isA<StateError>()),
    );
  });
}
