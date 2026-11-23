import 'package:shoucangjia/top_node.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(TopNodeName.reset);

  group('nameFromRoot', () {
    test('取路径最后一段', () {
      expect(TopNodeName.nameFromRoot('/vol1/SECRET'), 'SECRET');
      expect(TopNodeName.nameFromRoot('/vol1/我的媒体库'), '我的媒体库');
    });

    test('忽略尾部与重复分隔符', () {
      expect(TopNodeName.nameFromRoot('/vol1/SECRET/'), 'SECRET');
      expect(TopNodeName.nameFromRoot('/vol1//SECRET///'), 'SECRET');
    });

    test('Windows 反斜杠路径取盘符后的最后一段', () {
      expect(TopNodeName.nameFromRoot(r'E:\media\SECRET'), 'SECRET');
      expect(TopNodeName.nameFromRoot('E:/media/SECRET/'), 'SECRET');
    });

    test('只剩盘符或空路径不返回名字（不猜）', () {
      expect(TopNodeName.nameFromRoot('E:'), '');
      expect(TopNodeName.nameFromRoot('   '), '');
      expect(TopNodeName.nameFromRoot(null), '');
      expect(TopNodeName.nameFromRoot('/'), '');
    });
  });

  group('setFromRoot', () {
    test('解析成功即更新并返回 true', () {
      expect(TopNodeName.setFromRoot('/vol1/AAA'), isTrue);
      expect(TopNodeName.current, 'AAA');
    });

    test('解析不出时保持上一个已知值，不清空', () {
      TopNodeName.setFromRoot('/vol1/AAA');
      expect(TopNodeName.setFromRoot(''), isFalse);
      expect(TopNodeName.current, 'AAA');
      expect(TopNodeName.setFromRoot(null), isFalse);
      expect(TopNodeName.current, 'AAA');
    });

    test('同名不重复更新', () {
      TopNodeName.setFromRoot('/vol1/AAA');
      expect(TopNodeName.setFromRoot('/other/AAA'), isFalse);
      expect(TopNodeName.current, 'AAA');
    });

    test('换一个根目录名不同的媒体库后名称随之改变', () {
      TopNodeName.setFromRoot('/vol1/AAA');
      TopNodeName.setFromRoot('/vol1/BBB');
      expect(TopNodeName.current, 'BBB');
    });
  });

  group('set / reset', () {
    test('set 忽略空值', () {
      TopNodeName.set('X');
      TopNodeName.set('  ');
      TopNodeName.set(null);
      expect(TopNodeName.current, 'X');
    });

    test('reset 回到无根信息时的兜底文案', () {
      TopNodeName.set('X');
      TopNodeName.reset();
      expect(TopNodeName.current, kFallbackTopNodeName);
    });
  });
}
