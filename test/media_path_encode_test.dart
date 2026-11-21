// 0.9.102：文件名含 `#` / `?` 时的媒体地址转义。
//
// NAS 上的作品文件名可能带 `#`、`?`（如 `1#花絮.mp4`）。原先把相对路径直接拼进
// URL，`Uri.parse` 会把 `#` 之后当 fragment、`?` 之后当 query，请求到的就是另一个
// 路径，表现为封面 404 / 播放失败。`encodeMediaPath` 按字符做最小转义，且不重复
// 编码已存在的 `%XX`。
import 'package:flutter_test/flutter_test.dart';
import 'package:shoucangjia/main.dart';

void main() {
  group('encodeMediaPath', () {
    test('普通路径原样返回', () {
      expect(encodeMediaPath('/media/lib1/a/b.jpg'), '/media/lib1/a/b.jpg');
      expect(encodeMediaPath(''), '');
    });

    test('# 和 ? 转义成 %23 / %3F', () {
      expect(encodeMediaPath('/media/lib1/1#花絮.mp4'), '/media/lib1/1%23花絮.mp4');
      expect(encodeMediaPath('/media/lib1/a?b.jpg'), '/media/lib1/a%3Fb.jpg');
    });

    test('空格与控制字符转义', () {
      expect(encodeMediaPath('/media/lib1/a b.jpg'), '/media/lib1/a%20b.jpg');
      expect(encodeMediaPath('/media/lib1/a\tb.jpg'), '/media/lib1/a%09b.jpg');
    });

    test('已编码的 %XX 保持原样，避免二次编码', () {
      expect(encodeMediaPath('/media/lib1/a%23b.jpg'), '/media/lib1/a%23b.jpg');
      expect(encodeMediaPath('/media/lib1/%E4%B8%AD.jpg'),
          '/media/lib1/%E4%B8%AD.jpg');
    });

    test('孤立 % 转成 %25', () {
      expect(encodeMediaPath('/media/lib1/100%.jpg'), '/media/lib1/100%25.jpg');
      expect(
          encodeMediaPath('/media/lib1/ab%zz.jpg'), '/media/lib1/ab%25zz.jpg');
    });

    test('绝对 http(s) 地址原样返回', () {
      expect(encodeMediaPath('https://cdn.example.com/a#b.jpg'),
          'https://cdn.example.com/a#b.jpg');
    });
  });

  group('Cfg.media — 已带库段的路径', () {
    test('已知库段原样保留，不再套当前库（否则 /media/douyin/lib-x/... 必 404）', () {
      final c = Cfg()..lib = 'douyin';
      c.bindLibrary('lib1', 'http://10.0.0.2:8090');
      expect(c.media('/media/lib1/a/b.jpg'), '/media/lib1/a/b.jpg');
      expect(c.media('/media/lib1/a/b.jpg', lib: 'douyin'),
          '/media/lib1/a/b.jpg');
    });

    test('未知首段仍按当前库补齐（头像的 BASE 相对路径）', () {
      final c = Cfg()..lib = 'douyin';
      c.bindLibrary('douyin', 'http://10.0.0.2:8090');
      expect(c.media('/media/(14) 作者/_avatar/x.jpg'),
          '/media/douyin/(14) 作者/_avatar/x.jpg');
    });

    test('相对路径仍补当前库', () {
      final c = Cfg()..lib = 'lib1';
      c.bindLibrary('lib1', 'http://10.0.0.2:8090');
      expect(c.media('_cover/v1.jpg'), '/media/lib1/_cover/v1.jpg');
    });
  });

  group('Cfg.mediaUrl', () {
    test('带 # 的文件名生成可解析的绝对地址', () {
      final c = Cfg();
      c.bindLibrary('lib1', 'http://10.0.0.2:8090');
      final u = c.mediaUrl('/media/lib1/1#花絮.mp4', lib: 'lib1');
      final parsed = Uri.parse(u);
      expect(parsed.fragment, '');
      expect(parsed.query, '');
      expect(parsed.pathSegments.last, '1#花絮.mp4');
    });
  });
}
