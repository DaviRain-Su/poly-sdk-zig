# 认证模块 (auth)

> 提供 Polymarket API 的 L1 和 L2 认证支持。

## 概述

Polymarket API 使用两级认证系统：

- **L1 认证** - 使用 EIP-712 签名，用于创建/派生 API Key
- **L2 认证** - 使用 HMAC-SHA256 签名，用于日常 API 请求

## 模块结构

```
src/auth/
├── mod.zig           # 模块导出
├── l1.zig            # L1 认证 (EIP-712)
├── l2.zig            # L2 认证 (HMAC-SHA256)
├── headers.zig       # Header 类型定义
└── api_creds.zig     # API 凭证类型
```

## 子模块

| 文件 | 文档 | 描述 |
|------|------|------|
| l1.zig | [l1-auth.md](./l1-auth.md) | L1 认证 (EIP-712 签名) |
| l2.zig | [l2-auth.md](./l2-auth.md) | L2 认证 (HMAC-SHA256) |
| headers.zig | [l1-auth.md](./l1-auth.md) | L1/L2 Header 类型 |
| api_creds.zig | [l1-auth.md](./l1-auth.md) | API 凭证类型 |

## 快速开始

### L1 认证 (创建 API Key)

```zig
const auth = @import("poly-sdk-zig").auth;

// 创建 L1 认证器
const l1 = auth.L1Auth.init(&wallet, .{ .chain_id = 137 });

// 生成 L1 Header
const header = try l1.generateHeader();

// 转换为 HTTP headers
const http_headers = header.toHttpHeaders();
```

### L2 认证 (日常请求)

```zig
const auth = @import("poly-sdk-zig").auth;

// 创建 L2 认证器
const l2 = auth.L2Auth.init(&api_creds);

// 生成 L2 Header
const header = try l2.generateHeader(.{
    .method = "POST",
    .path = "/order",
    .body = order_json,
});

// 转换为 HTTP headers
const http_headers = header.toHttpHeaders();
```

## 类型导出

### 从 l1.zig

| 类型 | 描述 |
|------|------|
| `L1Auth` | L1 认证器 |
| `L1AuthOptions` | L1 认证选项 |

### 从 l2.zig

| 类型 | 描述 |
|------|------|
| `L2Auth` | L2 认证器 |
| `L2RequestOptions` | L2 请求选项 |

### 从 headers.zig

| 类型 | 描述 |
|------|------|
| `L1PolyHeader` | L1 认证 Header |
| `L2PolyHeader` | L2 认证 Header |

### 从 api_creds.zig

| 类型 | 描述 |
|------|------|
| `ApiCreds` | API 凭证 (key, secret, passphrase) |

## 认证流程

```
┌─────────────────────────────────────────────────────────────┐
│  首次使用 (L1)                                               │
│  1. 使用钱包签名 EIP-712 消息                                │
│  2. 调用 POST /auth/api-key 或 GET /auth/derive-api-key    │
│  3. 获取 API Key, Secret, Passphrase                       │
├─────────────────────────────────────────────────────────────┤
│  日常请求 (L2)                                               │
│  1. 构建签名消息: timestamp + method + path + body          │
│  2. 使用 API Secret 计算 HMAC-SHA256                        │
│  3. Base64 编码签名                                         │
│  4. 添加 POLY-* headers 到请求                              │
└─────────────────────────────────────────────────────────────┘
```

## 安全注意事项

1. **API Secret 保护**: 使用 `Secret` 类型包装，防止日志泄露
2. **时间戳同步**: 时间戳必须在服务器时间 ±30 秒内
3. **Nonce**: L1 认证使用 nonce 防止重放攻击

## 测试

```bash
# 测试整个 auth 模块
zig test src/auth/mod.zig

# 测试单个子模块
zig test src/auth/l1.zig
zig test src/auth/l2.zig
```
