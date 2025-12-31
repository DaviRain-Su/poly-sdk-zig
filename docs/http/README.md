# HTTP 模块

> 封装 Zig 标准库的 HTTP 客户端，提供便捷的 API 请求方法。

## 概述

`http` 模块提供了对 `std.http.Client` 的封装，适配 Zig 0.15 的新 API。

## 模块结构

```
src/http/
├── mod.zig           # 模块导出
└── client.zig        # HTTP 客户端封装
```

## 主要类型

### HttpClient

HTTP 客户端封装，提供 GET/POST/DELETE 请求方法。

```zig
const http = @import("poly-sdk-zig").http;

var client = http.HttpClient.init(allocator, .{
    .base_url = "https://clob.polymarket.com",
});
defer client.deinit();

// GET 请求
const response = try client.get("/markets");
defer allocator.free(response);

// POST 请求
const result = try client.post("/order", body);
defer allocator.free(result);
```

## Zig 0.15 HTTP API 适配

本模块适配了 Zig 0.15 的 HTTP Client API 变化：

- 使用 `request()` 创建请求
- 使用 `sendBodiless()` 或 `sendBodyUnflushed()` 发送请求
- 使用 `receiveHead()` 接收响应头
- 使用 `response.reader()` 读取响应体
- 使用 `std.Io.Limit.limited()` 设置读取限制

## 错误处理

| 错误 | 描述 |
|------|------|
| `ConnectionFailed` | 连接失败 |
| `ConnectionRefused` | 连接被拒绝 |
| `Timeout` | 请求超时 |
| `DnsResolutionFailed` | DNS 解析失败 |
| `TlsHandshakeFailed` | TLS 握手失败 |

## 测试

```bash
zig test src/http/client.zig
```
