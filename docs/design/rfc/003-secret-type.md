# RFC-003: 敏感数据的 Secret 类型

| 字段 | 值 |
|------|-----|
| **状态** | 已采纳 |
| **创建日期** | 2024-12-31 |
| **作者** | - |

## 问题

API 密钥、私钥和密码可能通过以下方式意外泄露：

1. 调试日志：`std.log.debug("creds: {}", .{credentials});`
2. 错误消息：`return error.AuthFailed; // 可能在堆栈跟踪中包含密钥`
3. 核心转储和崩溃报告

```zig
// 危险：原始敏感数据
const Credentials = struct {
    api_key: []const u8,
    passphrase: []const u8,
};

std.log.info("Using creds: {any}", .{creds});  // 泄露密钥！
```

## 需求

1. 防止敏感值的意外日志记录
2. 需要时允许有意访问
3. 正常操作零运行时开销
4. 与 Zig 的格式化系统配合工作

## 提案

创建一个泛型 `Secret(T)` 包装类型：

```zig
pub fn Secret(comptime T: type) type {
    return struct {
        const Self = @This();
        
        value: T,
        
        pub fn init(value: T) Self {
            return .{ .value = value };
        }
        
        /// 有意访问密钥值
        pub fn reveal(self: Self) T {
            return self.value;
        }
        
        /// 格式化始终输出 "[REDACTED]"
        pub fn format(self: Self, writer: anytype) !void {
            _ = self;
            try writer.writeAll("[REDACTED]");
        }
    };
}
```

### 使用方法

```zig
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

// 有意访问
const key = creds.api_key.reveal();
try signRequest(key);
```

## 备选方案

### 备选方案 1：禁用日志的运行时标志

```zig
var DISABLE_SECRET_LOGGING = true;
```

**优点**: 简单
**缺点**: 如果标志设置错误仍可能泄露，有运行时开销

**决定**: 拒绝 - 编译时安全性更好

### 备选方案 2：自定义日志函数

```zig
fn safeLog(comptime fmt: []const u8, args: anytype) void {
    // 过滤敏感字段
}
```

**优点**: 集中控制
**缺点**: 容易绕过，不能防止 `std.debug.print`

**决定**: 拒绝 - 不能解决根本问题

### 备选方案 3：静态加密

在内存中加密密钥，需要时才解密。

**优点**: 纵深防御
**缺点**: 复杂，密钥管理，性能开销

**决定**: 推迟 - 对未来增强有好处，但不是 MVP

## 决定

**使用编译时 Secret 包装器**，因为：

1. 零运行时成本（format 只在日志记录时调用）
2. 类型系统防止意外访问
3. `reveal()` 使有意访问显式且可被 grep 搜索
4. 与所有 Zig 格式化配合工作

## 实现注意事项

- 如果需要 FFI，Secret 应该与 `extern struct` 兼容
- 考虑为 `[]const u8` 专门添加 `SecretSlice`
- 添加 `eql` 方法用于比较密钥而不泄露

## 安全考虑

这是**纵深防御**，不是完整的解决方案：

- 内存仍然可以被转储
- 密钥仍在进程内存中
- 侧信道攻击仍然可能

对于生产环境，考虑：
- 内存安全的密钥存储（mlock, guard pages）
- 硬件安全模块（HSM）
- 短期凭证

## 参考资料

- [OWASP 敏感数据暴露](https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/04-Authentication_Testing/09-Testing_for_Weak_Password_Change_or_Reset_Functionalities)
- Rust 的 `secrecy` crate 使用类似模式
