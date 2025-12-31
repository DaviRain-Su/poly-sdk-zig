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

### 测试质量要求（强制）

**核心原则**: 所有测试必须通过，且无内存泄漏和段错误。

#### 必须满足的条件

1. **所有测试通过**: `zig build test` 和 `zig test src/root.zig` 必须 100% 通过
2. **无内存泄漏**: 使用 `std.testing.allocator` 会自动检测内存泄漏
3. **无段错误**: 测试不能崩溃或产生未定义行为

#### 测试验证命令

```bash
# 必须全部通过才能提交
zig build test           # 集成测试
zig test src/root.zig    # 完整测试套件

# 期望输出示例
# All 263 tests passed.
```

#### 内存泄漏检测

Zig 的 `std.testing.allocator` 会自动检测内存泄漏：

```zig
test "no memory leak" {
    const allocator = std.testing.allocator;
    
    // 如果忘记 free，测试会失败
    const buffer = try allocator.alloc(u8, 100);
    defer allocator.free(buffer);  // ✅ 必须释放
    
    // 测试代码...
}
```

#### 常见内存问题及解决方案

```zig
// ❌ 错误 - 内存泄漏
test "leaky test" {
    const allocator = std.testing.allocator;
    const data = try allocator.alloc(u8, 100);
    // 忘记 free -> 测试失败: memory leak detected
}

// ✅ 正确 - 使用 defer 释放
test "clean test" {
    const allocator = std.testing.allocator;
    const data = try allocator.alloc(u8, 100);
    defer allocator.free(data);
    // 测试代码...
}

// ❌ 错误 - ArrayList 内存泄漏
test "leaky arraylist" {
    const allocator = std.testing.allocator;
    var list = try std.ArrayList(u8).initCapacity(allocator, 16);
    // 忘记 deinit -> 内存泄漏
}

// ✅ 正确 - ArrayList 正确释放
test "clean arraylist" {
    const allocator = std.testing.allocator;
    var list = try std.ArrayList(u8).initCapacity(allocator, 16);
    defer list.deinit();
    // 测试代码...
}
```

#### 段错误预防

```zig
// ❌ 危险 - 可能段错误
test "dangerous" {
    var ptr: ?*u8 = null;
    _ = ptr.?.*;  // 解引用 null -> 段错误
}

// ✅ 安全 - 检查 null
test "safe" {
    var ptr: ?*u8 = null;
    if (ptr) |p| {
        _ = p.*;
    }
}

// ❌ 危险 - 数组越界
test "out of bounds" {
    const arr = [_]u8{ 1, 2, 3 };
    _ = arr[5];  // 越界 -> 段错误或未定义行为
}

// ✅ 安全 - 边界检查
test "bounds checked" {
    const arr = [_]u8{ 1, 2, 3 };
    if (5 < arr.len) {
        _ = arr[5];
    }
}
```

#### 提交前测试检查清单

```markdown
# 测试检查清单

- [ ] `zig build test` 通过
- [ ] `zig test src/root.zig` 通过
- [ ] 无 "memory leak detected" 错误
- [ ] 无段错误或崩溃
- [ ] 新代码有对应的测试
- [ ] 测试覆盖正常路径和错误路径
```

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
| Story 完成 | `ROADMAP.md` 对应任务标记 ✅ |
| 版本完成 | `ROADMAP.md` 当前状态、API 覆盖统计 |

#### ROADMAP.md 更新规范（强制）

**ROADMAP.md 是项目的唯一真相来源**，必须始终保持最新状态。

##### 必须更新 ROADMAP.md 的场景

| 场景 | 更新内容 |
|------|----------|
| Story 开始 | 对应 Story 状态改为 🔨 进行中 |
| Story 完成 | 对应 Story 状态改为 ✅ 已完成 |
| 版本完成 | 当前状态部分更新版本号和阶段状态 |
| 新增端点实现 | 对应端点状态从 ⏳ 改为 ✅ |
| API 覆盖变化 | 更新 "API 覆盖统计" 表格 |
| 新增 Story | 添加到对应版本的 Stories 表格 |
| 变更日志 | 在 "变更日志" 部分添加记录 |

##### ROADMAP.md 更新检查清单

每次 Session 完成后必须检查：

```markdown
# ROADMAP.md 更新检查

- [ ] 当前状态部分
  - [ ] 版本号是否正确？
  - [ ] 阶段状态是否正确？（⏳/🔨/✅）

- [ ] Stories 表格
  - [ ] 完成的 Story 是否标记为 ✅？
  - [ ] 进行中的 Story 是否标记为 🔨？

- [ ] 端点状态
  - [ ] 实现的端点是否标记为 ✅？
  - [ ] 未实现的端点是否保持 ⏳？

- [ ] API 覆盖统计
  - [ ] 各版本状态是否更新？

- [ ] 变更日志
  - [ ] 是否添加了今天的变更记录？
```

##### 示例：版本完成时的 ROADMAP.md 更新

```markdown
# 更新前
## 当前状态
**版本**: v0.1.0 (核心基础)  
**阶段**: v0.2 - 🔨 进行中

# 更新后
## 当前状态
**版本**: v0.2.0 (认证与订单)  
**阶段**: v0.2 - ✅ 已完成
```

```markdown
# 更新 API 覆盖统计
| 版本 | 功能 | 端点数量 | 状态 |
|------|------|----------|------|
| v0.1 | 公共 API (L0) | ~20 | ✅ 完成 |  # 从 🔨 改为 ✅
| v0.2 | 认证与订单 (L1/L2) | ~25 | ✅ 完成 |  # 从 ⏳ 改为 ✅
```

```markdown
# 添加变更日志
## 变更日志
| 日期 | 变更 |
|------|------|
| 2024-12-31 | v0.2 完成：加密、签名、认证、订单构建、CLOB 客户端 |
```

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

### Story 伪代码规范（强制）

**核心原则**: Story 文件中的所有伪代码/示例代码必须符合 Zig 0.15 规范。

#### 为什么重要

Story 文件是开发的蓝图。如果伪代码不符合 Zig 0.15 规范，开发时会导致：
- 编译错误
- API 使用错误
- 返工和时间浪费

#### 必须遵守的 Zig 0.15 规则

```zig
// ❌ 错误 - 旧版本 ArrayList API
var list = std.ArrayList(u8).init(allocator);
try list.append(item);
const slice = list.toOwnedSlice();

// ✅ 正确 - Zig 0.15 ArrayList API
var list = try std.ArrayList(u8).initCapacity(allocator, 16);
defer list.deinit();
try list.append(allocator, item);  // 需要 allocator 参数！
const slice = try list.toOwnedSlice(allocator);  // 需要 allocator 参数！
```

```zig
// ❌ 错误 - 旧版本 HTTP Client
const result = try client.fetch(.{ .url = url });

// ✅ 正确 - Zig 0.15 HTTP Client
var req = client.request(.GET, uri, .{}) catch return error.ConnectionFailed;
defer req.deinit();
req.sendBodiless() catch return error.ConnectionFailed;
var response = req.receiveHead(&.{}) catch return error.ConnectionFailed;
var reader = response.reader(&.{});
const body = reader.allocRemaining(allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch return error.ReadFailed;
```

```zig
// ❌ 错误 - 旧版本 format
pub fn format(self: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void

// ✅ 正确 - Zig 0.15 format (使用 {f})
pub fn format(self: Self, writer: anytype) !void
```

#### Story 伪代码检查清单

编写或审查 Story 文件时必须检查：

- [ ] `ArrayList.append()` 传入 `allocator` 参数
- [ ] `ArrayList.toOwnedSlice()` 传入 `allocator` 参数
- [ ] HTTP 请求使用 `request/response` 模式，非 `fetch`
- [ ] 自定义 `format` 函数使用简化签名
- [ ] `@typeInfo` 枚举使用小写 (`.slice` 非 `.Slice`)
- [ ] 所有资源有 `defer` 清理
- [ ] 错误处理使用 `try` 或显式 `catch`

#### 示例：正确的 Story 伪代码

```markdown
## 实现步骤

### 1. 创建订单列表

\`\`\`zig
var orders = try std.ArrayList(SignedOrder).initCapacity(allocator, 10);
defer orders.deinit();

for (order_args) |args| {
    const order = try builder.createOrder(args);
    try orders.append(allocator, order);  // ✅ 正确：传入 allocator
}

const order_slice = try orders.toOwnedSlice(allocator);  // ✅ 正确：传入 allocator
defer allocator.free(order_slice);
\`\`\`
```

### 阶段完成前检查规范（强制）

**核心原则**: 在开始下一个版本阶段之前，必须检查并解决之前版本的遗留问题。

#### 为什么重要

1. **技术债务累积**: 遗留问题会随时间增加，越拖越难解决
2. **依赖完整性**: 后续功能可能依赖前面未完成的功能
3. **测试覆盖**: 确保项目整体质量，避免漏洞
4. **文档一致性**: 保持 ROADMAP 与实际状态同步

#### 阶段完成检查流程

在标记版本为"已完成"之前，必须执行以下检查：

```
┌─────────────────────────────────────────────────────────────────┐
│  阶段完成检查流程                                                  │
├─────────────────────────────────────────────────────────────────┤
│  1. 全面文档扫描（查找所有未完成标记）                              │
│     ├── ROADMAP.md - 检查 ⏳ 状态的端点和功能                     │
│     ├── stories/*.md - 检查 [ ] 未勾选的任务                      │
│     ├── docs/**/*.md - 检查 TODO、FIXME、⏳ 标记                  │
│     └── 代码注释 - 检查 TODO、FIXME、XXX 标记                     │
├─────────────────────────────────────────────────────────────────┤
│  2. 分类和评估遗留问题                                             │
│     ├── 当前版本遗留 - 必须决定：完成/推迟/取消                   │
│     ├── 之前版本遗留 - 评估是否可以顺便解决                       │
│     └── 记录所有决定和原因                                        │
├─────────────────────────────────────────────────────────────────┤
│  3. 解决可处理的遗留问题                                           │
│     ├── 实现功能                                                   │
│     ├── 添加测试                                                   │
│     └── 更新相关文档                                              │
├─────────────────────────────────────────────────────────────────┤
│  4. 运行完整测试验证                                               │
│     ├── zig build test                                           │
│     ├── zig test src/root.zig                                    │
│     └── 确认无内存泄漏、无段错误                                  │
├─────────────────────────────────────────────────────────────────┤
│  5. 同步更新所有文档状态                                           │
│     ├── ROADMAP.md - 版本状态、端点状态、变更日志                 │
│     ├── stories/*.md - 任务完成状态                               │
│     ├── docs/**/*.md - 移除已解决的 TODO/FIXME                    │
│     └── 代码注释 - 清理已解决的 TODO/FIXME                        │
└─────────────────────────────────────────────────────────────────┘
```

#### 文档扫描命令

在阶段完成前，运行以下命令查找所有未完成标记：

```bash
# 1. 扫描 ROADMAP.md 中的待办项
grep -n "⏳" ROADMAP.md

# 2. 扫描 stories/ 中未完成的任务
grep -rn "\[ \]" stories/
grep -rn "⏳" stories/

# 3. 扫描 docs/ 中的 TODO 和未完成标记
grep -rn "TODO\|FIXME\|⏳\|\[ \]" docs/

# 4. 扫描代码中的 TODO 和 FIXME
grep -rn "TODO\|FIXME\|XXX" src/ --include="*.zig"

# 5. 一键扫描所有（推荐）
echo "=== ROADMAP.md ===" && grep -n "⏳" ROADMAP.md && \
echo "=== stories/ ===" && grep -rn "\[ \]\|⏳" stories/ && \
echo "=== docs/ ===" && grep -rn "TODO\|FIXME\|⏳\|\[ \]" docs/ && \
echo "=== src/ ===" && grep -rn "TODO\|FIXME\|XXX" src/ --include="*.zig"
```

#### 阶段完成检查清单

```markdown
# 阶段完成检查清单

## 1. 全面文档扫描
- [ ] 运行文档扫描命令，记录所有未完成标记
- [ ] ROADMAP.md 中的 ⏳ 端点列表
- [ ] stories/ 中未勾选的 [ ] 任务列表
- [ ] docs/ 中的 TODO/FIXME 列表
- [ ] src/ 中的 TODO/FIXME 列表

## 2. 当前版本检查
- [ ] 遍历 ROADMAP.md 中当前版本的所有端点
- [ ] 遍历当前版本 Story 文件的所有任务
- [ ] 确认所有计划功能都已实现
- [ ] 如有未实现，记录原因并决定：
  - [ ] 立即实现
  - [ ] 推迟到下个版本（更新所有相关文档）
  - [ ] 取消（更新所有相关文档并说明原因）

## 3. 历史遗留问题检查
- [ ] 查看 v0.1 遗留的 ⏳ 端点和 [ ] 任务
- [ ] 查看 v0.2 遗留的 ⏳ 端点和 [ ] 任务
- [ ] ...（依次检查所有之前版本）
- [ ] 评估每个遗留问题：
  - [ ] 可以顺便解决 → 立即实现
  - [ ] 工作量大 → 记录并保持推迟
  - [ ] 不再需要 → 移除或标记为取消

## 4. 解决遗留问题
- [ ] 实现可处理的功能
- [ ] 添加对应测试
- [ ] 更新相关文档

## 5. 测试验证
- [ ] `zig build test` 通过
- [ ] `zig test src/root.zig` 通过
- [ ] 测试数量是否合理增长
- [ ] 无内存泄漏
- [ ] 无段错误

## 6. 文档同步更新
- [ ] ROADMAP.md
  - [ ] 版本状态改为 ✅
  - [ ] 实现的端点改为 ✅
  - [ ] API 覆盖统计表格更新
  - [ ] 变更日志添加记录
- [ ] stories/*.md
  - [ ] 完成的任务勾选 [x]
  - [ ] Story 状态标记为完成
- [ ] docs/**/*.md
  - [ ] 移除已解决的 TODO/FIXME
  - [ ] 更新 API 文档
- [ ] 代码注释
  - [ ] 移除已解决的 TODO/FIXME
```

#### 未完成标记说明

| 标记 | 位置 | 含义 |
|------|------|------|
| `⏳` | ROADMAP.md, stories/, docs/ | 待开始或进行中 |
| `🔨` | ROADMAP.md, stories/ | 正在进行中 |
| `[ ]` | stories/, docs/ | 未完成的检查项/任务 |
| `TODO` | 代码注释, docs/ | 待实现的功能 |
| `FIXME` | 代码注释, docs/ | 需要修复的问题 |
| `XXX` | 代码注释 | 需要注意或重构的代码 |

#### 示例：v0.3 完成前的检查

```markdown
# v0.3 完成前检查

## 文档扫描结果

### ROADMAP.md 中的 ⏳
- v0.1: GET /sampling-markets, POST /books, POST /midpoints...
- v0.2: POST /auth/api-key, GET /auth/derive-api-key...
- v0.3: Readonly API Key (4 端点)

### stories/ 中未完成的 [ ]
- stories/v0.1-public-api.md: [ ] 批量端点实现
- stories/v0.2-l1-auth.md: [ ] API Key 创建端点

### docs/ 中的 TODO
- docs/design/api-coverage.md: TODO: 添加批量端点文档
- docs/clob/client.md: FIXME: 更新认证示例

### src/ 中的 TODO
- src/clob/client.zig:123: TODO: 添加重试逻辑
- src/auth/l1.zig:45: FIXME: 验证签名格式

## 当前版本 (v0.3) 检查
- [x] Builder API Key 管理 (4 端点) - ✅ 已完成
- [x] RFQ 端点 (10 端点) - ✅ 已完成
- [x] Heartbeat 端点 - ✅ 已完成
- [ ] Readonly API Key (4 端点) - ⏳ 推迟到 v0.3.1

## 历史遗留问题评估

### v0.1 遗留（可顺便解决）
- [ ] `GET /sampling-markets` - 简单，可以实现
- [ ] `POST /books` - 简单，可以实现
- [ ] `POST /midpoints` - 简单，可以实现

### v0.2 遗留（保持推迟）
- [ ] `POST /auth/api-key` (L1) - 需要更多研究
- [ ] `GET /auth/derive-api-key` (L1) - 需要更多研究

## 决定
1. 实现 v0.1 的批量端点（工作量小）
2. L1 认证端点需要更多调研，保持 ⏳
3. Readonly API Key 推迟到 v0.3.1
4. 清理 src/ 中已过时的 TODO 注释

## 测试结果
- 总测试数: 303 → 320（实现批量端点后）
- 通过: 320
- 内存泄漏: 无

## 文档更新
- [x] ROADMAP.md 更新完成
- [x] stories/v0.3-*.md 任务勾选
- [x] docs/clob/client.md TODO 清理
- [x] src/ 过时 TODO 清理
```

#### 遗留问题处理原则

| 优先级 | 处理方式 |
|--------|----------|
| 高 - 阻塞后续功能 | 必须在当前阶段解决 |
| 中 - 独立功能且工作量小 | 顺便解决，提高完成度 |
| 中 - 独立功能但工作量大 | 记录并推迟到下个版本 |
| 低 - 边缘功能 | 记录并推迟，不影响版本完成 |
| 无效 - 不再需要 | 移除标记，更新文档说明原因 |

#### 阶段完成标准

只有满足以下所有条件，才能标记版本为"已完成"：

1. **当前版本核心功能 100% 完成**（非核心功能可推迟）
2. **所有测试通过**，无内存泄漏
3. **文档状态同步**：
   - ROADMAP.md 中当前版本核心端点全部 ✅
   - 当前版本 Story 文件核心任务全部 [x]
   - 无遗漏的关键 TODO/FIXME
4. **遗留问题已评估并记录**

#### 文档更新前验证规则（强制）

**核心原则**: 在更新任何文档状态标记之前，必须先验证代码已完全实现。

##### 为什么重要

1. **防止虚假完成**: 避免文档显示"已完成"但代码实际未实现
2. **保持一致性**: 确保文档状态与代码实际状态一致
3. **减少混乱**: 防止后续开发者被错误状态误导

##### 验证流程

在将任何 `⏳` 改为 `✅` 或 `[ ]` 改为 `[x]` 之前，必须：

```
┌─────────────────────────────────────────────────────────────────┐
│  文档更新前验证流程                                                │
├─────────────────────────────────────────────────────────────────┤
│  1. 确认代码文件存在                                               │
│     ├── 检查对应的 .zig 文件是否已创建                            │
│     ├── 检查模块是否已导出到 root.zig                             │
│     └── 检查类型/函数是否已正确导出                               │
├─────────────────────────────────────────────────────────────────┤
│  2. 确认功能已实现                                                 │
│     ├── 检查函数/方法是否有完整实现（非空壳）                     │
│     ├── 检查核心逻辑是否完整                                      │
│     └── 检查错误处理是否完整                                      │
├─────────────────────────────────────────────────────────────────┤
│  3. 确认测试存在且通过                                             │
│     ├── 检查对应的测试是否已编写                                  │
│     ├── 运行 zig test 确认测试通过                                │
│     └── 确认无内存泄漏                                            │
├─────────────────────────────────────────────────────────────────┤
│  4. 更新文档状态                                                   │
│     ├── 只有以上全部确认后才能更新状态                            │
│     ├── 同时更新所有相关文档（ROADMAP, Story, docs/）             │
│     └── 记录更新的 Session ID                                     │
└─────────────────────────────────────────────────────────────────┘
```

##### 验证检查清单

```markdown
# 文档状态更新前验证

## 功能: [功能名称]

### 1. 代码存在性检查
- [ ] 源文件存在: `src/xxx/yyy.zig`
- [ ] 模块导出: `root.zig` 或 `mod.zig` 中有导出
- [ ] 类型/函数可访问: `pub const` 或 `pub fn`

### 2. 实现完整性检查
- [ ] 函数有完整实现（非 `@panic("TODO")` 或空函数体）
- [ ] 核心逻辑完整
- [ ] 错误处理完整

### 3. 测试验证
- [ ] 测试文件/测试块存在
- [ ] `zig test` 通过
- [ ] 无内存泄漏

### 4. 确认后更新
- [ ] 以上全部 ✓ 后，更新文档状态
```

##### 示例：验证 RFQ 模块

```bash
# 1. 检查文件存在
ls src/rfq/          # 确认目录存在
ls src/rfq/*.zig     # 确认文件存在

# 2. 检查导出
grep -n "rfq" src/root.zig        # 确认模块导出
grep -n "RfqClient" src/root.zig  # 确认类型导出

# 3. 检查实现（非空壳）
grep -n "pub fn" src/rfq/client.zig | head -20  # 查看公共函数

# 4. 运行测试
zig test src/root.zig 2>&1 | grep -E "rfq|passed"

# 5. 全部确认后，才能更新：
#    - stories/v0.3-rfq.md: 状态改为 ✅
#    - ROADMAP.md: RFQ 端点改为 ✅
#    - docs/design/api-coverage.md: RFQ 端点改为 ✅
```

##### 禁止行为

❌ **禁止**: 在代码未实现时就更新文档状态为"已完成"
❌ **禁止**: 只实现了部分功能就标记整个模块为"已完成"
❌ **禁止**: 测试未通过就更新文档状态
❌ **禁止**: 只更新部分文档（如只更新 ROADMAP 不更新 Story）

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
- [ ] ROADMAP.md 已更新？（Story 状态、版本状态、变更日志）
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

### HTTP Client（request/response API - Zig 0.15+）

**注意**: Zig 0.15 完全重构了 HTTP Client API，移除了 `fetch()` 方法。

```zig
var client: std.http.Client = .{ .allocator = allocator };
defer client.deinit();

// 解析 URI
const uri = std.Uri.parse(url) catch return error.BadRequest;

// 创建请求
var req = client.request(.GET, uri, .{
    .extra_headers = &.{
        .{ .name = "Accept", .value = "application/json" },
        .{ .name = "User-Agent", .value = "my-app/1.0" },
    },
}) catch return error.ConnectionFailed;
defer req.deinit();

// 发送 GET 请求（无 body）
req.sendBodiless() catch return error.ConnectionFailed;

// 或发送 POST 请求（带 body）
// req.transfer_encoding = .{ .content_length = body.len };
// var body_writer = req.sendBodyUnflushed(&.{}) catch return error.ConnectionFailed;
// body_writer.writer.writeAll(body) catch return error.ConnectionFailed;
// body_writer.end() catch return error.ConnectionFailed;
// if (req.connection) |conn| {
//     conn.flush() catch return error.ConnectionFailed;
// }

// 接收响应头
var response = req.receiveHead(&.{}) catch return error.ConnectionFailed;

// 检查状态码
if (response.head.status != .ok) {
    return error.HttpError;
}

// 读取响应体
var reader = response.reader(&.{});
const body = reader.allocRemaining(allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch return error.ReadFailed;
defer allocator.free(body);
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
- [ ] HTTP 请求使用 Zig 0.15 的 `request/response` API（非 fetch）
- [ ] 自定义 format 函数使用 `{f}` 格式说明符
- [ ] @typeInfo 枚举使用小写（如 `.slice` 而非 `.Slice`）

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

## Zig 版本兼容性问题记录

本节记录从旧版本 Zig 迁移到 **Zig 0.15** 时遇到的编译问题和解决方案。

### 1. ArrayList API 变更

**问题**: Zig 0.15 中 `ArrayList` 的修改方法需要显式传入 `allocator`。

```zig
// ❌ 旧版本 (Zig 0.14 及更早)
var list = std.ArrayList(u8).init(allocator);
try list.append(item);
const slice = list.toOwnedSlice();

// ✅ Zig 0.15+
var list = try std.ArrayList(u8).initCapacity(allocator, 16);
try list.append(allocator, item);
const slice = try list.toOwnedSlice(allocator);
```

**影响的方法**:
- `append(allocator, item)` - 添加元素
- `appendSlice(allocator, items)` - 添加多个元素
- `addOne(allocator)` - 获取新元素指针
- `ensureTotalCapacity(allocator, n)` - 确保容量
- `toOwnedSlice(allocator)` - 转换为拥有的切片
- `insertSlice(allocator, index, items)` - 插入元素

### 2. HTTP Client API 变更

**问题**: Zig 0.15 中 `std.http.Client` 的 API 完全重构，不再使用 `fetch` 模式。

```zig
// ❌ 旧版本 (fetch 模式)
const result = try client.fetch(.{
    .location = .{ .url = url },
    .method = .POST,
    .payload = body,
    .response_storage = .{ .dynamic = &response_buffer },
});

// ✅ Zig 0.15+ (request/response 模式)
var req = client.request(.GET, uri, .{
    .extra_headers = &headers,
}) catch |err| return mapError(err);
defer req.deinit();

// 发送请求
req.sendBodiless() catch return Error.ConnectionFailed;

// 或发送带 body 的请求
req.transfer_encoding = .{ .content_length = body.len };
var body_writer = req.sendBodyUnflushed(&.{}) catch return Error.ConnectionFailed;
body_writer.writer.writeAll(body) catch return Error.ConnectionFailed;
body_writer.end() catch return Error.ConnectionFailed;
if (req.connection) |conn| {
    conn.flush() catch return Error.ConnectionFailed;
}

// 接收响应
var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

// 读取响应体
var reader = response.reader(&.{});
const body = reader.allocRemaining(allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch return Error.ReadFailed;
```

**关键变更**:
- `fetch()` 方法已移除
- 使用 `request()` 创建请求对象
- 使用 `sendBodiless()` 或 `sendBodyUnflushed()` 发送请求
- 使用 `receiveHead()` 接收响应头
- 使用 `response.reader()` 读取响应体
- 使用 `std.Io.Limit.limited()` 设置读取限制

### 3. 自定义 format 函数签名变更

**问题**: Zig 0.15 中使用 `{f}` 格式化时，format 函数签名变化。

```zig
// ❌ 旧版本
pub fn format(
    self: Self,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;
    try writer.writeAll("[REDACTED]");
}

// 使用: std.fmt.bufPrint(&buf, "{}", .{secret});

// ✅ Zig 0.15+ (使用 {f} 格式)
pub fn format(self: Self, writer: anytype) !void {
    _ = self;
    try writer.writeAll("[REDACTED]");
}

// 使用: std.fmt.bufPrint(&buf, "{f}", .{secret});
```

**注意**: `{f}` 是 Zig 0.15 中调用自定义 format 方法的格式说明符。

### 4. 类型信息枚举大小写变更

**问题**: `@typeInfo` 返回的枚举值从大写改为小写。

```zig
// ❌ 旧版本
if (@typeInfo(T) == .Slice) { ... }
if (info.pointer.size == .Slice) { ... }

// ✅ Zig 0.15+
if (@typeInfo(T) == .slice) { ... }
if (info.pointer.size == .slice) { ... }
```

**影响的枚举**:
- `.Slice` → `.slice`
- `.Pointer` → `.pointer`
- `.Struct` → `.@"struct"`
- `.Enum` → `.@"enum"`
- `.Union` → `.@"union"`
- `.Array` → `.array`
- `.Optional` → `.optional`

### 5. Decimal.compare() 返回值类型

**问题**: 自定义 `compare()` 函数返回值应该是 `i2`，不是枚举。

```zig
// ❌ 错误 - 返回枚举
pub fn compare(self: Decimal, other: Decimal) std.math.Order {
    if (self.mantissa < other.mantissa) return .lt;
    if (self.mantissa > other.mantissa) return .gt;
    return .eq;
}

// ✅ 正确 - 返回 i2 (-1, 0, 1)
pub fn compare(self: Decimal, other: Decimal) i2 {
    if (self_adjusted < other_adjusted) return -1;
    if (self_adjusted > other_adjusted) return 1;
    return 0;
}
```

### 6. std.Uri.parse 错误处理

**问题**: `std.Uri.parse` 在 Zig 0.15 中可能抛出不同的错误。

```zig
// ✅ 正确处理
const uri = std.Uri.parse(url) catch return Error.BadRequest;
```

### 7. 模块导入路径

**问题**: 跨模块导入时路径处理。

```zig
// 从 src/clob/client.zig 导入 root.zig
const root = @import("../root.zig");

// 从 src/order/builder.zig 导入 signer
const signer = @import("../signer/mod.zig");
```

### 8. JSON 解析选项

**问题**: `std.json.parseFromSlice` 的选项变化。

```zig
// ✅ Zig 0.15+ 正确用法
const parsed = try std.json.parseFromSlice(MyStruct, allocator, json_string, .{
    .ignore_unknown_fields = true,
    .allocate = .alloc_always,  // 确保字符串被分配
});
defer parsed.deinit();
const data = parsed.value;
```

### 9. 哈希函数参数

**问题**: 某些哈希上下文函数签名变化。

```zig
// ✅ Zig 0.15+ secp256k1 ECDSA with Keccak256
const EcdsaSecp256k1Keccak256 = std.crypto.sign.ecdsa.Ecdsa(
    std.crypto.ecc.Secp256k1,
    std.crypto.hash.sha3.Keccak256,
);
```

### 10. 错误联合处理

**问题**: 某些标准库函数的错误类型变化。

```zig
// 需要处理更多的网络错误类型
fn mapConnectionError(err: anyerror) Error {
    return switch (err) {
        error.ConnectionRefused => Error.ConnectionRefused,
        error.ConnectionResetByPeer => Error.ConnectionReset,
        error.ConnectionTimedOut => Error.Timeout,
        error.NetworkUnreachable => Error.ConnectionFailed,
        error.UnknownHostName => Error.DnsResolutionFailed,
        else => Error.ConnectionFailed,
    };
}
```

### 常见迁移错误消息

| 错误消息 | 原因 | 解决方案 |
|---------|------|---------|
| `expected 2 argument(s), found 1` | ArrayList.append 需要 allocator | 添加 allocator 参数 |
| `ambiguous format string` | 自定义 format 需要 `{f}` | 使用 `{f}` 而非 `{}` |
| `no field named 'response_storage'` | fetch API 已移除 | 使用 request/response 模式 |
| `member access not allowed on type` | 枚举大小写变更 | 使用小写枚举值 |
| `expected type 'i2'` | compare 返回类型 | 返回 -1, 0, 1 而非枚举 |

### 迁移检查清单

- [ ] ArrayList 方法添加 allocator 参数
- [ ] HTTP 请求改用 request/response 模式
- [ ] 自定义 format 使用 `{f}` 格式
- [ ] @typeInfo 枚举使用小写
- [ ] 检查 compare 函数返回 i2
- [ ] 测试所有网络错误处理

---

## 相关文档

- `ROADMAP.md` - 项目路线图（Source of Truth）
- `stories/` - 工作单元（Stories）
- `docs/` - 详细设计文档
