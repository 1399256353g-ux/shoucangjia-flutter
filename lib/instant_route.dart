import 'package:flutter/material.dart';

/// 播放页入场不做路由转场（结构性做法，不是补丁）。
///
/// 抖音从作品卡片点进播放页是「瞬时切换」：手指抬起那一刻，卡片里的图
/// 直接变成播放页的首帧。默认 [MaterialPageRoute] 在 Android 上走
/// `ZoomPageTransitionsBuilder`（约 300ms 淡入 + 缩放），即使海报已经在
/// 内存里，转场也会把整页重新压暗一遍——0.9.147 记录的「最多一个转场
/// 时长的暗段（~100ms）」就是它。
///
/// 所以这里把转场时长设为 0：卡片图与播放页海报是同一张（同一 URL/解码
/// 宽度），切换就是同一张图继续显示，中间没有可被观察到的暗帧。
/// 不新增任何占位、定时器或守卫；进场/返回都是同一套零时长转场。
PageRouteBuilder<T> instantRoute<T>(WidgetBuilder builder) =>
    PageRouteBuilder<T>(
      pageBuilder: (context, animation, secondaryAnimation) =>
          builder(context),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          child,
    );
