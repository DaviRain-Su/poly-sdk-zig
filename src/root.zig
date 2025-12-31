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

/// Order module (OrderBuilder, types)
pub const order = @import("order/mod.zig");

/// RFQ (Request for Quote) module
pub const rfq = @import("rfq/mod.zig");

/// WebSocket module
pub const ws = @import("ws/mod.zig");

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
pub const L2Auth = auth.L2Auth;
pub const L1PolyHeader = auth.L1PolyHeader;
pub const L2PolyHeader = auth.L2PolyHeader;
pub const ApiCreds = auth.ApiCreds;

// Re-export order types
pub const OrderBuilder = order.OrderBuilder;
pub const OrderBuilderOptions = order.OrderBuilderOptions;
pub const SignedOrder = order.SignedOrder;
pub const Side = order.Side;
pub const SignatureType = order.SignatureType;
pub const TickSize = order.TickSize;
pub const TimeInForce = order.TimeInForce;
pub const OrderArgs = order.OrderArgs;
pub const MarketOrderArgs = order.MarketOrderArgs;
pub const CreateOrderOptions = order.CreateOrderOptions;

// Re-export RFQ types
pub const RfqClient = rfq.RfqClient;
pub const RfqError = rfq.RfqError;
pub const RfqMatchType = rfq.RfqMatchType;
pub const RfqRequestState = rfq.RfqRequestState;
pub const RfqQuoteState = rfq.RfqQuoteState;
pub const RfqRequest = rfq.RfqRequest;
pub const RfqQuote = rfq.RfqQuote;
pub const CreateRfqRequestParams = rfq.CreateRfqRequestParams;
pub const CreateRfqQuoteParams = rfq.CreateRfqQuoteParams;
pub const AcceptRfqQuoteParams = rfq.AcceptRfqQuoteParams;
pub const ApproveRfqOrderParams = rfq.ApproveRfqOrderParams;
pub const GetRfqRequestsParams = rfq.GetRfqRequestsParams;
pub const GetRfqQuotesParams = rfq.GetRfqQuotesParams;
pub const RfqConfig = rfq.RfqConfig;

// Re-export WebSocket types
pub const WebSocketClient = ws.WebSocketClient;
pub const WebSocketError = ws.WebSocketError;
pub const ConnectionState = ws.ConnectionState;
pub const WsEndpoints = ws.Endpoints;
pub const BookMessage = ws.BookMessage;
pub const PriceChangeMessage = ws.PriceChangeMessage;
pub const WsOrderMessage = ws.OrderMessage;
pub const WsTradeMessage = ws.TradeMessage;

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

test "root module L2Auth" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(allocator, "key", "secret", "pass");
    defer creds.deinit();

    const l2 = L2Auth.init(&creds);
    try std.testing.expectEqualStrings("key", l2.getApiKey());
}

test "root module order types" {
    // 创建钱包
    const wallet = try Wallet.fromPrivateKeyHex(
        "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318",
    );

    // 创建订单构建器
    const builder = OrderBuilder.init(&wallet, .{ .chain_id = 137 });
    try std.testing.expectEqual(@as(u64, 137), builder.getChainId());

    // 测试类型导出
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(Side.BUY));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(Side.SELL));

    // 测试 TickSize
    const tick = TickSize.@"0.01".toDecimal();
    try std.testing.expectEqual(@as(u8, 2), tick.scale);

    // 创建订单
    const signed_order = try builder.createOrderWithSalt(.{
        .token_id = "12345",
        .price = try Decimal.fromString("0.5"),
        .size = try Decimal.fromString("100"),
        .side = .BUY,
    }, .{}, 12345);

    try std.testing.expectEqual(@as(u256, 12345), signed_order.salt);
    try std.testing.expectEqual(Side.BUY, signed_order.side);
}

test "all submodules" {
    _ = @import("clob/mod.zig");
    _ = @import("types/mod.zig");
    _ = @import("error.zig");
    _ = @import("http/mod.zig");
    _ = @import("crypto/mod.zig");
    _ = @import("signer/mod.zig");
    _ = @import("auth/mod.zig");
    _ = @import("order/mod.zig");
    _ = @import("rfq/mod.zig");
    _ = @import("ws/mod.zig");
}

test "rfq module exports" {
    // Verify RFQ types are accessible
    _ = RfqClient;
    _ = RfqError;

    // Test enum types
    try std.testing.expectEqual(RfqMatchType.COMPLEMENTARY, RfqMatchType.fromString("COMPLEMENTARY").?);
    try std.testing.expectEqual(RfqRequestState.PENDING, RfqRequestState.fromString("PENDING").?);
    try std.testing.expectEqual(RfqQuoteState.ACCEPTED, RfqQuoteState.fromString("ACCEPTED").?);

    // Test struct types
    const request = RfqRequest{
        .request_id = "req-123",
        .state = "PENDING",
    };
    try std.testing.expectEqualStrings("req-123", request.request_id);

    const quote = RfqQuote{
        .quote_id = "quote-456",
        .match_type = "COMPLEMENTARY",
    };
    try std.testing.expectEqualStrings("quote-456", quote.quote_id);

    // Test parameter types
    const create_params = CreateRfqRequestParams{
        .asset_in = "USDC",
        .asset_out = "token-123",
        .amount_in = "10000",
    };
    try std.testing.expectEqualStrings("USDC", create_params.asset_in);

    const config = RfqConfig{
        .min_request_amount = "1000",
        .enabled = true,
    };
    try std.testing.expect(config.enabled);
}

test "ws module exports" {
    // Verify WebSocket types are accessible
    _ = WebSocketClient;
    _ = WebSocketError;
    _ = ConnectionState;

    // Test endpoints
    try std.testing.expectEqualStrings(
        "wss://ws-subscriptions-clob.polymarket.com/ws/market",
        WsEndpoints.marketUrl(),
    );
    try std.testing.expectEqualStrings(
        "wss://ws-subscriptions-clob.polymarket.com/ws/user",
        WsEndpoints.userUrl(),
    );

    // Test message types
    const book = BookMessage{
        .asset_id = "test",
        .market = "0x123",
        .bids = &.{},
        .asks = &.{},
        .timestamp = "123456",
    };
    try std.testing.expectEqualStrings("test", book.asset_id);

    // Test channel type
    try std.testing.expectEqualStrings("market", ws.ChannelType.market.toString());
    try std.testing.expectEqualStrings("user", ws.ChannelType.user.toString());
}
