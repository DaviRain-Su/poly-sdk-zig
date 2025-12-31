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
const L2Auth = root.auth.L2Auth;
const ApiCreds = root.auth.ApiCreds;
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
