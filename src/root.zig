//! Polymarket CLOB API Client for Zig
//!
//! A high-performance Zig implementation for interacting with Polymarket's
//! Central Limit Order Book (CLOB) API.
//!
//! ## Quick Start
//!
//! ```zig
//! const poly = @import("poly-sdk-zig");
//!
//! // Use core types
//! const price = try poly.types.Decimal.fromString("0.65");
//! const wallet = try poly.types.Address.fromHex("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
//! ```
//!
//! ## Modules
//!
//! - `types`: Core types (Decimal, Address, UUID, Secret)
//!
//! ## Design Principles
//!
//! - **Financial Precision**: All monetary values use `Decimal`, never `f64`
//! - **Security First**: Sensitive data wrapped in `Secret` to prevent logging
//! - **Memory Safety**: Explicit allocator management, no hidden allocations
//! - **Zig 0.15+**: Built for modern Zig with full API compatibility

const std = @import("std");

/// Core types module
pub const types = @import("types/mod.zig");

// Re-export commonly used types at root level for convenience
pub const Decimal = types.Decimal;
pub const Address = types.Address;
pub const UUID = types.UUID;
pub const Secret = types.Secret;
pub const SecretString = types.SecretString;

// ============================================================================
// Tests
// ============================================================================

test "root module exports" {
    // Verify all types are accessible
    _ = Decimal.ZERO;
    _ = Address.ZERO;
    _ = UUID.NIL;
    _ = SecretString.init("test");
}

test "all submodules" {
    _ = @import("types/mod.zig");
}
