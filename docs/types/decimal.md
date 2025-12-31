# Decimal

> **源文件**: [`src/types/decimal.zig`](../../src/types/decimal.zig)
> **RFC**: [001-decimal-type](../design/rfc/001-decimal-type.md)

用于金融计算的高精度十进制类型。

## 为什么需要

浮点数（`f64`）有精度问题。在 IEEE 754 中 `0.1 + 0.2 != 0.3`。

对于交易，我们需要**精确**的十进制算术。

## 设计

定点表示：`mantissa * 10^(-scale)`

```zig
pub const Decimal = struct {
    mantissa: i128,  // 有符号整数
    scale: u8,       // 小数位数 (0-18)
};
```

| 值 | mantissa | scale |
|----|----------|-------|
| `0.65` | 65 | 2 |
| `100` | 100 | 0 |
| `-0.001` | -1 | 3 |

## 使用方法

```zig
const std = @import("std");
const Decimal = @import("poly").Decimal;

// 从字符串解析
const price = try Decimal.fromString("0.65");
const size = try Decimal.fromString("100");

// 算术运算
const total = price.mul(size);  // 65.00（精确）

// 比较
if (price.lessThan(Decimal.ONE)) {
    // price < 1.0
}

// 格式化
std.debug.print("Total: {}\n", .{total});  // "Total: 65"
```

## API

### 创建

| 方法 | 描述 |
|------|------|
| `fromString(str)` | 从 `"123.456"` 解析 |
| `fromInt(i64)` | 从整数创建 |
| `fromParts(mantissa, scale)` | 直接构造 |

### 算术

| 方法 | 描述 |
|------|------|
| `add(other)` | 加法 |
| `sub(other)` | 减法 |
| `mul(other)` | 乘法 |
| `div(other)` | 除法（除零返回错误） |

### 比较

| 方法 | 描述 |
|------|------|
| `equal(other)` | 相等 |
| `lessThan(other)` | 小于 |
| `greaterThan(other)` | 大于 |
| `compare(other)` | 返回 -1, 0, 或 1 |

### 常量

| 常量 | 值 |
|------|-----|
| `ZERO` | 0 |
| `ONE` | 1 |
| `MAX_SCALE` | 18 |

## 测试

```bash
zig test src/types/decimal.zig
```
