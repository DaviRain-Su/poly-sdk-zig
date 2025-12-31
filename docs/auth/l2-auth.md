# L2 认证

> L2 级别认证使用 HMAC-SHA256 签名 API 请求，用于所有需要认证的端点。

## 概述

L2 认证是 Polymarket API 的第二级认证，用于：

1. **订单管理** - 创建、取消、查询订单
2. **交易历史** - 查询成交记录
3. **账户信息** - 余额、额度查询
4. **通知管理** - 查看、删除通知

L2 认证使用 HMAC-SHA256 签名，确保请求的完整性和身份验证。

## 认证流程

```
1. 创建 L2Auth 实例
   └── 传入 ApiCreds（API Key, Secret, Passphrase）

2. 构造签名消息
   └── message = timestamp + method + path + body

3. 计算 HMAC-SHA256
   └── mac = HMAC-SHA256(api_secret, message)

4. Base64 编码
   └── signature = Base64(mac)

5. 生成 L2 Header
   └── POLY-API-KEY, POLY-SIGNATURE, POLY-TIMESTAMP, POLY-PASSPHRASE
```

## 快速开始

```zig
const poly = @import("poly-sdk-zig");

// 1. 获取 API 凭证（通常从 L1 认证获取）
var creds = try poly.ApiCreds.fromJson(allocator, json_response);
defer creds.deinit();

// 2. 创建 L2 认证器
const l2 = poly.L2Auth.init(&creds);

// 3. 生成 L2 Header
const header = try l2.generateHeader(.{
    .method = "POST",
    .path = "/order",
    .body = order_json,
});

// 4. 获取 HTTP Headers
const http_headers = header.toHttpHeaders();
// [
//   { "POLY-API-KEY", "your-api-key" },
//   { "POLY-SIGNATURE", "base64-hmac-signature" },
//   { "POLY-TIMESTAMP", "1704067200" },
//   { "POLY-PASSPHRASE", "your-passphrase" }
// ]
```

## API 参考

### L2Auth

```zig
pub const L2Auth = struct {
    creds: *const ApiCreds,

    /// 初始化 L2 认证器
    pub fn init(creds: *const ApiCreds) L2Auth;

    /// 生成 L2 认证 Header
    pub fn generateHeader(self: *const L2Auth, options: L2AuthRequestOptions) L2AuthError!L2PolyHeader;

    /// 使用指定时间戳生成 Header（用于测试）
    pub fn generateHeaderWithTimestamp(
        self: *const L2Auth,
        options: L2AuthRequestOptions,
        timestamp: i64,
    ) L2AuthError!L2PolyHeader;

    /// 获取 API Key
    pub fn getApiKey(self: *const L2Auth) []const u8;

    /// 获取 API Passphrase
    pub fn getApiPassphrase(self: *const L2Auth) []const u8;
};
```

### L2AuthRequestOptions

```zig
pub const L2AuthRequestOptions = struct {
    /// HTTP 方法（大写，如 "GET", "POST", "DELETE"）
    method: []const u8,
    /// 请求路径（如 "/order", "/data/orders"）
    path: []const u8,
    /// 请求体（可选，用于 POST/PUT 请求）
    body: ?[]const u8 = null,
};
```

### L2PolyHeader

```zig
pub const L2PolyHeader = struct {
    poly_api_key: []const u8,
    poly_signature: [44]u8,
    poly_timestamp: [20]u8,
    poly_passphrase: []const u8,

    /// 获取 API Key
    pub fn getApiKey(self: *const L2PolyHeader) []const u8;

    /// 获取签名
    pub fn getSignature(self: *const L2PolyHeader) []const u8;

    /// 获取时间戳
    pub fn getTimestamp(self: *const L2PolyHeader) []const u8;

    /// 获取 passphrase
    pub fn getPassphrase(self: *const L2PolyHeader) []const u8;

    /// 转换为 HTTP Header 数组
    pub fn toHttpHeaders(self: *const L2PolyHeader) [4]std.http.Header;
};
```

## HMAC-SHA256 签名算法

### 签名消息格式

```
message = timestamp + method + path + body
```

### 示例

```
timestamp = "1704067200"
method = "POST"
path = "/order"
body = '{"tokenId":"123","side":"BUY"}'

message = "1704067200POST/order{\"tokenId\":\"123\",\"side\":\"BUY\"}"
```

### 签名计算

```zig
const hmac = poly.crypto.hmac;

// 1. 构造消息
const message = "1704067200POST/order{\"tokenId\":\"123\"}";

// 2. 计算 HMAC
const mac = hmac.hmacSha256(api_secret, message);

// 3. Base64 编码
var sig_buf: [44]u8 = undefined;
const signature = hmac.toBase64(&mac, &sig_buf);
```

## 使用 L2 认证的端点

| 类别 | 端点 | 方法 |
|------|------|------|
| API Key | `/auth/api-keys` | GET |
| API Key | `/auth/api-key` | DELETE |
| 订单 | `/order` | POST |
| 订单 | `/orders` | POST |
| 订单 | `/data/orders` | GET |
| 订单 | `/data/order/{id}` | GET |
| 订单 | `/order` | DELETE |
| 订单 | `/orders` | DELETE |
| 订单 | `/cancel-all` | DELETE |
| 交易 | `/data/trades` | GET |
| 账户 | `/balance-allowance` | GET |
| 通知 | `/notifications` | GET/DELETE |

## 错误处理

| HTTP 状态码 | 错误描述 | 处理方式 |
|------------|---------|---------|
| 401 | 签名无效 | 检查 HMAC 计算 |
| 401 | 时间戳过期 | 同步服务器时间 |
| 401 | API Key 无效 | 重新获取 API Key |

## 示例：完整流程

```zig
const std = @import("std");
const poly = @import("poly-sdk-zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 创建 API 凭证
    var creds = try poly.ApiCreds.init(
        allocator,
        "your-api-key",
        "your-api-secret",
        "your-passphrase",
    );
    defer creds.deinit();

    // 2. 创建 L2 认证器
    const l2 = poly.L2Auth.init(&creds);

    // 3. 生成 GET 请求的 Header
    {
        const header = try l2.generateHeader(.{
            .method = "GET",
            .path = "/data/orders",
            .body = null,
        });

        std.debug.print("GET /data/orders\n", .{});
        const http_headers = header.toHttpHeaders();
        for (http_headers) |h| {
            std.debug.print("  {s}: {s}\n", .{ h.name, h.value });
        }
    }

    // 4. 生成 POST 请求的 Header
    {
        const body = "{\"tokenId\":\"123\",\"side\":\"BUY\"}";
        const header = try l2.generateHeader(.{
            .method = "POST",
            .path = "/order",
            .body = body,
        });

        std.debug.print("\nPOST /order\n", .{});
        const http_headers = header.toHttpHeaders();
        for (http_headers) |h| {
            std.debug.print("  {s}: {s}\n", .{ h.name, h.value });
        }
    }
}
```

## 安全注意事项

1. **时间戳**: 服务器接受一定范围内的时间戳，过期请求会被拒绝
2. **API Secret**: 使用 `Secret` 类型保护，防止日志泄露
3. **消息顺序**: 签名消息的各部分顺序是固定的：timestamp + method + path + body
4. **空 body**: 当请求没有 body 时，签名消息中不包含 body 部分
5. **大小写**: HTTP 方法必须是大写（GET, POST, DELETE 等）

## 与 L1 认证的区别

| 特性 | L1 认证 | L2 认证 |
|------|---------|---------|
| 签名算法 | EIP-712 | HMAC-SHA256 |
| 用途 | API Key 管理 | 常规 API 请求 |
| 需要钱包 | 是 | 否 |
| 需要 API 凭证 | 否 | 是 |
| Header 内容 | 地址+签名+时间戳+nonce | API Key+签名+时间戳+passphrase |

## 相关链接

- [HMAC - Wikipedia](https://en.wikipedia.org/wiki/HMAC)
- [Polymarket API 文档](https://docs.polymarket.com/)
- [v0.2-l2-auth Story](../../stories/v0.2-l2-auth.md)
- [L1 认证文档](l1-auth.md)
