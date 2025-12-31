# 认证流程设计文档

本文档详细描述 Polymarket Zig CLOB Client SDK 的认证机制设计。

## 目录

- [1. 认证概述](#1-认证概述)
- [2. L1 认证](#2-l1-认证)
- [3. L2 认证](#3-l2-认证)
- [4. Builder 认证](#4-builder-认证)
- [5. 签名类型](#5-签名类型)
- [6. 实现细节](#6-实现细节)
- [7. 安全考虑](#7-安全考虑)

---

## 1. 认证概述

Polymarket CLOB API 使用两级认证机制：

```
┌─────────────────────────────────────────────────────────────────────┐
│                        认证层次结构                                  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                    L1 认证 (私钥签名)                        │   │
│   │                                                              │   │
│   │   用途: 创建/派生 API 凭证                                   │   │
│   │   机制: EIP-712 签名                                         │   │
│   │   安全级别: 最高                                             │   │
│   └──────────────────────────┬──────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │                    L2 认证 (API 凭证)                        │   │
│   │                                                              │   │
│   │   用途: 日常 API 请求认证                                    │   │
│   │   机制: HMAC-SHA256 签名                                     │   │
│   │   安全级别: 中等                                             │   │
│   └──────────────────────────┬──────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│   ┌─────────────────────────────────────────────────────────────┐   │
│   │               Builder 认证 (可选，L2 扩展)                   │   │
│   │                                                              │   │
│   │   用途: Builder 程序专用 API                                 │   │
│   │   机制: 额外 HMAC 头 + L2                                    │   │
│   │   安全级别: 中等                                             │   │
│   └─────────────────────────────────────────────────────────────┘   │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 1.1 认证级别对比

| 特性 | L1 认证 | L2 认证 | Builder 认证 |
|------|---------|---------|--------------|
| 需要私钥 | 是 | 否 | 否 |
| 需要 API 凭证 | 否 | 是 | 是 |
| 签名机制 | EIP-712 | HMAC-SHA256 | HMAC-SHA256 |
| 用途 | 获取凭证 | API 调用 | Builder API |
| 安全级别 | 高 | 中 | 中 |

### 1.2 凭证结构

```zig
pub const Credentials = struct {
    /// API 密钥 (UUID)
    key: Uuid,
    
    /// 用于 HMAC 签名的密钥 (Base64 编码)
    secret: Secret([]const u8),
    
    /// 附加在请求头中的口令
    passphrase: Secret([]const u8),
};
```

---

## 2. L1 认证

### 2.1 概述

L1 认证使用钱包私钥签署 EIP-712 结构化消息，证明用户对钱包的控制权。

### 2.2 EIP-712 消息结构

```zig
/// ClobAuth EIP-712 结构
pub const ClobAuth = struct {
    /// 签名者地址
    address: Address,
    /// 时间戳 (字符串格式)
    timestamp: []const u8,
    /// Nonce 值 (用于区分不同的 API 密钥)
    nonce: u256,
    /// 固定消息
    message: []const u8,
};

/// EIP-712 域
pub const ClobAuthDomain = struct {
    name: []const u8 = "ClobAuthDomain",
    version: []const u8 = "1",
    chain_id: u256,
};
```

### 2.3 L1 认证头

| 头名称 | 描述 | 示例 |
|--------|------|------|
| `POLY_ADDRESS` | 签名者地址 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| `POLY_SIGNATURE` | EIP-712 签名 | `0x1234...` |
| `POLY_TIMESTAMP` | Unix 时间戳 | `1704067200` |
| `POLY_NONCE` | Nonce 值 | `0` |

### 2.4 实现

```zig
// src/auth/l1.zig

const std = @import("std");
const crypto = @import("../crypto/mod.zig");
const types = @import("../types/mod.zig");

pub const L1Headers = struct {
    poly_address: []const u8,
    poly_signature: []const u8,
    poly_timestamp: []const u8,
    poly_nonce: []const u8,

    pub fn deinit(self: *L1Headers, allocator: std.mem.Allocator) void {
        allocator.free(self.poly_address);
        allocator.free(self.poly_signature);
        allocator.free(self.poly_timestamp);
        allocator.free(self.poly_nonce);
    }
};

/// 创建 L1 认证头
pub fn createHeaders(
    allocator: std.mem.Allocator,
    signer: anytype,
    chain_id: u64,
    timestamp: i64,
    nonce: ?u32,
) !L1Headers {
    const naive_nonce = nonce orelse 0;

    // 构建 ClobAuth 结构
    const auth = ClobAuth{
        .address = signer.address(),
        .timestamp = try std.fmt.allocPrint(allocator, "{d}", .{timestamp}),
        .nonce = @as(u256, naive_nonce),
        .message = "This message attests that I control the given wallet",
    };
    defer allocator.free(auth.timestamp);

    // 构建域
    const domain = crypto.Eip712Domain{
        .name = "ClobAuthDomain",
        .version = "1",
        .chain_id = chain_id,
    };

    // 计算签名哈希
    const hash = computeSigningHash(auth, domain);

    // 签名
    const signature = try signer.signHash(hash);

    // 构建头
    return L1Headers{
        .poly_address = try types.address.toHex(signer.address(), allocator),
        .poly_signature = try formatSignature(allocator, signature),
        .poly_timestamp = try std.fmt.allocPrint(allocator, "{d}", .{timestamp}),
        .poly_nonce = try std.fmt.allocPrint(allocator, "{d}", .{naive_nonce}),
    };
}

const ClobAuth = struct {
    address: types.Address,
    timestamp: []const u8,
    nonce: u256,
    message: []const u8,

    /// EIP-712 类型哈希
    pub fn typeHash() [32]u8 {
        const type_string = "ClobAuth(address address,string timestamp,uint256 nonce,string message)";
        var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
        hasher.update(type_string);
        return hasher.finalResult();
    }

    /// 计算结构哈希
    pub fn structHash(self: ClobAuth) [32]u8 {
        var hasher = std.crypto.hash.sha3.Keccak256.init(.{});

        // 类型哈希
        hasher.update(&typeHash());

        // address (左填充到 32 字节)
        var addr_padded: [32]u8 = [_]u8{0} ** 32;
        @memcpy(addr_padded[12..32], &self.address);
        hasher.update(&addr_padded);

        // timestamp (keccak256 of string)
        var ts_hasher = std.crypto.hash.sha3.Keccak256.init(.{});
        ts_hasher.update(self.timestamp);
        hasher.update(&ts_hasher.finalResult());

        // nonce (大端 32 字节)
        var nonce_bytes: [32]u8 = undefined;
        std.mem.writeInt(u256, &nonce_bytes, self.nonce, .big);
        hasher.update(&nonce_bytes);

        // message (keccak256 of string)
        var msg_hasher = std.crypto.hash.sha3.Keccak256.init(.{});
        msg_hasher.update(self.message);
        hasher.update(&msg_hasher.finalResult());

        return hasher.finalResult();
    }
};

fn computeSigningHash(auth: ClobAuth, domain: crypto.Eip712Domain) [32]u8 {
    var hasher = std.crypto.hash.sha3.Keccak256.init(.{});
    hasher.update(&[_]u8{ 0x19, 0x01 });
    hasher.update(&domain.structHash());
    hasher.update(&auth.structHash());
    return hasher.finalResult();
}

fn formatSignature(allocator: std.mem.Allocator, sig: [65]u8) ![]u8 {
    var result = try allocator.alloc(u8, 132); // "0x" + 130 hex chars
    result[0] = '0';
    result[1] = 'x';

    const hex = "0123456789abcdef";
    for (sig, 0..) |byte, i| {
        result[2 + i * 2] = hex[byte >> 4];
        result[2 + i * 2 + 1] = hex[byte & 0x0F];
    }

    return result;
}
```

### 2.5 L1 API 端点

| 端点 | 方法 | 描述 |
|------|------|------|
| `/auth/api-key` | POST | 创建新的 API 凭证 |
| `/auth/derive-api-key` | GET | 派生现有 API 凭证 |

---

## 3. L2 认证

### 3.1 概述

L2 认证使用 API 凭证（从 L1 获取）通过 HMAC-SHA256 签署请求。

### 3.2 签名消息格式

```
{timestamp}{method}{path}{body}
```

示例：
```
1704067200GET/data/orders
1704067200POST/orders{"order":...}
```

### 3.3 L2 认证头

| 头名称 | 描述 | 示例 |
|--------|------|------|
| `POLY_ADDRESS` | 签名者地址 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` |
| `POLY_API_KEY` | API 密钥 | `550e8400-e29b-41d4-a716-446655440000` |
| `POLY_PASSPHRASE` | 口令 | `randomPassphraseString` |
| `POLY_SIGNATURE` | HMAC 签名 | `eHaylCwqRSOa2LFD77Nt_SaTpbsxzN8eTEI3LryhEj4=` |
| `POLY_TIMESTAMP` | Unix 时间戳 | `1704067200` |

### 3.4 实现

```zig
// src/auth/l2.zig

const std = @import("std");
const base64 = std.base64;
const types = @import("../types/mod.zig");
const Credentials = @import("credentials.zig").Credentials;

pub const L2Headers = struct {
    poly_address: []const u8,
    poly_api_key: []const u8,
    poly_passphrase: []const u8,
    poly_signature: []const u8,
    poly_timestamp: []const u8,

    pub fn deinit(self: *L2Headers, allocator: std.mem.Allocator) void {
        allocator.free(self.poly_address);
        allocator.free(self.poly_api_key);
        // passphrase 是 credentials 的引用，不需要释放
        allocator.free(self.poly_signature);
        allocator.free(self.poly_timestamp);
    }

    /// 转换为 HTTP 头格式
    pub fn toHttpHeaders(self: L2Headers) [5][2][]const u8 {
        return .{
            .{ "POLY_ADDRESS", self.poly_address },
            .{ "POLY_API_KEY", self.poly_api_key },
            .{ "POLY_PASSPHRASE", self.poly_passphrase },
            .{ "POLY_SIGNATURE", self.poly_signature },
            .{ "POLY_TIMESTAMP", self.poly_timestamp },
        };
    }
};

pub const Request = struct {
    method: []const u8,
    path: []const u8,
    body: ?[]const u8,
};

/// 创建 L2 认证头
pub fn createHeaders(
    allocator: std.mem.Allocator,
    credentials: Credentials,
    address: types.Address,
    request: Request,
    timestamp: i64,
) !L2Headers {
    // 构建签名消息
    const message = try buildMessage(allocator, request, timestamp);
    defer allocator.free(message);

    // HMAC 签名
    const signature = try hmacSign(allocator, credentials.secret.reveal(), message);

    return L2Headers{
        .poly_address = try types.address.toHex(address, allocator),
        .poly_api_key = try credentials.key.toString(allocator),
        .poly_passphrase = credentials.passphrase.reveal(),
        .poly_signature = signature,
        .poly_timestamp = try std.fmt.allocPrint(allocator, "{d}", .{timestamp}),
    };
}

/// 构建签名消息
fn buildMessage(allocator: std.mem.Allocator, request: Request, timestamp: i64) ![]u8 {
    const body = request.body orelse "";
    return std.fmt.allocPrint(
        allocator,
        "{d}{s}{s}{s}",
        .{ timestamp, request.method, request.path, body },
    );
}

/// HMAC-SHA256 签名
fn hmacSign(allocator: std.mem.Allocator, secret: []const u8, message: []const u8) ![]u8 {
    // Base64 URL-safe 解码密钥
    const decoder = base64.url_safe.Decoder;
    var decoded_secret: [64]u8 = undefined;
    const decoded_len = try decoder.calcSizeForSlice(secret);
    try decoder.decode(decoded_secret[0..decoded_len], secret);

    // HMAC-SHA256
    var mac: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&mac, message, decoded_secret[0..decoded_len]);

    // Base64 URL-safe 编码结果
    const encoder = base64.url_safe.Encoder;
    const encoded_len = encoder.calcSize(32);
    var result = try allocator.alloc(u8, encoded_len);
    _ = encoder.encode(result, &mac);

    return result;
}

test "l2 message building" {
    const allocator = std.testing.allocator;
    const request = Request{
        .method = "GET",
        .path = "/orders",
        .body = null,
    };
    const message = try buildMessage(allocator, request, 1);
    defer allocator.free(message);
    try std.testing.expectEqualStrings("1GET/orders", message);
}

test "l2 message with body" {
    const allocator = std.testing.allocator;
    const request = Request{
        .method = "POST",
        .path = "/orders",
        .body = "{\"foo\":\"bar\"}",
    };
    const message = try buildMessage(allocator, request, 1000000);
    defer allocator.free(message);
    try std.testing.expectEqualStrings("1000000POST/orders{\"foo\":\"bar\"}", message);
}
```

---

## 4. Builder 认证

### 4.1 概述

Builder 认证是 L2 认证的扩展，用于 Polymarket Builder 程序的特殊 API 访问。

### 4.2 Builder 认证头

在 L2 头基础上添加：

| 头名称 | 描述 |
|--------|------|
| `POLY_BUILDER_API_KEY` | Builder API 密钥 |
| `POLY_BUILDER_PASSPHRASE` | Builder 口令 |
| `POLY_BUILDER_SIGNATURE` | Builder HMAC 签名 |
| `POLY_BUILDER_TIMESTAMP` | 时间戳 |

### 4.3 配置类型

```zig
/// Builder 认证配置
pub const BuilderConfig = union(enum) {
    /// 本地配置：使用本地存储的 Builder 凭证
    local: Credentials,
    
    /// 远程配置：从签名服务器获取签名
    remote: struct {
        host: []const u8,
        token: ?[]const u8,
    },
};
```

### 4.4 实现

```zig
// src/auth/builder.zig

const std = @import("std");
const l2 = @import("l2.zig");
const types = @import("../types/mod.zig");
const Credentials = @import("credentials.zig").Credentials;

pub const BuilderConfig = union(enum) {
    local: Credentials,
    remote: struct {
        host: []const u8,
        token: ?[]const u8,
    },
};

pub const BuilderHeaders = struct {
    poly_builder_api_key: []const u8,
    poly_builder_passphrase: []const u8,
    poly_builder_signature: []const u8,
    poly_builder_timestamp: []const u8,

    pub fn deinit(self: *BuilderHeaders, allocator: std.mem.Allocator) void {
        allocator.free(self.poly_builder_api_key);
        allocator.free(self.poly_builder_signature);
        allocator.free(self.poly_builder_timestamp);
    }
};

/// 创建 Builder 认证头
pub fn createHeaders(
    allocator: std.mem.Allocator,
    config: BuilderConfig,
    request: l2.Request,
    timestamp: i64,
) !BuilderHeaders {
    switch (config) {
        .local => |credentials| {
            return createLocalHeaders(allocator, credentials, request, timestamp);
        },
        .remote => |remote_config| {
            return createRemoteHeaders(allocator, remote_config, request, timestamp);
        },
    }
}

fn createLocalHeaders(
    allocator: std.mem.Allocator,
    credentials: Credentials,
    request: l2.Request,
    timestamp: i64,
) !BuilderHeaders {
    const message = try l2.buildMessage(allocator, request, timestamp);
    defer allocator.free(message);

    const signature = try l2.hmacSign(allocator, credentials.secret.reveal(), message);

    return BuilderHeaders{
        .poly_builder_api_key = try credentials.key.toString(allocator),
        .poly_builder_passphrase = credentials.passphrase.reveal(),
        .poly_builder_signature = signature,
        .poly_builder_timestamp = try std.fmt.allocPrint(allocator, "{d}", .{timestamp}),
    };
}

fn createRemoteHeaders(
    allocator: std.mem.Allocator,
    config: struct { host: []const u8, token: ?[]const u8 },
    request_info: l2.Request,
    timestamp: i64,
) !BuilderHeaders {
    // 构建请求体
    const payload = .{
        .method = request_info.method,
        .path = request_info.path,
        .body = request_info.body orelse "",
        .timestamp = timestamp,
    };

    const json_body = try std.json.stringifyAlloc(allocator, payload, .{});
    defer allocator.free(json_body);

    // Zig 0.15: HTTP Client API
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    // 构建额外的 headers
    var extra_headers_list = try std.ArrayList(std.http.Header).initCapacity(allocator, 2);
    defer extra_headers_list.deinit();

    try extra_headers_list.append(allocator, .{ 
        .name = "Content-Type", 
        .value = "application/json" 
    });

    if (config.token) |token| {
        const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
        defer allocator.free(auth_value);
        try extra_headers_list.append(allocator, .{ 
            .name = "Authorization", 
            .value = auth_value 
        });
    }

    // 使用 fetch API (Zig 0.15)
    var response_buffer = try std.ArrayList(u8).initCapacity(allocator, 4096);
    defer response_buffer.deinit();

    const result = try client.fetch(.{
        .location = .{ .url = config.host },
        .method = .POST,
        .extra_headers = extra_headers_list.items,
        .payload = json_body,
        .response_writer = response_buffer.writer(),
    });

    if (result.status != .ok) {
        return error.RemoteSigningFailed;
    }

    // 解析响应
    const response = try std.json.parseFromSlice(
        struct {
            poly_builder_api_key: []const u8,
            poly_builder_timestamp: []const u8,
            poly_builder_passphrase: []const u8,
            poly_builder_signature: []const u8,
        },
        allocator,
        response_buffer.items,
        .{},
    );
    defer response.deinit();

    return BuilderHeaders{
        .poly_builder_api_key = try allocator.dupe(u8, response.value.poly_builder_api_key),
        .poly_builder_passphrase = response.value.poly_builder_passphrase,
        .poly_builder_signature = try allocator.dupe(u8, response.value.poly_builder_signature),
        .poly_builder_timestamp = try allocator.dupe(u8, response.value.poly_builder_timestamp),
    };
}
```

---

## 5. 签名类型

### 5.1 概述

不同类型的钱包需要不同的签名处理方式。

### 5.2 签名类型定义

```zig
pub const SignatureType = enum(u8) {
    /// EOA (Externally Owned Account)
    /// 标准以太坊钱包，如 MetaMask、硬件钱包
    /// 用户直接控制私钥
    eoa = 0,

    /// Proxy/Magic 钱包
    /// 通过 Magic Link 或 Email 登录的用户
    /// 使用委托签名
    proxy = 1,

    /// Gnosis Safe 多签钱包
    /// 使用代理合约
    gnosis_safe = 2,
};
```

### 5.3 Funder 地址

对于 Proxy 和 Gnosis Safe 钱包，`funder` 地址是持有资金的实际地址（在 Polymarket 上显示的地址），而签名地址可能不同。

```zig
/// 验证 funder 和 signature_type 的组合
fn validateFunderAndSignatureType(
    funder: ?types.Address,
    signature_type: SignatureType,
) !void {
    switch (signature_type) {
        .eoa => {
            // EOA 不能有 funder
            if (funder != null) {
                return error.InvalidFunderWithEoa;
            }
        },
        .proxy, .gnosis_safe => {
            // Proxy/Safe 必须有 funder
            if (funder == null) {
                return error.MissingFunderForProxy;
            }
            // funder 不能是零地址
            if (std.mem.eql(u8, &funder.?, &types.ZERO_ADDRESS)) {
                return error.ZeroFunderAddress;
            }
        },
    }
}
```

### 5.4 使用场景

| 钱包类型 | SignatureType | 需要 Funder | 说明 |
|----------|---------------|-------------|------|
| MetaMask | `eoa` | 否 | 直接使用私钥签名 |
| 硬件钱包 | `eoa` | 否 | 直接使用私钥签名 |
| Magic/Email | `proxy` | 是 | 导出私钥后使用 |
| Gnosis Safe | `gnosis_safe` | 是 | 多签代理钱包 |

---

## 6. 实现细节

### 6.1 完整认证流程

```zig
// 认证流程示例

// 1. 创建未认证客户端
var client = try Client(.unauthenticated).init(allocator, .{});

// 2. 创建签名器
var signer = try LocalSigner.fromHex(private_key);
signer = signer.withChainId(137);  // Polygon

// 3. 认证 (L1 -> L2)
var auth_client = try client.authenticate(&signer, .{
    .signature_type = .eoa,
});

// 内部流程:
// a. 验证链 ID
// b. 验证 funder/signature_type 组合
// c. 使用 L1 认证获取 Credentials
//    - 构建 ClobAuth EIP-712 消息
//    - 签名
//    - POST /auth/api-key 或 GET /auth/derive-api-key
// d. 创建 Authenticated 状态的客户端

// 4. 使用 L2 认证进行 API 调用
const orders = try auth_client.orders(.{}, null);

// 内部流程:
// a. 构建签名消息: "{timestamp}{method}{path}{body}"
// b. HMAC-SHA256 签名
// c. 添加 L2 头
// d. 发送请求
```

### 6.2 凭证管理

```zig
// src/auth/credentials.zig

const std = @import("std");
const types = @import("../types/mod.zig");

pub const Credentials = struct {
    key: types.Uuid,
    secret: types.Secret([]const u8),
    passphrase: types.Secret([]const u8),

    /// 从 JSON 解析
    pub fn fromJson(allocator: std.mem.Allocator, json: []const u8) !Credentials {
        const parsed = try std.json.parseFromSlice(
            struct {
                apiKey: []const u8,
                secret: []const u8,
                passphrase: []const u8,
            },
            allocator,
            json,
            .{},
        );
        defer parsed.deinit();

        return Credentials{
            .key = try types.Uuid.fromString(parsed.value.apiKey),
            .secret = types.Secret([]const u8).init(try allocator.dupe(u8, parsed.value.secret)),
            .passphrase = types.Secret([]const u8).init(try allocator.dupe(u8, parsed.value.passphrase)),
        };
    }

    /// 序列化为 JSON
    pub fn toJson(self: Credentials, allocator: std.mem.Allocator) ![]u8 {
        return std.json.stringifyAlloc(allocator, .{
            .apiKey = try self.key.toString(allocator),
            .secret = self.secret.reveal(),
            .passphrase = self.passphrase.reveal(),
        }, .{});
    }

    /// 安全清零
    pub fn zeroize(self: *Credentials) void {
        self.secret.zeroize();
        self.passphrase.zeroize();
    }
};
```

### 6.3 时间戳处理

```zig
/// 获取认证用时间戳
fn getTimestamp(self: *Client, config: Config) !i64 {
    if (config.use_server_time) {
        // 使用服务器时间（更准确但增加延迟）
        return self.serverTime();
    } else {
        // 使用本地时间
        return std.time.timestamp();
    }
}
```

---

## 7. 安全考虑

### 7.1 私钥保护

```zig
// 不要这样做！
std.debug.print("Private key: {s}\n", .{private_key});  // 危险！

// 使用 Secret 类型包装
const secret = types.Secret([]const u8).init(private_key);
std.debug.print("Secret: {}\n", .{secret});  // 输出: "[REDACTED]"
```

### 7.2 凭证存储建议

1. **不要硬编码**：使用环境变量或安全存储
2. **加密存储**：如果需要持久化，使用加密
3. **最小权限**：只存储必要的凭证
4. **定期轮换**：定期更新 API 凭证

### 7.3 网络安全

1. **强制 HTTPS**：所有 API 调用使用 HTTPS
2. **证书验证**：验证 TLS 证书
3. **时间戳验证**：防止重放攻击

### 7.4 错误处理

```zig
// 不要泄露敏感信息
fn handleAuthError(err: anyerror) void {
    switch (err) {
        error.InvalidSignature => {
            std.log.err("Authentication failed: invalid signature", .{});
            // 不要: std.log.err("Signature was: {s}", .{signature});
        },
        error.InvalidCredentials => {
            std.log.err("Authentication failed: invalid credentials", .{});
            // 不要: std.log.err("API key was: {s}", .{api_key});
        },
        else => {
            std.log.err("Authentication failed: {}", .{err});
        },
    }
}
```

### 7.5 Nonce 管理

```zig
/// Nonce 用于区分同一地址的不同 API 密钥
/// 
/// 使用场景:
/// - 默认 nonce = 0 用于主密钥
/// - nonce = 1, 2, ... 用于额外的密钥
/// 
/// 注意:
/// - 同一 nonce 只能创建一次密钥
/// - 使用 deriveApiKey 可以恢复已创建的密钥
/// - 丢失 nonce 将无法恢复对应的密钥
```
