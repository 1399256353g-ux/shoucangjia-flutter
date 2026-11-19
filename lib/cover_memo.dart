// 0.9.53：单元库封面解析的记忆化。
//
// 背景：`_unitCoverUrl` 每次重建都要走完整封面链（手动 `cover.u` → `_cover/`
// 版本 → 子树最高播放基础库 → 子树第一个有封面的基础库），最后一步是
// 对 `unit.allBasics` 的线性扫描，每个基础库还要再查一次封面与播放记录。
// 主页/单元库页/星标页在滚动时每帧都可能重建这些卡片，重复计算完全是浪费。
//
// 规则：
//  - 键由调用方拼好（单元库 id + 影响结果的信号，如封面版本/播放修订号/服务地址）；
//  - 命中直接返回，未命中计算并存入；
//  - 条目超过 [maxEntries] 时淘汰最久未使用的一条（LRU），
//    不再整体清空——整体清空会让翻页/滚动时刚算好的封面全部重算；
//    FIFO 会让常驻首屏的少数单元库被持续写入的新键挤出、每帧重算，
//    命中即视为「最近使用」，故改为 LRU（0.9.103）；
//  - 只缓存字符串（封面 URL 或空串），不持有任何 widget/字符串以外的对象。
class CoverMemo {
  CoverMemo({this.maxEntries = 512});

  /// 条目上限；超出时按使用顺序淘汰最久未用的一条（LRU）。
  final int maxEntries;

  final Map<String, String> _cache = <String, String>{};

  /// 已缓存条目数（供诊断/测试）。
  int get size => _cache.length;

  /// 命中次数（供诊断）。
  int get hits => _hits;
  int _hits = 0;

  /// 未命中次数（供诊断）。
  int get misses => _misses;
  int _misses = 0;

  /// 因超出上限被淘汰的条目数（供诊断/测试）。
  int get evictions => _evictions;
  int _evictions = 0;

  /// 取缓存；未命中时调用 [compute] 并记住结果（含空串）。
  String resolve(String key, String Function() compute) {
    // 命中即更新「最近使用」：先摘下再放回末尾（Map 保持插入顺序）。
    final cached = _cache.remove(key);
    if (cached != null) {
      _hits++;
      _cache[key] = cached;
      return cached;
    }
    _misses++;
    final value = compute();
    // 只淘汰最旧一条：清空整表会让刚用过的键全部失效，滚动时反复重算。
    while (_cache.length >= maxEntries && _cache.isNotEmpty) {
      _cache.remove(_cache.keys.first); // 表头 = 最久未使用
      _evictions++;
    }
    _cache[key] = value;
    return value;
  }

  /// 清空（封面被手动设置/清除、换连接等需要立即生效时调用）。
  void clear() {
    _cache.clear();
    _hits = 0;
    _misses = 0;
    _evictions = 0;
  }
}
