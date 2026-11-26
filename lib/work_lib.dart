/// 作品条目的「来源库」读写（**唯一实现**）。
///
/// 跨库列表（收藏夹 / 搜索 / 推荐 / 作者合并）会给每条作品挂一个 `_lib`
/// 字段，标明它来自哪个基础库。这个字段的**读取**在 `main` 与 `author_merge`
/// 里此前有六种写法：
///
/// ```
/// main._PlayerPageState._libFor    w['_lib'] ?? widget.lib ?? cfg.lib
/// main.WorkGrid._libFor            w['_lib'] ?? widget.lib ?? cfg.lib   ← 逐字符相同
/// main._AuthorGridPage._libOfWork  w['_lib'] ?? primaryLib
/// author_merge.worksOfLib          w['_lib'] ?? fallbackLib（各自 trim）
/// author_merge.libFilterOptions    w['_lib'] ?? fallbackLib（各自 trim）
/// 若干「只取原值、不要兜底」处        w['_lib'] ?? ''
/// ```
///
/// 两件事必须分开：
///
///  - **取原值**（[workLibTag]）：用来分组、拼去重键、判断「这条有没有来源」。
///    不能兜底——兜底之后「跨库列表里没标来源的条目」会被当成当前库，
///    与真正来自当前库的条目合并成一组。
///  - **取请求库**（[workLibOf]）：用来取鉴权头、拼媒体地址。必须兜底，
///    否则空库 id 会走成「不带 Authorization」→ 401 白图。
///
/// 两件事此前混在同一个表达式里，于是同一行代码既做判定又做兜底：改一处
/// 判定就会连带改坏请求头。现在分成两个名字，调用点自己选语义。
library;

/// 作品的来源库标记（**原值**，不兜底）。没有标记返回空串。
String workLibTag(dynamic work) {
  if (work is! Map) return '';
  return '${work['_lib'] ?? ''}'.trim();
}

/// 作品实际要用的库 id：有标记用标记，否则用 [fallback]（常为当前库）。
///
/// [fallback] 为空时返回空串——那表示「不知道属于哪个库」，调用方应自行
/// 决定是跳过还是按无鉴权处理，**不要**在这里替它猜一个库。
String workLibOf(dynamic work, {String fallback = ''}) {
  final tag = workLibTag(work);
  if (tag.isNotEmpty) return tag;
  return fallback.trim();
}

/// 给作品条目挂上来源库标记（返回新 Map，不改入参）。
///
/// 写入侧此前在 `main` 里写了五遍 `{...Map<String, dynamic>.from(w),
/// '_lib': lib}`：四处一致，一处（作者合并的 auMap）在 `ls` 为空时兜到
/// `cfg.lib`——同一份数据在两条入口上有两种「没有来源」的表示。
Map<String, dynamic> withWorkLib(Map work, String lib) => {
      ...Map<String, dynamic>.from(work),
      '_lib': lib.trim(),
    };
