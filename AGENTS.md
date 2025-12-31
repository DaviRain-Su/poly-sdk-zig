# AGENTS.md - AI 编码代理规范

本文档定义了 AI 编码代理在 Polymarket Zig CLOB Client SDK 项目中的行为准则。

**Zig 版本**: 0.15.2 (最低要求)

---

## 文档语言规范

**强制规则**: 项目中所有文档必须使用**中文**编写。

- README.md、ROADMAP.md、所有 Story 文件、docs/ 下的文档都使用中文
- 代码注释可以使用英文（遵循 Zig 惯例）
- 变量名、函数名使用英文（编程规范）

---

## 构建命令

```bash
# 构建项目
zig build

# 运行可执行文件
zig build run

# 运行所有测试
zig build test

# 运行单个文件测试
zig test src/types/decimal.zig

# 使用优化构建
zig build -Doptimize=ReleaseFast

# 清理构建缓存
rm -rf .zig-cache zig-out
```

---

## 项目结构

```
src/
├── root.zig          # 库入口（公共 API 导出）
├── main.zig          # CLI 可执行文件入口
├── types/            # 核心类型（Decimal, Address, UUID, Secret）
├── clob/             # CLOB 客户端实现
├── auth/             # 认证模块（L1/L2/Builder）
├── crypto/           # 加密操作
├── http/             # HTTP 客户端封装
├── error.zig         # 错误定义
└── constants.zig     # 常量和配置
```

---

## 代码风格规范

### 命名约定

```zig
// 类型名: PascalCase
const MyStruct = struct {};
const ClientState = enum {};

// 函数和变量: camelCase
fn processOrder() void {}
var orderCount: u32 = 0;

// 常量: snake_case 或 SCREAMING_SNAKE_CASE
const max_retries = 3;
const POLYGON_CHAIN_ID: u64 = 137;

// 文件名: snake_case.zig
// order_builder.zig, http_client.zig
```

### 导入顺序

```zig
const std = @import("std");

// 导入分组：先 std，再项目模块
const types = @import("types/mod.zig");
const Decimal = types.Decimal;
```

### 文档注释

所有公共 API 必须有文档注释：

```zig
/// 创建新的限价订单
///
/// 参数:
///   - token_id: 代币标识符
///   - price: 订单价格 (0 < price < 1)
///
/// 返回: 可签名的订单对象
/// 错误: InvalidPrice, InvalidSize
pub fn createLimitOrder(token_id: []const u8, price: Decimal) !SignableOrder {
    // ...
}
```

---

## Zig 0.15 API 要求（关键）

### ArrayList（Unmanaged - 需要 allocator）

```zig
// 初始化 - 始终使用 initCapacity
var list = try std.ArrayList(T).initCapacity(allocator, 16);
defer list.deinit();

// ❌ 错误 - Zig 0.15 的 append 需要 allocator
list.append(item);
try list.append(item);

// ✅ 正确 - 传入 allocator 参数
try list.append(allocator, item);
try list.appendSlice(allocator, items);
const ptr = try list.addOne(allocator);
try list.ensureTotalCapacity(allocator, n);
const owned = try list.toOwnedSlice(allocator);

// AssumeCapacity 系列不需要 allocator
list.appendAssumeCapacity(item);
```

### ArrayList API 速查表（Zig 0.15+）

| 方法 | 需要 allocator | 说明 |
|------|---------------|------|
| `initCapacity(allocator, n)` | 是 | 初始化并预分配容量 |
| `deinit()` | 否 | 释放内存 |
| `append(allocator, item)` | 是 | 添加单个元素 |
| `appendSlice(allocator, items)` | 是 | 添加多个元素 |
| `addOne(allocator)` | 是 | 获取新元素指针 |
| `ensureTotalCapacity(allocator, n)` | 是 | 确保容量 |
| `toOwnedSlice(allocator)` | 是 | 转换为拥有的切片 |
| `appendAssumeCapacity(item)` | 否 | 假设容量足够 |
| `items` 字段 | 否 | 只读访问 |

### HashMap

```zig
// Managed（StringHashMap, AutoHashMap）- 存储 allocator
var map = std.StringHashMap(V).init(allocator);
defer map.deinit();
try map.put(key, value);  // 不需要 allocator

// Unmanaged（StringHashMapUnmanaged）- 需要 allocator
var umap = std.StringHashMapUnmanaged(V){};
defer umap.deinit(allocator);
try umap.put(allocator, key, value);  // 需要 allocator

// 使用 getOrPut 避免重复查找
const result = try map.getOrPut(key);
if (!result.found_existing) {
    result.value_ptr.* = new_value;
}
```

### HTTP Client（fetch API）

```zig
var client: std.http.Client = .{ .allocator = allocator };
defer client.deinit();

// 简单 GET 请求
const result = try client.fetch(.{
    .location = .{ .url = "https://example.com/api" },
});

// 带响应体的请求
var response_buffer = try std.ArrayList(u8).initCapacity(allocator, 4096);
defer response_buffer.deinit();

const result2 = try client.fetch(.{
    .location = .{ .url = url },
    .method = .POST,
    .payload = body,
    .extra_headers = &.{ .{ .name = "Content-Type", .value = "application/json" } },
    .response_writer = response_buffer.writer(),
});

if (result2.status == .ok) {
    // 使用 response_buffer.items
}
```

### std.json

```zig
// 解析并释放
const parsed = try std.json.parseFromSlice(MyStruct, allocator, json_string, .{});
defer parsed.deinit();
const data = parsed.value;

// 序列化
const json_output = try std.json.stringifyAlloc(allocator, data, .{});
defer allocator.free(json_output);
```

### std.fmt

```zig
// 分配式格式化
const formatted = try std.fmt.allocPrint(allocator, "value: {d}", .{42});
defer allocator.free(formatted);

// 非分配式格式化（使用缓冲区）
var buffer: [256]u8 = undefined;
const result = try std.fmt.bufPrint(&buffer, "value: {d}", .{42});
```

---

## 内存管理

### 资源清理

```zig
// 始终使用 defer 清理
const buffer = try allocator.alloc(u8, size);
defer allocator.free(buffer);

// 使用 errdefer 处理错误路径清理
fn createResource(allocator: Allocator) !*Resource {
    const res = try allocator.create(Resource);
    errdefer allocator.destroy(res);
    
    res.data = try allocator.alloc(u8, 100);
    errdefer allocator.free(res.data);
    
    try res.initialize();
    return res;
}
```

### Arena Allocator 用于临时分配

```zig
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const temp = arena.allocator();
// arena.deinit() 会一次性释放所有分配
```

### 字符串所有权

```zig
// 借用 - 不要释放
fn process(borrowed: []const u8) void {
    // 只读，不能释放
}

// 拥有 - 调用者必须释放
fn createString(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.dupe(u8, "owned string");
}

const owned = try createString(allocator);
defer allocator.free(owned);
```

---

## 错误处理

```zig
// ❌ 错误 - 静默忽略错误
const result = doSomething() catch null;

// ✅ 正确 - 传播错误
const result = try doSomething();

// ✅ 正确 - 有意义的错误处理
const result = doSomething() catch |err| {
    std.log.err("Failed: {}", .{err});
    return err;
};
```

---

## 项目特定规则

### 金融计算

```zig
// ❌ 永远不要用 f64 处理金钱
const price: f64 = 0.65;
const total = price * 100.0;  // 可能是 64.99999999...

// ✅ 正确 - 使用 Decimal
const price = try Decimal.fromString("0.65");
const size = try Decimal.fromString("100");
const total = price.mul(size);  // 精确的 65.00
```

### 敏感数据

```zig
// ❌ 错误 - 原始敏感数据
const Credentials = struct {
    secret: []const u8,      // 可能被意外打印
};

// ✅ 正确 - 使用 Secret 包装
const Credentials = struct {
    secret: Secret([]const u8),
    passphrase: Secret([]const u8),
};

// Secret.format() 输出 "[REDACTED]"
```

### 禁止 async/await

Zig 0.11+ 移除了原生 async/await。使用同步代码或线程：

```zig
// 同步（推荐）
const result = try fetchData();

// 并发操作使用线程
const thread = try std.Thread.spawn(.{}, workerFn, .{});
```

### Comptime 约束

```zig
// ❌ 错误 - 运行时值作为 comptime 参数
fn process(runtime_type: type) void { ... }

// ✅ 正确 - comptime 参数在编译时已知
fn process(comptime T: type) void { ... }
```

### 日志规范

```zig
// ❌ 错误 - 泄露敏感信息
std.log.info("API Key: {s}", .{credentials.key});

// ✅ 正确 - 安全日志
std.log.info("Request to {s}", .{endpoint});
std.log.debug("Order ID: {s}", .{order_id});
```

---

## 提交前检查清单

### Zig 0.15 API
- [ ] `ArrayList` 使用 `initCapacity` 并向变更方法传入 `allocator`
- [ ] `toOwnedSlice` 传入 `allocator` 参数
- [ ] 区分 Managed（`StringHashMap`）和 Unmanaged（`StringHashMapUnmanaged`）
- [ ] HTTP 请求使用 Zig 0.15 的 `fetch` API

### 内存安全
- [ ] 所有分配都有对应的 `defer`/`errdefer`
- [ ] 使用 `errdefer` 处理错误路径清理
- [ ] 没有使用 `async`/`await`（Zig 0.11+ 已移除）

### 项目规则
- [ ] 敏感数据使用 `Secret` 包装
- [ ] 金融计算使用 `Decimal`，不使用 `f64`
- [ ] 日志不包含敏感信息
- [ ] 公共 API 有文档注释
- [ ] 测试通过：`zig build test`

### 文档规范
- [ ] 所有文档使用中文编写
- [ ] Story 文件包含 Session ID 和 Session Log
- [ ] 文档结构镜像代码结构

---

## 相关文档

- `ROADMAP.md` - 项目路线图（Source of Truth）
- `stories/` - 工作单元（Stories）
- `docs/` - 详细设计文档
