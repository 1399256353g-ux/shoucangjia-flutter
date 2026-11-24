// HTTP Basic 鉴权头的唯一实现。
//
// 现状（第十一批清理前）：`'Basic ${base64Encode(utf8.encode('$user:$pass'))}'`
// 在 `main.dart` 里被**逐字手写 7 份**（服务器连通性测试、首页聚合、
// 星标刷新、连接探测、库统计、单元库爬虫配置、以及 `Cfg.headersFor` 自身）。
// 只要有一处把 `user:pass` 的顺序或分隔符写错，就会出现「只有一个接口 401」
// 这种最难查的现象——所以格式只允许有一个出处。
//
// 注意：这里只负责**格式**。凭据从哪来（Cfg 绑定 / ServerConn）仍由调用方决定，
// 本文件不持有任何凭据。

import 'dart:convert';

/// `Authorization` 头的值：`Basic base64(user:pass)`。
///
/// 空用户名或空密码也照常编码（服务端会回 401，由业务层给文案），
/// 不在这里抛异常——鉴权失败不是客户端崩溃的理由。
String basicAuthHeader(String user, String pass) =>
    'Basic ${base64Encode(utf8.encode('$user:$pass'))}';
