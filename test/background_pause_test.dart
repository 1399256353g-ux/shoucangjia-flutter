import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/background_pause.dart';

void main() {
  group('shouldPauseInBackground', () {
    test('移动端 inactive 即暂停（来电/通知中心）', () {
      expect(
          shouldPauseInBackground(state: 'inactive', isMobile: true), isTrue);
    });

    test('桌面端失去焦点不暂停，最小化/隐藏才暂停', () {
      expect(
          shouldPauseInBackground(state: 'inactive', isMobile: false), isFalse);
      for (final s in ['hidden', 'paused', 'detached']) {
        expect(shouldPauseInBackground(state: s, isMobile: false), isTrue);
      }
    });

    test('前台不暂停，未知状态不暂停', () {
      expect(
          shouldPauseInBackground(state: 'resumed', isMobile: true), isFalse);
      expect(
          shouldPauseInBackground(state: 'unknown', isMobile: true), isFalse);
    });
  });

  group('shouldResumeFromBackground', () {
    test('后台自动暂停后回前台恢复', () {
      expect(
          shouldResumeFromBackground(
              pausedByBackground: true, userPaused: false),
          isTrue);
    });

    test('用户手动暂停或非后台暂停都不自动恢复', () {
      expect(
          shouldResumeFromBackground(
              pausedByBackground: true, userPaused: true),
          isFalse);
      expect(
          shouldResumeFromBackground(
              pausedByBackground: false, userPaused: false),
          isFalse);
    });
  });
}
