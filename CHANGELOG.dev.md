# 开发日志

本文档记录项目的实际开发进度，包括每次会话的工作内容、遇到的问题和解决方案。

---

## 会话记录

### Session 2024-12-31-002

**日期**: 2024-12-31  
**时长**: ~30 分钟  
**目标**: 实现 Secret 类型，将所有文档翻译为中文

#### 完成的工作

1. **实现 Secret 类型** (`src/types/secret.zig`)
   - 泛型包装器 `Secret(T)` 防止敏感数据意外日志泄露
   - `init()`, `reveal()`, `eql()` 方法
   - `format()` 输出 `[REDACTED]`
   - 常量时间比较（防止时序攻击）
   - `SecretString` 类型别名
   - 8 个测试全部通过

2. **文档中文化** - 将 12 个英文文档翻译为中文
   - `ROADMAP.md`
   - `README.md`
   - `docs/README.md`
   - `docs/types/decimal.md`
   - `docs/types/secret.md`（新建）
   - `docs/design/rfc/001-decimal-type.md`
   - `docs/design/rfc/002-arraylist-allocator.md`
   - `docs/design/rfc/003-secret-type.md`
   - `stories/_template.md`
   - `stories/v0.1-types.md`
   - `stories/v0.1-error.md`
   - `stories/v0.1-http.md`
   - `stories/v0.1-public-api.md`

#### 遇到的问题

1. **Zig 0.15 format API 变化**
   - 问题：`{}`格式字符串报错 "ambiguous format string"
   - 原因：Zig 0.15 需要明确指定 `{f}` 来调用自定义 format 方法
   - 解决：将测试中的 `{}` 改为 `{f}`

2. **Zig 0.15 类型枚举名变化**
   - 问题：`.Slice` 找不到
   - 原因：Zig 0.15 改为小写 `.slice`
   - 解决：`info.pointer.size == .slice`

3. **Zig 0.15 format 签名变化**
   - 问题：format 函数签名不匹配
   - 原因：`{f}` 只传递 writer，不传递 fmt 和 options
   - 解决：简化 format 签名为 `fn format(self: Self, writer: anytype) !void`

#### 下一步

- [ ] 实现 Address 类型（EIP-55 校验和）
- [ ] 实现 UUID 类型
- [ ] 创建 `types/mod.zig` 模块导出

---

### Session 2024-12-31-001

**日期**: 2024-12-31  
**时长**: ~1 小时  
**目标**: 项目初始化，建立文档体系，实现 Decimal 类型

#### 完成的工作

1. **建立 Agentic Coding 文档体系**
   - 创建 `ROADMAP.md` 作为唯一真相来源
   - 创建 `AGENTS.md` AI 编码规范
   - 创建 `stories/` 目录存放工作单元
   - 创建 `docs/` 目录存放设计文档

2. **实现 Decimal 类型** (`src/types/decimal.zig`)
   - 高精度定点数：`i128 mantissa + u8 scale`
   - 从字符串解析、算术运算、比较
   - JSON 序列化支持
   - 10 个测试全部通过

3. **设计文档**
   - RFC-001: Decimal 类型设计决策
   - RFC-002: ArrayList Allocator 模式（Zig 0.15）
   - RFC-003: Secret 类型设计

#### 遇到的问题

1. **Zig 0.15 ArrayList API**
   - 问题：`append()` 等方法需要传入 allocator
   - 解决：记录在 AGENTS.md 和 RFC-002 中

#### 学到的经验

- Zig 0.15 有很多 API 变化，需要特别注意
- 文档驱动开发帮助保持清晰的项目结构

---

## 当前状态快照

**版本**: v0.0.0 (Pre-release)  
**阶段**: v0.1 - 核心基础

### 已实现

| 模块 | 文件 | 测试 | 文档 |
|------|------|------|------|
| Decimal | `src/types/decimal.zig` | ✅ 10 tests | ✅ |
| Secret | `src/types/secret.zig` | ✅ 8 tests | ✅ |

### 待实现

| 模块 | 文件 | 优先级 |
|------|------|--------|
| Address | `src/types/address.zig` | 高 |
| UUID | `src/types/uuid.zig` | 高 |
| types/mod.zig | `src/types/mod.zig` | 中 |

### 测试命令

```bash
# 运行所有 types 测试
zig test src/types/decimal.zig
zig test src/types/secret.zig

# 构建项目
zig build
```

---

## Zig 0.15 注意事项

在开发过程中发现的 Zig 0.15 特性变化：

### ArrayList API

```zig
// ✅ 正确
try list.append(allocator, item);
try list.toOwnedSlice(allocator);

// ❌ 错误（Zig 0.14 语法）
try list.append(item);
```

### Format API

```zig
// ✅ Zig 0.15 的 {f} 格式
pub fn format(self: Self, writer: anytype) !void {
    try writer.writeAll("[REDACTED]");
}

// 使用
std.fmt.bufPrint(&buffer, "{f}", .{value});
```

### 类型信息枚举

```zig
// ✅ Zig 0.15（小写）
info.pointer.size == .slice

// ❌ 旧版本（大写）
info.pointer.size == .Slice
```

---

## 继续开发的 Prompt

```
我正在开发 Polymarket CLOB API 的 Zig 客户端。

项目位置: /home/davirain/dev/poly-sdk-zig/
Zig 版本: 0.15.2

## 开始前必读

1. AGENTS.md - 编码规范（Zig 0.15 API、中文文档要求）
2. CHANGELOG.dev.md - 开发日志（当前状态、已知问题）
3. stories/v0.1-types.md - 当前工作单元

## 当前状态

- ✅ Decimal 类型（10 tests）
- ✅ Secret 类型（8 tests）
- ⏳ Address 类型待实现
- ⏳ UUID 类型待实现

## 下一步

继续实现 Address 类型（EIP-55 校验和）。
```
