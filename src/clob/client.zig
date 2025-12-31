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
const root = @import("../root.zig");

// Auth imports
const L1Auth = root.auth.L1Auth;
const L2Auth = root.auth.L2Auth;
const ApiCreds = root.auth.ApiCreds;
const L1PolyHeader = root.auth.L1PolyHeader;
const L2PolyHeader = root.auth.L2PolyHeader;
const BuilderAuth = root.auth.BuilderAuth;
const BuilderCreds = root.auth.BuilderCreds;
const BuilderPolyHeader = root.auth.BuilderPolyHeader;

// Order imports
const SignedOrder = root.order.SignedOrder;
const OrderBuilder = root.order.OrderBuilder;
const OrderBuilderOptions = root.order.OrderBuilderOptions;
const OrderArgs = root.order.OrderArgs;
const MarketOrderArgs = root.order.MarketOrderArgs;
const MarketOrderOptions = root.order.MarketOrderOptions;
const CreateOrderOptions = root.order.CreateOrderOptions;
const TimeInForce = root.order.TimeInForce;
const Wallet = root.signer.Wallet;

// RFQ imports
const RfqClient = root.rfq.RfqClient;

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
    // L0 - Public endpoints
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

    // L2 - Authenticated endpoints
    pub const ORDER = "/order";
    pub const ORDERS = "/orders";
    pub const DATA_ORDERS = "/data/orders";
    pub const DATA_ORDER = "/data/order";
    pub const CANCEL_ALL = "/cancel-all";
    pub const CANCEL_MARKET_ORDERS = "/cancel-market-orders";
    pub const DATA_TRADES = "/data/trades";
    pub const BALANCE_ALLOWANCE = "/balance-allowance";
    pub const NOTIFICATIONS = "/notifications";
    pub const API_KEYS = "/auth/api-keys";
    pub const API_KEY = "/auth/api-key";
    pub const BAN_STATUS = "/auth/ban-status/closed-only";

    // Heartbeat (注意使用 /v1/ 前缀)
    pub const HEARTBEAT = "/v1/heartbeats";

    // Builder endpoints
    pub const BUILDER_API_KEY = "/auth/builder-api-key";
    pub const BUILDER_TRADES = "/builder/trades";

    // v0.5 - Rewards and Analytics endpoints
    pub const ORDER_SCORING = "/order-scoring";
    pub const ORDERS_SCORING = "/orders-scoring";
    pub const LIVE_ACTIVITY_EVENTS = "/live-activity/events";
    pub const FEE_RATE = "/fee-rate";
    pub const BALANCE_ALLOWANCE_UPDATE = "/balance-allowance/update";

    // Batch endpoints
    pub const BOOKS = "/books";
    pub const MIDPOINTS = "/midpoints";
    pub const PRICES = "/prices";
    pub const SPREADS = "/spreads";
    pub const LAST_TRADES_PRICES = "/last-trades-prices";
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
    /// Chain ID (137 = Polygon mainnet, 80002 = Amoy testnet)
    chain_id: u64 = 137,
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

    // Authentication (optional)
    wallet: ?*const Wallet = null,
    api_creds: ?*const ApiCreds = null,

    // Builder authentication (optional)
    builder_creds: ?*const BuilderCreds = null,

    /// Initialize CLOB client (public API only)
    pub fn init(allocator: std.mem.Allocator, config: Config) ClobClient {
        return ClobClient{
            .allocator = allocator,
            .config = config,
            .http_client = .{ .allocator = allocator },
        };
    }

    /// Initialize authenticated CLOB client
    pub fn initWithAuth(
        allocator: std.mem.Allocator,
        config: Config,
        wallet: *const Wallet,
        creds: *const ApiCreds,
    ) ClobClient {
        return ClobClient{
            .allocator = allocator,
            .config = config,
            .http_client = .{ .allocator = allocator },
            .wallet = wallet,
            .api_creds = creds,
        };
    }

    /// Initialize authenticated CLOB client with Builder credentials
    pub fn initWithBuilder(
        allocator: std.mem.Allocator,
        config: Config,
        wallet: *const Wallet,
        creds: *const ApiCreds,
        builder_creds: *const BuilderCreds,
    ) ClobClient {
        return ClobClient{
            .allocator = allocator,
            .config = config,
            .http_client = .{ .allocator = allocator },
            .wallet = wallet,
            .api_creds = creds,
            .builder_creds = builder_creds,
        };
    }

    /// Deinitialize client
    pub fn deinit(self: *ClobClient) void {
        self.http_client.deinit();
    }

    /// Check if client has authentication configured
    pub fn hasAuth(self: *const ClobClient) bool {
        return self.api_creds != null;
    }

    /// Check if client has Builder authentication configured
    pub fn hasBuilderAuth(self: *const ClobClient) bool {
        return self.builder_creds != null;
    }

    /// Get RFQ (Request for Quote) sub-client
    ///
    /// Returns an RfqClient that shares the same HTTP connection and
    /// authentication with the main ClobClient.
    ///
    /// ## Example
    ///
    /// ```zig
    /// var client = ClobClient.initWithAuth(allocator, .{}, &wallet, &creds);
    /// defer client.deinit();
    ///
    /// // Create RFQ request
    /// const request = try client.rfq().createRfqRequest(.{
    ///     .asset_in = "USDC",
    ///     .asset_out = token_id,
    ///     .amount_in = "10000",
    /// });
    ///
    /// // Get best quote
    /// const best = try client.rfq().getRfqBestQuote(request.request_id);
    /// ```
    pub fn rfqClient(self: *ClobClient) RfqClient {
        return RfqClient.init(
            self.allocator,
            &self.http_client,
            self.config.base_url,
            self.api_creds,
        );
    }

    /// Build full URL from path
    fn buildUrl(self: *ClobClient, path: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}{s}", .{ self.config.base_url, path });
    }

    /// Perform GET request and return raw body
    fn doGet(self: *ClobClient, path: []const u8) ![]u8 {
        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        const uri = std.Uri.parse(url) catch return Error.BadRequest;

        var req = self.http_client.request(.GET, uri, .{
            .extra_headers = &.{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
            },
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
        defer req.deinit();

        req.sendBodiless() catch return Error.ConnectionFailed;
        var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

        // Check for HTTP errors
        if (errorFromStatus(response.head.status)) |err| {
            return err;
        }

        // Read response body
        return readResponseBody(self.allocator, &response) catch return Error.ConnectionFailed;
    }

    /// Read response body into a newly allocated slice
    fn readResponseBody(allocator: std.mem.Allocator, response: anytype) ![]u8 {
        var reader = response.reader(&.{});
        return reader.allocRemaining(allocator, std.Io.Limit.limited(10 * 1024 * 1024)) catch return error.ReadFailed;
    }

    /// Perform authenticated GET request
    fn doAuthGet(self: *ClobClient, path: []const u8) ![]u8 {
        const creds = self.api_creds orelse return Error.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Generate L2 auth header
        const l2 = L2Auth.init(creds);
        const auth_header = l2.generateHeader(.{
            .method = "GET",
            .path = path,
            .body = null,
        }) catch return Error.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return Error.BadRequest;

        var req = self.http_client.request(.GET, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
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
        defer req.deinit();

        req.sendBodiless() catch return Error.ConnectionFailed;
        var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

        if (errorFromStatus(response.head.status)) |err| {
            return err;
        }

        return readResponseBody(self.allocator, &response) catch return Error.ConnectionFailed;
    }

    /// Perform authenticated POST request
    fn doAuthPost(self: *ClobClient, path: []const u8, body: []const u8) ![]u8 {
        const creds = self.api_creds orelse return Error.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Generate L2 auth header
        const l2 = L2Auth.init(creds);
        const auth_header = l2.generateHeader(.{
            .method = "POST",
            .path = path,
            .body = body,
        }) catch return Error.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return Error.BadRequest;

        var req = self.http_client.request(.POST, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
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
        defer req.deinit();

        // Send body
        req.transfer_encoding = .{ .content_length = body.len };
        var body_writer = req.sendBodyUnflushed(&.{}) catch return Error.ConnectionFailed;
        body_writer.writer.writeAll(body) catch return Error.ConnectionFailed;
        body_writer.end() catch return Error.ConnectionFailed;
        if (req.connection) |conn| {
            conn.flush() catch return Error.ConnectionFailed;
        }

        var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

        if (errorFromStatus(response.head.status)) |err| {
            return err;
        }

        return readResponseBody(self.allocator, &response) catch return Error.ConnectionFailed;
    }

    /// Perform authenticated DELETE request
    fn doAuthDelete(self: *ClobClient, path: []const u8, body: ?[]const u8) ![]u8 {
        const creds = self.api_creds orelse return Error.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Generate L2 auth header
        const l2 = L2Auth.init(creds);
        const auth_header = l2.generateHeader(.{
            .method = "DELETE",
            .path = path,
            .body = body,
        }) catch return Error.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return Error.BadRequest;

        var req = self.http_client.request(.DELETE, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
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
        defer req.deinit();

        // Send body if provided
        if (body) |b| {
            req.transfer_encoding = .{ .content_length = b.len };
            var body_writer = req.sendBodyUnflushed(&.{}) catch return Error.ConnectionFailed;
            body_writer.writer.writeAll(b) catch return Error.ConnectionFailed;
            body_writer.end() catch return Error.ConnectionFailed;
            if (req.connection) |conn| {
                conn.flush() catch return Error.ConnectionFailed;
            }
        } else {
            req.sendBodiless() catch return Error.ConnectionFailed;
        }

        var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

        if (errorFromStatus(response.head.status)) |err| {
            return err;
        }

        return readResponseBody(self.allocator, &response) catch return Error.ConnectionFailed;
    }

    /// Perform Builder authenticated GET request
    fn doBuilderGet(self: *ClobClient, path: []const u8) ![]u8 {
        const builder_creds = self.builder_creds orelse return Error.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Generate Builder auth header
        const builder_auth = BuilderAuth.init(builder_creds);
        const auth_header = builder_auth.generateHeader(.{
            .method = "GET",
            .path = path,
            .body = null,
        }) catch return Error.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return Error.BadRequest;

        var req = self.http_client.request(.GET, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
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
        defer req.deinit();

        req.sendBodiless() catch return Error.ConnectionFailed;
        var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

        if (errorFromStatus(response.head.status)) |err| {
            return err;
        }

        return readResponseBody(self.allocator, &response) catch return Error.ConnectionFailed;
    }

    /// Perform Builder authenticated POST request
    fn doBuilderPost(self: *ClobClient, path: []const u8, body: []const u8) ![]u8 {
        const builder_creds = self.builder_creds orelse return Error.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Generate Builder auth header
        const builder_auth = BuilderAuth.init(builder_creds);
        const auth_header = builder_auth.generateHeader(.{
            .method = "POST",
            .path = path,
            .body = body,
        }) catch return Error.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return Error.BadRequest;

        var req = self.http_client.request(.POST, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
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
        defer req.deinit();

        // Send body
        req.transfer_encoding = .{ .content_length = body.len };
        var body_writer = req.sendBodyUnflushed(&.{}) catch return Error.ConnectionFailed;
        body_writer.writer.writeAll(body) catch return Error.ConnectionFailed;
        body_writer.end() catch return Error.ConnectionFailed;
        if (req.connection) |conn| {
            conn.flush() catch return Error.ConnectionFailed;
        }

        var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

        if (errorFromStatus(response.head.status)) |err| {
            return err;
        }

        return readResponseBody(self.allocator, &response) catch return Error.ConnectionFailed;
    }

    /// Perform Builder authenticated DELETE request
    fn doBuilderDelete(self: *ClobClient, path: []const u8, body: ?[]const u8) ![]u8 {
        const builder_creds = self.builder_creds orelse return Error.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Generate Builder auth header
        const builder_auth = BuilderAuth.init(builder_creds);
        const auth_header = builder_auth.generateHeader(.{
            .method = "DELETE",
            .path = path,
            .body = body,
        }) catch return Error.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return Error.BadRequest;

        var req = self.http_client.request(.DELETE, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
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
        defer req.deinit();

        // Send body if provided
        if (body) |b| {
            req.transfer_encoding = .{ .content_length = b.len };
            var body_writer = req.sendBodyUnflushed(&.{}) catch return Error.ConnectionFailed;
            body_writer.writer.writeAll(b) catch return Error.ConnectionFailed;
            body_writer.end() catch return Error.ConnectionFailed;
            if (req.connection) |conn| {
                conn.flush() catch return Error.ConnectionFailed;
            }
        } else {
            req.sendBodiless() catch return Error.ConnectionFailed;
        }

        var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

        if (errorFromStatus(response.head.status)) |err| {
            return err;
        }

        return readResponseBody(self.allocator, &response) catch return Error.ConnectionFailed;
    }

    // =========================================================================
    // L2 Auth Method Aliases (for clearer code)
    // =========================================================================

    /// L2 authenticated GET request (alias for doAuthGet)
    fn doL2Get(self: *ClobClient, path: []const u8) ![]u8 {
        return self.doAuthGet(path);
    }

    /// L2 authenticated POST request (alias for doAuthPost)
    fn doL2Post(self: *ClobClient, path: []const u8, body: []const u8) ![]u8 {
        return self.doAuthPost(path, body);
    }

    /// L2 authenticated DELETE request (alias for doAuthDelete with null body)
    fn doL2Delete(self: *ClobClient, path: []const u8) ![]u8 {
        return self.doAuthDelete(path, null);
    }

    // =========================================================================
    // L1 Auth Methods (EIP-712 signature for API Key management)
    // =========================================================================

    /// Perform L1 authenticated POST request
    ///
    /// L1 authentication uses EIP-712 signatures for wallet verification.
    /// Used for creating and deriving API keys.
    fn doL1Post(self: *ClobClient, path: []const u8, body: ?[]const u8) ![]u8 {
        const wallet = self.wallet orelse return Error.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Generate L1 auth header
        const l1 = L1Auth.init(wallet, .{ .chain_id = self.config.chain_id });
        const auth_header = l1.generateHeader() catch return Error.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return Error.BadRequest;

        var req = self.http_client.request(.POST, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
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
        defer req.deinit();

        // Send body if provided
        if (body) |b| {
            req.transfer_encoding = .{ .content_length = b.len };
            var body_writer = req.sendBodyUnflushed(&.{}) catch return Error.ConnectionFailed;
            body_writer.writer.writeAll(b) catch return Error.ConnectionFailed;
            body_writer.end() catch return Error.ConnectionFailed;
            if (req.connection) |conn| {
                conn.flush() catch return Error.ConnectionFailed;
            }
        } else {
            req.sendBodiless() catch return Error.ConnectionFailed;
        }

        var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

        if (errorFromStatus(response.head.status)) |err| {
            return err;
        }

        return readResponseBody(self.allocator, &response) catch return Error.ConnectionFailed;
    }

    /// Perform L1 authenticated GET request
    fn doL1Get(self: *ClobClient, path: []const u8) ![]u8 {
        const wallet = self.wallet orelse return Error.Unauthorized;

        const url = try self.buildUrl(path);
        defer self.allocator.free(url);

        // Generate L1 auth header
        const l1 = L1Auth.init(wallet, .{ .chain_id = self.config.chain_id });
        const auth_header = l1.generateHeader() catch return Error.Unauthorized;

        const poly_headers = auth_header.toHttpHeaders();

        const uri = std.Uri.parse(url) catch return Error.BadRequest;

        var req = self.http_client.request(.GET, uri, .{
            .extra_headers = &[_]std.http.Header{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "User-Agent", .value = "poly-sdk-zig/0.1.0" },
                .{ .name = "Content-Type", .value = "application/json" },
                poly_headers[0],
                poly_headers[1],
                poly_headers[2],
                poly_headers[3],
            },
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
        defer req.deinit();

        req.sendBodiless() catch return Error.ConnectionFailed;
        var response = req.receiveHead(&.{}) catch return Error.ConnectionFailed;

        if (errorFromStatus(response.head.status)) |err| {
            return err;
        }

        return readResponseBody(self.allocator, &response) catch return Error.ConnectionFailed;
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

    /// Get sampling markets - GET /sampling-markets
    ///
    /// Returns a random sample of markets. Useful for initial data loading
    /// or when you don't need the full market list.
    pub fn getSamplingMarkets(self: *ClobClient) !std.json.Parsed([]types.Market) {
        const body = try self.doGet(Endpoints.SAMPLING_MARKETS);
        defer self.allocator.free(body);

        return std.json.parseFromSlice([]types.Market, self.allocator, body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get sampling simplified markets - GET /sampling-simplified-markets
    ///
    /// Returns a random sample of simplified markets.
    pub fn getSamplingSimplifiedMarkets(self: *ClobClient) !std.json.Parsed([]types.SimplifiedMarket) {
        const path = "/sampling-simplified-markets";
        const body = try self.doGet(path);
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

    // =========================================================================
    // L2 Authenticated Endpoints - Order Management
    // =========================================================================

    /// Post a single order - POST /order
    ///
    /// Requires L2 authentication.
    pub fn postOrder(
        self: *ClobClient,
        order: *const SignedOrder,
        order_type: types.OrderType,
    ) !types.PostOrderResponse {
        // Build request body
        var buffers = SignedOrder.OrderDataBuffers{};
        const order_data = order.toOrderData(&buffers);

        // Serialize to JSON
        const request_body = .{
            .order = order_data,
            .orderType = order_type.toString(),
        };

        const json_body = std.json.stringifyAlloc(self.allocator, request_body, .{}) catch return Error.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = try self.doAuthPost(Endpoints.ORDER, json_body);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.PostOrderResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Post multiple orders - POST /orders
    ///
    /// Requires L2 authentication.
    /// All orders in the batch will use the same order type.
    pub fn postOrders(
        self: *ClobClient,
        orders: []const SignedOrder,
        order_type: types.OrderType,
    ) !types.PostOrdersResponse {
        // Build order data array
        // 需要分配缓冲区数组
        const buffer_count = orders.len;
        var buffers_list = self.allocator.alloc(SignedOrder.OrderDataBuffers, buffer_count) catch return Error.OutOfMemory;
        defer self.allocator.free(buffers_list);

        var order_data_list = self.allocator.alloc(SignedOrder.OrderDataView, buffer_count) catch return Error.OutOfMemory;
        defer self.allocator.free(order_data_list);

        for (orders, 0..) |*order, i| {
            order_data_list[i] = order.toOrderData(&buffers_list[i]);
        }

        // Build request body - 使用简化的结构以避免 JSON 序列化问题
        // API 期望的格式: { "orders": [{ "order": {...}, "orderType": "GTC" }, ...] }
        var json_buf = std.ArrayList(u8).init(self.allocator);
        defer json_buf.deinit();

        var writer = json_buf.writer();
        try writer.writeAll("{\"orders\":[");

        for (order_data_list, 0..) |order_data, i| {
            if (i > 0) try writer.writeByte(',');
            try writer.writeAll("{\"order\":");
            try std.json.stringify(order_data, .{}, writer);
            try writer.writeAll(",\"orderType\":\"");
            try writer.writeAll(order_type.toString());
            try writer.writeAll("\"}");
        }

        try writer.writeAll("]}");

        const json_body = json_buf.items;
        const response_body = try self.doAuthPost(Endpoints.ORDERS, json_body);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.PostOrdersResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get open orders - GET /data/orders
    ///
    /// Requires L2 authentication.
    pub fn getOpenOrders(self: *ClobClient, params: types.OpenOrdersParams) !std.json.Parsed(types.PaginatedOrders) {
        var path_buf: [512]u8 = undefined;
        var path_len: usize = 0;

        // Start with base path
        const base = Endpoints.DATA_ORDERS;
        @memcpy(path_buf[0..base.len], base);
        path_len = base.len;

        // Add query parameters
        var has_params = false;

        if (params.id) |id| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "id={s}", .{id}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.market) |market| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "market={s}", .{market}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.asset_id) |asset_id| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "asset_id={s}", .{asset_id}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.next_cursor) |cursor| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "next_cursor={s}", .{cursor}) catch return Error.BadRequest;
            path_len += param.len;
        }

        const path = path_buf[0..path_len];
        const response_body = try self.doAuthGet(path);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice(types.PaginatedOrders, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get a single order by ID - GET /data/order/{id}
    ///
    /// Requires L2 authentication.
    pub fn getOrder(self: *ClobClient, order_id: []const u8) !std.json.Parsed(types.OpenOrder) {
        var path_buf: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ Endpoints.DATA_ORDER, order_id });

        const response_body = try self.doAuthGet(path);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice(types.OpenOrder, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Cancel a single order - DELETE /order
    ///
    /// Requires L2 authentication.
    pub fn cancelOrder(self: *ClobClient, order_id: []const u8) !types.CancelOrderResponse {
        const request_body = .{ .orderID = order_id };

        const json_body = std.json.stringifyAlloc(self.allocator, request_body, .{}) catch return Error.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = try self.doAuthDelete(Endpoints.ORDER, json_body);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.CancelOrderResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Cancel multiple orders - DELETE /orders
    ///
    /// Requires L2 authentication.
    pub fn cancelOrders(self: *ClobClient, order_ids: []const []const u8) !types.CancelOrderResponse {
        const request_body = .{ .orderIDs = order_ids };

        const json_body = std.json.stringifyAlloc(self.allocator, request_body, .{}) catch return Error.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = try self.doAuthDelete(Endpoints.ORDERS, json_body);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.CancelOrderResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Cancel all open orders - DELETE /cancel-all
    ///
    /// Requires L2 authentication.
    pub fn cancelAll(self: *ClobClient) !types.CancelOrderResponse {
        const response_body = try self.doAuthDelete(Endpoints.CANCEL_ALL, null);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.CancelOrderResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Cancel all orders for a market - DELETE /cancel-market-orders
    ///
    /// Requires L2 authentication.
    pub fn cancelMarketOrders(self: *ClobClient, params: types.CancelMarketOrdersRequest) !types.CancelOrderResponse {
        const json_body = std.json.stringifyAlloc(self.allocator, params, .{}) catch return Error.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = try self.doAuthDelete(Endpoints.CANCEL_MARKET_ORDERS, json_body);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.CancelOrderResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    // =========================================================================
    // L2 Authenticated Endpoints - Trades
    // =========================================================================

    /// Get trades - GET /data/trades
    ///
    /// Requires L2 authentication.
    pub fn getTrades(self: *ClobClient, params: types.TradesParams) !std.json.Parsed(types.PaginatedTrades) {
        var path_buf: [512]u8 = undefined;
        var path_len: usize = 0;

        const base = Endpoints.DATA_TRADES;
        @memcpy(path_buf[0..base.len], base);
        path_len = base.len;

        var has_params = false;

        if (params.id) |id| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "id={s}", .{id}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.market) |market| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "market={s}", .{market}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.next_cursor) |cursor| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "next_cursor={s}", .{cursor}) catch return Error.BadRequest;
            path_len += param.len;
        }

        const path = path_buf[0..path_len];
        const response_body = try self.doAuthGet(path);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice(types.PaginatedTrades, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    // =========================================================================
    // L2 Authenticated Endpoints - Account
    // =========================================================================

    /// Get balance and allowance - GET /balance-allowance
    ///
    /// Requires L2 authentication.
    pub fn getBalanceAllowance(self: *ClobClient, params: types.BalanceAllowanceParams) !types.BalanceAllowanceResponse {
        var path_buf: [512]u8 = undefined;
        var path_len: usize = 0;

        const base = Endpoints.BALANCE_ALLOWANCE;
        @memcpy(path_buf[0..base.len], base);
        path_len = base.len;

        var has_params = false;

        if (params.asset_type) |asset_type| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "asset_type={s}", .{asset_type.toString()}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.token_id) |token_id| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "token_id={s}", .{token_id}) catch return Error.BadRequest;
            path_len += param.len;
        }

        const path = path_buf[0..path_len];
        const response_body = try self.doAuthGet(path);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.BalanceAllowanceResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get notifications - GET /notifications
    ///
    /// Requires L2 authentication.
    pub fn getNotifications(self: *ClobClient) !std.json.Parsed([]types.Notification) {
        const response_body = try self.doAuthGet(Endpoints.NOTIFICATIONS);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.Notification, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Drop notifications - DELETE /notifications
    ///
    /// Requires L2 authentication.
    pub fn dropNotifications(self: *ClobClient, ids: []const []const u8) !types.DropNotificationsResponse {
        const request_body = .{ .ids = ids };

        const json_body = std.json.stringifyAlloc(self.allocator, request_body, .{}) catch return Error.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = try self.doAuthDelete(Endpoints.NOTIFICATIONS, json_body);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.DropNotificationsResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    // =========================================================================
    // L1 Authenticated Endpoints - API Key Management
    // =========================================================================

    /// Create a new API key using L1 (EIP-712) authentication
    ///
    /// Endpoint: POST /auth/api-key
    /// Auth: L1 (Wallet signature required)
    ///
    /// This creates a new API key for the authenticated wallet.
    /// The returned credentials should be stored securely.
    ///
    /// ## Example
    /// ```zig
    /// var client = ClobClient.init(allocator, .{});
    /// client.wallet = &wallet;  // Set wallet for L1 auth
    ///
    /// var creds = try client.createApiKey();
    /// defer creds.deinit();
    ///
    /// // Now use creds for L2 authentication
    /// ```
    pub fn createApiKey(self: *ClobClient) !ApiCreds {
        if (self.wallet == null) return Error.Unauthorized;

        const response_body = try self.doL1Post(Endpoints.API_KEY, null);
        defer self.allocator.free(response_body);

        return ApiCreds.fromJson(self.allocator, response_body) catch Error.InvalidJson;
    }

    /// Derive an existing API key using L1 (EIP-712) authentication
    ///
    /// Endpoint: GET /auth/derive-api-key
    /// Auth: L1 (Wallet signature required)
    ///
    /// If an API key already exists for this wallet, this endpoint returns it.
    /// This is useful when you've lost your API credentials but still have access to the wallet.
    ///
    /// ## Example
    /// ```zig
    /// var creds = try client.deriveApiKey();
    /// defer creds.deinit();
    /// ```
    pub fn deriveApiKey(self: *ClobClient) !ApiCreds {
        if (self.wallet == null) return Error.Unauthorized;

        const path = "/auth/derive-api-key";
        const response_body = try self.doL1Get(path);
        defer self.allocator.free(response_body);

        return ApiCreds.fromJson(self.allocator, response_body) catch Error.InvalidJson;
    }

    /// Create or derive API key (convenience method)
    ///
    /// Auth: L1 (Wallet signature required)
    ///
    /// This method first tries to derive an existing API key. If that fails
    /// (e.g., no key exists), it creates a new one.
    ///
    /// This is the recommended way to obtain API credentials when you're not
    /// sure if a key already exists.
    ///
    /// ## Example
    /// ```zig
    /// var client = ClobClient.init(allocator, .{});
    /// client.wallet = &wallet;
    ///
    /// var creds = try client.createOrDeriveApiKey();
    /// defer creds.deinit();
    ///
    /// // Use creds for authenticated requests
    /// ```
    pub fn createOrDeriveApiKey(self: *ClobClient) !ApiCreds {
        if (self.wallet == null) return Error.Unauthorized;

        // First try to derive existing key
        if (self.deriveApiKey()) |creds| {
            return creds;
        } else |err| {
            // If derive fails (e.g., no existing key), create a new one
            if (err == Error.NotFound or err == Error.Unauthorized) {
                return self.createApiKey();
            }
            return err;
        }
    }

    /// Set wallet for L1 authentication
    ///
    /// This is useful when you want to use L1 endpoints on an existing client.
    pub fn setWallet(self: *ClobClient, wallet: *const Wallet) void {
        self.wallet = wallet;
    }

    /// Set API credentials for L2 authentication
    ///
    /// This is useful after obtaining credentials via createOrDeriveApiKey().
    pub fn setApiCreds(self: *ClobClient, creds: *const ApiCreds) void {
        self.api_creds = creds;
    }

    // =========================================================================
    // L2 Authenticated Endpoints - Heartbeat
    // =========================================================================

    /// Send heartbeat - POST /v1/heartbeats
    ///
    /// Requires L2 authentication.
    ///
    /// The heartbeat endpoint is used by market makers to keep their orders active.
    /// If no heartbeat is received within 10 seconds, all orders will be canceled.
    ///
    /// Recommended to call every 5-8 seconds in a background thread.
    pub fn postHeartbeat(self: *ClobClient) !types.HeartbeatResponse {
        const response_body = try self.doAuthPost(Endpoints.HEARTBEAT, "{}");
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.HeartbeatResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    // =========================================================================
    // Builder Authenticated Endpoints
    // =========================================================================

    /// Create a Builder API Key - POST /auth/builder-api-key
    ///
    /// Requires L2 authentication (NOT Builder authentication).
    /// Returns a new Builder API Key that can be used for Builder-specific endpoints.
    pub fn createBuilderApiKey(self: *ClobClient) !types.BuilderApiKeyResponse {
        const response_body = try self.doAuthPost(Endpoints.BUILDER_API_KEY, "{}");
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.BuilderApiKeyResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        // Copy strings to return owned data
        return types.BuilderApiKeyResponse{
            .api_key = parsed.value.api_key,
            .api_secret = parsed.value.api_secret,
            .passphrase = parsed.value.passphrase,
            .created_at = parsed.value.created_at,
        };
    }

    /// Get all Builder API Keys - GET /auth/builder-api-key
    ///
    /// Requires L2 authentication.
    /// Returns a list of all Builder API Keys associated with the account.
    pub fn getBuilderApiKeys(self: *ClobClient) !std.json.Parsed([]types.BuilderApiKeyInfo) {
        const response_body = try self.doAuthGet(Endpoints.BUILDER_API_KEY);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.BuilderApiKeyInfo, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Revoke a Builder API Key - DELETE /auth/builder-api-key
    ///
    /// Requires L2 authentication.
    /// Revokes the specified Builder API Key.
    pub fn revokeBuilderApiKey(self: *ClobClient, api_key: []const u8) !types.RevokeBuilderApiKeyResponse {
        const request_body = .{ .apiKey = api_key };

        const json_body = std.json.stringifyAlloc(self.allocator, request_body, .{}) catch return Error.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = try self.doAuthDelete(Endpoints.BUILDER_API_KEY, json_body);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(types.RevokeBuilderApiKeyResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
        }) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get Builder trades - GET /builder/trades
    ///
    /// Requires Builder authentication.
    /// Returns the trade history for the Builder account.
    pub fn getBuilderTrades(self: *ClobClient, params: types.BuilderTradesParams) !std.json.Parsed(types.PaginatedBuilderTrades) {
        var path_buf: [512]u8 = undefined;
        var path_len: usize = 0;

        const base = Endpoints.BUILDER_TRADES;
        @memcpy(path_buf[0..base.len], base);
        path_len = base.len;

        var has_params = false;

        if (params.market) |market| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "market={s}", .{market}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.asset_id) |asset_id| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "asset_id={s}", .{asset_id}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.before) |before| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "before={d}", .{before}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.after) |after| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "after={d}", .{after}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.limit) |limit| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "limit={d}", .{limit}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.next_cursor) |cursor| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "next_cursor={s}", .{cursor}) catch return Error.BadRequest;
            path_len += param.len;
        }

        const path = path_buf[0..path_len];
        const response_body = try self.doBuilderGet(path);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice(types.PaginatedBuilderTrades, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    // =========================================================================
    // Convenience Methods
    // =========================================================================

    /// Create an order using the OrderBuilder
    ///
    /// Convenience method that wraps OrderBuilder.createOrder.
    /// Requires wallet to be set.
    pub fn createOrder(
        self: *ClobClient,
        args: OrderArgs,
        options: CreateOrderOptions,
    ) !SignedOrder {
        const wallet = self.wallet orelse return Error.Unauthorized;
        const builder = OrderBuilder.init(wallet, .{ .chain_id = self.config.chain_id });
        return builder.createOrder(args, options) catch return Error.BadRequest;
    }

    /// Create and post an order in one step
    ///
    /// Convenience method that creates, signs, and posts an order.
    pub fn createAndPostOrder(
        self: *ClobClient,
        args: OrderArgs,
        options: CreateOrderOptions,
        order_type: types.OrderType,
    ) !types.PostOrderResponse {
        const order = try self.createOrder(args, options);
        return self.postOrder(&order, order_type);
    }

    /// Create a market order using the OrderBuilder
    ///
    /// Convenience method that wraps OrderBuilder.createMarketOrder.
    /// Requires wallet and order book to be provided.
    ///
    /// Note: For market orders, you should first fetch the order book using
    /// getOrderBook(), then pass it to this method.
    pub fn createMarketOrder(
        self: *ClobClient,
        args: MarketOrderArgs,
        order_book: *const types.OrderBookSummary,
        options: MarketOrderOptions,
    ) !SignedOrder {
        const wallet = self.wallet orelse return Error.Unauthorized;
        const builder = OrderBuilder.init(wallet, .{ .chain_id = self.config.chain_id });
        return builder.createMarketOrder(args, order_book, options) catch return Error.BadRequest;
    }

    /// Create and post a market order in one step
    ///
    /// Convenience method that creates, signs, and posts a market order.
    /// The order type is determined by MarketOrderOptions.time_in_force (FOK or FAK).
    pub fn createAndPostMarketOrder(
        self: *ClobClient,
        args: MarketOrderArgs,
        order_book: *const types.OrderBookSummary,
        options: MarketOrderOptions,
    ) !types.PostOrderResponse {
        const order = try self.createMarketOrder(args, order_book, options);

        // Map TimeInForce to OrderType
        const order_type: types.OrderType = switch (options.time_in_force) {
            .FOK => .FOK,
            .FAK => .FAK,
            .GTC => .GTC,
            .GTD => .GTD,
        };

        return self.postOrder(&order, order_type);
    }

    // =========================================================================
    // v0.5 - Order Scoring Endpoints (L2 authenticated)
    // =========================================================================

    /// Check if a single order is currently scoring for liquidity rewards
    ///
    /// Endpoint: GET /order-scoring
    /// Auth: L2 (API Key required)
    pub fn isOrderScoring(self: *ClobClient, order_id: []const u8) !bool {
        if (self.api_creds == null) return Error.Unauthorized;

        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}?orderId={s}", .{
            Endpoints.ORDER_SCORING,
            order_id,
        }) catch return Error.BadRequest;

        const response_body = try self.doL2Get(path);
        defer self.allocator.free(response_body);

        // 解析响应 - 通常返回 true/false 或包含 scoring 字段的对象
        const parsed = std.json.parseFromSlice(
            struct { scoring: bool = false },
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value.scoring;
    }

    /// Check if multiple orders are currently scoring for liquidity rewards
    ///
    /// Endpoint: POST /orders-scoring
    /// Auth: L2 (API Key required)
    pub fn areOrdersScoring(self: *ClobClient, order_ids: []const []const u8) !std.json.Parsed([]types.OrderScoringResult) {
        if (self.api_creds == null) return Error.Unauthorized;

        // 构建请求体
        var body_list = try std.ArrayList(u8).initCapacity(self.allocator, 256);
        defer body_list.deinit(self.allocator);

        try body_list.appendSlice(self.allocator, "{\"orderIds\":[");
        for (order_ids, 0..) |id, i| {
            if (i > 0) try body_list.append(self.allocator, ',');
            try body_list.append(self.allocator, '"');
            try body_list.appendSlice(self.allocator, id);
            try body_list.append(self.allocator, '"');
        }
        try body_list.appendSlice(self.allocator, "]}");

        const request_body = try body_list.toOwnedSlice(self.allocator);
        defer self.allocator.free(request_body);

        const response_body = try self.doL2Post(Endpoints.ORDERS_SCORING, request_body);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.OrderScoringResult, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    // =========================================================================
    // v0.5 - Market Analytics Endpoints (L0 public)
    // =========================================================================

    /// Get market trade events for a specific condition ID
    ///
    /// Endpoint: GET /live-activity/events/{condition_id}
    /// Auth: L0 (no auth required)
    pub fn getMarketTradesEvents(
        self: *ClobClient,
        condition_id: []const u8,
        params: struct {
            limit: ?u32 = null,
            offset: ?u32 = null,
        },
    ) !std.json.Parsed(types.MarketTradeEvents) {
        var path_buf: [512]u8 = undefined;
        var path_len: usize = 0;

        // 构建路径
        const base = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{
            Endpoints.LIVE_ACTIVITY_EVENTS,
            condition_id,
        }) catch return Error.BadRequest;
        path_len = base.len;

        var has_params = false;

        if (params.limit) |limit| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "limit={d}", .{limit}) catch return Error.BadRequest;
            path_len += param.len;
            has_params = true;
        }

        if (params.offset) |offset| {
            path_buf[path_len] = if (has_params) '&' else '?';
            path_len += 1;
            const param = std.fmt.bufPrint(path_buf[path_len..], "offset={d}", .{offset}) catch return Error.BadRequest;
            path_len += param.len;
        }

        const path = path_buf[0..path_len];
        const response_body = try self.doGet(path);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice(types.MarketTradeEvents, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get fee rate for a market
    ///
    /// Endpoint: GET /fee-rate
    /// Auth: L0 (no auth required)
    pub fn getFeeRateBps(self: *ClobClient, token_id: ?[]const u8) !types.FeeRateResponse {
        var path_buf: [256]u8 = undefined;
        var path: []const u8 = undefined;

        if (token_id) |id| {
            path = std.fmt.bufPrint(&path_buf, "{s}?token_id={s}", .{
                Endpoints.FEE_RATE,
                id,
            }) catch return Error.BadRequest;
        } else {
            path = Endpoints.FEE_RATE;
        }

        const response_body = try self.doGet(path);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(
            types.FeeRateResponse,
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    // =========================================================================
    // v0.5 - Batch Endpoints (L0 public)
    // =========================================================================

    /// Get multiple order books in a single request
    ///
    /// Endpoint: POST /books
    /// Auth: L0 (no auth required)
    pub fn getOrderBooks(self: *ClobClient, token_ids: []const []const u8) !std.json.Parsed([]types.OrderBookSummary) {
        // 构建请求体
        var body_list = try std.ArrayList(u8).initCapacity(self.allocator, 256);
        defer body_list.deinit(self.allocator);

        try body_list.appendSlice(self.allocator, "[");
        for (token_ids, 0..) |id, i| {
            if (i > 0) try body_list.append(self.allocator, ',');
            try body_list.append(self.allocator, '"');
            try body_list.appendSlice(self.allocator, id);
            try body_list.append(self.allocator, '"');
        }
        try body_list.appendSlice(self.allocator, "]");

        const request_body = try body_list.toOwnedSlice(self.allocator);
        defer self.allocator.free(request_body);

        const response_body = try self.doPost(Endpoints.BOOKS, request_body);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.OrderBookSummary, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get multiple midpoints in a single request
    ///
    /// Endpoint: POST /midpoints
    /// Auth: L0 (no auth required)
    pub fn getMidpoints(self: *ClobClient, token_ids: []const []const u8) !std.json.Parsed([]types.MidpointResponse) {
        var body_list = try std.ArrayList(u8).initCapacity(self.allocator, 256);
        defer body_list.deinit(self.allocator);

        try body_list.appendSlice(self.allocator, "[");
        for (token_ids, 0..) |id, i| {
            if (i > 0) try body_list.append(self.allocator, ',');
            try body_list.append(self.allocator, '"');
            try body_list.appendSlice(self.allocator, id);
            try body_list.append(self.allocator, '"');
        }
        try body_list.appendSlice(self.allocator, "]");

        const request_body = try body_list.toOwnedSlice(self.allocator);
        defer self.allocator.free(request_body);

        const response_body = try self.doPost(Endpoints.MIDPOINTS, request_body);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.MidpointResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get multiple prices in a single request
    ///
    /// Endpoint: POST /prices
    /// Auth: L0 (no auth required)
    pub fn getPrices(self: *ClobClient, token_ids: []const []const u8, side: ?types.Side) !std.json.Parsed([]types.PriceResponse) {
        var body_list = try std.ArrayList(u8).initCapacity(self.allocator, 256);
        defer body_list.deinit(self.allocator);

        try body_list.appendSlice(self.allocator, "{\"token_ids\":[");
        for (token_ids, 0..) |id, i| {
            if (i > 0) try body_list.append(self.allocator, ',');
            try body_list.append(self.allocator, '"');
            try body_list.appendSlice(self.allocator, id);
            try body_list.append(self.allocator, '"');
        }
        try body_list.appendSlice(self.allocator, "]");

        if (side) |s| {
            try body_list.appendSlice(self.allocator, ",\"side\":\"");
            try body_list.appendSlice(self.allocator, if (s == .BUY) "BUY" else "SELL");
            try body_list.append(self.allocator, '"');
        }

        try body_list.append(self.allocator, '}');

        const request_body = try body_list.toOwnedSlice(self.allocator);
        defer self.allocator.free(request_body);

        const response_body = try self.doPost(Endpoints.PRICES, request_body);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.PriceResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get multiple spreads in a single request
    ///
    /// Endpoint: POST /spreads
    /// Auth: L0 (no auth required)
    pub fn getSpreads(self: *ClobClient, token_ids: []const []const u8) !std.json.Parsed([]types.SpreadResponse) {
        var body_list = try std.ArrayList(u8).initCapacity(self.allocator, 256);
        defer body_list.deinit(self.allocator);

        try body_list.appendSlice(self.allocator, "[");
        for (token_ids, 0..) |id, i| {
            if (i > 0) try body_list.append(self.allocator, ',');
            try body_list.append(self.allocator, '"');
            try body_list.appendSlice(self.allocator, id);
            try body_list.append(self.allocator, '"');
        }
        try body_list.appendSlice(self.allocator, "]");

        const request_body = try body_list.toOwnedSlice(self.allocator);
        defer self.allocator.free(request_body);

        const response_body = try self.doPost(Endpoints.SPREADS, request_body);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.SpreadResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Get multiple last trade prices in a single request
    ///
    /// Endpoint: POST /last-trades-prices
    /// Auth: L0 (no auth required)
    pub fn getLastTradesPrices(self: *ClobClient, token_ids: []const []const u8) !std.json.Parsed([]types.LastTradePriceResponse) {
        var body_list = try std.ArrayList(u8).initCapacity(self.allocator, 256);
        defer body_list.deinit(self.allocator);

        try body_list.appendSlice(self.allocator, "[");
        for (token_ids, 0..) |id, i| {
            if (i > 0) try body_list.append(self.allocator, ',');
            try body_list.append(self.allocator, '"');
            try body_list.appendSlice(self.allocator, id);
            try body_list.append(self.allocator, '"');
        }
        try body_list.appendSlice(self.allocator, "]");

        const request_body = try body_list.toOwnedSlice(self.allocator);
        defer self.allocator.free(request_body);

        const response_body = try self.doPost(Endpoints.LAST_TRADES_PRICES, request_body);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.LastTradePriceResponse, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    // =========================================================================
    // v0.5 - API Key Management Endpoints (L2 authenticated)
    // =========================================================================

    /// Get list of API keys for the authenticated user
    ///
    /// Endpoint: GET /auth/api-keys
    /// Auth: L2 (API Key required)
    pub fn getApiKeys(self: *ClobClient) !std.json.Parsed([]types.ApiKeyInfo) {
        if (self.api_creds == null) return Error.Unauthorized;

        const response_body = try self.doL2Get(Endpoints.API_KEYS);
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.ApiKeyInfo, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Delete an API key
    ///
    /// Endpoint: DELETE /auth/api-key
    /// Auth: L2 (API Key required)
    pub fn deleteApiKey(self: *ClobClient, api_key: []const u8) !types.DeleteApiKeyResponse {
        if (self.api_creds == null) return Error.Unauthorized;

        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}?api_key={s}", .{
            Endpoints.API_KEY,
            api_key,
        }) catch return Error.BadRequest;

        const response_body = try self.doL2Delete(path);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(
            types.DeleteApiKeyResponse,
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get closed-only mode status (ban status)
    ///
    /// Endpoint: GET /auth/ban-status/closed-only
    /// Auth: L2 (API Key required)
    pub fn getClosedOnlyMode(self: *ClobClient) !types.ClosedOnlyModeResponse {
        if (self.api_creds == null) return Error.Unauthorized;

        const response_body = try self.doL2Get(Endpoints.BAN_STATUS);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(
            types.ClosedOnlyModeResponse,
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Update balance allowance (refresh from chain)
    ///
    /// Endpoint: GET /balance-allowance/update
    /// Auth: L2 (API Key required)
    pub fn updateBalanceAllowance(self: *ClobClient) !types.UpdateBalanceAllowanceResponse {
        if (self.api_creds == null) return Error.Unauthorized;

        const response_body = try self.doL2Get(Endpoints.BALANCE_ALLOWANCE_UPDATE);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(
            types.UpdateBalanceAllowanceResponse,
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    // =========================================================================
    // Readonly API Key Endpoints (L2 authenticated)
    // =========================================================================

    /// Create a readonly API key
    ///
    /// Endpoint: POST /auth/readonly-api-key
    /// Auth: L2 (API Key required)
    ///
    /// Readonly API keys can only be used for reading data, not placing orders.
    pub fn createReadonlyApiKey(self: *ClobClient, params: types.CreateReadonlyApiKeyParams) !types.CreateReadonlyApiKeyResponse {
        if (self.api_creds == null) return Error.Unauthorized;

        const json_body = std.json.stringifyAlloc(self.allocator, params, .{}) catch return Error.OutOfMemory;
        defer self.allocator.free(json_body);

        const response_body = try self.doL2Post("/auth/readonly-api-key", json_body);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(
            types.CreateReadonlyApiKeyResponse,
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Get all readonly API keys for the authenticated user
    ///
    /// Endpoint: GET /auth/readonly-api-keys
    /// Auth: L2 (API Key required)
    pub fn getReadonlyApiKeys(self: *ClobClient) !std.json.Parsed([]types.ReadonlyApiKeyInfo) {
        if (self.api_creds == null) return Error.Unauthorized;

        const response_body = try self.doL2Get("/auth/readonly-api-keys");
        defer self.allocator.free(response_body);

        return std.json.parseFromSlice([]types.ReadonlyApiKeyInfo, self.allocator, response_body, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch Error.InvalidJson;
    }

    /// Delete a readonly API key
    ///
    /// Endpoint: DELETE /auth/readonly-api-key
    /// Auth: L2 (API Key required)
    pub fn deleteReadonlyApiKey(self: *ClobClient, api_key: []const u8) !types.DeleteReadonlyApiKeyResponse {
        if (self.api_creds == null) return Error.Unauthorized;

        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "/auth/readonly-api-key?api_key={s}", .{api_key}) catch return Error.BadRequest;

        const response_body = try self.doL2Delete(path);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(
            types.DeleteReadonlyApiKeyResponse,
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.InvalidJson;
        defer parsed.deinit();

        return parsed.value;
    }

    /// Validate a readonly API key (public endpoint)
    ///
    /// Endpoint: GET /auth/validate-readonly-api-key
    /// Auth: None (public endpoint)
    ///
    /// This endpoint can be used to check if a readonly API key is valid
    /// without requiring authentication.
    pub fn validateReadonlyApiKey(self: *ClobClient, api_key: []const u8) !types.ValidateReadonlyApiKeyResponse {
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "/auth/validate-readonly-api-key?api_key={s}", .{api_key}) catch return Error.BadRequest;

        const response_body = try self.doGet(path);
        defer self.allocator.free(response_body);

        const parsed = std.json.parseFromSlice(
            types.ValidateReadonlyApiKeyResponse,
            self.allocator,
            response_body,
            .{ .ignore_unknown_fields = true },
        ) catch return Error.InvalidJson;
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

test "ClobClient.hasAuth" {
    var client = ClobClient.init(std.testing.allocator, .{});
    defer client.deinit();

    try std.testing.expect(!client.hasAuth());
}

test "ClobClient L2 endpoints" {
    try std.testing.expectEqualStrings("/order", Endpoints.ORDER);
    try std.testing.expectEqualStrings("/orders", Endpoints.ORDERS);
    try std.testing.expectEqualStrings("/data/orders", Endpoints.DATA_ORDERS);
    try std.testing.expectEqualStrings("/cancel-all", Endpoints.CANCEL_ALL);
    try std.testing.expectEqualStrings("/data/trades", Endpoints.DATA_TRADES);
    try std.testing.expectEqualStrings("/balance-allowance", Endpoints.BALANCE_ALLOWANCE);
}

test "ClobClient unauthenticated access to L2 endpoints" {
    var client = ClobClient.init(std.testing.allocator, .{});
    defer client.deinit();

    // Should return Unauthorized for L2 endpoints without auth
    const result = client.cancelAll();
    try std.testing.expectError(Error.Unauthorized, result);
}

test "ClobClient Builder endpoints constants" {
    try std.testing.expectEqualStrings("/auth/builder-api-key", Endpoints.BUILDER_API_KEY);
    try std.testing.expectEqualStrings("/builder/trades", Endpoints.BUILDER_TRADES);
}

test "ClobClient.hasBuilderAuth" {
    var client = ClobClient.init(std.testing.allocator, .{});
    defer client.deinit();

    try std.testing.expect(!client.hasBuilderAuth());
}

test "ClobClient unauthenticated access to Builder endpoints" {
    var client = ClobClient.init(std.testing.allocator, .{});
    defer client.deinit();

    // Should return Unauthorized for Builder endpoints without auth
    const result = client.getBuilderTrades(.{});
    try std.testing.expectError(Error.Unauthorized, result);
}

test "ClobClient.rfqClient returns RfqClient" {
    var client = ClobClient.init(std.testing.allocator, .{});
    defer client.deinit();

    const rfq = client.rfqClient();

    // Verify RfqClient has correct configuration
    try std.testing.expectEqualStrings(BASE_URL_MAINNET, rfq.base_url);
    try std.testing.expectEqual(@as(?*const ApiCreds, null), rfq.api_creds);
}

test "ClobClient.rfqClient with auth" {
    const allocator = std.testing.allocator;

    // Create mock credentials
    var creds = try ApiCreds.init(allocator, "test-key", "test-secret", "test-pass");
    defer creds.deinit();

    // Create mock wallet
    const wallet = try root.signer.Wallet.fromPrivateKeyHex(
        "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318",
    );

    var client = ClobClient.initWithAuth(allocator, .{}, &wallet, &creds);
    defer client.deinit();

    const rfq = client.rfqClient();

    // Verify RfqClient has auth configured
    try std.testing.expect(rfq.api_creds != null);
    try std.testing.expectEqualStrings("test-key", rfq.api_creds.?.getApiKey());
}

test "ClobClient L1 endpoints - unauthenticated" {
    var client = ClobClient.init(std.testing.allocator, .{});
    defer client.deinit();

    // Should return Unauthorized for L1 endpoints without wallet
    const create_result = client.createApiKey();
    try std.testing.expectError(Error.Unauthorized, create_result);

    const derive_result = client.deriveApiKey();
    try std.testing.expectError(Error.Unauthorized, derive_result);

    const create_or_derive_result = client.createOrDeriveApiKey();
    try std.testing.expectError(Error.Unauthorized, create_or_derive_result);
}

test "ClobClient.setWallet and setApiCreds" {
    const allocator = std.testing.allocator;

    var client = ClobClient.init(allocator, .{});
    defer client.deinit();

    // Initially no auth
    try std.testing.expect(!client.hasAuth());
    try std.testing.expect(client.wallet == null);

    // Set wallet
    const wallet = try root.signer.Wallet.fromPrivateKeyHex(
        "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318",
    );
    client.setWallet(&wallet);
    try std.testing.expect(client.wallet != null);

    // Set credentials
    var creds = try ApiCreds.init(allocator, "key", "secret", "pass");
    defer creds.deinit();
    client.setApiCreds(&creds);
    try std.testing.expect(client.hasAuth());
}
