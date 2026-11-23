import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/work_key.dart';

void main() {
  test('workKey 带库前缀且忽略空 id', () {
    expect(workKey(lib: 'douyin', id: '123'), 'douyin/123');
    expect(workKey(lib: '', id: '123'), '123');
    expect(workKey(lib: 'douyin', id: '  '), '');
    expect(workKey(lib: '', id: ''), '');
  });

  test('workKey 去首尾空白，库不同则键不同', () {
    expect(workKey(lib: ' l1 ', id: ' a '), 'l1/a');
    expect(workKey(lib: 'l1', id: 'a'), isNot(workKey(lib: 'l2', id: 'a')));
  });
}
