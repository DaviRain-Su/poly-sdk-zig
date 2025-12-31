# RFC-002: ArrayList Allocator 模式 (Zig 0.15)

| 字段 | 值 |
|------|-----|
| **状态** | 已采纳 |
| **创建日期** | 2024-12-31 |
| **作者** | - |

## 问题

Zig 0.15 将 `std.ArrayList` 默认改为 **Unmanaged**。这意味着：

```zig
// ❌ 这段代码在 Zig 0.15 中能编译但是错误的
var list = try std.ArrayList(u8).initCapacity(allocator, 16);
try list.append(item);  // 错误：缺少 allocator 参数
```

正确的用法是：

```zig
// ✅ Zig 0.15 中正确
try list.append(allocator, item);
```

这是相对早期 Zig 版本的**破坏性变更**，是一个常见的 bug 来源。

## 需求

1. 所有代码必须在 Zig 0.15.2+ 上正确编译
2. 内存分配模式必须显式
3. 防止由于错误的 ArrayList 使用导致的运行时 panic

## 提案

### 规则 1：始终使用 `initCapacity`

```zig
// ❌ 不要使用 init()
var list = std.ArrayList(T).init(allocator);

// ✅ 使用 initCapacity() 并估计大小
var list = try std.ArrayList(T).initCapacity(allocator, 16);
```

### 规则 2：向变更方法传递 allocator

| 方法 | Zig 0.14 | Zig 0.15 |
|------|----------|----------|
| `append` | `list.append(item)` | `list.append(allocator, item)` |
| `appendSlice` | `list.appendSlice(items)` | `list.appendSlice(allocator, items)` |
| `addOne` | `list.addOne()` | `list.addOne(allocator)` |
| `toOwnedSlice` | `list.toOwnedSlice()` | `list.toOwnedSlice(allocator)` |
| `ensureTotalCapacity` | `list.ensureTotalCapacity(n)` | `list.ensureTotalCapacity(allocator, n)` |

### 规则 3：AssumeCapacity 变体不需要 allocator

```zig
// 这些不需要 allocator 是安全的（无重新分配）
list.appendAssumeCapacity(item);
list.addOneAssumeCapacity();
```

## 备选方案

### 备选方案 1：使用 Managed ArrayList 包装器

创建一个内部存储 allocator 的包装器。

**优点**: 更干净的 API，匹配旧行为
**缺点**: 额外的间接，非惯用 Zig

**决定**: 拒绝 - 遵循 Zig 惯例，显式分配

### 备选方案 2：使用 ArrayListAligned

**优点**: 不同的 API，可能更清晰
**缺点**: 在 0.15 中仍然是 unmanaged，同样的问题

**决定**: 拒绝 - 不能解决问题

## 决定

**明确遵循 Zig 0.15 约定**：

1. 在 AGENTS.md 中记录该模式
2. 包含快速参考表
3. 所有代码审查必须检查 ArrayList 使用

## 实现

添加到 AGENTS.md：

```zig
// Zig 0.15 ArrayList API 快速参考
| 方法 | 需要 allocator |
|------|----------------|
| initCapacity(allocator, n) | 是 |
| deinit() | 否 |
| append(allocator, item) | 是 |
| appendSlice(allocator, items) | 是 |
| toOwnedSlice(allocator) | 是 |
| appendAssumeCapacity(item) | 否 |
```

## 参考资料

- [Zig 0.15 发布说明](https://ziglang.org/download/0.15.0/release-notes.html)
- [std.ArrayList 源代码](https://github.com/ziglang/zig/blob/master/lib/std/array_list.zig)
