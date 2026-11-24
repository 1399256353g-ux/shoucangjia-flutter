// 异常 → 用户可读文案的唯一实现。
//
// 问题：页面里到处是
//
//     catch (e) { setState(() => err = '$e'); }
//     ... Text('加载失败：$err')
//
// 而 `$e` 对 `Exception` 的 `toString()` 是 `Exception: <message>`，
// 对 `TimeoutException` 是 `TimeoutException after 0:00:08.000000: Future not
// completed`。于是用户看到的是：
//
//     加载失败：Exception: HTTP 500
//     加载失败：TimeoutException after 0:00:10.000000: Future not completed
//
// 第二条尤其糟：既看不懂，也把内部实现（Future、时长精度）暴露在界面上。
//
// 这里只做一件事——把异常翻译成人话，**保留可行动的关键信息**
// （状态码、错误措辞），不保留 Dart 运行时前缀。
//
// 注意：这不是「把错误藏起来」。真正需要原始堆栈的地方走日志
// （`crash_guard` / `PauseTrace`），不靠 UI 文案。凡是加 `*: $e` 的展示位，
// 都应该过一遍这个函数。

/// 异常 / 任意对象 → 单行可读文案。
///
/// - `Exception: X` → `X`
/// - `TimeoutException after ...` → `请求超时`
/// - `SocketException: ...` / `ClientException: ...` → `连接失败`
/// - 其它 → 原样（去掉换行，避免撑破单行布局）
String errorText(Object? e) {
  if (e == null) return '未知错误';
  var s = '$e';
  // 只取第一行：多行错误在单行位置会把布局撑破。
  final nl = s.indexOf('\n');
  if (nl >= 0) s = s.substring(0, nl);
  s = s.trim();
  if (s.isEmpty) return '未知错误';

  // Dart 的包装前缀，逐个剥掉（可能叠加：Exception: SocketException: ...）。
  for (final prefix in const [
    'Exception: ',
    'Bad state: ',
  ]) {
    while (s.startsWith(prefix)) {
      s = s.substring(prefix.length).trim();
    }
  }

  if (s.startsWith('TimeoutException')) return '请求超时';
  if (s.startsWith('SocketException')) return '连接失败';
  if (s.startsWith('ClientException')) {
    // `ClientException: Connection closed before full header was received`
    // 这类是网络层问题，对用户只有「连接失败」有意义。
    return '连接失败';
  }
  if (s.startsWith('FormatException')) {
    // JSON 解析失败：服务端返回了非 JSON（多半是登录页/错误页）。
    return '返回内容无法解析';
  }
  if (s.startsWith('HandshakeException')) return '安全连接失败';
  if (s.startsWith('HttpException')) return '连接中断';

  if (s.isEmpty) return '未知错误';
  return s;
}
