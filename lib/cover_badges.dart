/// G13：网格封面角标——视频显示时长，图文显示图片张数。
///
/// 时长优先读索引里的 `du`（秒，服务端 ffprobe 生成）；缺省时不显示，
/// 避免用 0:00 误导。图文张数直接取媒体列表长度。
library;

import 'json_num.dart';
import 'time_labels.dart';
import 'work_forms.dart';
import 'work_safety.dart';

/// 封面角标时长上限（秒）：100 小时。
///
/// 媒体时长不可能超过这个量级；超过它的 `du` 只有一种来源——坏数据。
/// 数值本身与播放页时长文案的上限（`time_labels.kMaxClockSeconds`）相同，
/// 但两者是**不同出口的不同决定**：角标放不下就不画（返回空串），
/// 进度行要占位（`--:--`）。所以这里只引用同一个上限值，不复制一个数字。
const int kBadgeMaxSeconds = kMaxClockSeconds;

/// 把秒数格式化成 `m:ss`（超过 1 小时为 `h:mm:ss`）。
/// 非法/非正数返回空串，调用方据此隐藏角标。
///
/// **超出人类可信区间的时长同样返回空串**（[kBadgeMaxSeconds]）：服务端把
/// `du` 写成 `1e18` 或 int 上限时，这个函数以前会一本正经地算出
/// `277777777777777:46:40`（实测），角标把整张封面挤爆。数值没有算错，
/// 是输入不可能是真的媒体时长——比「显示一个荒唐数字」更诚实的答案是
/// 「不显示」，与「缺 `du` 就不显示」走同一条出口。
String formatBadgeDuration(num? seconds) {
  if (seconds == null) return '';
  final total = seconds.toDouble();
  if (total.isNaN || total.isInfinite || total < 1) return '';
  if (total > kBadgeMaxSeconds) return '';
  final s = total.round();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  // 角标贴近封面、横向空间紧：不足 1 小时时分钟**不补零**（`0:05` 而非
  // `00:05`）。这是与播放页进度（`00:05`）有意的区别，不是同一规则的副本，
  // 因此不并入 [formatClockSeconds]。
  final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

num? _asSeconds(dynamic raw) => numOrNull(raw);

/// 作品在封面右下角显示的角标文字；无可用信息时返回 null。
String? workCoverBadge(dynamic work) {
  if (work is! Map) return null;
  final type = '${work['t'] ?? ''}';
  if (workKind(work) == 'chapters') {
    final n = workChapterCount(work);
    return n > 1 ? '$n 集' : null;
  }
  if (type == 'p') {
    // 单图作品的 `m` 是字符串：只数 List 会让它没有「1 图」角标。
    final n = workMediaPaths(work).length;
    return n > 0 ? '$n 图' : null;
  }
  if (type == 'v') {
    final d = formatBadgeDuration(_asSeconds(workTotalDuration(work)));
    return d.isEmpty ? null : d;
  }
  return null;
}
