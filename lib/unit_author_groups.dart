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
      other is AuthorGroupFile && other.lib == lib && other.authorDir == authorDir;

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

  /// 只有落盘的手动组才能删除/改成员；派生组改不了，只能「拆」出新的手动组。
  bool get editable => !auto;

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
      split: v['split'] == true,
      auto: v['auto'] == true,
      works: v['works'] is num ? (v['works'] as num).toInt() : 0,
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

  const UnitAuthorRequest({
    required this.unit,
    required this.action,
    this.groupId = '',
    this.name = '',
    this.files = const <AuthorGroupFile>[],
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
  String? get error => unitAuthorRequestError(
        action: action,
        unit: unit,
        groupId: groupId,
        files: files,
        groupFiles: null,
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

/// 面板上「还没被任何组占用、可以参与合并」的成员。
///
/// [alreadyIn] 是当前组要排除掉的成员（编辑已有组时把自己算进来没有意义）。
List<AuthorGroupFile> mergeableFiles(
  Iterable<AuthorGroupFile> available, {
  Iterable<String> alreadyIn = const <String>[],
}) {
  final skip = <String>{for (final k in alreadyIn) k.trim()};
  final seen = <String>{};
  final out = <AuthorGroupFile>[];
  for (final f in available) {
    if (skip.contains(f.key)) continue;
    if (!seen.add(f.key)) continue;
    out.add(f);
  }
  return out;
}

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
      works: v['works'] is num ? (v['works'] as num).toInt() : 0,
      avatar: '${v['av'] ?? ''}'.trim(),
      bio: '${v['bio'] ?? ''}'.trim(),
      split: v['split'] == true,
      auto: v['auto'] == true,
    );
  }
}

/// `/api/unit/authors.json` 的完整响应。
class UnitAuthorCards {
  final String unit;
  final List<UnitAuthorCard> cards;
  final List<UnitAuthorGroup> explicit;

  const UnitAuthorCards({
    this.unit = '',
    this.cards = const <UnitAuthorCard>[],
    this.explicit = const <UnitAuthorGroup>[],
  });

  /// 已合并的组（≥2 成员）。
  List<UnitAuthorCard> get merged =>
      cards.where((c) => c.merged).toList(growable: false);

  /// 还没进组的独立作者（可以勾选参与合并）。
  List<UnitAuthorCard> get singles =>
      cards.where((c) => !c.merged && c.files.length == 1).toList(growable: false);

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
    final explicit = <UnitAuthorGroup>[];
    final rawExplicit = json['explicit'];
    if (rawExplicit is List) {
      for (final g in rawExplicit) {
        final o = UnitAuthorGroup.fromJson(g);
        if (o != null) explicit.add(o);
      }
    }
    return UnitAuthorCards(
      unit: '${json['unit'] ?? ''}'.trim(),
      cards: cards,
      explicit: explicit,
    );
  }
}

/// 面板卡片的一句话副标题：作品数 + 来源数。
///
/// 只拼结构信息（作品数、成员数），不含任何作者名/路径——面板显示名字是
/// owner 自己要看的，但本函数不把它拼进日志或文案以外的位置。
String unitAuthorCardSummary(UnitAuthorCard c) {
  final parts = <String>[];
  if (c.merged) parts.add('合并 ${c.files.length} 个文件夹');
  if (c.works > 0) parts.add('${c.works} 作品');
  if (c.split) parts.add('已拆分');
  if (c.auto) parts.add('自动');
  return parts.join(' · ');
}
