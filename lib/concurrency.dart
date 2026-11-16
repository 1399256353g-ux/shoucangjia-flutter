// 有界并发（性能优化 · 0.9.23）。
//
// 背景：搜索页要扫全部 39 个基础库的 works.json，原来是串行 await，
// 每个库一次（甚至多次分页）往返，整页要等好几秒。改成有界并发后
// 局域网下基本一次往返的时间就能取完；并发上限避免把 NAS 打满。
//
// 约定：
//  - 结果顺序与输入一致（与 Future.wait 相同，但可控并发）；
//  - `run` 抛出的异常会向上抛，调用方自己决定是否吞掉（搜索页按库兜底）；
//  - `onProgress` 每完成一个调用一次，参数为 (已完成, 总数)。
library;

Future<List<T>> mapConcurrent<S, T>(
  List<S> items,
  int limit,
  Future<T> Function(S item) run, {
  void Function(int done, int total)? onProgress,
}) async {
  if (items.isEmpty) return <T>[];
  final total = items.length;
  final width = limit < 1 ? 1 : (limit > total ? total : limit);
  final results = List<T?>.filled(total, null);
  var next = 0;
  var done = 0;

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= total) return;
      results[i] = await run(items[i]);
      done++;
      onProgress?.call(done, total);
    }
  }

  final workers = <Future<void>>[];
  for (var i = 0; i < width; i++) {
    workers.add(worker());
  }
  await Future.wait(workers);
  return results.cast<T>();
}
