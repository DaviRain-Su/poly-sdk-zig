# Decimal

> **Source**: [`src/types/decimal.zig`](../../src/types/decimal.zig)
> **RFC**: [001-decimal-type](../design/rfc/001-decimal-type.md)

High-precision decimal type for financial calculations.

## Why

Floating-point (`f64`) has precision issues. `0.1 + 0.2 != 0.3` in IEEE 754.

For trading, we need **exact** decimal arithmetic.

## Design

Fixed-point representation: `mantissa * 10^(-scale)`

```zig
pub const Decimal = struct {
    mantissa: i128,  // Signed integer
    scale: u8,       // Decimal places (0-18)
};
```

| Value | mantissa | scale |
|-------|----------|-------|
| `0.65` | 65 | 2 |
| `100` | 100 | 0 |
| `-0.001` | -1 | 3 |

## Usage

```zig
const std = @import("std");
const Decimal = @import("poly").Decimal;

// Parse from string
const price = try Decimal.fromString("0.65");
const size = try Decimal.fromString("100");

// Arithmetic
const total = price.mul(size);  // 65.00 (exact)

// Comparison
if (price.lessThan(Decimal.ONE)) {
    // price < 1.0
}

// Format
std.debug.print("Total: {}\n", .{total});  // "Total: 65"
```

## API

### Creation

| Method | Description |
|--------|-------------|
| `fromString(str)` | Parse from `"123.456"` |
| `fromInt(i64)` | From integer |
| `fromParts(mantissa, scale)` | Direct construction |

### Arithmetic

| Method | Description |
|--------|-------------|
| `add(other)` | Addition |
| `sub(other)` | Subtraction |
| `mul(other)` | Multiplication |
| `div(other)` | Division (returns error if zero) |

### Comparison

| Method | Description |
|--------|-------------|
| `equal(other)` | Equality |
| `lessThan(other)` | Less than |
| `greaterThan(other)` | Greater than |
| `compare(other)` | Returns -1, 0, or 1 |

### Constants

| Constant | Value |
|----------|-------|
| `ZERO` | 0 |
| `ONE` | 1 |
| `MAX_SCALE` | 18 |

## Tests

```bash
zig test src/types/decimal.zig
```
