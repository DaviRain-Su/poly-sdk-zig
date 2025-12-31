//! Polymarket CLOB API module.
//!
//! This module provides access to Polymarket's Central Limit Order Book API.
//!
//! ## Example
//!
//! ```zig
//! const poly = @import("poly-sdk-zig");
//!
//! var client = poly.clob.ClobClient.init(allocator, .{});
//! defer client.deinit();
//!
//! // Get server status
//! const ok = try client.getOk();
//! defer ok.deinit();
//!
//! // Get markets
//! const markets = try client.getMarkets(.{});
//! ```

pub const types = @import("types/mod.zig");
pub const client = @import("client.zig");

// Re-export main types
pub const ClobClient = client.ClobClient;
pub const Config = client.Config;
pub const Endpoints = client.Endpoints;
pub const ApiResponse = client.ApiResponse;

pub const BASE_URL_MAINNET = client.BASE_URL_MAINNET;
pub const BASE_URL_TESTNET = client.BASE_URL_TESTNET;

// Re-export common types
pub const OrderType = types.OrderType;
pub const Side = types.Side;
pub const Market = types.Market;
pub const Token = types.Token;
pub const OrderBookSummary = types.OrderBookSummary;

// ============================================================================
// Tests
// ============================================================================

test "module imports" {
    _ = types;
    _ = client;
}

test "type exports" {
    _ = ClobClient;
    _ = Config;
    _ = OrderType.GTC;
    _ = Side.BUY;
}
