/// 删除监测：解析服务端 `/api/deleted.json`（来自抖音库 `_deleted.log`）。
///
/// 只读日志，不删除/不改动媒体；App 里只展示「已删除/取消收藏」记录。
class DeletedEntry {
  final String at;
  final String author;
  final String date;
  final String title;
  final String workId;
  final String collection;
  final String link;
  final String cover;

  const DeletedEntry({
    required this.at,
    required this.author,
    required this.date,
    required this.title,
    required this.workId,
    required this.collection,
    required this.link,
    required this.cover,
  });

  bool get hasCover => cover.trim().isNotEmpty;

  /// `2026-11-17T01:06:37.489Z` → `11-17 09:06`（本地时区）。
  String get atLabel {
    final t = DateTime.tryParse(at);
    if (t == null) return at;
    final l = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}

class DeletedReport {
  final int total;
  final int updated;
  final List<DeletedEntry> items;

  const DeletedReport(
      {required this.total, required this.updated, required this.items});

  static const empty = DeletedReport(total: 0, updated: 0, items: []);

  String get updatedLabel {
    if (updated <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(updated * 1000).toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

DeletedReport parseDeletedReport(dynamic raw) {
  if (raw is! Map) return DeletedReport.empty;
  final list = raw['items'];
  final out = <DeletedEntry>[];
  if (list is List) {
    for (final e in list) {
      if (e is! Map) continue;
      out.add(DeletedEntry(
        at: '${e['at'] ?? ''}',
        author: '${e['a'] ?? ''}',
        date: '${e['d'] ?? ''}',
        title: '${e['t'] ?? ''}',
        workId: '${e['id'] ?? ''}',
        collection: '${e['c'] ?? ''}',
        link: '${e['u'] ?? ''}',
        cover: '${e['th'] ?? ''}',
      ));
    }
  }
  final total = (raw['total'] as num?)?.toInt() ?? out.length;
  final updated = (raw['updated'] as num?)?.toInt() ?? 0;
  return DeletedReport(total: total, updated: updated, items: out);
}
