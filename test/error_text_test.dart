import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/error_text.dart';

void main() {
  group('errorText：异常 → 界面上能读懂的一句话', () {
    test('剥掉 Dart 的 Exception: 前缀', () {
      // 旧文案：加载失败：Exception: HTTP 500
      expect(errorText(Exception('HTTP 500')), 'HTTP 500');
    });

    test('超时不把 Future/精度暴露给用户', () {
      final e = TimeoutExceptionStub('after 0:00:08.000000: Future not completed');
      final s = errorText(e);
      expect(s, '请求超时');
      expect(s.contains('Future'), isFalse);
      expect(s.contains('0:00:08'), isFalse);
    });

    test('网络层异常统一为连接失败', () {
      expect(errorText(Exception('SocketException: Connection refused')),
          '连接失败');
      expect(
          errorText(Exception(
              'ClientException: Connection closed before full header was received')),
          '连接失败');
    });

    test('非 JSON 响应给出可理解的原因', () {
      expect(errorText(const FormatException('Unexpected character')),
          '返回内容无法解析');
    });

    test('业务措辞原样保留（不吞服务端给的原因）', () {
      expect(errorText(Exception('该库不存在')), '该库不存在');
      expect(errorText('缺少库标识'), '缺少库标识');
    });

    test('多行错误只取第一行，不撑破单行布局', () {
      expect(errorText(Exception('第一行\n第二行\n第三行')), '第一行');
    });

    test('空值与空串退化，不留空白文案', () {
      expect(errorText(null), '未知错误');
      expect(errorText(''), '未知错误');
      expect(errorText('   '), '未知错误');
    });

    test('叠加前缀一路剥干净', () {
      expect(errorText(Exception(Exception('HTTP 404'))), 'HTTP 404');
    });
  });
}

/// 轻量替身：不依赖 dart:async 的 TimeoutException 构造细节，
/// 只复现它的 toString 形状。
class TimeoutExceptionStub implements Exception {
  TimeoutExceptionStub(this.detail);
  final String detail;
  @override
  String toString() => 'TimeoutException $detail';
}
