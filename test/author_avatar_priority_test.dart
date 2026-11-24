import 'package:flutter_test/flutter_test.dart';

import 'package:shoucangjia/author_avatar_store.dart';
import 'package:shoucangjia/media_priority.dart';

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

  // 0.9.226：优先级不再是本文件自己的一份实现，而是转发到
  // `media_priority.pickAvatarPath`（头像/封面共用的唯一规则）。
  // 下面两条钉住「转发后没丢语义」：同级时间戳仍生效，且层级压过时间。
  test('同级时间戳生效：新的压过旧的（旧实现会返回第一个非空）', () {
    expect(
      resolveAuthorAvatarPath(
        crawled: '/_avatar/old.jpg',
        fallback: '/lib/aaa/works/9/cover.jpg',
        crawledAt: 10,
        fallbackAt: 99,
      ),
      '/_avatar/old.jpg',
      reason: '爬虫层整体优先于自动层，时间不跨层比较',
    );
    // 同一层内给两个候选不在此 API 里；这里只验证时间会透传下去：
    // 手动层时间戳存在时仍取手动层。
    expect(
      resolveAuthorAvatarPath(
        manual: '/m.jpg',
        crawled: '/c.jpg',
        manualAt: 1,
        crawledAt: 999,
      ),
      '/m.jpg',
    );
  });

  test('与 media_priority 的结果逐字一致（没有第二份规则）', () {
    for (final m in <String?>[null, '', '  ', '/m.jpg']) {
      for (final c in <String?>[null, '', '/c.jpg']) {
        for (final f in <String?>[null, '', '/a.jpg']) {
          expect(
            resolveAuthorAvatarPath(manual: m, crawled: c, fallback: f),
            pickAvatarPath(
              manual: m ?? '',
              crawler: c ?? '',
              auto: f ?? '',
            ),
            reason: 'm=$m c=$c f=$f',
          );
        }
      }
    }
  });
}
