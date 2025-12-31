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

## 开发流程规范（文档驱动开发）

**核心原则**: 文档先行，代码跟随，测试验证，文档收尾。

### 开发周期

每个功能/修改都必须遵循以下流程：

```
┌─────────────────────────────────────────────────────────────────┐
│  1. 文档准备阶段                                                   │
│     ├── 更新/创建设计文档 (docs/design/)                          │
│     ├── 更新 ROADMAP.md (如果是新功能)                            │
│     └── 更新 Story 文件 (stories/)                                │
├─────────────────────────────────────────────────────────────────┤
│  2. 编码阶段                                                       │
│     ├── 实现功能代码                                               │
│     ├── 添加代码注释                                               │
│     ├── 同步更新 docs/ 对应文档（必须！）                          │
│     └── 更新模块文档 (docs/types/, docs/crypto/, docs/clob/ 等)   │
├─────────────────────────────────────────────────────────────────┤
│  3. 测试阶段                                                       │
│     ├── 单元测试 (zig test src/xxx.zig)                           │
│     ├── 集成测试 (zig build test)                                 │
│     └── 示例测试 (examples/*.zig)                                 │
├─────────────────────────────────────────────────────────────────┤
│  4. 文档收尾阶段                                                   │
│     ├── 更新 CHANGELOG.dev.md (会话记录)                          │
│     ├── 更新 API 文档 (如有变化)                                   │
│     └── 更新 README.md (如有用户可见变化)                          │
└─────────────────────────────────────────────────────────────────┘
```

### 阶段详解

#### 1. 文档准备阶段

在写任何代码之前，必须先准备文档：

```markdown
# 检查清单

- [ ] 功能是否已在 ROADMAP.md 中规划？
- [ ] 是否需要新的设计文档 (RFC)？
- [ ] Story 文件是否已创建/更新？
- [ ] API 覆盖分析是否需要更新？
```

**需要创建/更新的文档**：

| 场景 | 需要更新的文档 |
|------|---------------|
| 新功能 | ROADMAP.md, Story 文件, 设计文档 |
| Bug 修复 | Story 文件 |
| API 变更 | api-coverage.md, types.md |
| 新类型 | types.md, 对应的 docs/types/*.md |

#### 2. 编码阶段

编码时同步更新相关文档：

```zig
/// 每个公共 API 必须有文档注释
/// 
/// 示例:
/// ```zig
/// const order = try client.createOrder(.{...});
/// ```
pub fn createOrder(args: OrderArgs) !SignedOrder {
    // 实现...
}
```

**编码后立即更新**：
- 模块文档 (`docs/types/xxx.md`)
- API 使用示例
- 代码内注释

#### 3. 测试阶段

测试分三个层次：

```bash
# 1. 单元测试 - 测试单个模块
zig test src/types/decimal.zig
zig test src/types/secret.zig

# 2. 集成测试 - 测试整个项目
zig build test

# 3. 示例测试 - 验证用户场景
zig build run-examples  # 或手动运行 examples/
```

**测试后更新**：
- 测试覆盖率说明
- 已知问题/限制
- 性能说明（如适用）

#### 4. 文档收尾阶段

每次开发完成后必须更新：

```markdown
# CHANGELOG.dev.md 更新模板

### Session YYYY-MM-DD-NNN

**日期**: YYYY-MM-DD
**时长**: ~XX 分钟
**目标**: 简要描述

#### 完成的工作
1. ...
2. ...

#### 测试结果
- 单元测试: X tests passed
- 集成测试: passed/failed
- 示例测试: passed/failed

#### 下一步
- [ ] ...
```

### 文档同步更新规范（强制）

**核心原则**: 代码和文档必须同步更新，不允许代码实现后文档滞后。

#### docs/ 目录结构镜像 src/

```
src/                          docs/
├── types/                    ├── types/
│   ├── decimal.zig          │   ├── decimal.md
│   ├── address.zig          │   ├── address.md
│   └── ...                  │   └── ...
├── crypto/                   ├── crypto/
│   ├── keccak.zig           │   ├── README.md (模块概述)
│   ├── ecdsa.zig            │   ├── keccak.md
│   └── hmac.zig             │   └── ecdsa.md
├── clob/                     ├── clob/
│   └── client.zig           │   └── client.md
└── ...                       └── ...
```

#### 文档更新触发条件

| 代码变更类型 | 必须更新的文档 |
|-------------|---------------|
| 新增模块 | `docs/<module>/README.md` + 各文件对应的 `.md` |
| 新增类型 | `docs/types/<type>.md` + `docs/design/types.md` |
| 新增 API 端点 | `docs/design/api-coverage.md` |
| 新增公共函数 | 对应模块的 `.md` 文件 |
| 修改函数签名 | 对应模块的 `.md` 文件 |
| 修改行为/逻辑 | 对应模块的 `.md` 文件 |
| 新增错误类型 | `docs/error.md` (如存在) |

#### 文档内容要求

每个模块文档 (`docs/<module>/<file>.md`) 必须包含：

```markdown
# <模块名>

> 简要描述模块功能

## 概述

模块的用途和设计理念。

## 类型

### TypeName

描述、字段、方法。

## 函数

### functionName

```zig
pub fn functionName(args) ReturnType
```

- **参数**: 参数说明
- **返回**: 返回值说明
- **错误**: 可能的错误
- **示例**: 使用示例

## 示例

完整的使用示例代码。

## 注意事项

使用时的注意点、限制、安全考虑等。
```

#### 文档质量要求

1. **示例代码必须可编译**: 文档中的示例代码必须是有效的 Zig 代码
2. **保持同步**: 函数签名、参数名、返回类型必须与代码一致
3. **中文编写**: 所有文档内容使用中文
4. **链接有效**: 文档间的链接必须有效

### 文档更新检查清单

每次提交前运行：

```markdown
# 文档完整性检查

## 准备阶段
- [ ] ROADMAP.md 是否反映当前规划？
- [ ] Story 文件是否记录了工作内容？

## 编码阶段  
- [ ] 代码有文档注释？
- [ ] 模块文档已更新？
- [ ] docs/ 中对应的 .md 文件已创建/更新？

## 测试阶段
- [ ] 单元测试通过？ `zig test src/xxx.zig`
- [ ] 集成测试通过？ `zig build test`
- [ ] 示例可运行？

## 收尾阶段
- [ ] CHANGELOG.dev.md 已更新？
- [ ] README.md 需要更新吗？
- [ ] docs/README.md 导航正确？
- [ ] 新模块是否已添加到 docs/README.md 的目录中？
```

### 示例：添加新类型的完整流程

以添加 `Address` 类型为例：

```
1. 文档准备
   ├── 检查 ROADMAP.md (v0.1-types 已包含 Address)
   ├── 更新 stories/v0.1-types.md (添加 Address 任务)
   └── 查看 docs/design/types.md (确认类型定义)

2. 编码
   ├── 创建 src/types/address.zig
   ├── 添加文档注释
   ├── 创建 docs/types/address.md
   └── 更新 src/types/mod.zig

3. 测试
   ├── 运行 zig test src/types/address.zig
   ├── 运行 zig build test
   └── 更新 examples/basic_types.zig

4. 文档收尾
   ├── 更新 CHANGELOG.dev.md
   ├── 更新 docs/README.md (添加链接)
   └── 标记 ROADMAP.md 中 Address 为 ✅
```

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
