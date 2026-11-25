import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'haptics.dart';

/// 右侧竖排首字母索引条（owner 2026-11-22 / 2026-11-23 补滑动）。
///
/// 交互：
///  - 点某个字母 → 跳到该字母首位；
///  - **按住上下滑动** → 手指所在格子的字母即选中，列表跟随跳转；
///  - 屏幕左侧中部显示放大的字母浮层（白色半透明），松手约 400ms 后消失；
///  - 只有「切换到新字母」时触发一次轻震动，同字母内滑动不重复。
///
/// 命中宽度 ≥28dp，浮层用 [IgnorePointer] 且不占布局，不吃卡片点击。
/// 索引条每个字母占的行高（dp）。
///
/// 固定行高是「字母少也不散开、字母多也排得下」的前提：整列按它累加、
/// 垂直居中，字母增减时从中心向上下对称扩展。
const double kAuthorLetterRowHeight = 13;

class AuthorLetterBar extends StatefulWidget {
  const AuthorLetterBar({
    super.key,
    required this.letters,
    required this.onLetter,
    this.width = 28,
    this.hudHideDelay = const Duration(milliseconds: 400),
    this.keyPrefix,
  });

  final List<String> letters;
  final ValueChanged<String> onLetter;
  final double width;
  final Duration hudHideDelay;

  /// 每个字母文本的 key 前缀（如 `basic-author-index-`），供 widget 测试定位。
  final String? keyPrefix;

  /// 手指纵向位移 → 第几个字母；非法输入返回 -1。
  /// 手指纵向位移 → 第几个字母；非法输入返回 -1。
  ///
  /// owner 2026-11-25：字母改为「固定行高 + 整体居中」后，不能再按
  /// `height / count` 均分。整列实际占 `count * kAuthorLetterRowHeight`，
  /// 上下各留 (height - 整列高) / 2 的空白；落在空白里时夹到首/末字母。
  static int hitIndex({
    required double dy,
    required double height,
    required int count,
  }) {
    if (count <= 0) return -1;
    final column = count * kAuthorLetterRowHeight;
    final top = height > column ? (height - column) / 2 : 0.0;
    final local = dy - top;
    if (local < 0) return 0;
    final i = (local / kAuthorLetterRowHeight).floor();
    if (i > count - 1) return count - 1;
    return i;
  }

  @override
  State<AuthorLetterBar> createState() => _AuthorLetterBarState();
}

class _AuthorLetterBarState extends State<AuthorLetterBar> {
  String? _active;
  String? _hudLetter;
  OverlayEntry? _hudEntry;
  Timer? _hudTimer;

  void _hapticOnce() {
    // 统一走 haptics.dart 的唯一选择反馈实现，不在页面里再复制一份。
    hapticSelect();
  }

  void _pick(String letter) {
    if (_active == letter) return;
    setState(() => _active = letter);
    widget.onLetter(letter);
    _hapticOnce();
    _showHud(letter);
  }

  void _showHud(String letter) {
    _hudLetter = letter;
    _hudTimer?.cancel();
    if (_hudEntry == null) {
      final overlay = Overlay.maybeOf(context);
      if (overlay == null) return;
      _hudEntry = OverlayEntry(
        builder: (_) => _LetterHud(letter: _hudLetter ?? ''),
      );
      overlay.insert(_hudEntry!);
    }
    _hudEntry?.markNeedsBuild();
  }

  void _scheduleHide() {
    _hudTimer?.cancel();
    _hudTimer = Timer(widget.hudHideDelay, () {
      // 松手后清掉当前字母：下一次点同一个字母仍应跳转。
      if (mounted) setState(() => _active = null);
      _removeHud();
    });
  }

  void _removeHud() {
    _hudTimer?.cancel();
    _hudTimer = null;
    _hudEntry?.remove();
    _hudEntry = null;
    _hudLetter = null;
  }

  @override
  void dispose() {
    _removeHud();
    super.dispose();
  }

  void _handleLocal(Offset local, double height) {
    final i = AuthorLetterBar.hitIndex(
        dy: local.dy, height: height, count: widget.letters.length);
    if (i < 0 || i >= widget.letters.length) return;
    _pick(widget.letters[i]);
  }

  @override
  Widget build(BuildContext context) {
    final letters = widget.letters;
    if (letters.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (_, cons) {
      final height = cons.maxHeight;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 起手就按「手指按下那一格」算，不要等拖动阈值过了再用当前位置，
        // 否则快速下滑会把起点字母跳过去（首个字母丢失）。
        dragStartBehavior: DragStartBehavior.down,
        // 点按与拖动都按「手指落在哪一格」判定，避免逐个字母建手势。
        onTapDown: (d) => _handleLocal(d.localPosition, height),
        onTapUp: (_) => _scheduleHide(),
        onVerticalDragStart: (d) => _handleLocal(d.localPosition, height),
        onVerticalDragUpdate: (d) => _handleLocal(d.localPosition, height),
        onVerticalDragEnd: (_) => _scheduleHide(),
        onVerticalDragCancel: _scheduleHide,
        child: SizedBox(
          width: widget.width,
          height: height,
          child: Column(
            // owner 2026-11-25：「首字母少的时候字母间隔那么大，不论多少
            // 字母，排的紧凑一点，首字母增加时从中间依次向上下扩展」。
            //
            // 原来每个字母用 Expanded 平分整个高度：字母少时被拉得很散，
            // 字母多时又挤成一条。改为**固定行高 + 整体垂直居中**——
            // 字母增减时整列从中心向上下对称扩展，间距始终紧凑一致。
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in letters)
                SizedBox(
                  height: kAuthorLetterRowHeight,
                  child: Center(
                    child: Text(
                      l,
                      key: widget.keyPrefix == null
                          ? null
                          : ValueKey('${widget.keyPrefix}$l'),
                      style: TextStyle(
                        fontSize: letters.length > 18 ? 8.5 : 9.5,
                        height: 1.0,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant
                            .withValues(alpha: _active == l ? 1.0 : 0.7),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/// 左中部的放大字母浮层：纯展示，不吃指针。
class _LetterHud extends StatelessWidget {
  const _LetterHud({required this.letter});
  final String letter;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 28,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              letter,
              style: const TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
