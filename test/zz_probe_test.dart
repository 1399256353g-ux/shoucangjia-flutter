import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/byte_size.dart';
import 'package:shoucangjia/deleted_monitor.dart';
import 'package:shoucangjia/watch_progress.dart';
import 'package:shoucangjia/collection_sync.dart';
import 'package:shoucangjia/library_refresh.dart';
import 'package:shoucangjia/sync_ledger.dart';

void p(String label, Object? v) => print('PROBE $label => $v');

void main() {
  test('probe10', () {
    // 字节边界：每一档都用「该档上限 + 1」
    for (final b in [1023, 1024, 1048575, 1048576, 1073741823, 1073741824, 1099511627775, 1099511627776]) {
      p('bytes $b', formatBytes(b));
    }
    p('watch fraction dur0', WatchProgress(positionMs: 5, durationMs: 0, done: false, updatedAt: 1).fraction);
    p('watch fraction pos>dur', WatchProgress(positionMs: 99, durationMs: 10, done: false, updatedAt: 1).fraction);
    p('watchedDone pos inf', watchedDone(positionMs: 9223372036854775807, durationMs: 100));
    p('resumeMs huge', resumeMs(WatchProgress(positionMs: 9223372036854775807, durationMs: 9223372036854775807, done: false, updatedAt: 1)));
  });
}
