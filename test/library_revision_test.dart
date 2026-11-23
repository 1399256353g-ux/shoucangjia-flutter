import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/library_revision.dart';

void main() {
  group('LibDataRevision', () {
    test('初始为 0，bump 后自增', () {
      expect(LibDataRevision.revisionOf('lib-r1'), 0);
      LibDataRevision.bump('lib-r1');
      expect(LibDataRevision.revisionOf('lib-r1'), 1);
      LibDataRevision.bump('lib-r1');
      expect(LibDataRevision.revisionOf('lib-r1'), 2);
    });

    test('按库隔离：刷 A 不影响 B', () {
      LibDataRevision.bump('lib-r2');
      expect(LibDataRevision.revisionOf('lib-r2'), 1);
      expect(LibDataRevision.revisionOf('lib-r3'), 0);
    });

    test('空 id 不广播（避免全局抖动）', () {
      LibDataRevision.bump('');
      LibDataRevision.bump('   ');
      expect(LibDataRevision.revisionOf(''), 0);
      expect(LibDataRevision.revisionOf('   '), 0);
    });

    test('listenable 与 bump 同源：监听者能收到新值', () {
      var hits = 0;
      final l = LibDataRevision.listenable('lib-r4');
      void fn() => hits++;
      l.addListener(fn);
      LibDataRevision.bump('lib-r4');
      expect(hits, 1);
      expect(LibDataRevision.revisionOf('lib-r4'), 1);
      l.removeListener(fn);
      LibDataRevision.bump('lib-r4');
      expect(hits, 1);
    });
  });
}
