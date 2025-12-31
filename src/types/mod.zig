//! Core types for the Polymarket CLOB client.
//!
//! This module exports all fundamental types used throughout the SDK:
//!
//! - `Decimal`: High-precision decimal for financial calculations (never use f64!)
//! - `Address`: Ethereum address with EIP-55 checksum support
//! - `UUID`: Universally unique identifier (v4)
//! - `Secret`: Wrapper to prevent sensitive data from being logged
//!
//! ## Example
//!
//! ```zig
//! const types = @import("types/mod.zig");
//!
//! const price = try types.Decimal.fromString("0.65");
//! const wallet = try types.Address.fromHex("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
//! const order_id = types.UUID.v4();
//! const api_key = types.SecretString.init("sk_live_xxx");
//! ```

const std = @import("std");

// Re-export all types
pub const decimal = @import("decimal.zig");
pub const address = @import("address.zig");
pub const uuid = @import("uuid.zig");
pub const secret = @import("secret.zig");
pub const contracts = @import("contracts.zig");

// Convenience type aliases
pub const Decimal = decimal.Decimal;
pub const Address = address.Address;
pub const UUID = uuid.UUID;
pub const Secret = secret.Secret;
pub const SecretString = secret.SecretString;

// Contract configuration types
pub const ContractConfig = contracts.ContractConfig;
pub const Chain = contracts.Chain;

// ============================================================================
// Tests - verify all modules compile and work together
// ============================================================================

test "all types import" {
    // Just verify imports work
    _ = Decimal.ZERO;
    _ = Address.ZERO;
    _ = UUID.NIL;
    _ = SecretString.init("test");
}

test "decimal module" {
    _ = @import("decimal.zig");
}

test "address module" {
    _ = @import("address.zig");
}

test "uuid module" {
    _ = @import("uuid.zig");
}

test "secret module" {
    _ = @import("secret.zig");
}

test "contracts module" {
    _ = @import("contracts.zig");
}

test "type interop example" {
    // Simulate a typical order creation scenario
    const price = try Decimal.fromString("0.65");
    const size = try Decimal.fromString("100");
    const total = price.mul(size);

    try std.testing.expect(total.equal(try Decimal.fromString("65")));

    const wallet = try Address.fromHex("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
    try std.testing.expect(!wallet.isZero());

    const order_id = UUID.v4();
    try std.testing.expectEqual(@as(u4, 4), order_id.getVersion());

    const api_key = SecretString.init("sk_live_xxx");
    try std.testing.expectEqualStrings("sk_live_xxx", api_key.reveal());
}
