# iOS 原生播放器（AVPlayer）接入方案

阶段4 · 平台层。范围：**只解决 iOS**，Android / Windows / Linux 不动。
本轮交付 = 抽象层 + iOS 原生后端骨架 + 本文档；**未接线**，`lib/main.dart` 一行未改。

---

## 1. 结论

- iOS 的问题（黑屏有声、纹理重建、起播卡顿）根因在 `media_kit` 的
  「libmpv + 外部纹理」这条链，不在播放页逻辑。换播放器 ≠ 修纹理，
  要用一条**没有纹理**的渲染路径：AVPlayer + `AVPlayerLayer` 平台视图。
- 依赖可用：`video_player 2.10.1` 已解析并写入 `pubspec.yaml` / `pubspec.lock`
  （只新增 5 个传递依赖，未升级任何现有包）。
- 抽象层 `lib/player_backend.dart` 已就绪，`MpvBackend` 是**零行为改动**包装；
  `docs/skeletons/ios_native_player.dart` 已能完成打开/播放/暂停/seek/停止/音量/速率与
  七路事件流，**缺三块原生能力**（截图、`videoGravity`、loop-file），已在
  `PlayerCapabilities` 里显式声明，不用猜。
- 本轮不接线：iOS 继续走 mpv。接线步骤与回退开关见 §6、§7。

---

## 2. 为什么 iOS 要单独走原生

现状（`lib/main.dart`）：

| 现象 | 现有兜底 | 说明 |
|---|---|---|
| 有声无画 | `_blackGuard`（2.6s 看门狗）+ `_videoGen++` 重建纹理 + 降级软解 `_retryWithSoftwareDecode` | 兜底本身就是「重建一次纹理再看看」，每次重建都是一次闪黑 |
| 切条/切全屏卡顿 | 槽位池 + 预渲染 + 固定基准尺寸（720p）+ `RepaintBoundary` | 全部是在绕开外部纹理的重建成本 |
| 首帧慢 | 海报遮挡 + `_firstFrameSeen`（position ≥ 120ms） | mpv 要 demux + 解码 + 首帧上传纹理，链路长 |

这三条兜底都是**在纹理架构上打补丁**（违反工作守则 §1/§2）。
AVPlayerLayer 由 iOS 合成器直接合成，不存在「Flutter 纹理没拿到新帧」这种状态，
`_blackGuard` / `_videoGen` 这一整套在 iOS 上**根本不需要**，
这是「换结构」而不是「加兜底」。

---

## 3. 依赖与构建状态

| 项 | 结果 |
|---|---|
| `flutter pub add video_player --dry-run` | 可解析（有网），`video_player 2.10.1` |
| 实际安装 | `flutter pub add video_player` → 成功，`Changed 7 dependencies` |
| lock 影响 | 仅新增：`video_player` / `_android` / `_avfoundation` / `_platform_interface` / `_web` + `csslib` / `html`；**无现有包版本变动** |
| `flutter analyze lib` | `No issues found!` |
| `flutter test -r compact` | `All tests passed!`（818 个用例，EXIT=0） |
| iOS 产物编译 | **本机（Linux 网关）无法构建**，需 macOS + Xcode 执行 `flutter build ios --simulator` |

> 注意：`video_player` 会带进 `video_player_android`，Android 端多一个未使用的
> 插件依赖（体积可忽略）。若后续要彻底剔除，改用条件依赖/独立 flavor 再评估。

---

## 4. 接口设计

`lib/player_backend.dart`

```dart
abstract class PlayerBackend {
  String get name;
  PlayerCapabilities get capabilities;
  PlayerSnapshot get state;              // 同步快照（自救判断用）

  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<bool> get completedStream;
  Stream<VideoParamsSnapshot> get videoParamsStream;
  Stream<PlayerError> get errorStream;

  Future<void> open(PlayerSource source, {bool play = true});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
  Future<void> setVolume(double volume); // 0..100，沿用 media_kit 语义
  Future<void> setRate(double rate);
  Future<void> setLoopPlayback(bool enabled);
  Future<Uint8List?> screenshot({String format = 'image/jpeg'});

  Widget buildVideo({Key? key, BoxFit fit = BoxFit.contain});
  Future<void> dispose();
}
```

配套类型：

| 类型 | 用途 |
|---|---|
| `PlayerSource` | uri + httpHeaders（NAS 鉴权）+ title |
| `VideoParamsSnapshot` | 显示尺寸/比例，`unknown` 表示首帧前 |
| `PlayerSnapshot` | position/duration/playing/buffering/completed/volume/rate |
| `PlayerError` | 原始错误文本（`classifyPlaybackError` 可直接复用） |
| `PlayerCapabilities` | 能力开关，见下 |
| `selectPlayerBackendKind({isIOS, iosNativeEnabled})` | 纯逻辑选后端（可单测） |

能力对照（`PlayerCapabilities.mpv` / `.iosNative`）：

| 能力 | mpv | iOS 原生 |
|---|---|---|
| `videoScreenshot` | ✅ | ❌（TODO：AVAssetImageGenerator） |
| `playlistLoop` | ✅ | ❌（插件 `setLooping` 会重新起播，项目节奏不符） |
| `runtimeDecodeSwitch` | ✅ | ❌（无软解开关，只能换后端重开） |
| `nativeVideoParams` | ✅（dw/dh/aspect） | ❌（只有解码尺寸 + rotation，接口层换算） |
| `backgroundAudio` | 由应用/插件控制 | ✅（需 `UIBackgroundModes`，本轮不用） |
| `needsTextureRebuildWorkaround` | ✅ | ❌ |

约定：**所有控制方法不抛异常**，失败从 `errorStream` 上报（与播放页现有
`try {} catch (_) {}` 风格一致，接线时不需要到处加 try）。

### MpvBackend 与现有代码的等价性

| 现有实现（`main.dart`） | `MpvBackend` |
|---|---|
| `Player(configuration: PlayerConfiguration(title: 'Dizi', bufferSize: 32MB))` | 相同 |
| `VideoController(player, configuration: VideoControllerConfiguration(hwdec: hwdecFor(mode)))` | 相同 |
| `Video(controller: vc, fit: BoxFit.fill, controls: NoVideoControls)` | `buildVideo()` 相同参数 |
| `p.stream.{position,duration,playing,buffering,completed,error,videoParams}` | 原样透传（`error`/`videoParams` 做形状转换） |

迁移期逃生口：`MpvBackend.rawPlayer` / `rawController`。

### IosNativeBackend 关键实现点

`docs/skeletons/ios_native_player.dart`

- `VideoPlayerController.networkUrl(uri, httpHeaders:, viewType: platformView)`
- `initialize()` 完成后补发 duration / videoParams / position，再恢复音量与速率
- `addListener` 把 `VideoPlayerValue` 差分翻译成七路事件流（只推变化字段）
- completed 采用边沿触发 + 回退重武装（`position < duration - 1s` 时重新武装）
- `stop()` = pause + seek(0)（保留控制器供槽位复用）；真正释放走 `dispose()`
- 画面：平台视图用 `AspectRatio`（**不放进 FittedBox**），纹理视图按 720p
  基准 + `FittedBox`（与现有 mpv 布局一致）

---

## 5. iOS 与 mpv 行为差异对照

### 5.1 首帧

| | mpv | iOS 原生 |
|---|---|---|
| 首帧信号 | `videoParams.dw/dh > 0` + 位置走动 | `initialize()` 返回 ≈ `AVPlayerItem.status == ready`（时长/尺寸已知），**首帧上屏要等 AVPlayerLayer 合成** |
| 实际观感 | 需等 demux + 解码 + 纹理上屏，首帧明显偏慢 | 通常 < 1 帧，但 `initialize()` 完成 ≠ 画面已经上屏，仍有极短黑帧可能 |
| 建议 | 现有海报遮挡 + `_firstFrameSeen(120ms)` 可保留 | 同样保留海报遮挡；更准的做法是原生 `addBoundaryTimeObserver`（后续） |

### 5.2 纹理 / 渲染

| | mpv | iOS 原生 |
|---|---|---|
| 载体 | Flutter 外部纹理（libmpv 共享 surface） | `AVPlayerLayer`（平台视图）或 Flutter 纹理（每帧拷 CVPixelBuffer） |
| 缩放/全屏 | 纹理重建 → 闪黑、Windows 上直接崩 | 平台视图跟随 UIView 尺寸，**不重建** |
| 比例 | `dw/dh/aspect`（已按 PAR 校正） | `value.size` + `rotationCorrection` → `value.aspectRatio` |
| `BoxFit` | `Video(fit:)` 直接支持 | 无 `videoGravity` 参数，插件固定 `ResizeAspect`（letterbox）；`cover` 需自算容器尺寸或写原生 |
| 槽位切换 | 必须换 `key` 重建 `Video` | 平台视图切换控制器同样需要重建 widget，但无纹理回收问题 |

### 5.3 音频会话

| | mpv | iOS 原生 |
|---|---|---|
| 会话 | 由 media_kit / 系统默认 | `FVPVideoPlayerPlugin.initialize` 把 `AVAudioSession` **升级到 `Playback`**（静音开关下也出声） |
| 混音 | 不涉及 | 默认不混音（会中断其他 App 音频）；要混音用 `VideoPlayerOptions(mixWithOthers: true)` → `AVAudioSessionCategoryOptionMixWithOthers` |
| 与现有设置页音量/静音 | 应用层音量 0..100 | 同接口，内部 `/100` 映射到 `setVolume` |

### 5.4 后台

| | mpv | iOS 原生 |
|---|---|---|
| 行为 | `Video(pauseUponEnteringBackgroundMode: true)` + 应用 `shouldPauseInBackground` | 插件不做生命周期处理；App 挂起后 AVPlayer 基本停摆 |
| 后台出声 | 需要额外配置 | 需要 `Info.plist` 的 `UIBackgroundModes: audio` + 主动激活会话 |
| 本项目建议 | 保持「iOS 只在 `paused` 暂停」（`background_pause.dart` 现状） | 不变，不要为了原生播放放开后台 |

### 5.5 其他

| 维度 | mpv | iOS 原生 |
|---|---|---|
| 位置刷新 | native push，约 100ms | Flutter 侧 `Timer.periodic(100ms)` → `platform.position`（每秒 10 次 method channel 往返） |
| seek | 精确（默认） | `toleranceBefore/After = kCMTimeZero`（精确），仅结尾用 1ms 容差 |
| 单条循环 | `loop-file`（项目刻意不用，见 `main.dart:9693` 注释） | 无；`setLooping` 会 seek(0) 重新起播，会闪首帧 → 停在末帧，循环交上层 |
| 截图 | `player.screenshot(format:)` 可用（封面上传） | 无 API → 封面功能需补原生，否则 iOS 上「取当前帧」不可用 |
| 错误分类 | 字符串，`classifyPlaybackError` 已适配 | `value.errorDescription`，AVFoundation 英文/错误码，**需补映射** |
| 网络鉴权 | libmpv 自带 HTTP 栈，不受 ATS 限制 | `AVURLAsset` 走系统网络栈，**受 ATS 限制**；局域网 http 若被拒，需配 `NSAppTransportSecurity`（`NSAllowsLocalNetworking` 或对应例外域名） |

---

## 6. 接入步骤（下一轮执行）

> 原则：只替换「槽位里的播放器对象」与「事件流来源」，播放页的
> 调度/手势/进度/连播逻辑一行不动。每步可单独回滚。

### 步骤 0 · 前置

1. macOS 上 `flutter pub get` + `flutter build ios --simulator` 通过。
2. 真机/模拟器验证 `IosNativeBackend` 能出画面（用 `IosVideoSurface.platformView`）。
3. 确认 NAS 地址在 ATS 下的表现（见 §5.5）。

### 步骤 1 · 槽位后端化（不改调用点）

`lib/main.dart:7057` `_PlaybackSlot`：

```dart
class _PlaybackSlot {
  late final PlayerBackend backend;   // 新增
  // 过渡期保留旧字段，现有 200+ 处 player.xxx 不用动
  Player get player => (backend as MpvBackend).rawPlayer;
  VideoController get vc => (backend as MpvBackend).rawController;
}
```

构造时按 `selectPlayerBackendKind` 选实现。**此时行为完全不变**（都是 MpvBackend）。

### 步骤 2 · 事件流切换

`_bindPlayer`（`main.dart:7567`）里：`p.stream.position` → `backend.positionStream`，
其余六路同理。注意 `p.stream.error` 已是 `Stream<String>`，换成 `Stream<PlayerError>`
后取 `.message` 交给 `classifyPlaybackError`。

### 步骤 3 · 画面组件切换

`main.dart:10370` 的 `Video(...)` → `_active.backend.buildVideo(fit: fit)`；
`key: ValueKey('video-...-$_videoGen')` 只在
`capabilities.needsTextureRebuildWorkaround == true` 时保留。

### 步骤 4 · 关闭 mpv 专属兜底

- `_blackGuard`（`main.dart:8534`）：仅 `needsTextureRebuildWorkaround` 时启用。
- `_videoGen` 重建：同上。
- `_retryWithSoftwareDecode`（`main.dart:7980`）：仅 `runtimeDecodeSwitch` 时可用；
  iOS 上解码失败直接走 `_showFailure`（或换后端重开一次）。
- `screenshot`（`main.dart:10636`）：`capabilities.videoScreenshot == false` 时
  前端隐藏「用当前帧做封面」，改为提示「iOS 暂不支持」，不要静默失败。

### 步骤 5 · 循环语义

`completedStream` 分支里，`loopOne` 时：
- mpv：`seek(0)` + `play()`（现状）
- iOS：同样 `seek(0)` + `play()`，但**预期会有一次重新起播**（AVPlayer 无 loop-file）。
  若观感不可接受，改为「停在末帧 + 显示重播按钮」，这属于产品决策，先报 owner。

---

## 7. 回退开关设计

三层，任何一层都能独立把人拉回 mpv：

### 7.1 编译期

`PlayerBackendKind` 默认值留在 `mpv`；`iosNative` 必须先显式打开。

### 7.2 运行期（设置项，持久化）

建议在 `AppSettings` 增加（字段名待接线时定）：

```dart
/// iOS 播放后端：mpv / iosNative / auto（默认 mpv，灰度期改 auto）
static const String prefsKeyPlayerBackend = 'player_backend_v1';
static PlayerBackendKind iosBackend = PlayerBackendKind.mpv;
```

判断入口只有一处，纯函数，可单测：

```dart
final kind = selectPlayerBackendKind(
  isIOS: Platform.isIOS,
  iosNativeEnabled: AppSettings.iosBackend != PlayerBackendKind.mpv,
);
```

设置页暴露「iOS 播放器：兼容(mpv) / 原生(推荐)」，切换后**下次进播放页生效**
（不改已打开槽位，避免中途换实现导致状态错乱）。

### 7.3 自动降级（会话级）

iOS 原生后端连续 2 次在 `open()` 阶段失败（`errorStream` 早于 duration 到达），
本次会话标记 `iosNativeBroken = true`，`selectPlayerBackendKind` 直接返回 `mpv`，
并在播放页顶部给一次性提示「已切回兼容播放器」。只降不升，进程重启才重新尝试。
**注意**：这是「结构性降级」（换后端），不是「在原生路径里再加一个重试」，
不与 §2 的补丁禁令冲突。

---

## 8. 风险与未完成项

| # | 风险 | 影响 | 处置 |
|---|---|---|---|
| R1 | 平台视图与 Flutter 手势/变换叠加 | 全屏动画、切换动画中可能掉帧或错位 | 平台视图一律走 `AspectRatio`，不做 FittedBox 缩放；全屏用 `AVPlayerLayer` 自身尺寸 |
| R2 | 无 `videoGravity` | 竖屏源「铺满」效果要靠容器裁剪实现 | 先用容器尺寸模拟 `cover`；必要时写原生 `VideoPlayerView` 子类 |
| R3 | 无截图 | iOS 上「用当前帧做封面」不可用 | 前端按 capability 隐藏；后续用 `AVAssetImageGenerator` 补 |
| R4 | 位置精度依赖 Flutter 轮询 | 进度条 100ms 一次 method channel；滑动时可能有额外开销 | 先实测；不够再用原生 `addPeriodicTimeObserver` 写专用通道 |
| R5 | ATS | 局域网 http 可能被 AVPlayer 拒绝 | 真机验证后按需配 `Info.plist`，不要一上来开 `NSAllowsArbitraryLoads` |
| R6 | mpv 仍随包 | `media_kit_libs_video` 是全平台依赖，iOS 包里仍有 libmpv 体积 | 灰度稳定后再评估拆条件依赖/flavor，不在本轮做 |
| R7 | 错误文案差异 | `classifyPlaybackError` 是给 mpv/中文错误写的 | 补 AVFoundation 错误码映射（`-11800` 系列等） |
| R8 | `stop()` 语义差异 | mpv 卸载媒体，iOS 只归零 | 预缓冲池依赖「复用」，文档已写明；不要按 mpv 语义写调用方 |

---

## 9. 验证清单（下一轮）

- [ ] macOS：`flutter analyze` 0 error / `flutter test` 全绿 / `flutter build ios --simulator`
- [ ] 真机：竖屏 9:16 视频首帧出现时间（对比 mpv）
- [ ] 真机：快速上下滑 20 条，画面无黑屏、无闪、无音频丢帧
- [ ] 真机：切全屏 / 退出全屏 10 次，不崩、不黑
- [ ] 真机：静音开关拨到静音，仍有声（`Playback` 会话）
- [ ] 真机：切后台 → 回前台，按现有 `shouldPauseInBackground` 行为暂停不自动播
- [ ] 真机：播完一条，`completed` 只触发一次；单条循环重播没有卡死
- [ ] 真机：NAS 鉴权头生效（401 时 `errorStream` 有可读错误）
- [ ] 指标：守卫定时器数量（iOS 应为 0 个 `_blackGuard`）、起播耗时、滑动重建次数（对比本轮前）

---

## 10. 文件清单（本轮）

| 文件 | 说明 |
|---|---|
| `lib/player_backend.dart` | 接口 + 数据类型 + `MpvBackend`（零行为改动） + 后端选择纯函数 |
| `docs/skeletons/ios_native_player.dart` | `IosNativeBackend`（AVPlayer / video_player）+ `IosVideoSurface` |
| `docs/ios-native-player.md` | 本文档 |
| `pubspec.yaml` | 新增 `video_player: ^2.10.1` |
| `pubspec.lock` | 仅新增 7 条依赖记录 |

未改动：`lib/main.dart`、任何测试、版本号。未 commit / push。
