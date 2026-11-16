// 横向筛选条：桌面端可用鼠标拖动/滚轮横向滚动。
//
// Windows/macOS 上默认只有触控能拖动横向 ListView，鼠标滚轮只作用于纵向，
// 导致排行榜等页面末尾的筛选词条点不到。这里统一注入鼠标拖动 + 滚轮转横向。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class HorizontalChipBar extends StatefulWidget {
  final double height;
  final EdgeInsets padding;
  final List<Widget> children;
  final bool showScrollbar;

  const HorizontalChipBar({
    super.key,
    required this.children,
    this.height = 46,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.showScrollbar = true,
  });

  @override
  State<HorizontalChipBar> createState() => _HorizontalChipBarState();
}

class _HorizontalChipBarState extends State<HorizontalChipBar> {
  final ScrollController _c = ScrollController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      controller: _c,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      children: widget.children,
    );
    return SizedBox(
      height: widget.height,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
          scrollbars: false,
        ),
        child: Listener(
          onPointerSignal: (e) {
            if (e is! PointerScrollEvent || !_c.hasClients) return;
            final delta = e.scrollDelta.dy != 0
                ? e.scrollDelta.dy
                : e.scrollDelta.dx;
            if (delta == 0) return;
            _c.jumpTo((_c.offset + delta)
                .clamp(0.0, _c.position.maxScrollExtent));
          },
          child: widget.showScrollbar
              ? Scrollbar(
                  controller: _c,
                  thumbVisibility: false,
                  child: list,
                )
              : list,
        ),
      ),
    );
  }
}
