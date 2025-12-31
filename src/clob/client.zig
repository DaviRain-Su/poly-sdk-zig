//! Polymarket CLOB API Client.
//!
//! This client provides access to Polymarket's Central Limit Order Book API.
//! It supports all public (L0) endpoints that don't require authentication.
//!
//! ## Example
//!
//! ```zig
//! const clob = @import("clob/client.zig");
//!
//! var client = clob.ClobClient.init(allocator, .{});
//! defer client.deinit();
//!
//! // Check server status
//! const ok = try client.getOk();
//!
//! // Get markets
//! const markets = try client.getMarkets(.{});
//!
//! // Get order book
//! const book = try client.getOrderBook("token_id_here");
//! ```

const std = @import("std");
const types = @import("types/mod.zig");

/// HTTP Error types
pub const Error = error{
    ConnectionFailed,
    ConnectionRefused,
    Timeout,
    DnsResolutionFailed,
    TlsHandshakeFailed,
    ConnectionReset,
    BadRequest,
    Unauthorized,
    Forbidden,
    NotFound,
    MethodNotAllowed,
    Conflict,
    UnprocessableEntity,
    RateLimited,
    InternalServerError,
    BadGateway,
    ServiceUnavailable,
    GatewayTimeout,
    UnknownHttpError,
    InvalidJson,
    OutOfMemory,
};

/// Map HTTP status to error
fn errorFromStatus(status: std.http.Status) ?Error {
    const code = @intFromEnum(status);
    return switch (code) {
        200...299 => null,
        400 => Error.BadRequest,
        401 => Error.Unauthorized,
        403 => Error.Forbidden,
        404 => Error.NotFound,
        429 => Error.RateLimited,
        500 => Error.InternalServerError,
        502 => Error.BadGateway,
        503 => Error.ServiceUnavailable,
        504 => Error.GatewayTimeout,
        else => Error.UnknownHttpError,
    };
}

/// CLOB API endpoints
pub const Endpoints = struct {
    pub const OK = "/";
    pub const TIME = "/time";
    pub const MARKETS = "/markets";
    pub const SIMPLIFIED_MARKETS = "/simplified-markets";
    pub const SAMPLING_MARKETS = "/sampling-markets";
    pub const BOOK = "/book";
    pub const PRICE = "/price";
    pub const MIDPOINT = "/midpoint";
    pub const SPREAD = "/spread";
    pub const TICK_SIZE = "/tick-size";
    pub const NEG_RISK = "/neg-risk";
    pub const LAST_TRADE_PRICE = "/last-trade-price";
};

/// Default base URLs
pub const BASE_URL_MAINNET = "https://clob.polymarket.com";
pub const BASE_URL_TESTNET = "https://clob-testnet.polymarket.com";

/// Client configuration
pub const Config = struct {
    /// Base URL for API requests
    base_url: []const u8 = BASE_URL_MAINNET,
    /// Request timeout in nanoseconds
    timeout_ns: u64 = 30 * std.time.ns_per_s,
};

/// Response wrapper for API calls
pub fn ApiResponse(comptime T: type) type {
    return struct {
        const Self = @This();
        data: T,

        pub fn getData(self: Self) T {
            return self.data;
        }
    };
}

/// Simple OK response
pub const OkResponse = struct {
    body: []const u8,
};

/// Server time response
pub const ServerTimeResponse = struct {
    timestamp: ?i64 = null,
};

/// Polymarket CLOB API Client
pub const ClobClient = struct {
    allocator: std.mem.Allocator,
    config: Config,
    http_client: std.http.Client,

    /// Initialize CLOB client
    pub fn init(allocator: std.mem.Allocator, config: Config) ClobClient {
        return ClobClient{
            .allocator = allocator,
            .config = config,
            .http_client = .{ .allocator = allocator },
        };
    }

    /// Deinitialize client
    pub fn deinit(self: *ClobClient) void {
        self.http_client.deinit();
    }

    /// Build full URL from path
    fn buildUrl(self: *ClobClient, path: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.config.base_url, path });
    }

    /// Perform GET request and return raw body
    fn doGet(self: *ClobClient, path: []const u8) ![]u8 {
        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        var response_buffer = try std.ArrayList(u8).initCapacity(self.allocator, 4096);
        errdefer response_buffer.deinit(self.allocator);

        const result = self.http_client.fetch(.{
            .location = .{ .url = url },
            .method = .GET,
            .extra_headers = &.{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
            },
            .response_storage = .{ .dynamic = &response_buffer },
        }) catch |err| {
            return switch (err) {
                error.ConnectionRefused => Error.ConnectionRefused,
                error.ConnectionResetByPeer => Error.ConnectionReset,
                error.ConnectionTimedOut => Error.Timeout,
                error.NetworkUnreachable => Error.ConnectionFailed,
                error.UnknownHostName => Error.DnsResolutionFailed,
                else => Error.ConnectionFailed,
            };
        };

        // Check for HTTP errors
        if (errorFromStatus(result.status)) |err| {
            response_buffer.deinit(self.allocator);
            return err;
        }

        return response_buffer.toOwnedSlice(self.allocator);
    }

    // =========================================================================
    // Server Status Endpoints
    // =========================================================================

    /// Check if server is OK - GET /
    pub fn getOk(self: *ClobClient) !OkResponse {
        const body = try self.doGet(Endpoints.OK);
        return OkResponse{ .body = body };
    }

    /// Free OK response
    pub fn freeOkResponse(self: *ClobClient, response: *OkResponse) void {
        self.allocator.free(response.body);
    }

    /// Get server timestamp - GET /time
    pub fn getServerTime(self: *ClobClient) !ServerTimeResponse {
        const body = try self.doGet(Endpoints.TIME);
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(ServerTimeResponse, self.allocator, body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    // =========================================================================
    // Market Endpoints
    // =========================================================================

    /// Get all markets - GET /markets
    pub fn getMarkets(self: *ClobClient, params: types.MarketsParams) !std.json.Parsed([]types.Market) {
        var path_buf: [256]u8 = undefined;
        const path = blk: {
            if (params.next_cursor) |cursor| {
                break :blk std.fmt.bufPrint(&path_buf, "{s}?next_cursor={s}", .{ Endpoints.MARKETS, cursor }) catch Endpoints.MARKETS;
            } else {
                break :blk Endpoints.MARKETS;
            }
        };

        const body = try self.doGet(path);
        defer self.allocator.free(body);

        return std.json.parseFromSlice([]types.Market, self.allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get simplified markets - GET /simplified-markets
    pub fn getSimplifiedMarkets(self: *ClobClient) !std.json.Parsed([]types.SimplifiedMarket) {
        const body = try self.doGet(Endpoints.SIMPLIFIED_MARKETS);
        defer self.allocator.free(body);

        return std.json.parseFromSlice([]types.SimplifiedMarket, self.allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get single market by condition ID - GET /markets/{condition_id}
    pub fn getMarket(self: *ClobClient, condition_id: []const u8) !std.json.Parsed(types.Market) {
        var path_buf: [256]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ Endpoints.MARKETS, condition_id });

        const body = try self.doGet(path);
        defer self.allocator.free(body);

        return std.json.parseFromSlice(types.Market, self.allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    // =========================================================================
    // Price and Order Book Endpoints
    // =========================================================================

    /// Get order book for a token - GET /book?token_id=...
    pub fn getOrderBook(self: *ClobClient, token_id: []const u8) !std.json.Parsed(types.OrderBookSummary) {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}?token_id={s}", .{ Endpoints.BOOK, token_id });

        const body = try self.doGet(path);
        defer self.allocator.free(body);

        return std.json.parseFromSlice(types.OrderBookSummary, self.allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get price for a token - GET /price?token_id=...&side=...
    pub fn getPrice(self: *ClobClient, token_id: []const u8, side: types.Side) !types.PriceResponse {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}?token_id={s}&side={s}", .{
            Endpoints.PRICE,
            token_id,
            side.toString(),
        });

        const body = try self.doGet(path);
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(types.PriceResponse, self.allocator, body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get midpoint price for a token - GET /midpoint?token_id=...
    pub fn getMidpoint(self: *ClobClient, token_id: []const u8) !types.MidpointResponse {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}?token_id={s}", .{ Endpoints.MIDPOINT, token_id });

        const body = try self.doGet(path);
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(types.MidpointResponse, self.allocator, body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get spread for a token - GET /spread?token_id=...
    pub fn getSpread(self: *ClobClient, token_id: []const u8) !types.SpreadResponse {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}?token_id={s}", .{ Endpoints.SPREAD, token_id });

        const body = try self.doGet(path);
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(types.SpreadResponse, self.allocator, body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get tick size for a token - GET /tick-size?token_id=...
    pub fn getTickSize(self: *ClobClient, token_id: []const u8) !types.TickSizeResponse {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}?token_id={s}", .{ Endpoints.TICK_SIZE, token_id });

        const body = try self.doGet(path);
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(types.TickSizeResponse, self.allocator, body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get neg risk status for a token - GET /neg-risk?token_id=...
    pub fn getNegRisk(self: *ClobClient, token_id: []const u8) !types.NegRiskResponse {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}?token_id={s}", .{ Endpoints.NEG_RISK, token_id });

        const body = try self.doGet(path);
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(types.NegRiskResponse, self.allocator, body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get last trade price for a token - GET /last-trade-price?token_id=...
    pub fn getLastTradePrice(self: *ClobClient, token_id: []const u8) !types.LastTradePriceResponse {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}?token_id={s}", .{ Endpoints.LAST_TRADE_PRICE, token_id });

        const body = try self.doGet(path);
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(types.LastTradePriceResponse, self.allocator, body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "ClobClient init" {
    var client = ClobClient.init(std.testing.allocator, .{});
    defer client.deinit();

    try std.testing.expectEqualStrings(BASE_URL_MAINNET, client.config.base_url);
}

test "ClobClient with custom config" {
    var client = ClobClient.init(std.testing.allocator, .{
        .base_url = BASE_URL_TESTNET,
        .timeout_ns = 60 * std.time.ns_per_s,
    });
    defer client.deinit();

    try std.testing.expectEqualStrings(BASE_URL_TESTNET, client.config.base_url);
}

test "Endpoints constants" {
    try std.testing.expectEqualStrings("/", Endpoints.OK);
    try std.testing.expectEqualStrings("/time", Endpoints.TIME);
    try std.testing.expectEqualStrings("/markets", Endpoints.MARKETS);
    try std.testing.expectEqualStrings("/book", Endpoints.BOOK);
}

test "errorFromStatus success" {
    try std.testing.expectEqual(@as(?Error, null), errorFromStatus(.ok));
    try std.testing.expectEqual(@as(?Error, null), errorFromStatus(.created));
    try std.testing.expectEqual(@as(?Error, null), errorFromStatus(.no_content));
}

test "errorFromStatus errors" {
    try std.testing.expectEqual(Error.BadRequest, errorFromStatus(.bad_request).?);
    try std.testing.expectEqual(Error.Unauthorized, errorFromStatus(.unauthorized).?);
    try std.testing.expectEqual(Error.NotFound, errorFromStatus(.not_found).?);
    try std.testing.expectEqual(Error.RateLimited, errorFromStatus(.too_many_requests).?);
    try std.testing.expectEqual(Error.InternalServerError, errorFromStatus(.internal_server_error).?);
}
