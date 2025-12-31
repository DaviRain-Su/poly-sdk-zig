# 错误模块

> 定义项目中使用的所有错误类型。

## 概述

`error.zig` 定义了 Polymarket SDK 中使用的错误类型，包括：

- HTTP 错误
- 认证错误
- 解析错误
- 验证错误

## 错误分类

### HTTP 错误

| 错误 | HTTP 状态码 | 描述 |
|------|------------|------|
| `BadRequest` | 400 | 请求格式错误 |
| `Unauthorized` | 401 | 未授权 |
| `Forbidden` | 403 | 禁止访问 |
| `NotFound` | 404 | 资源不存在 |
| `RateLimited` | 429 | 请求过于频繁 |
| `InternalServerError` | 500 | 服务器内部错误 |
| `BadGateway` | 502 | 网关错误 |
| `ServiceUnavailable` | 503 | 服务不可用 |
| `GatewayTimeout` | 504 | 网关超时 |

### 连接错误

| 错误 | 描述 |
|------|------|
| `ConnectionFailed` | 连接失败 |
| `ConnectionRefused` | 连接被拒绝 |
| `ConnectionReset` | 连接被重置 |
| `Timeout` | 连接超时 |
| `DnsResolutionFailed` | DNS 解析失败 |
| `TlsHandshakeFailed` | TLS 握手失败 |

### 解析错误

| 错误 | 描述 |
|------|------|
| `InvalidJson` | JSON 解析失败 |
| `InvalidResponse` | 响应格式错误 |

## 使用示例

```zig
const Error = @import("poly-sdk-zig").Error;

fn handleError(err: Error) void {
    switch (err) {
        Error.Unauthorized => {
            // 重新认证
        },
        Error.RateLimited => {
            // 等待后重试
        },
        else => {
            // 其他错误处理
        },
    }
}
```

## HTTP 状态码映射

```zig
pub fn fromHttpStatus(status: std.http.Status) ?Error {
    return switch (@intFromEnum(status)) {
        200...299 => null,
        400 => Error.BadRequest,
        401 => Error.Unauthorized,
        403 => Error.Forbidden,
        404 => Error.NotFound,
        429 => Error.RateLimited,
        500 => Error.InternalServerError,
        502 => Error.BadGateway,
        503 => Error.ServiceUnavailable,
        504 => Error.GatewayTimeout,
        else => Error.UnknownHttpError,
    };
}
```

## 可重试错误

以下错误可以安全重试：

- `RateLimited` - 等待后重试
- `ServiceUnavailable` - 服务暂时不可用
- `GatewayTimeout` - 网关超时
- `ConnectionReset` - 连接被重置

## 测试

```bash
zig test src/error.zig
```
