# Secret

> **Source**: [`src/types/secret.zig`](../../src/types/secret.zig)
> **RFC**: [003-secret-type](../design/rfc/003-secret-type.md)

防止敏感数据意外泄露的包装类型。

## Why

API 密钥、私钥和密码可能通过以下方式意外泄露：

- 调试日志：`std.log.debug("creds: {}", .{credentials})`
- 错误消息
- 核心转储和崩溃报告

`Secret(T)` 包装器确保格式化时输出 `[REDACTED]` 而非实际值。

## 设计

```zig
pub fn Secret(comptime T: type) type {
    return struct {
        value: T,
        
        pub fn init(value: T) Self { ... }
        pub fn reveal(self: Self) T { ... }
        pub fn format(self: Self, writer: anytype) !void {
            try writer.writeAll("[REDACTED]");
        }
    };
}
```

## 使用方法

```zig
const std = @import("std");
const Secret = @import("poly").Secret;

const Credentials = struct {
    api_key: Secret([]const u8),
    passphrase: Secret([]const u8),
};

const creds = Credentials{
    .api_key = Secret([]const u8).init("sk_live_xxx"),
    .passphrase = Secret([]const u8).init("secret123"),
};

// 安全：输出 "[REDACTED]"
std.log.info("Using key: {f}", .{creds.api_key});

// 有意访问（可被 grep 搜索）
const key = creds.api_key.reveal();
try signRequest(key);
```

## API

### 创建

| 方法 | 描述 |
|------|------|
| `init(value)` | 包装一个值 |

### 访问

| 方法 | 描述 |
|------|------|
| `reveal()` | 获取原始值（有意访问） |
| `eql(other)` | 安全比较（不泄露值） |

### 格式化

| 方法 | 描述 |
|------|------|
| `format(writer)` | 输出 `[REDACTED]` |
| `jsonStringify(...)` | JSON 序列化为 `"[REDACTED]"` |

### 类型别名

```zig
pub const SecretString = Secret([]const u8);
```

## 安全说明

这是**纵深防御**措施，不是完整的安全解决方案：

- 内存仍可被转储
- 密钥仍在进程内存中
- 侧信道攻击仍然可能

生产环境建议：
- 使用内存安全的密钥存储（mlock, guard pages）
- 硬件安全模块（HSM）
- 短期凭证

## 测试

```bash
zig test src/types/secret.zig
```

8 个测试全部通过：
- secret init and reveal
- secret format outputs redacted
- secret equality
- secret with integer type
- secret integer equality
- secret in struct
- secret constant time comparison
- SecretString alias
