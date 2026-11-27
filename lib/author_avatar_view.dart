/// 作者头像的**唯一渲染实现**（0.9.290 · 第六十七批）。
///
/// 为什么要有这个文件：
///
/// 头像此前有两份渲染代码：
///
/// ```
/// main.AuthorAvatar                       ClipOval + CachedNetworkImage + 首字母占位
///                                        （作者总览 / 排行榜 / 作者主页）
/// basic_lib_page._authorAvatar            ClipOval + Container + CachedNetworkImage
///                                        （基础库页作者 tab）
/// ```
///
/// 两份「各自都画得出来」，所以不会报错、也没有第二份实现可对比。差异却是
/// 实打实的：
///
///  - 基础库页那份**不监听** `AuthorAvatarStore`：在作者主页手动设的头像，
///    进基础库页作者 tab 仍然是旧图（真缺陷）；
///  - 占位样式两份不同（一个 0xFF546E7A 实心圆 + `avatarInitial`，一个
///    半透明主题色 + 自己算字号），同一个作者在两个页面占位长得不一样；
///  - 解码宽度、`w=` 宽度、`fit` 各写一遍，改一处另一处不跟。
///
/// 本文件只做「给定路径，画一个头像」：地址与鉴权的解析由调用方注入
/// （`main` 传全局 `cfg`，基础库页传自己的绑定表，避免 lib 包反向依赖
/// `main.dart`）。手动覆盖 / 作者级索引的优先级合成收在
/// [resolveAvatarSource]，两处共用同一条规则。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'author_avatar.dart' show AvatarLetterPlaceholder;
import 'author_grid.dart' show avatarDecodeWidth;
import 'cover_cache.dart' show DiziCache;
import 'lib_cover.dart' show libOfMediaPath, libFromMediaPath;
import 'media_resize.dart' show kAvatarImageWidth, withImageWidth;

/// 手动覆盖 + 调用方给的兜底路径 → 实际要请求的路径，以及它所属的库。
///
/// 规则（owner 指定，全 App 一条）：
///  1. 手动设置的本机/服务端头像优先于爬虫结果与自动兜底；
///  2. 覆盖图可能来自别的库，库归属按**路径自己的前缀**取，取不到才回落到
///     调用方给的库（否则会带着错误的 `Authorization` 去请求 → 401 空白）；
///  3. 没有覆盖时原样用兜底，库归属也用调用方给的。
///
/// 此前这条规则在 `main.AuthorAvatar` 与 `basic_lib_page._authorAvatar` 各写
/// 一遍，基础库页那份只挑了 `av`/兜底、完全没看手动覆盖。
({String path, String? lib}) resolveAvatarSource({
  required String manual,
  required String fallback,
  String? fallbackLib,
}) {
  final m = manual.trim();
  if (m.isEmpty) return (path: fallback, lib: fallbackLib);
  final own = libOfMediaPath(m);
  return (path: m, lib: own.isEmpty ? fallbackLib : own);
}

/// 已经有**最终路径**时，它所属的库（取不到用调用方给的库）。
///
/// 与 [resolveAvatarSource] 的区别：那条链还要在「手动覆盖 / 兜底」之间挑一个，
/// 这里路径已经定了，只差「这条路径属于哪个库」——决定带哪个 `Authorization`。
/// 播放页此前自己写 `libOfMediaPath(p).isEmpty ? _curLib : …`，是全 App 第三份
/// 同义判断（封面解析里还有两份各自实现）。
String avatarLibOf(String path, {String? fallbackLib}) =>
    libFromMediaPath(path, fallbackLib: fallbackLib);

/// 画一个圆形作者头像：无图/加载中/失败都退到首字母占位（emoji 安全）。
///
/// - [mediaPath]：已经按优先级挑好的媒体路径（空串表示没有头像）；
/// - [lib]：该路径所属的库，决定媒体地址与鉴权头；
/// - [urlOf] / [headersOf]：地址与鉴权的解析入口，必须与同页封面用的
///   同一套（`main` 是全局 `cfg`，基础库页是注入的绑定表）。
class AuthorAvatarView extends StatelessWidget {
  const AuthorAvatarView({
    super.key,
    required this.name,
    required this.mediaPath,
    this.lib,
    required this.size,
    required this.urlOf,
    required this.headersOf,
  });

  final String name;
  final String mediaPath;
  final String? lib;
  final double size;
  final String Function(String path, {String? lib}) urlOf;
  final Map<String, String> Function([String? lib]) headersOf;

  @override
  Widget build(BuildContext context) {
    final src = mediaPath.trim();
    // 统一占位：无图/加载中/失败都不空白，用首字母圆形占位（emoji 安全）。
    final placeholder = AvatarLetterPlaceholder(name: name, size: size);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: src.isEmpty
            ? placeholder
            : CachedNetworkImage(
                cacheManager: DiziCache.manager,
                // 头像最大显示 64dp：要 200px 缩图即可（服务端 `w=`）。
                imageUrl:
                    withImageWidth(urlOf(src, lib: lib), kAvatarImageWidth),
                httpHeaders: headersOf(lib),
                fit: BoxFit.cover,
                // 按实际显示尺寸 × 像素比解码，避免整张大图进内存。
                memCacheWidth: avatarDecodeWidth(
                    displaySize: size,
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context)),
                fadeInDuration: Duration.zero,
                placeholder: (_, __) => placeholder,
                errorWidget: (_, __, ___) => placeholder,
              ),
      ),
    );
  }
}
