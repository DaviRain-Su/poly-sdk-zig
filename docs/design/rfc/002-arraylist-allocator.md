# RFC-002: ArrayList Allocator Pattern (Zig 0.15)

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Created** | 2024-12-31 |
| **Author** | - |

## Problem

Zig 0.15 changed `std.ArrayList` to be **Unmanaged** by default. This means:

```zig
// ❌ This code compiles but is WRONG in Zig 0.15
var list = try std.ArrayList(u8).initCapacity(allocator, 16);
try list.append(item);  // ERROR: missing allocator parameter
```

The correct usage is:

```zig
// ✅ Correct in Zig 0.15
try list.append(allocator, item);
```

This is a **breaking change** from earlier Zig versions and a common source of bugs.

## Requirements

1. All code must compile correctly on Zig 0.15.2+
2. Memory allocation patterns must be explicit
3. Prevent runtime panics from incorrect ArrayList usage

## Proposal

### Rule 1: Always use `initCapacity`

```zig
// ❌ Don't use init()
var list = std.ArrayList(T).init(allocator);

// ✅ Use initCapacity() with estimated size
var list = try std.ArrayList(T).initCapacity(allocator, 16);
```

### Rule 2: Pass allocator to mutation methods

| Method | Zig 0.14 | Zig 0.15 |
|--------|----------|----------|
| `append` | `list.append(item)` | `list.append(allocator, item)` |
| `appendSlice` | `list.appendSlice(items)` | `list.appendSlice(allocator, items)` |
| `addOne` | `list.addOne()` | `list.addOne(allocator)` |
| `toOwnedSlice` | `list.toOwnedSlice()` | `list.toOwnedSlice(allocator)` |
| `ensureTotalCapacity` | `list.ensureTotalCapacity(n)` | `list.ensureTotalCapacity(allocator, n)` |

### Rule 3: AssumeCapacity variants don't need allocator

```zig
// These are safe without allocator (no reallocation)
list.appendAssumeCapacity(item);
list.addOneAssumeCapacity();
```

## Alternatives Considered

### Alternative 1: Use Managed ArrayList wrapper

Create a wrapper that stores the allocator internally.

**Pros**: Cleaner API, matches old behavior
**Cons**: Extra indirection, non-idiomatic Zig

**Decision**: Rejected - follow Zig idioms, be explicit about allocation

### Alternative 2: Use ArrayListAligned

**Pros**: Different API, might be clearer
**Cons**: Still unmanaged in 0.15, same problem

**Decision**: Rejected - doesn't solve the problem

## Decision

**Follow Zig 0.15 conventions explicitly**:

1. Document the pattern in AGENTS.md
2. Include quick reference table
3. All code reviews must check ArrayList usage

## Implementation

Add to AGENTS.md:

```zig
// Zig 0.15 ArrayList API Quick Reference
| Method | Needs allocator |
|--------|----------------|
| initCapacity(allocator, n) | Yes |
| deinit() | No |
| append(allocator, item) | Yes |
| appendSlice(allocator, items) | Yes |
| toOwnedSlice(allocator) | Yes |
| appendAssumeCapacity(item) | No |
```

## References

- [Zig 0.15 Release Notes](https://ziglang.org/download/0.15.0/release-notes.html)
- [std.ArrayList source](https://github.com/ziglang/zig/blob/master/lib/std/array_list.zig)
