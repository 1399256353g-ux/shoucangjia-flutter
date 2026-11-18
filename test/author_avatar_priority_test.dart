import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_avatar_store.dart';

/// B3：头像优先级「手动 > 爬虫/作品自带 > 自动兜底」。
void main() {
  test('手动覆盖压过爬虫与兜底', () {
    expect(
      resolveAuthorAvatarPath(
        manual: '/lib/aaa/works/1/cover.jpg',
        crawled: '/_avatar/b.jpg',
        fallback: '/lib/aaa/works/2/cover.jpg',
      ),
      '/lib/aaa/works/1/cover.jpg',
    );
  });

  test('无手动时取爬虫结果，忽略兜底', () {
    expect(
      resolveAuthorAvatarPath(
        manual: '',
        crawled: '/_avatar/b.jpg',
        fallback: '/thumb.jpg',
      ),
      '/_avatar/b.jpg',
    );
  });

  test('只有兜底时用兜底', () {
    expect(
      resolveAuthorAvatarPath(fallback: '/thumb.jpg'),
      '/thumb.jpg',
    );
  });

  test('全空/空白返回空串，不产生脏路径', () {
    expect(resolveAuthorAvatarPath(), '');
    expect(
      resolveAuthorAvatarPath(manual: '  ', crawled: '', fallback: null),
      '',
    );
  });
}
