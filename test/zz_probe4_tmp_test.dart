import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/home_top_bar.dart';
import 'package:shoucangjia/taskbar_layout.dart';
import 'package:shoucangjia/text_fold.dart';
import 'package:shoucangjia/breadcrumb.dart';
import 'package:shoucangjia/preload_pool.dart';
import 'package:shoucangjia/decode_plan.dart';
import 'package:shoucangjia/media_priority.dart';
import 'package:shoucangjia/work_safety.dart';

void main() {
  test('probe4', () {
    print('--- topbar ---');
    for (final w in [double.nan, double.infinity, 0.0, 100.0, 400.0]) {
      try {
        final l = topBarLayout([TopBarAction.open], [], width: w);
        print('w=$w -> ${l.visible.length}/${l.overflow.length}');
      } catch (e) { print('w=$w THROW $e'); }
    }
    print('--- fold ---');
    print('[${foldFullWidthAscii('（１）ＡＢ：／　')}]');
    print('--- breadcrumb tail ---');
    print('--- preload pool ---');
  });
}
