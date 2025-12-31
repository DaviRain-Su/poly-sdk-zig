# RFC-001: Decimal Type for Financial Calculations

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Created** | 2024-12-31 |
| **Author** | - |

## Problem

Financial calculations require exact precision. Floating-point numbers (`f64`) have inherent precision issues:

```zig
const price: f64 = 0.65;
const size: f64 = 100.0;
const total = price * size;  // May be 64.99999999... instead of 65.00
```

This is unacceptable for a trading SDK where every cent matters.

## Requirements

1. Exact decimal arithmetic (no floating-point errors)
2. Support up to 18 decimal places (Ethereum standard)
3. Parse from string: `"0.65"`, `"-123.456"`
4. JSON serialization as quoted string
5. Zero-cost comparison operations
6. No external dependencies

## Proposal

Use fixed-point representation: `mantissa * 10^(-scale)`

```zig
pub const Decimal = struct {
    mantissa: i128,  // Signed to support negative values
    scale: u8,       // Number of decimal places (0-18)
};
```

### Examples

| Value | mantissa | scale |
|-------|----------|-------|
| `0.65` | 65 | 2 |
| `100` | 100 | 0 |
| `-0.001` | -1 | 3 |
| `123.456789` | 123456789 | 6 |

### API

```zig
// Creation
const d = try Decimal.fromString("0.65");
const d = Decimal.fromInt(100);

// Arithmetic
const sum = a.add(b);
const diff = a.sub(b);
const product = a.mul(b);
const quotient = try a.div(b);

// Comparison
if (a.lessThan(b)) { ... }
if (a.equal(b)) { ... }

// Output
std.debug.print("{}", .{d});  // "0.65"
const json = d.jsonStringify(...);  // "\"0.65\""
```

## Alternatives Considered

### Alternative 1: Use `f128`

**Pros**: Simple, built-in type
**Cons**: Still has precision issues, just less frequent

**Decision**: Rejected - precision errors are unacceptable

### Alternative 2: External library (e.g., GMP)

**Pros**: Battle-tested, arbitrary precision
**Cons**: External dependency, complexity, larger binary

**Decision**: Rejected - we only need 18 decimal places, not arbitrary precision

### Alternative 3: Fixed-point with i64

**Pros**: Simpler, faster
**Cons**: Limited range (max ~9.2 quintillion with 18 decimals)

**Decision**: Rejected - i128 provides sufficient range without performance penalty

## Decision

**Use i128 mantissa + u8 scale** because:

1. No precision loss for any realistic financial value
2. No external dependencies
3. Simple implementation
4. Sufficient range for all use cases

## Implementation Notes

- Use `@divTrunc` for division to match standard financial rounding
- Normalize after operations to remove trailing zeros
- JSON format: always quoted string to preserve precision
- Scale capped at 18 (MAX_SCALE) to prevent overflow

## References

- [IEEE 754 Floating Point](https://en.wikipedia.org/wiki/IEEE_754)
- [EIP-20 Token Standard](https://eips.ethereum.org/EIPS/eip-20) (18 decimals)
- Polymarket uses 6 decimal places for USDC prices
