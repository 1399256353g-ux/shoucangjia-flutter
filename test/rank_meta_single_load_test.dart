import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 0.9.321 第八十五批（项 4）：
///
/// 排行榜页 `initState` 原先同时启动 `loadLibs()` 与 `load()`，两者**各自**
/// `LibMeta.load(cfg.lib)` 再各自 `metas[cfg.lib] = meta`：
///
/// ```
/// loadLibs: final meta = await LibMeta.load(cfg.lib); … metas[cfg.lib] = meta;
/// load:     final meta = await LibMeta.load(cfg.lib); … metas[cfg.lib] = meta;
/// ```
///
/// 同一个库两次 await（缓存命中时纯浪费，未命中时两次往返），两次 setState，
/// 而且「谁后 return 谁覆盖」——两次请求落在不同的 5 分钟窗口时，晚到的旧
/// 结果会顶掉先写好的新结果。现在两条路径都走唯一的 `_ensureMeta`。
String _codeNoComments(String path) => File(path)
    .readAsStringSync().replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _body(String src, String start, String end) {
  final a = src.indexOf(start);
  final b = a < 0 ? -1 : src.indexOf(end, a);
  if (a <= 0 || b <= a) throw StateError('片段定位失败：$start → $end');
  return src.substring(a, b);
}

void main() {
  final main = _codeNoComments('lib/main.dart');
  final rank = _body(main, 'class _RankPageState extends State<RankPage>',
      'class LibraryRankPage');

  test('元数据写入只有一处（_ensureMeta）', () {
    expect(rank.contains('Future<LibMeta?> _ensureMeta(String lib'),
        isTrue);
    // 页面里不得再有第二处直接赋值 metas[...]
    final writes = RegExp(r'metas\[[^\]]+\]\s*=').allMatches(rank).length;
    expect(writes, 1,
        reason: '还有 $writes 处直接写 metas，谁后 return 谁覆盖');
    expect(rank.contains('metas[lib] = meta'), isTrue);
  });

  test('本页只剩 load 一处装载，不再拉注册库列表', () {
    // 0.9.372：`loadLibs` 已整段删除——它唯一的产物是 `libs` 列表，
    // 而那个列表唯一的读取方是逐行算 `libName`（`AuthorRankTile` 从未读过
    // 该字段）。删掉之后 `initState` 只启动 `load()`，元数据仍只经
    // `_ensureMeta` 装一次。
    expect(rank.contains('loadLibs'), isFalse,
        reason: '本页没有库选择器，注册库列表是死数据');

    final load = _body(
        rank, 'Future<void> load() async {', 'void _prefetchRankAvatars()');
    expect(load.contains('LibMeta.load('), isFalse,
        reason: 'load 自己又拉了一次');
    expect(load.contains('_ensureMeta(cfg.lib)'), isTrue);
  });

  test('选中别的库仍只走同一个装载入口', () {
    final sel = _body(
        rank, 'Future<void> _loadMetaFor(String lib)', 'Future<void> load() async {');
    expect(sel.contains('_ensureMeta(lib, showLoading: true)'), isTrue);
    expect(sel.contains('LibMeta.load('), isFalse);
  });
}
