# HMAC-SHA256 消息认证

> 用于 L2 API 请求签名的消息认证码

## 概述

HMAC-SHA256 用于 Polymarket L2 API 的请求签名。每个需要认证的请求都包含一个 HMAC 签名，服务器使用它来验证请求的真实性和完整性。

## 类型

### Mac

32 字节消息认证码类型。

```zig
pub const Mac = [32]u8;
```

### Hmac

流式 HMAC 计算器。

```zig
pub const Hmac = struct {
    pub fn init(key: []const u8) Hmac;
    pub fn update(self: *Hmac, data: []const u8) void;
    pub fn final(self: *Hmac) Mac;
    pub fn finalTo(self: *Hmac, out: *Mac) void;
};
```

## 函数

### hmacSha256

计算 HMAC-SHA256。

```zig
pub fn hmacSha256(key: []const u8, message: []const u8) Mac
```

**参数**:
- `key`: 密钥（API Secret）
- `message`: 消息

**返回**: 32 字节 MAC

**示例**:
```zig
const mac = hmacSha256("secret", "message");
```

### toBase64

将 MAC 编码为 Base64 字符串。

```zig
pub fn toBase64(mac: *const Mac, buffer: *[44]u8) []const u8
```

**参数**:
- `mac`: 32 字节 MAC
- `buffer`: 输出缓冲区（44 字节）

**返回**: Base64 编码的字符串

**示例**:
```zig
const mac = hmacSha256("secret", "message");
var buffer: [44]u8 = undefined;
const base64 = toBase64(&mac, &buffer);
// => "i19IcCmVwVmMVz2x4hhmqbgl1KeU0WnXBgoDYFeWNgs="
```

### toBase64Alloc

将 MAC 编码为 Base64 字符串（分配内存）。

```zig
pub fn toBase64Alloc(allocator: std.mem.Allocator, mac: *const Mac) ![]u8
```

**参数**:
- `allocator`: 内存分配器
- `mac`: 32 字节 MAC

**返回**: Base64 编码的字符串（调用者负责释放）

### toHex

将 MAC 格式化为十六进制字符串。

```zig
pub fn toHex(mac: *const Mac, buffer: *[64]u8) []const u8
```

### verify

验证 MAC（常量时间比较）。

```zig
pub fn verify(key: []const u8, message: []const u8, expected: *const Mac) bool
```

**参数**:
- `key`: 密钥
- `message`: 消息
- `expected`: 期望的 MAC

**返回**: MAC 是否匹配

**示例**:
```zig
const mac = hmacSha256("secret", "message");
const valid = verify("secret", "message", &mac);  // true
const invalid = verify("secret", "wrong", &mac);  // false
```

## 常量

| 常量 | 值 | 描述 |
|------|---|------|
| `MAC_LENGTH` | 32 | MAC 长度（字节） |
| `BASE64_ENCODED_LENGTH` | 44 | Base64 编码后长度 |

## L2 API 签名

### 签名消息格式

```
message = timestamp + method + path + body
```

- `timestamp`: Unix 时间戳（秒）
- `method`: HTTP 方法（GET, POST, DELETE）
- `path`: API 路径（如 `/order`）
- `body`: 请求体（JSON 字符串，GET 请求为空）

### 签名流程

```zig
const crypto = @import("poly-sdk-zig").crypto;

// 1. 构建签名消息
const timestamp = "1704067200";
const method = "POST";
const path = "/order";
const body = "{\"tokenId\":\"123\"}";

// 2. 计算 HMAC
var hmac = crypto.Hmac.init(api_secret);
hmac.update(timestamp);
hmac.update(method);
hmac.update(path);
hmac.update(body);
const mac = hmac.final();

// 3. Base64 编码
var buffer: [44]u8 = undefined;
const signature = crypto.macToBase64(&mac, &buffer);

// 4. 设置 HTTP Header
// POLY-SIGNATURE: <signature>
```

### 完整示例

```zig
fn generateL2Signature(
    api_secret: []const u8,
    timestamp: []const u8,
    method: []const u8,
    path: []const u8,
    body: ?[]const u8,
) [44]u8 {
    var hmac = crypto.Hmac.init(api_secret);
    hmac.update(timestamp);
    hmac.update(method);
    hmac.update(path);
    if (body) |b| {
        hmac.update(b);
    }
    const mac = hmac.final();
    
    var buffer: [44]u8 = undefined;
    _ = crypto.macToBase64(&mac, &buffer);
    return buffer;
}
```

## 已知测试向量

| 密钥 | 消息 | HMAC (hex) |
|------|------|------------|
| `"secret"` | `"message"` | `8b5f48702995c1598c573db1e21866a9b825d4a794d169d7060a03605796360b` |
| `"key"` | `""` | `5d5d139563c95b5967b9bd9a8c9b233a9dedb45072794cd232dc1b74832607d0` |

## 安全注意事项

1. **密钥保护**: API Secret 应该使用 `Secret` 类型包装
2. **常量时间比较**: 使用 `verify` 函数进行 MAC 验证，它使用常量时间比较防止时序攻击
3. **时间戳**: 时间戳应该在服务器可接受范围内（通常 ±30 秒）
4. **重放保护**: 时间戳用于防止重放攻击

## 技术实现

本模块使用 Zig 标准库的 `std.crypto.auth.hmac.sha2.HmacSha256`：

```zig
const HmacSha256 = std.crypto.auth.hmac.sha2.HmacSha256;
```
