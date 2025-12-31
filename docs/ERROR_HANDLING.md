# 错误处理设计文档

本文档详细描述 Polymarket Zig CLOB Client SDK 的错误处理机制。

## 目录

- [1. 设计原则](#1-设计原则)
- [2. 错误分类](#2-错误分类)
- [3. 错误类型定义](#3-错误类型定义)
- [4. 错误处理模式](#4-错误处理模式)
- [5. HTTP 错误映射](#5-http-错误映射)
- [6. 用户指南](#6-用户指南)

---

## 1. 设计原则

### 1.1 Zig 错误处理特性

Zig 使用错误联合类型（Error Union）进行错误处理：

```zig
// 返回类型是 !T 或 Error!T
fn doSomething() !Result {
    // 可能返回错误或结果
}

// 使用 try 传播错误
const result = try doSomething();

// 使用 catch 处理错误
const result = doSomething() catch |err| {
    // 处理错误
};
```

### 1.2 设计目标

1. **明确性**：错误类型清晰表达失败原因
2. **可恢复性**：区分可恢复和不可恢复错误
3. **上下文**：提供足够的错误上下文信息
4. **安全性**：不泄露敏感信息

---

## 2. 错误分类

### 2.1 错误层次结构

```
┌─────────────────────────────────────────────────────────────────────┐
│                          错误分类                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    网络错误 (NetworkError)                   │    │
│  │  ConnectionFailed, Timeout, DnsError, TlsError              │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    认证错误 (AuthError)                      │    │
│  │  InvalidSignature, InvalidCredentials, Unauthorized,        │    │
│  │  NonceAlreadyUsed, ChainIdNotSet                           │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    验证错误 (ValidationError)                │    │
│  │  InvalidPrice, InvalidSize, InvalidTickSize,                │    │
│  │  MissingTokenId, MissingSide, InsufficientLiquidity        │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    API 错误 (ApiError)                       │    │
│  │  BadRequest, NotFound, RateLimited, Geoblocked,             │    │
│  │  InternalServerError                                        │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    配置错误 (ConfigError)                    │    │
│  │  MissingContractConfig, UnsupportedChain,                   │    │
│  │  InvalidFunderWithEoa, MissingFunderForProxy                │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
│  ┌─────────────────────────────────────────────────────────────┐    │
│  │                    解析错误 (ParseError)                     │    │
│  │  JsonParseError, InvalidHex, InvalidDecimal,                │    │
│  │  InvalidUuid, InvalidAddress                                │    │
│  └─────────────────────────────────────────────────────────────┘    │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. 错误类型定义

### 3.1 主错误集

```zig
// src/error.zig

const std = @import("std");

/// SDK 错误集合
pub const Error = error{
    // ===== 网络错误 =====
    /// 无法建立连接
    ConnectionFailed,
    /// 请求超时
    Timeout,
    /// DNS 解析失败
    DnsError,
    /// TLS/SSL 错误
    TlsError,
    /// 连接被重置
    ConnectionReset,

    // ===== 认证错误 =====
    /// 签名无效
    InvalidSignature,
    /// 凭证无效
    InvalidCredentials,
    /// 未授权
    Unauthorized,
    /// Nonce 已被使用
    NonceAlreadyUsed,
    /// 链 ID 未设置
    ChainIdNotSet,
    /// 不支持的链
    UnsupportedChain,
    /// 凭证已过期
    CredentialsExpired,

    // ===== 验证错误 =====
    /// 价格无效
    InvalidPrice,
    /// 数量无效
    InvalidSize,
    /// 价格精度无效
    InvalidTickSize,
    /// 缺少代币 ID
    MissingTokenId,
    /// 缺少交易方向
    MissingSide,
    /// 缺少价格
    MissingPrice,
    /// 缺少数量
    MissingSize,
    /// 缺少金额
    MissingAmount,
    /// 流动性不足
    InsufficientLiquidity,
    /// 仅 GTD 订单可设置过期时间
    ExpirationOnlyForGtd,
    /// 市价单订单类型无效
    InvalidOrderTypeForMarket,
    /// 卖单必须使用 shares
    SellOrderMustUseShares,
    /// 无效的交易方向
    InvalidSide,
    /// 小数位数过多
    TooManyDecimalPlaces,

    // ===== API 错误 =====
    /// 请求格式错误 (400)
    BadRequest,
    /// 资源未找到 (404)
    NotFound,
    /// 请求频率限制 (429)
    RateLimited,
    /// 地理位置限制
    Geoblocked,
    /// 服务器内部错误 (500)
    InternalServerError,
    /// 服务不可用 (503)
    ServiceUnavailable,
    /// 网关超时 (504)
    GatewayTimeout,
    /// 未知 API 错误
    UnknownApiError,

    // ===== 配置错误 =====
    /// 缺少合约配置
    MissingContractConfig,
    /// EOA 签名类型不能有 funder
    InvalidFunderWithEoa,
    /// Proxy/Safe 签名类型必须有 funder
    MissingFunderForProxy,
    /// Funder 地址为零
    ZeroFunderAddress,

    // ===== 解析错误 =====
    /// JSON 解析失败
    JsonParseError,
    /// 无效的十六进制字符串
    InvalidHex,
    /// 无效的十进制数字符串
    InvalidDecimalString,
    /// 无效的 UUID
    InvalidUuid,
    /// 无效的地址
    InvalidAddress,
    /// 无效的地址长度
    InvalidAddressLength,
    /// 无效的十六进制字符
    InvalidHexCharacter,
    /// 无效的 UUID 长度
    InvalidUuidLength,

    // ===== 内部错误 =====
    /// 内存分配失败
    OutOfMemory,
    /// 缓冲区溢出
    BufferOverflow,
    /// 无市场价格
    NoMarketPrice,
};

/// 错误详情（可选使用）
pub const ErrorDetails = struct {
    /// 错误代码
    code: Error,
    /// 错误消息
    message: []const u8,
    /// HTTP 状态码（如果适用）
    http_status: ?u16 = null,
    /// 请求路径（如果适用）
    path: ?[]const u8 = null,
    /// 原始错误消息（来自服务器）
    raw_message: ?[]const u8 = null,

    pub fn format(
        self: ErrorDetails,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Error: {s}", .{@errorName(self.code)});

        if (self.message.len > 0) {
            try writer.print(" - {s}", .{self.message});
        }

        if (self.http_status) |status| {
            try writer.print(" (HTTP {d})", .{status});
        }

        if (self.path) |path| {
            try writer.print(" at {s}", .{path});
        }
    }
};
```

### 3.2 错误辅助函数

```zig
// src/error.zig (续)

/// 从 HTTP 状态码映射到错误
pub fn fromHttpStatus(status: u16) Error {
    return switch (status) {
        400 => Error.BadRequest,
        401 => Error.Unauthorized,
        403 => Error.Geoblocked,
        404 => Error.NotFound,
        429 => Error.RateLimited,
        500 => Error.InternalServerError,
        502 => Error.ServiceUnavailable,
        503 => Error.ServiceUnavailable,
        504 => Error.GatewayTimeout,
        else => Error.UnknownApiError,
    };
}

/// 检查错误是否可重试
pub fn isRetryable(err: Error) bool {
    return switch (err) {
        Error.Timeout,
        Error.ConnectionReset,
        Error.RateLimited,
        Error.ServiceUnavailable,
        Error.GatewayTimeout,
        => true,
        else => false,
    };
}

/// 获取建议的重试延迟（毫秒）
pub fn getRetryDelay(err: Error, attempt: u32) u64 {
    const base_delay: u64 = switch (err) {
        Error.RateLimited => 5000,  // 5 秒
        Error.ServiceUnavailable => 10000,  // 10 秒
        else => 1000,  // 1 秒
    };

    // 指数退避，最大 60 秒
    const multiplier = std.math.pow(u64, 2, attempt);
    return @min(base_delay * multiplier, 60000);
}

/// 获取错误消息
pub fn getMessage(err: Error) []const u8 {
    return switch (err) {
        Error.ConnectionFailed => "Failed to connect to server",
        Error.Timeout => "Request timed out",
        Error.InvalidSignature => "Signature verification failed",
        Error.InvalidCredentials => "API credentials are invalid",
        Error.Unauthorized => "Not authorized to access this resource",
        Error.NonceAlreadyUsed => "Nonce has already been used to create an API key",
        Error.ChainIdNotSet => "Chain ID not set on signer",
        Error.InvalidPrice => "Price is invalid or out of range",
        Error.InvalidSize => "Size is invalid or out of range",
        Error.InvalidTickSize => "Price precision exceeds minimum tick size",
        Error.MissingTokenId => "Token ID is required",
        Error.MissingSide => "Side (buy/sell) is required",
        Error.InsufficientLiquidity => "Not enough liquidity to fill order",
        Error.RateLimited => "Too many requests, please slow down",
        Error.Geoblocked => "Access denied due to geographic restrictions",
        Error.MissingContractConfig => "Contract configuration not found for chain",
        else => "An error occurred",
    };
}
```

---

## 4. 错误处理模式

### 4.1 基本错误处理

```zig
const poly = @import("poly_sdk");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var client = try poly.Client.init(allocator, .{});
    defer client.deinit();

    // 方式 1: 传播错误
    const markets = try client.markets(null);

    // 方式 2: 处理特定错误
    const ok = client.ok() catch |err| {
        switch (err) {
            error.ConnectionFailed => {
                std.log.err("Cannot connect to server", .{});
                return err;
            },
            error.Timeout => {
                std.log.warn("Request timed out, retrying...", .{});
                // 重试逻辑
                return client.ok();
            },
            else => return err,
        }
    };

    std.debug.print("Server status: {s}\n", .{ok});
}
```

### 4.2 重试模式

```zig
/// 带重试的请求执行
fn executeWithRetry(
    comptime F: type,
    func: F,
    max_retries: u32,
) !@typeInfo(F).Fn.return_type.? {
    var attempt: u32 = 0;
    while (true) : (attempt += 1) {
        const result = func() catch |err| {
            if (attempt >= max_retries or !poly.error.isRetryable(err)) {
                return err;
            }

            const delay = poly.error.getRetryDelay(err, attempt);
            std.log.warn(
                "Request failed with {}, retrying in {d}ms (attempt {d}/{d})",
                .{ err, delay, attempt + 1, max_retries },
            );
            std.time.sleep(delay * std.time.ns_per_ms);
            continue;
        };
        return result;
    }
}

// 使用
const markets = try executeWithRetry(
    @TypeOf(client.markets),
    struct {
        fn call() !poly.Page(poly.MarketResponse) {
            return client.markets(null);
        }
    }.call,
    3,
);
```

### 4.3 错误上下文包装

```zig
/// 包装错误并添加上下文
pub fn Context(comptime E: type) type {
    return struct {
        inner: E,
        context: []const u8,
        source_location: ?std.builtin.SourceLocation,

        pub fn wrap(err: E, context: []const u8) @This() {
            return .{
                .inner = err,
                .context = context,
                .source_location = @src(),
            };
        }

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            try writer.print("{s}: {}", .{ self.context, self.inner });

            if (self.source_location) |loc| {
                try writer.print(" at {s}:{d}", .{ loc.file, loc.line });
            }
        }
    };
}

// 使用
fn createOrder(client: *Client, params: OrderParams) !Order {
    const tick_size = client.tickSize(params.token_id) catch |err| {
        return Context(Error).wrap(err, "Failed to fetch tick size");
    };
    // ...
}
```

### 4.4 错误日志记录

```zig
/// 错误日志辅助
pub fn logError(err: anyerror, context: []const u8) void {
    const message = if (@typeInfo(@TypeOf(err)) == .ErrorSet)
        poly.error.getMessage(err)
    else
        "Unknown error";

    std.log.err("{s}: {s} - {}", .{ context, message, err });
}

// 使用
client.postOrder(order) catch |err| {
    logError(err, "Order submission failed");
    return err;
};
```

---

## 5. HTTP 错误映射

### 5.1 状态码映射表

| HTTP 状态码 | 错误类型 | 描述 | 可重试 |
|-------------|----------|------|--------|
| 400 | `BadRequest` | 请求格式错误 | 否 |
| 401 | `Unauthorized` | 未认证或认证失败 | 否 |
| 403 | `Geoblocked` | 地理位置限制 | 否 |
| 404 | `NotFound` | 资源未找到 | 否 |
| 429 | `RateLimited` | 请求频率限制 | 是 |
| 500 | `InternalServerError` | 服务器内部错误 | 是 |
| 502 | `ServiceUnavailable` | 网关错误 | 是 |
| 503 | `ServiceUnavailable` | 服务不可用 | 是 |
| 504 | `GatewayTimeout` | 网关超时 | 是 |

### 5.2 HTTP 响应处理 (Zig 0.15+)

```zig
/// 处理 HTTP 响应 (使用 fetch API)
fn handleFetchResult(
    allocator: std.mem.Allocator,
    result: std.http.Client.FetchResult,
    response_body: []const u8,
) ![]const u8 {
    const status = result.status;

    if (status.class() != .success) {
        const err = poly.error.fromHttpStatus(@intFromEnum(status));

        // 记录错误详情
        std.log.err("API error: HTTP {d} - {s}", .{ @intFromEnum(status), response_body });

        return err;
    }

    // 返回响应体的副本（调用者拥有）
    return try allocator.dupe(u8, response_body);
}

/// 完整的 fetch 示例
fn fetchApi(allocator: std.mem.Allocator, client: *std.http.Client, url: []const u8) ![]const u8 {
    var response_buffer = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer response_buffer.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = url },
        .response_writer = response_buffer.writer(),
    });

    return try handleFetchResult(allocator, result, response_buffer.items);
}
```

### 5.3 API 错误响应解析

```zig
/// API 错误响应结构
pub const ApiErrorResponse = struct {
    error: ?[]const u8 = null,
    message: ?[]const u8 = null,
    code: ?[]const u8 = null,
};

/// 解析 API 错误响应
fn parseApiError(body: []const u8) ?ApiErrorResponse {
    return std.json.parseFromSlice(
        ApiErrorResponse,
        allocator,
        body,
        .{ .ignore_unknown_fields = true },
    ) catch null;
}
```

---

## 6. 用户指南

### 6.1 常见错误及解决方案

#### 连接错误

```zig
error.ConnectionFailed
```

**原因:** 无法连接到 CLOB API 服务器

**解决方案:**
1. 检查网络连接
2. 验证 API 端点是否正确
3. 检查防火墙设置

#### 认证错误

```zig
error.InvalidSignature
```

**原因:** 签名验证失败

**解决方案:**
1. 确保私钥正确
2. 检查链 ID 是否匹配（Polygon: 137, Amoy: 80002）
3. 验证时间戳是否在有效范围内

```zig
error.NonceAlreadyUsed
```

**原因:** 尝试使用已使用的 nonce 创建 API 密钥

**解决方案:**
1. 使用 `deriveApiKey` 恢复现有凭证
2. 使用不同的 nonce 创建新密钥

#### 验证错误

```zig
error.InvalidTickSize
```

**原因:** 价格精度超过市场允许的最小精度

**解决方案:**
1. 调用 `tickSize` 获取市场的最小精度
2. 使用 `truncWithScale` 截断价格

```zig
error.InsufficientLiquidity
```

**原因:** 订单簿中没有足够的流动性来执行市价单

**解决方案:**
1. 减少订单数量
2. 使用 FAK 订单类型允许部分成交
3. 改用限价单

#### 频率限制

```zig
error.RateLimited
```

**原因:** 请求频率超过限制

**解决方案:**
1. 实现请求节流
2. 使用指数退避重试
3. 批量请求以减少调用次数

### 6.2 错误处理最佳实践

```zig
const poly = @import("poly_sdk");

pub fn placeOrder(
    client: *poly.Client(.authenticated),
    params: OrderParams,
) !poly.PostOrderResponse {
    // 1. 预检查
    if (params.size.isZero()) {
        return error.InvalidSize;
    }

    // 2. 获取市场信息（带错误处理）
    const tick_size = client.tickSize(params.token_id) catch |err| {
        std.log.err("Failed to get tick size for {s}: {}", .{ params.token_id, err });
        return err;
    };

    // 3. 验证价格精度
    if (params.price.scale() > tick_size.minimum_tick_size.scale()) {
        std.log.warn(
            "Price precision {d} exceeds tick size {d}, truncating",
            .{ params.price.scale(), tick_size.minimum_tick_size.scale() },
        );
        params.price = params.price.truncWithScale(tick_size.minimum_tick_size.scale());
    }

    // 4. 构建订单
    const order = client.limitOrder()
        .tokenId(params.token_id)
        .price(params.price)
        .size(params.size)
        .side(params.side)
        .build() catch |err| {
            std.log.err("Failed to build order: {}", .{err});
            return err;
        };

    // 5. 签名
    const signed = try client.sign(&signer, order);

    // 6. 提交（带重试）
    var attempts: u32 = 0;
    while (attempts < 3) : (attempts += 1) {
        const response = client.postOrder(signed) catch |err| {
            if (poly.error.isRetryable(err)) {
                const delay = poly.error.getRetryDelay(err, attempts);
                std.log.warn("Order submission failed, retrying in {d}ms", .{delay});
                std.time.sleep(delay * std.time.ns_per_ms);
                continue;
            }
            return err;
        };
        return response[0];
    }

    return error.Timeout;
}
```

### 6.3 调试技巧

```zig
// 启用详细日志
pub const std_options = struct {
    pub const log_level = .debug;
};

// 打印完整错误信息
fn debugError(err: anyerror) void {
    std.debug.print("Error: {}\n", .{err});
    if (@errorReturnTrace()) |trace| {
        std.debug.dumpStackTrace(trace);
    }
}
```
