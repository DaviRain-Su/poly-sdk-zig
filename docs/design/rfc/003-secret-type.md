# RFC-003: Secret Type for Sensitive Data

| Field | Value |
|-------|-------|
| **Status** | Accepted |
| **Created** | 2024-12-31 |
| **Author** | - |

## Problem

API keys, private keys, and passphrases can be accidentally leaked through:

1. Debug logging: `std.log.debug("creds: {}", .{credentials});`
2. Error messages: `return error.AuthFailed; // may include key in stack trace`
3. Core dumps and crash reports

```zig
// Dangerous: raw sensitive data
const Credentials = struct {
    api_key: []const u8,
    passphrase: []const u8,
};

std.log.info("Using creds: {any}", .{creds});  // LEAKS SECRETS!
```

## Requirements

1. Prevent accidental logging of sensitive values
2. Allow intentional access when needed
3. Zero runtime overhead for normal operations
4. Work with Zig's format system

## Proposal

Create a generic `Secret(T)` wrapper type:

```zig
pub fn Secret(comptime T: type) type {
    return struct {
        const Self = @This();
        
        value: T,
        
        pub fn init(value: T) Self {
            return .{ .value = value };
        }
        
        /// Intentionally access the secret value
        pub fn reveal(self: Self) T {
            return self.value;
        }
        
        /// Format always outputs "[REDACTED]"
        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = self;
            _ = fmt;
            _ = options;
            try writer.writeAll("[REDACTED]");
        }
    };
}
```

### Usage

```zig
const Credentials = struct {
    api_key: Secret([]const u8),
    passphrase: Secret([]const u8),
};

const creds = Credentials{
    .api_key = Secret([]const u8).init("sk_live_xxx"),
    .passphrase = Secret([]const u8).init("secret123"),
};

// Safe: prints "[REDACTED]"
std.log.info("Using key: {}", .{creds.api_key});

// Intentional access
const key = creds.api_key.reveal();
try signRequest(key);
```

## Alternatives Considered

### Alternative 1: Runtime flag to disable logging

```zig
var DISABLE_SECRET_LOGGING = true;
```

**Pros**: Simple
**Cons**: Still possible to leak if flag is wrong, runtime overhead

**Decision**: Rejected - compile-time safety is better

### Alternative 2: Custom logging function

```zig
fn safeLog(comptime fmt: []const u8, args: anytype) void {
    // Filter sensitive fields
}
```

**Pros**: Centralized control
**Cons**: Easy to bypass, doesn't protect against `std.debug.print`

**Decision**: Rejected - doesn't solve the root problem

### Alternative 3: Encryption at rest

Encrypt secrets in memory, decrypt only when needed.

**Pros**: Defense in depth
**Cons**: Complexity, key management, performance overhead

**Decision**: Deferred - good for future enhancement, not MVP

## Decision

**Use compile-time Secret wrapper** because:

1. Zero runtime cost (format is only called during logging)
2. Type system prevents accidental access
3. `reveal()` makes intentional access explicit and grep-able
4. Works with all Zig formatting

## Implementation Notes

- Secret should be `extern struct` compatible if needed for FFI
- Consider adding `SecretSlice` for `[]const u8` specifically
- Add `eql` method for comparing secrets without revealing

## Security Considerations

This is **defense in depth**, not a complete solution:

- Memory can still be dumped
- Secrets are still in process memory
- Side-channel attacks are still possible

For production, consider:
- Memory-safe secret storage (mlock, guard pages)
- Hardware security modules (HSM)
- Short-lived credentials

## References

- [OWASP Sensitive Data Exposure](https://owasp.org/www-project-web-security-testing-guide/latest/4-Web_Application_Security_Testing/04-Authentication_Testing/09-Testing_for_Weak_Password_Change_or_Reset_Functionalities)
- Rust's `secrecy` crate for similar pattern
