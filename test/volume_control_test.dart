import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/volume_control.dart';

void main() {
  group('H14 音量拖动换算', () {
    test('200px 对应 100%，向右增大、向左减小', () {
      expect(volumeFromDrag(50, 100), 100);
      expect(volumeFromDrag(50, -100), 0);
      expect(volumeFromDrag(50, 50), 75);
    });

    test('越界夹紧，宽度非法时保持原值', () {
      expect(volumeFromDrag(90, 500), 100);
      expect(volumeFromDrag(10, -500), 0);
      expect(volumeFromDrag(42, 30, width: 0), 42);
    });

    test('静音切换恢复上次音量，上次无效时满音量', () {
      expect(volumeAfterMuteToggle(nowMuted: true, current: 80, last: 80), 0);
      expect(
          volumeAfterMuteToggle(nowMuted: false, current: 0, last: 65), 65);
      expect(volumeAfterMuteToggle(nowMuted: false, current: 0, last: 0), 100);
    });

    test('图标档位', () {
      expect(volumeIconLevel(0), 'mute');
      expect(volumeIconLevel(80, muted: true), 'mute');
      expect(volumeIconLevel(30), 'down');
      expect(volumeIconLevel(80), 'up');
    });
  });
}
