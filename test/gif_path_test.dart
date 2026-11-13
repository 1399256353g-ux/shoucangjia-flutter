import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/main.dart' as app;

void main() {
  test('GIF 路径识别（含大小写与查询串）', () {
    expect(app.isGifPath('/media/lib/PIC/a_01.gif'), isTrue);
    expect(app.isGifPath('/media/lib/PIC/a_01.GIF'), isTrue);
    expect(app.isGifPath('/media/lib/PIC/a_01.gif?x=1'), isTrue);
    expect(app.isGifPath('/media/lib/PIC/a_01.webp'), isFalse);
    expect(app.isGifPath('/media/lib/PIC/a_01.jpg'), isFalse);
    expect(app.isGifPath('/media/lib/PIC/agif_01.png'), isFalse);
    expect(app.isGifPath('/media/lib/VID/a.mp4'), isFalse);
  });
}
