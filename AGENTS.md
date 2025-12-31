# AGENTS.md - Coding Agent Guidelines

This document provides guidelines for AI coding agents working on the Polymarket Zig CLOB Client SDK.

**Zig Version**: 0.15.2 (minimum)

## Build Commands

```bash
# Build the project
zig build

# Run the executable
zig build run

# Run all tests
zig build test

# Run tests for a single file
zig test src/types/decimal.zig

# Run with specific optimization
zig build -Doptimize=ReleaseFast

# Clean build cache
rm -rf .zig-cache zig-out
```

## Project Structure

```
src/
├── root.zig          # Library entry point (public API exports)
├── main.zig          # CLI executable entry point
├── types/            # Core types (Decimal, Address, UUID, Secret)
├── clob/             # CLOB client implementation
├── auth/             # Authentication (L1/L2/Builder)
├── crypto/           # Cryptographic operations
├── http/             # HTTP client wrapper
├── error.zig         # Error definitions
└── constants.zig     # Constants and configurations
```

## Code Style Guidelines

### Naming Conventions

```zig
// Types: PascalCase
const MyStruct = struct {};
const ClientState = enum {};

// Functions and variables: camelCase
fn processOrder() void {}
var orderCount: u32 = 0;

// Constants: snake_case or SCREAMING_SNAKE_CASE
const max_retries = 3;
const POLYGON_CHAIN_ID: u64 = 137;

// File names: snake_case.zig
// order_builder.zig, http_client.zig
```

### Imports

```zig
const std = @import("std");

// Group imports: std first, then project modules
const types = @import("types/mod.zig");
const Decimal = types.Decimal;
```

### Documentation

All public APIs must have doc comments:

```zig
/// Creates a new limit order.
///
/// Parameters:
///   - token_id: Token identifier
///   - price: Order price (0 < price < 1)
///
/// Returns: Signable order object
/// Errors: InvalidPrice, InvalidSize
pub fn createLimitOrder(token_id: []const u8, price: Decimal) !SignableOrder {
    // ...
}
```

## Zig 0.15 API Requirements (CRITICAL)

### ArrayList (Unmanaged - requires allocator)

```zig
// Initialization - always use initCapacity
var list = try std.ArrayList(T).initCapacity(allocator, 16);
defer list.deinit();

// ❌ WRONG - Zig 0.15 append needs allocator
list.append(item);
try list.append(item);

// ✅ CORRECT - pass allocator parameter
try list.append(allocator, item);
try list.appendSlice(allocator, items);
const ptr = try list.addOne(allocator);
try list.ensureTotalCapacity(allocator, n);
const owned = try list.toOwnedSlice(allocator);

// AssumeCapacity variants don't need allocator
list.appendAssumeCapacity(item);
```

### ArrayList API Quick Reference (Zig 0.15+)

| Method | Needs allocator | Description |
|--------|----------------|-------------|
| `initCapacity(allocator, n)` | Yes | Initialize with capacity |
| `deinit()` | No | Free memory |
| `append(allocator, item)` | Yes | Add single element |
| `appendSlice(allocator, items)` | Yes | Add multiple elements |
| `addOne(allocator)` | Yes | Get pointer to new element |
| `ensureTotalCapacity(allocator, n)` | Yes | Ensure capacity |
| `toOwnedSlice(allocator)` | Yes | Convert to owned slice |
| `appendAssumeCapacity(item)` | No | Assumes capacity exists |
| `items` field | No | Read-only access |

### HashMap

```zig
// Managed (StringHashMap, AutoHashMap) - stores allocator
var map = std.StringHashMap(V).init(allocator);
defer map.deinit();
try map.put(key, value);  // No allocator needed

// Unmanaged (StringHashMapUnmanaged) - needs allocator
var umap = std.StringHashMapUnmanaged(V){};
defer umap.deinit(allocator);
try umap.put(allocator, key, value);  // Needs allocator

// Use getOrPut to avoid duplicate lookups
const result = try map.getOrPut(key);
if (!result.found_existing) {
    result.value_ptr.* = new_value;
}
```

### HTTP Client (fetch API)

```zig
var client: std.http.Client = .{ .allocator = allocator };
defer client.deinit();

// Simple GET
const result = try client.fetch(.{
    .location = .{ .url = "https://example.com/api" },
});

// With response body
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
    // Use response_buffer.items
}
```

### std.json

```zig
// Parse and free
const parsed = try std.json.parseFromSlice(MyStruct, allocator, json_string, .{});
defer parsed.deinit();
const data = parsed.value;

// Stringify
const json_output = try std.json.stringifyAlloc(allocator, data, .{});
defer allocator.free(json_output);
```

### std.fmt

```zig
// Allocating format
const formatted = try std.fmt.allocPrint(allocator, "value: {d}", .{42});
defer allocator.free(formatted);

// Non-allocating format (use buffer)
var buffer: [256]u8 = undefined;
const result = try std.fmt.bufPrint(&buffer, "value: {d}", .{42});
```

## Memory Management

### Resource Cleanup

```zig
// Always use defer for cleanup
const buffer = try allocator.alloc(u8, size);
defer allocator.free(buffer);

// Use errdefer for error path cleanup
fn createResource(allocator: Allocator) !*Resource {
    const res = try allocator.create(Resource);
    errdefer allocator.destroy(res);
    
    res.data = try allocator.alloc(u8, 100);
    errdefer allocator.free(res.data);
    
    try res.initialize();
    return res;
}
```

### Arena Allocator for Temporary Allocations

```zig
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const temp = arena.allocator();
// All allocations freed at once with arena.deinit()
```

### String Ownership

```zig
// Borrowed - don't free
fn process(borrowed: []const u8) void {
    // Read-only, cannot free
}

// Owned - caller must free
fn createString(allocator: std.mem.Allocator) ![]u8 {
    return try allocator.dupe(u8, "owned string");
}

const owned = try createString(allocator);
defer allocator.free(owned);
```

## Error Handling

```zig
// ❌ WRONG - silently ignoring errors
const result = doSomething() catch null;

// ✅ CORRECT - propagate errors
const result = try doSomething();

// ✅ CORRECT - meaningful error handling
const result = doSomething() catch |err| {
    std.log.err("Failed: {}", .{err});
    return err;
};
```

## Project-Specific Rules

### Financial Calculations

```zig
// ❌ NEVER use f64 for money
const price: f64 = 0.65;
const total = price * 100.0;  // May be 64.99999999...

// ✅ CORRECT - use Decimal
const price = try Decimal.fromString("0.65");
const size = try Decimal.fromString("100");
const total = price.mul(size);  // Exact 65.00
```

### Sensitive Data

```zig
// ❌ WRONG - raw sensitive data
const Credentials = struct {
    secret: []const u8,      // May be accidentally printed
};

// ✅ CORRECT - wrap with Secret
const Credentials = struct {
    secret: Secret([]const u8),
    passphrase: Secret([]const u8),
};

// Secret.format() outputs "[REDACTED]"
```

### No async/await

Zig 0.11+ removed native async/await. Use synchronous code or threads:

```zig
// Synchronous (preferred)
const result = try fetchData();

// Threading for concurrent operations
const thread = try std.Thread.spawn(.{}, workerFn, .{});
```

### Comptime Constraints

```zig
// ❌ WRONG - runtime value as comptime parameter
fn process(runtime_type: type) void { ... }

// ✅ CORRECT - comptime parameter known at compile time
fn process(comptime T: type) void { ... }
```

### Logging

```zig
// ❌ WRONG - leaking sensitive info
std.log.info("API Key: {s}", .{credentials.key});

// ✅ CORRECT - safe logging
std.log.info("Request to {s}", .{endpoint});
std.log.debug("Order ID: {s}", .{order_id});
```

## Pre-Commit Checklist

### Zig 0.15 API
- [ ] `ArrayList` uses `initCapacity` and passes `allocator` to mutation methods
- [ ] `toOwnedSlice` passes `allocator` parameter
- [ ] Distinguish Managed (`StringHashMap`) vs Unmanaged (`StringHashMapUnmanaged`)
- [ ] HTTP requests use Zig 0.15 `fetch` API

### Memory Safety
- [ ] All allocations have corresponding `defer`/`errdefer`
- [ ] Use `errdefer` for error path cleanup
- [ ] No `async`/`await` usage (removed in Zig 0.11+)

### Project Rules
- [ ] Sensitive data wrapped with `Secret`
- [ ] Financial calculations use `Decimal`, not `f64`
- [ ] Logs don't contain sensitive information
- [ ] Public APIs have doc comments
- [ ] Tests pass: `zig build test`

## Additional Documentation

See `docs/` for detailed design documents:
- `docs/ARCHITECTURE.md` - System architecture
- `docs/TYPES.md` - Type system design
- `docs/API_REFERENCE.md` - API documentation
