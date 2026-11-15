/// L6：单条循环与自动连播的联动规则（纯值，便于单测）。
///
/// 规则：
///  - 打开单条循环时，自动连播立即关闭，并记住「打开循环前的连播状态」；
///  - 关闭单条循环时，连播恢复到打开前的状态（原来开着才恢复为开）；
///  - 循环开启期间手动切换连播只影响当下，不会覆盖记忆值；
///  - 循环本身优先级最高：连播开着也不会越过循环去播下一条。
library;

class LoopLink {
  /// 单条循环是否开启。
  final bool loopOne;

  /// 自动连播是否开启。
  final bool autoplay;

  /// 打开循环前的连播状态，关闭循环时用它恢复。
  final bool restoreAutoplay;

  const LoopLink({
    this.loopOne = false,
    this.autoplay = true,
    bool? restoreAutoplay,
  }) : restoreAutoplay = restoreAutoplay ?? autoplay;

  LoopLink copyWith({bool? loopOne, bool? autoplay, bool? restoreAutoplay}) =>
      LoopLink(
        loopOne: loopOne ?? this.loopOne,
        autoplay: autoplay ?? this.autoplay,
        restoreAutoplay: restoreAutoplay ?? this.restoreAutoplay,
      );

  /// 切换单条循环。开启时关掉连播并记住原状态；关闭时恢复记忆中的连播。
  LoopLink toggleLoop() {
    if (loopOne) {
      return copyWith(loopOne: false, autoplay: restoreAutoplay);
    }
    return copyWith(
      loopOne: true,
      autoplay: false,
      restoreAutoplay: autoplay,
    );
  }

  /// 切换自动连播（循环开启时也允许切，但退出循环会回到记忆值）。
  LoopLink toggleAutoplay() => copyWith(autoplay: !autoplay);

  /// 连播实际是否应调度下一条：循环开着时永远不调度。
  bool get nextEnabled => autoplay && !loopOne;

  @override
  bool operator ==(Object other) =>
      other is LoopLink &&
      other.loopOne == loopOne &&
      other.autoplay == autoplay &&
      other.restoreAutoplay == restoreAutoplay;

  @override
  int get hashCode => Object.hash(loopOne, autoplay, restoreAutoplay);
}
