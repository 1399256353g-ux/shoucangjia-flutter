/// 接口超时的唯一出处（第一百一十七批）。
///
/// 此前 `timeout(const Duration(seconds: N))` 在 16 个文件里写了 92 遍，N 由
/// 每个页面自己定（2/6/8/10/12/15/20/30/60）。同一个端点因此有多个上限，而
/// **短的那个才是实际生效的**：
///
/// | 端点 | 各调用点用的上限 | 后果 |
/// |---|---|---|
/// | `/api/libraries` | 8 / 10 / 12 / 15 | 慢盘上首页库列表 8s 就断，另一页等到 15s |
/// | `/api/libraries.json` | 8 / 10 / 12 / 20 | 同一份注册表在不同页面「读得出来 / 读不出来」 |
/// | `/api/authors.json` | 12 / 20 | 大索引在 12s 的调用点永远空，另处却正常 |
/// | `/api/crawler` | 8 / 10 / 15 | 同一份爬虫配置三个页面对「慢」的容忍不同 |
/// | `/api/author_stats.json` | 8 / 10 | 同上 |
///
/// 现在按**读到的体量/动作性质**分档，一个端点只落一档。分档的硬规则：
/// **每档的取值取该档已有调用点的最大值，只会放宽、绝不收紧**。此前 20s 能
/// 读出来的作者索引不会变成 12s；反之 8s 就读不完的库列表现在有 15s。放宽的
/// 代价是「服务器掉线时晚几秒才报错」，比「明明活着却报失败」轻。
///
/// 留在原处、**不属于接口超时**的三处：手势判定 400ms、整条作品下载 5 分钟、
/// Windows 全屏切换 2s（都不是 HTTP 读，档位化会让它们变成另一种东西）。
library;

/// 只判活：`/api/auth`、连接测试里那两条请求。
///
/// 连接测试的意义是「快告诉我通不通」，所以它整段按探测档走，不跟着数据读取
/// 的上限一起放宽。
const Duration kTimeoutProbe = Duration(seconds: 8);

/// 普通读：小 JSON。状态、单库索引、设置、统计、删除记录、同步日志。
const Duration kTimeoutRead = Duration(seconds: 12);

/// 中等读：库列表 / 注册表 / 爬虫配置。比小 JSON 大，但仍是元数据。
const Duration kTimeoutReadSlow = Duration(seconds: 15);

/// 重读：全量作者表、作品列表、排行、推荐、维护扫描、目录树。
const Duration kTimeoutReadHeavy = Duration(seconds: 20);

/// 普通写：建/删/改一条记录、触发同步、设置保存。
const Duration kTimeoutWrite = Duration(seconds: 20);

/// 会动磁盘目录的写：重命名分类目录、批量移动/删除作品文件。
const Duration kTimeoutHeavyWrite = Duration(seconds: 30);

/// 上传/生成：封面写入、头像设置、重建索引。
const Duration kTimeoutUpload = Duration(seconds: 60);

/// 深度扫描：维护巡检的 `deep=1`（要遍历全部媒体文件）。
///
/// 与 [kTimeoutReadHeavy] 分开是因为它不是「读一份 JSON」，而是让服务端去
/// 摸每一个媒体文件；用同一档会让「深度扫描」在慢盘上必然超时。
const Duration kTimeoutDeepScan = Duration(seconds: 90);

/// **整批**多条请求一起去取的上限（不是单条请求的上限）。
///
/// 与其它档不同，这一档保持 10s 不放宽：它管的是「首屏同时问 4 台服务器」，
/// 放宽会让一台掉线的服务器把首屏多卡几秒，而每台服务器自己的请求还有各档
/// 上限兜着。
const Duration kTimeoutBatch = Duration(seconds: 10);
