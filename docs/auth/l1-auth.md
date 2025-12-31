# L1 认证

> L1 级别认证使用 EIP-712 签名验证钱包所有权，用于 API Key 管理。

## 概述

L1 认证是 Polymarket API 的第一级认证，主要用于：

1. **创建 API Key** - 为新钱包创建 API 凭证
2. **派生 API Key** - 获取现有钱包的 API 凭证

L1 认证使用 EIP-712 结构化数据签名，证明请求者拥有钱包的私钥。

## 认证流程

```
1. 创建 L1Auth 实例
   └── 传入 Wallet 和 chain_id

2. 生成 L1 Header
   ├── 构造 ClobAuth EIP-712 消息
   ├── 计算签名摘要
   └── 使用私钥签名

3. 发送 API 请求
   └── 附加 L1 Header（POLY-ADDRESS, POLY-SIGNATURE, POLY-TIMESTAMP, POLY-NONCE）

4. 服务器验证
   ├── 验证时间戳在有效范围内（±30秒）
   ├── 验证 nonce 未被使用
   └── 验证签名来自声明的地址
```

## 快速开始

```zig
const poly = @import("poly-sdk-zig");

// 1. 创建钱包
const wallet = try poly.Wallet.fromPrivateKeyHex("0x...");

// 2. 创建 L1 认证器
const l1 = poly.L1Auth.init(&wallet, .{
    .chain_id = 137,  // Polygon mainnet
});

// 3. 生成 L1 Header
const header = try l1.generateHeader();

// 4. 获取 HTTP Headers
const http_headers = header.toHttpHeaders();
// [
//   { "POLY-ADDRESS", "0x..." },
//   { "POLY-SIGNATURE", "0x..." },
//   { "POLY-TIMESTAMP", "1704067200" },
//   { "POLY-NONCE", "12345" }
// ]
```

## API 参考

### L1Auth

```zig
pub const L1Auth = struct {
    wallet: *const Wallet,
    chain_id: u64,

    /// 初始化 L1 认证器
    pub fn init(wallet: *const Wallet, options: L1AuthOptions) L1Auth;

    /// 生成 L1 认证 Header
    pub fn generateHeader(self: *const L1Auth) L1AuthError!L1PolyHeader;

    /// 使用指定 nonce 生成 Header（用于测试）
    pub fn generateHeaderWithNonce(self: *const L1Auth, nonce: u256) L1AuthError!L1PolyHeader;

    /// 获取链 ID
    pub fn getChainId(self: *const L1Auth) u64;

    /// 获取钱包地址
    pub fn getAddress(self: *const L1Auth) [42]u8;
};
```

### L1AuthOptions

```zig
pub const L1AuthOptions = struct {
    /// 链 ID（137 = Polygon mainnet, 80002 = Amoy testnet）
    chain_id: u64 = 137,
};
```

### L1PolyHeader

```zig
pub const L1PolyHeader = struct {
    poly_address: [42]u8,      // 钱包地址
    poly_signature: [132]u8,   // EIP-712 签名
    poly_timestamp: [20]u8,    // Unix 时间戳
    poly_nonce: [20]u8,        // 随机 nonce

    /// 获取地址字符串
    pub fn getAddress(self: *const L1PolyHeader) []const u8;

    /// 获取签名字符串
    pub fn getSignature(self: *const L1PolyHeader) []const u8;

    /// 获取时间戳字符串
    pub fn getTimestamp(self: *const L1PolyHeader) []const u8;

    /// 获取 nonce 字符串
    pub fn getNonce(self: *const L1PolyHeader) []const u8;

    /// 转换为 HTTP Header 数组
    pub fn toHttpHeaders(self: *const L1PolyHeader) [4]std.http.Header;
};
```

### ApiCreds

```zig
pub const ApiCreds = struct {
    api_key: []const u8,
    api_secret: Secret([]const u8),
    api_passphrase: Secret([]const u8),

    /// 从 JSON 响应解析
    pub fn fromJson(allocator: Allocator, json_str: []const u8) !ApiCreds;

    /// 手动构造
    pub fn init(allocator: Allocator, key: []const u8, secret: []const u8, passphrase: []const u8) !ApiCreds;

    /// 释放资源（会先清零敏感数据）
    pub fn deinit(self: *ApiCreds) void;

    /// 安全清零敏感数据
    pub fn zeroize(self: *ApiCreds) void;
};
```

## EIP-712 消息结构

L1 认证使用以下 EIP-712 消息结构：

### 域（Domain）

```javascript
{
    name: "ClobAuthDomain",
    version: "1",
    chainId: 137  // 或 80002 (Amoy)
}
```

### 类型（Types）

```javascript
{
    ClobAuth: [
        { name: "address", type: "address" },
        { name: "timestamp", type: "string" },
        { name: "nonce", type: "uint256" },
        { name: "message", type: "string" }
    ]
}
```

### 消息（Message）

```javascript
{
    address: "0x...",  // 钱包地址
    timestamp: "1704067200",  // Unix 时间戳（秒）
    nonce: 12345,  // 随机 nonce
    message: "This message attests that I control the given wallet"
}
```

## API 端点

### 创建 API Key

**端点**: `POST /auth/api-key`

**请求头**:
```http
POLY-ADDRESS: 0x1234567890123456789012345678901234567890
POLY-SIGNATURE: 0x...
POLY-TIMESTAMP: 1704067200
POLY-NONCE: 12345
```

**响应**:
```json
{
    "apiKey": "your-api-key",
    "secret": "your-api-secret",
    "passphrase": "your-passphrase"
}
```

### 派生 API Key

**端点**: `GET /auth/derive-api-key`

**请求头**: 同上

**响应**: 同上

## 错误处理

| HTTP 状态码 | 错误描述 | 处理方式 |
|------------|---------|---------|
| 400 | 签名无效 | 检查 EIP-712 签名流程 |
| 401 | 认证失败 | 检查地址匹配 |
| 409 | API Key 已存在 | 使用 `derive` 代替 `create` |

## 链 ID

| 网络 | Chain ID | 用途 |
|------|----------|------|
| Polygon Mainnet | 137 | 生产环境 |
| Polygon Amoy | 80002 | 测试环境 |

## 安全注意事项

1. **时间戳**: 服务器接受 ±30 秒范围内的时间戳
2. **Nonce**: 用于防止重放攻击，每个请求应使用唯一 nonce
3. **API 凭证**: `api_secret` 和 `api_passphrase` 使用 `Secret` 类型保护，防止日志泄露
4. **内存清理**: 调用 `ApiCreds.deinit()` 会先清零敏感数据再释放内存

## 示例：完整流程

```zig
const std = @import("std");
const poly = @import("poly-sdk-zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // 1. 创建钱包
    const wallet = try poly.Wallet.fromPrivateKeyHex(
        "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318"
    );

    // 2. 创建 L1 认证器
    const l1 = poly.L1Auth.init(&wallet, .{ .chain_id = 137 });

    // 3. 生成 L1 Header
    const header = try l1.generateHeader();

    // 4. 打印 Header
    std.debug.print("Address: {s}\n", .{header.getAddress()});
    std.debug.print("Timestamp: {s}\n", .{header.getTimestamp()});
    std.debug.print("Nonce: {s}\n", .{header.getNonce()});

    // 5. 使用 HTTP Headers（示例）
    const http_headers = header.toHttpHeaders();
    for (http_headers) |h| {
        std.debug.print("{s}: {s}\n", .{ h.name, h.value });
    }

    // 6. 解析 API 响应
    const json_response =
        \\{"apiKey":"test-key","secret":"test-secret","passphrase":"test-pass"}
    ;
    var creds = try poly.ApiCreds.fromJson(allocator, json_response);
    defer creds.deinit();

    std.debug.print("API Key: {s}\n", .{creds.getApiKey()});
}
```

## 相关链接

- [EIP-712: Typed structured data hashing and signing](https://eips.ethereum.org/EIPS/eip-712)
- [Polymarket API 文档](https://docs.polymarket.com/)
- [v0.2-l1-auth Story](../../stories/v0.2-l1-auth.md)
