/// 注册库 ID 的规则（客户端侧唯一一份）。
///
/// 注意区分两个名字相近的文件：
///   - `lib_id.dart`   —— **已有**：`node:<rel>` ↔ `<rel>` 两种 id 形式的
///     归一与等价键枚举（配色/emoji 落盘用）。
///   - `registry_lib_id.dart`（本文件）—— 新建注册库时用户输入的那个 id 的
///     **字符集与长度规则**。
///
/// 服务端 `gallery_server.js` 有一条硬规则 `libIdOk()`：
///
/// ```js
/// function libIdOk(id){ return /^[a-z0-9][a-z0-9_-]{0,31}$/.test(String(id||"")); }
/// ```
///
/// 客户端此前把同一条规则抄在新建库那一处（`main.dart` 的 `_add`），
/// 于是有三件事只能靠人记：
///
/// 1. **归一化顺序**：用户输入 `  My-Lib  `，客户端应当先 `trim` +
///    `toLowerCase` 再判定——服务端不认大写，客户端若只校验不归一，
///    就会发出一个必定被 400 拒掉的 id，而错误提示只说「格式不正确」。
/// 2. **长度上限 32**：`{0,31}` 是「首字符之后最多 31 个」，总长 32。
///    只写 `+` 的实现会放行 33 位，用户点「添加」才被服务端拒。
/// 3. **提示措辞**：一处改「格式不正确」、另一处没改，用户在两个入口
///    看到两种说法。
///
/// 判定、归一化、提示三件事都收在这里；调用点只问 [registryLibIdError] 一句。
library;

/// 库 ID 总长度上限（与服务端 `{0,31}` + 首字符一致）。
const int kRegistryLibIdMaxLength = 32;

/// 服务端规则原文。只在这里出现一次。
final RegExp kRegistryLibIdPattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,31}$');

/// 格式不合法时给用户的提示。
const String kRegistryLibIdFormatText = '库 ID 格式不正确';

/// 归一化：去首尾空白 + 转小写。服务端只认小写，这一步要在校验**之前**做。
String normalizeRegistryLibId(String raw) => raw.trim().toLowerCase();

/// 校验一个（已归一化或未归一化的）库 ID；合法返回 null，否则返回提示文案。
///
/// 传入未归一化的字符串时会先归一化再判定——调用点不必记得先 `trim`。
String? registryLibIdError(String raw) => kRegistryLibIdPattern
        .hasMatch(normalizeRegistryLibId(raw))
    ? null
    : kRegistryLibIdFormatText;
