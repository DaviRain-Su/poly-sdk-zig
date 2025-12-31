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
//! // Create CLOB client
//! var client = poly.ClobClient.init(allocator, .{});
//! defer client.deinit();
//!
//! // Check server status
//! const ok = try client.getOk();
//! defer client.freeOkResponse(&ok);
//!
//! // Get markets
//! const markets = try client.getMarkets(.{});
//! defer markets.deinit();
//!
//! // Use core types
//! const price = try poly.Decimal.fromString("0.65");
//! const wallet = try poly.Address.fromHex("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");
//! ```
//!
//! ## Modules
//!
//! - `clob`: CLOB API client and types
//! - `types`: Core types (Decimal, Address, UUID, Secret)
//! - `crypto`: Cryptographic primitives (Keccak256, ECDSA, HMAC)
//! - `signer`: Wallet and EIP-712 signing utilities
//! - `auth`: Authentication (L1/L2 auth, API credentials)
//! - `errors`: Error types and utilities
//! - `http`: HTTP client utilities
//!
//! ## Design Principles
//!
//! - **Financial Precision**: All monetary values use `Decimal`, never `f64`
//! - **Security First**: Sensitive data wrapped in `Secret` to prevent logging
//! - **Memory Safety**: Explicit allocator management, no hidden allocations
//! - **Zig 0.15+**: Built for modern Zig with full API compatibility

const std = @import("std");

/// CLOB API client module
pub const clob = @import("clob/mod.zig");

/// Core types module
pub const types = @import("types/mod.zig");

/// Error types and utilities
pub const errors = @import("error.zig");

/// HTTP client module
pub const http = @import("http/mod.zig");

/// Cryptographic primitives module
pub const crypto = @import("crypto/mod.zig");

/// Signer module (Wallet, EIP-712)
pub const signer = @import("signer/mod.zig");

/// Authentication module (L1/L2 auth)
pub const auth = @import("auth/mod.zig");

// Re-export CLOB client at root level for convenience
pub const ClobClient = clob.ClobClient;

// Re-export commonly used types at root level for convenience
pub const Decimal = types.Decimal;
pub const Address = types.Address;
pub const UUID = types.UUID;
pub const Secret = types.Secret;
pub const SecretString = types.SecretString;

// Re-export error types
pub const Error = errors.Error;
pub const ErrorContext = errors.ErrorContext;

// Re-export HTTP types
pub const HttpClient = http.HttpClient;

// Re-export crypto types
pub const PrivateKey = crypto.PrivateKey;
pub const PublicKey = crypto.PublicKey;
pub const Signature = crypto.Signature;
pub const keccak256 = crypto.keccak256;
pub const hmacSha256 = crypto.hmacSha256;

// Re-export signer types
pub const Wallet = signer.Wallet;
pub const WalletError = signer.WalletError;

// Re-export auth types
pub const L1Auth = auth.L1Auth;
pub const L1PolyHeader = auth.L1PolyHeader;
pub const L2PolyHeader = auth.L2PolyHeader;
pub const ApiCreds = auth.ApiCreds;

// ============================================================================
// Tests
// ============================================================================

test "root module exports" {
    // Verify all types are accessible
    _ = Decimal.ZERO;
    _ = Address.ZERO;
    _ = UUID.NIL;
    _ = SecretString.init("test");

    // Verify error types are accessible
    const ctx = ErrorContext.fromError(Error.NotFound);
    try std.testing.expect(ctx.message.len > 0);

    // Verify HTTP types are accessible
    _ = HttpClient;

    // Verify CLOB client is accessible
    _ = ClobClient;

    // Verify crypto types are accessible
    const hash = keccak256("test");
    try std.testing.expectEqual(@as(usize, 32), hash.len);

    // Verify signer types are accessible
    const wallet = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    var addr_buf: [42]u8 = undefined;
    _ = wallet.getAddressLowerHex(&addr_buf);

    // Verify auth types are accessible
    const l1 = L1Auth.init(&wallet, .{ .chain_id = 137 });
    try std.testing.expectEqual(@as(u64, 137), l1.getChainId());
}

test "all submodules" {
    _ = @import("clob/mod.zig");
    _ = @import("types/mod.zig");
    _ = @import("error.zig");
    _ = @import("http/mod.zig");
    _ = @import("crypto/mod.zig");
    _ = @import("signer/mod.zig");
    _ = @import("auth/mod.zig");
}
