/// A1：单元库「作者文件夹挂载」的协议与规则层（纯逻辑，无 UI、无网络）。
///
/// 背景（owner 2026-11-24）：「这么好的作者文件夹挂载机制你是一点没改啊」——
/// 服务端已经有分组能力，客户端此前一个入口都没有。
///
/// 服务端契约（`gallery_server.js` 的 `/api/unit-author-groups.json`
/// 与 `/api/unit/authors.json`）：
///
/// | 方法 | 请求 | 响应 |
/// |---|---|---|
/// | GET | `?unit=<单元库id>` | `{ok, unit, groups:[…], auto:[…]}` |
/// | POST | `{unit, action, …}` | `{ok, unit, groupId?}` |
///
/// 组的形状：`{id, name, files:[{lib, authorDir}], split}`；
/// `auto:true` 的组是服务端按「同单元库内同名作者」现算的派生组，**不落盘**。
///
/// 本文件只做三件可单测的事：
///  1. 把响应解析成不可变的模型（坏数据一律按空处理，不抛异常）；
///  2. 生成四种操作的请求体（`merge` / `split` / `setFiles` / `delete`）；
///  3. 在发请求**之前**就按服务端同一套规则挡下必然 400 的请求。
///
/// 第 3 点是刻意重复一次服务端校验：不是「不信任服务端」，而是让面板能
/// 立刻把「至少要挂载 1 个」这种错误显示在按钮旁边，而不是等一次往返。
/// 服务端仍是唯一权威——它挡下的请求客户端也必须挡下，反之不成立
/// （客户端只挡确定性错误，避免两边规则漂移后误拦合法请求）。
library;

import 'api_url.dart';
import 'count_label.dart';
import 'json_num.dart';
import 'label_fallback.dart';

/// 一个被挂载的作者文件夹：基础库 id + 库内作者目录名。
class AuthorGroupFile {
  final String lib;
  final String authorDir;

  const AuthorGroupFile({required this.lib, required this.authorDir});

  /// 解析容错：两段都必须非空，否则视为无效成员（返回 null）。
  static AuthorGroupFile? fromJson(Object? v) {
    if (v is! Map) return null;
    final lib = '${v['lib'] ?? ''}'.trim();
    final dir = '${v['authorDir'] ?? ''}'.trim();
    if (lib.isEmpty || dir.isEmpty) return null;
    return AuthorGroupFile(lib: lib, authorDir: dir);
  }

  Map<String, dynamic> toJson() =>
      <String, dynamic>{'lib': lib, 'authorDir': authorDir};

  /// 成员身份键：服务端 `sanitizeGroupFiles` 的去重与「不能整组拆走」都用它。
  String get key => '$lib|$authorDir';

  @override
  bool operator ==(Object other) =>
      other is AuthorGroupFile &&
      other.lib == lib &&
      other.authorDir == authorDir;

  @override
  int get hashCode => Object.hash(lib, authorDir);
}

/// 一个作者组（手动组或服务端派生组）。
class UnitAuthorGroup {
  final String id;
  final String name;

  /// 组内出现的所有作者名（服务端 `names`，可能比 [name] 多）。
  final List<String> names;
  final List<AuthorGroupFile> files;

  /// 用户显式拆过：拆出来的组永远不会再被自动合并（服务端 `split`）。
  final bool split;

  /// 服务端按同名作者现算的派生组（不落盘，删除请求对它无意义）。
  final bool auto;

  /// 合并后的作品数与封面/简介（服务端已聚合，客户端只显示）。
  final int works;
  final String avatar;
  final String bio;

  const UnitAuthorGroup({
    required this.id,
    required this.name,
    this.names = const <String>[],
    this.files = const <AuthorGroupFile>[],
    this.split = false,
    this.auto = false,
    this.works = 0,
    this.avatar = '',
    this.bio = '',
  });

  /// 至少两个成员才算「合并」；单成员组只是普通作者，不需要特殊显示。
  bool get isMerge => files.length >= 2;

  /// 面板副标题。必须与 [unitAuthorCardSummary] 走同一个出口：此前面板手写
  /// `N 个文件夹 · M 作品` 再把「已拆」单独渲染成小标签，而摘要函数里写的是
  /// 「已拆分」，同一条事实两套文案。
  String get summary => authorMergeSummary(
        fileCount: files.length,
        works: works,
        merged: isMerge,
        split: split,
        auto: auto,
        names: names.length,
      );

  static UnitAuthorGroup? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = '${v['id'] ?? ''}'.trim();
    if (id.isEmpty) return null;
    final files = <AuthorGroupFile>[];
    final rawFiles = v['files'];
    if (rawFiles is List) {
      for (final f in rawFiles) {
        final o = AuthorGroupFile.fromJson(f);
        if (o != null) files.add(o);
      }
    }
    final names = <String>[];
    final rawNames = v['names'];
    if (rawNames is List) {
      for (final n in rawNames) {
        final s = '$n'.trim();
        if (s.isNotEmpty) names.add(s);
      }
    }
    return UnitAuthorGroup(
      id: id,
      name: '${v['name'] ?? ''}'.trim(),
      names: names,
      files: files,
      split: boolOf(v['split']),
      auto: boolOf(v['auto']),
      works: intOf(v['works']),
      avatar: '${v['av'] ?? ''}'.trim(),
      bio: '${v['bio'] ?? ''}'.trim(),
    );
  }
}

/// 一次 GET 的完整结果：手动组 + 派生组。
class UnitAuthorGroupsState {
  final String unit;
  final List<UnitAuthorGroup> groups;
  final List<UnitAuthorGroup> auto;

  const UnitAuthorGroupsState({
    this.unit = '',
    this.groups = const <UnitAuthorGroup>[],
    this.auto = const <UnitAuthorGroup>[],
  });

  bool get isEmpty => groups.isEmpty && auto.isEmpty;

  /// 手动组里已经被占用的成员键：派生组展示时要排除它们，否则同一作者
  /// 会在「已合并」与「自动可合并」两处各出现一次。
  Set<String> get claimedKeys => <String>{
        for (final g in groups)
          for (final f in g.files) f.key,
      };

  static UnitAuthorGroupsState fromJson(Object? json) {
    if (json is! Map) return const UnitAuthorGroupsState();
    List<UnitAuthorGroup> list(Object? raw) {
      final out = <UnitAuthorGroup>[];
      if (raw is List) {
        for (final g in raw) {
          final o = UnitAuthorGroup.fromJson(g);
          if (o != null) out.add(o);
        }
      }
      return out;
    }

    return UnitAuthorGroupsState(
      unit: '${json['unit'] ?? ''}'.trim(),
      groups: list(json['groups']),
      auto: list(json['auto']),
    );
  }
}

/// 四种写操作（与服务端 `body.action` 一一对应，名称不可改）。
enum UnitAuthorAction {
  merge('merge'),
  split('split'),
  setFiles('setFiles'),
  delete('delete');

  const UnitAuthorAction(this.wire);

  /// 服务端字符串；改这里等于改协议。
  final String wire;
}

/// 一次写请求。
class UnitAuthorRequest {
  final String unit;
  final UnitAuthorAction action;

  /// `split` / `setFiles` / `delete` 必填。
  final String groupId;

  /// `merge` 时可给新组取名（留空则按第一个成员名显示）。
  final String name;

  /// `merge` / `split` / `setFiles` 的成员列表。
  final List<AuthorGroupFile> files;

  /// `split` 时的原组成员（判定「不能把整组都拆走」要用）。
  ///
  /// 只在 `split` 有意义；`merge` / `setFiles` / `delete` 传空即可。
  final List<AuthorGroupFile> groupFiles;

  const UnitAuthorRequest({
    required this.unit,
    required this.action,
    this.groupId = '',
    this.name = '',
    this.files = const <AuthorGroupFile>[],
    this.groupFiles = const <AuthorGroupFile>[],
  });

  Map<String, dynamic> toBody() {
    final out = <String, dynamic>{'unit': unit, 'action': action.wire};
    if (groupId.trim().isNotEmpty) out['groupId'] = groupId.trim();
    if (name.trim().isNotEmpty) out['name'] = name.trim();
    if (action != UnitAuthorAction.delete && files.isNotEmpty) {
      out['files'] = [for (final f in files) f.toJson()];
    }
    return out;
  }

  /// 客户端可判定的非法请求（其余交给服务端）。
  ///
  /// [groupFiles] 是 `split` 的原组成员。此前这里写死 `null`，于是
  /// 「不能把整组都拆走」这条**在请求对象上永远不生效**——挂载页只能绕过
  /// 它、直接调 [unitAuthorRequestError] 并另传 `groupFiles`。同一个校验
  /// 两个入口，其中一个静默放行了服务端必然 400 的请求（整组拆走＝解散，
  /// 那是 delete 的语义）。现在把原组成员挂到请求上，`error` 就是唯一入口。
  String? get error => unitAuthorRequestError(
        action: action,
        unit: unit,
        groupId: groupId,
        files: files,
        groupFiles: groupFiles,
      );
}

/// 与服务端同一套规则的前置校验；合法返回 null，非法返回中文原因。
///
/// [groupFiles] 只在 [UnitAuthorAction.split] 时有意义：判定「不能把整组都
/// 拆走」必须知道原组还剩什么。传 null 时跳过这一条（GET 前还不知道原组）。
String? unitAuthorRequestError({
  required UnitAuthorAction action,
  required String unit,
  String groupId = '',
  List<AuthorGroupFile> files = const <AuthorGroupFile>[],
  List<AuthorGroupFile>? groupFiles,
}) {
  if (unit.trim().isEmpty) return '缺少单元库';
  // 成员去重后再判数量：客户端很容易因为重复点击把同一个文件夹点两次，
  // 服务端 sanitizeGroupFiles 会去重，这里先按同一口径算，免得两边结论不同。
  final seen = <String>{};
  final uniq = <AuthorGroupFile>[];
  for (final f in files) {
    if (f.lib.trim().isEmpty || f.authorDir.trim().isEmpty) continue;
    if (seen.add(f.key)) uniq.add(f);
  }

  switch (action) {
    case UnitAuthorAction.merge:
      if (uniq.length < 1) return '至少要挂载 1 个作者文件夹';
      return null;
    case UnitAuthorAction.setFiles:
      if (groupId.trim().isEmpty) return '缺少组 id';
      if (uniq.length < 1) return '至少要挂载 1 个作者文件夹';
      return null;
    case UnitAuthorAction.delete:
      if (groupId.trim().isEmpty) return '缺少组 id';
      return null;
    case UnitAuthorAction.split:
      if (groupId.trim().isEmpty) return '缺少组 id';
      if (uniq.length < 1) return '拆出项不能为空';
      if (groupFiles != null) {
        final keep = <String>{for (final f in uniq) f.key};
        final rest = groupFiles.where((f) => !keep.contains(f.key)).length;
        // 服务端：rest.length === 0 → 400「不能把整组都拆走」。
        // 拆走全部等于「解散组」，那是 delete 的语义，不是 split。
        if (groupFiles.isNotEmpty && rest == 0) return '不能把整组都拆走（用删除解散）';
      }
      return null;
  }
}

/// GET / POST 地址；`unit` 作为查询参数（与其它 `/api/unit/*` 同一写法）。
String unitAuthorGroupsUrl(String base, String unit) =>
    joinApiUrl(base, '/api/unit-author-groups.json',
        query: unit.trim().isEmpty ? null : {'unit': unit.trim()});

/// 作者卡片列表地址（`/api/unit/authors.json?unit=`）。
String unitAuthorsUrl(String base, String unit) => joinApiUrl(
      base,
      '/api/unit/authors.json',
      query: unit.trim().isEmpty ? null : {'unit': unit.trim()},
    );

/// 新建作者目录地址（`POST /api/unit/authors/create`）。
String unitAuthorCreateUrl(String base) =>
    joinApiUrl(base, '/api/unit/authors/create');

/// 作者目录名规则（与服务端 `authorDirNameOf` 同一口径）：
/// `name_raw` 非空用它，否则 `"@" + name`。
String authorDirForName(String name, {String nameRaw = ''}) {
  final raw = nameRaw.trim();
  if (raw.isNotEmpty) return raw;
  final n = name.trim();
  return n.isEmpty ? '' : '@$n';
}

/// 作者目录名是否合法（服务端 `sanitizeAuthorDir` 的客户端镜像）。
///
/// 服务端规则：非空、不含 `/` `\`、不含 `..`、不是 `.`、不含 `:*?"<>|`、
/// 长度 ≤200，且**必须以 `@` 开头**（这是作者目录与普通目录的区分标记）。
String? authorDirError(String dir) {
  final d = dir.trim();
  if (d.isEmpty) return '作者目录不能为空';
  if (d.length > 200) return '作者目录过长';
  if (d.contains('/') || d.contains('\\')) return '作者目录不能包含路径分隔符';
  if (d.contains('..')) return '作者目录不能包含 ..';
  if (d == '.') return '作者目录名非法';
  if (RegExp(r'[:*?"<>|]').hasMatch(d)) return '作者目录不能包含 : * ? " < > |';
  if (!d.startsWith('@')) return '作者目录必须以 @ 开头';
  return null;
}

/// `/api/unit/authors.json` 的一张作者卡。
///
/// 与 [UnitAuthorGroup] 的区别：这张表里**同时**包含已合并组（`groupId` 非空）
/// 与还没进组的单个作者（`groupId` 为空、`files` 只有一项）。
/// 面板要在一个列表里勾选「谁跟谁合并」，所以必须保留单项。
class UnitAuthorCard {
  /// 已合并组的 id；空串表示这是一个还没进组的独立作者。
  final String groupId;
  final String name;
  final List<String> names;
  final List<AuthorGroupFile> files;
  final int works;
  final String avatar;
  final String bio;
  final bool split;
  final bool auto;

  const UnitAuthorCard({
    this.groupId = '',
    required this.name,
    this.names = const <String>[],
    this.files = const <AuthorGroupFile>[],
    this.works = 0,
    this.avatar = '',
    this.bio = '',
    this.split = false,
    this.auto = false,
  });

  /// 是否已经是一个多成员合并组。
  bool get merged => files.length >= 2;

  static UnitAuthorCard? fromJson(Object? v) {
    if (v is! Map) return null;
    final files = <AuthorGroupFile>[];
    final rawFiles = v['files'];
    if (rawFiles is List) {
      for (final f in rawFiles) {
        final o = AuthorGroupFile.fromJson(f);
        if (o != null) files.add(o);
      }
    }
    final names = <String>[];
    final rawNames = v['names'];
    if (rawNames is List) {
      for (final n in rawNames) {
        final s = '$n'.trim();
        if (s.isNotEmpty) names.add(s);
      }
    }
    final name = '${v['name'] ?? ''}'.trim();
    // 没有名字也没有成员的文件不能成为一张卡（否则面板里会出现空行）。
    if (name.isEmpty && files.isEmpty) return null;
    return UnitAuthorCard(
      groupId: '${v['groupId'] ?? ''}'.trim(),
      name: name,
      names: names,
      files: files,
      works: intOf(v['works']),
      avatar: '${v['av'] ?? ''}'.trim(),
      bio: '${v['bio'] ?? ''}'.trim(),
      split: boolOf(v['split']),
      auto: boolOf(v['auto']),
    );
  }
}

/// `/api/unit/authors.json` 的完整响应。
class UnitAuthorCards {
  final String unit;
  final List<UnitAuthorCard> cards;

  const UnitAuthorCards({
    this.unit = '',
    this.cards = const <UnitAuthorCard>[],
  });

  static UnitAuthorCards fromJson(Object? json) {
    if (json is! Map) return const UnitAuthorCards();
    final cards = <UnitAuthorCard>[];
    final raw = json['cards'];
    if (raw is List) {
      for (final c in raw) {
        final o = UnitAuthorCard.fromJson(c);
        if (o != null) cards.add(o);
      }
    }
    return UnitAuthorCards(
      unit: '${json['unit'] ?? ''}'.trim(),
      cards: cards,
    );
  }
}

/// 组/作者卡副标题的**唯一**拼装口。
///
/// 只拼结构信息（成员数、作者名个数、作品数、标记），不含任何作者名/路径——
/// 面板显示名字是 owner 自己要看的，但本函数不把名字拼进文案。
///
/// 为什么要有这一个函数：`unitAuthorCardSummary` 曾经只在测试里被断言，
/// 而面板真实路径自己内联了一份 `N 个文件夹 · M 作品` 并把「已拆」单独画成
/// 标签——断言绿、产品里跑的是另一份，正是本项目反复踩的「替身」模式。
String authorMergeSummary({
  required int fileCount,
  required int works,
  required bool merged,
  required bool split,
  required bool auto,
  int names = 0,
}) {
  final parts = <String>[];
  parts.add(merged ? '合并 $fileCount 个文件夹' : '$fileCount 个文件夹');
  // 合并组可能由多个不同名的作者目录组成，`names` 比成员数更能说明"并了几个作者"。
  if (names > 1) parts.add('含 $names 个作者名');
  if (works > 0) parts.add('${formatCount(works)} 作品');
  if (split) parts.add('已拆分');
  if (auto) parts.add('自动');
  return parts.join(' · ');
}

/// 一张作者卡的副标题（转发到 [authorMergeSummary]，保持单一出口）。
String unitAuthorCardSummary(UnitAuthorCard c) => authorMergeSummary(
      fileCount: c.files.length,
      works: c.works,
      merged: c.merged,
      split: c.split,
      auto: c.auto,
      names: c.names.length,
    );

// ── 作者主页的挂载视图（owner 2026-11-25）─────────────────────────────
//
// owner：「这套机制怎么想挂载入口也应该在作者主页吧，单元库点进去再选哪个
// 作者吗？搞笑」。挂载是**作者维度**的操作：打开某个作者，才该看到这个作者
// 存在于哪些基础库/文件夹、是否已被合并。
//
// 服务端 `GET /api/author/mounts?name=` 返回：
//   items  [{lib, libName, authorDir, works, av, unitRel}]
//   groups [{unit, groupId, files:[{lib,authorDir}], split}]

/// 作者在某一个基础库里的一个作者目录。
class AuthorMountItem {
  final String lib;
  final String libName;
  final String authorDir;
  final int works;
  final String avatar;

  /// 该基础库所属的单元库 rel；空串表示没归属（不参与自动合并）。
  final String unitRel;

  const AuthorMountItem({
    required this.lib,
    this.libName = '',
    required this.authorDir,
    this.works = 0,
    this.avatar = '',
    this.unitRel = '',
  });

  static AuthorMountItem? fromJson(Object? v) {
    if (v is! Map) return null;
    final lib = '${v['lib'] ?? ''}'.trim();
    final dir = '${v['authorDir'] ?? ''}'.trim();
    if (lib.isEmpty || dir.isEmpty) return null;
    return AuthorMountItem(
      lib: lib,
      libName: '${v['libName'] ?? ''}'.trim(),
      authorDir: dir,
      works: intOf(v['works']),
      avatar: '${v['av'] ?? ''}'.trim(),
      unitRel: '${v['unitRel'] ?? ''}'.trim(),
    );
  }

  /// 列表行里这个库叫什么。
  ///
  /// 0.9.352：此前是裸 `isEmpty`——名字是纯空格时把一个空串写到行首
  /// （看起来像「这行没有库名」），而两个挂载面板用的是 `trim().isEmpty`
  /// 回落 id。同一个库在列表里会一个有名一个消失。
  String get displayLib => libLabelOf(lib, libName);
}

/// 该作者所在的某个手动组（用于判断是否已被手动合并/拆分）。
class AuthorMountGroup {
  final String unit;
  final String groupId;
  final List<AuthorGroupFile> files;
  final bool split;

  const AuthorMountGroup({
    required this.unit,
    required this.groupId,
    this.files = const <AuthorGroupFile>[],
    this.split = false,
  });

  static AuthorMountGroup? fromJson(Object? v) {
    if (v is! Map) return null;
    final unit = '${v['unit'] ?? ''}'.trim();
    final gid = '${v['groupId'] ?? ''}'.trim();
    if (gid.isEmpty) return null;
    final files = <AuthorGroupFile>[];
    final raw = v['files'];
    if (raw is List) {
      for (final f in raw) {
        final o = AuthorGroupFile.fromJson(f);
        if (o != null) files.add(o);
      }
    }
    return AuthorMountGroup(
        unit: unit, groupId: gid, files: files, split: boolOf(v['split']));
  }
}

/// 一个作者的完整挂载情况。
class AuthorMounts {
  final String name;
  final List<AuthorMountItem> items;
  final List<AuthorMountGroup> groups;

  const AuthorMounts({
    this.name = '',
    this.items = const <AuthorMountItem>[],
    this.groups = const <AuthorMountGroup>[],
  });

  static const empty = AuthorMounts();

  static AuthorMounts fromJson(Object? v) {
    if (v is! Map) return empty;
    final items = <AuthorMountItem>[];
    final raw = v['items'];
    if (raw is List) {
      for (final e in raw) {
        final o = AuthorMountItem.fromJson(e);
        if (o != null) items.add(o);
      }
    }
    final groups = <AuthorMountGroup>[];
    final rawG = v['groups'];
    if (rawG is List) {
      for (final e in rawG) {
        final o = AuthorMountGroup.fromJson(e);
        if (o != null) groups.add(o);
      }
    }
    return AuthorMounts(
        name: '${v['name'] ?? ''}'.trim(), items: items, groups: groups);
  }

  /// 该作者一共出现在几个基础库。
  int get libCount => items.map((e) => e.lib).toSet().length;

  /// 该作者一共出现在几个文件夹（同一个库里可能有多个目录）。
  int get dirCount => items.length;

  /// 需要展示「多库/多文件夹」信息：至少两处才有意义。
  bool get isMulti => items.length >= 2;

  /// 该作者所在的单元库（**已按祖先关系折叠**，按出现顺序）。
  ///
  /// owner 2026-11-26：「明明一个都没有跨，还显示跨了 2 个」。
  ///
  /// 实测确认的根因：作者的文件分别落在 `A` 与 `A/B` 时（B 是 A 的下级），
  /// 旧实现把两者当成 2 个单元库 → 显示「跨 2 个单元库」，可他一步都没走出 A。
  ///
  /// 计数规则（这里定死，界面文案必须与它一致）：
  /// 把 rel 按段比较，**祖先被后代覆盖**——若 X 是 Y 的前缀，只算 Y。
  /// 折叠后剩几个，就是「跨了几个单元库」：
  ///  - `A` + `A/B`            → 1 个（都在 A 里）
  ///  - `A/B` + `A/C`          → 2 个（A 下面两个不同单元库）
  ///  - `A/B` + `X/Y`          → 2 个（分属两棵子树）
  ///
  /// 不再用「先去重再数」——那正是把父子当成两处的原因。
  List<String> get units {
    final raw = <String>[];
    for (final i in items) {
      final u = i.unitRel.trim();
      if (u.isEmpty || raw.contains(u)) continue;
      raw.add(u);
    }
    if (raw.length <= 1) return raw;
    // 段级前缀判定：用 `/` 边界，避免 `A/B` 误判成 `A/BC` 的祖先。
    bool isAncestor(String a, String b) =>
        b.length > a.length && b.startsWith('$a/');
    final out = <String>[];
    for (final u in raw) {
      // u 被别的更深的 rel 包含 → 不算独立单元库。
      if (raw.any((o) => isAncestor(u, o))) continue;
      out.add(u);
    }
    return out;
  }

  /// 是否全部分布在同一个单元库内（这样服务端才能自动/手动合并成一张卡）。
  bool get sameUnitOnly => units.length <= 1;

  /// 该作者已被哪个组覆盖（返回组 id；没有返回空串）。
  String groupIdIn(String unit) {
    for (final g in groups) {
      if (g.unit == unit) return g.groupId;
    }
    return '';
  }
}

/// `GET /api/author/mounts?name=` 地址。
String authorMountsUrl(String base, String name) {
  final n = name.trim().replaceFirst(RegExp(r'^@+'), '');
  return joinApiUrl(base, '/api/author/mounts',
      query: n.isEmpty ? null : {'name': n});
}

/// 挂载设置不再按「目录树」勾选，而是按**基础库**勾选。
///
/// owner 2026-11-28：
/// > 「不要用文件目录的方式进行设置了，列出直属单元库下所有基础库，让用户
/// >   自己选作者作品存在于直接上级单元库下哪些基础库，选择后在对应基础库下
/// >   创建作者文件夹，若已经存在则直接使用，除 others 之外，各基础库同名文件夹
/// >   默认自动归属同一作者，保留一张作者卡，可手动拆分，作品不可跨过直接上级
/// >   单元库分布，只能分布在直属单元库下的基础库内。」
///
/// 所以挂载页只需要两件事：
///  1. 列出**直属**上级单元库下的全部基础库（下面这个函数）；
///  2. 用户勾选哪些基础库有该作者 → 在这些库里建 `@作者`（已存在则直接用）。
///
/// 「直接上级单元库」的范围由 [basicsOfUnitScope] 定死：一个单元库的
/// `allBasics`（自己 + 下级单元库的基础库）。作品不得跨出这个集合。
List<T> basicsOfUnitScope<T>(Iterable<T> allBasicsOfUnit) =>
    [for (final b in allBasicsOfUnit) b];

/// 把「勾选了哪些基础库」翻译成建目录请求。
///
/// 一个作者在 N 个基础库里各有一个 `@作者名` 目录；同名即同一作者
/// （服务端 `sanitizeAuthorDir` 用同一个目录名规则）。返回去重后的目录名
/// 与每个基础库一组请求体，便于调用方逐个 POST（已存在=409，静默跳过）。
///
/// [authorDir] 必须已经过 `authorDirError` 校验；这里不再猜名字。
List<Map<String, String>> createAuthorBodies({
  required String authorDir,
  required Iterable<String> libs,
}) {
  final seen = <String>{};
  final out = <Map<String, String>>[];
  for (final l in libs) {
    final lib = l.trim();
    if (lib.isEmpty || !seen.add(lib)) continue;
    out.add(<String, String>{'lib': lib, 'name': authorDir});
  }
  return out;
}

/// 建目录结果的**唯一**汇总文案。
///
/// 0.9.360：这段「新建 N 个 · 已存在 N 个 · 失败 N 个，一个都没有时说明
/// 未创建」在三处逐字重复（作者页、基础库页、单元库挂载页）。三份都
/// 「看起来正常」，于是往里加一项统计时只会加到一个页面：另外两处仍然
/// 只报两个数字，用户换个入口建目录就少看到一类结果。
///
/// 三个计数都为零时返回「未创建任何目录」——不同的措辞会让用户以为
/// 「这次和上次不一样」，其实是同一件事（一个请求都没发出去）。
String authorCreateSummary({
  required int made,
  required int existed,
  required int failed,
}) {
  final parts = <String>[
    if (made > 0) '新建 $made 个',
    if (existed > 0) '已存在 $existed 个',
    if (failed > 0) '失败 $failed 个',
  ];
  return parts.isEmpty ? '未创建任何目录' : parts.join(' · ');
}
