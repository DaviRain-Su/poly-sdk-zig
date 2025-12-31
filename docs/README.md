# Documentation

Documentation mirrors the source code structure. Each implemented module has a corresponding doc.

## Structure

```
docs/
├── README.md           # This file
├── design/
│   └── rfc/            # Design decisions (Why)
│       ├── 001-decimal-type.md
│       ├── 002-arraylist-allocator.md
│       └── 003-secret-type.md
└── types/              # Mirrors src/types/
    └── decimal.md      # Documents src/types/decimal.zig
```

## Implemented Modules

| Source | Documentation | Status |
|--------|---------------|--------|
| `src/types/decimal.zig` | [types/decimal.md](./types/decimal.md) | ✅ |
| `src/types/address.zig` | - | ⏳ Not implemented |
| `src/types/uuid.zig` | - | ⏳ Not implemented |
| `src/types/secret.zig` | - | ⏳ Not implemented |

## RFCs

Design decisions with problem, solution, and alternatives considered.

| RFC | Title | Status |
|-----|-------|--------|
| [001](./design/rfc/001-decimal-type.md) | Decimal Type | Accepted |
| [002](./design/rfc/002-arraylist-allocator.md) | ArrayList Allocator (Zig 0.15) | Accepted |
| [003](./design/rfc/003-secret-type.md) | Secret Type | Accepted |

## Principle

> **Documentation follows code, not the other way around.**

- Only document what exists in `src/`
- Each `.zig` file can have a corresponding `.md` file
- RFCs explain **why**, module docs explain **what** and **how**
