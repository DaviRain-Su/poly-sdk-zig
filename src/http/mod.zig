//! HTTP module for Polymarket CLOB API.
//!
//! Provides HTTP client functionality for making API requests.
//!
//! ## Example
//!
//! ```zig
//! const http = @import("http/mod.zig");
//!
//! var client = http.HttpClient.init(allocator, .{
//!     .base_url = "https://clob.polymarket.com",
//! });
//! defer client.deinit();
//!
//! const response = try client.get("/markets", .{});
//! defer response.deinit();
//!
//! if (response.isSuccess()) {
//!     const markets = try response.json([]Market);
//! } else {
//!     const ctx = response.getErrorContext();
//!     std.log.err("{s}", .{ctx.?.message});
//! }
//! ```

pub const client = @import("client.zig");

// Re-export main types
pub const HttpClient = client.HttpClient;
pub const Config = client.Config;
pub const Response = client.Response;
pub const RequestOptions = client.RequestOptions;
pub const Error = client.Error;
pub const ErrorContext = client.ErrorContext;

// Re-export utility functions
pub const buildQueryString = client.buildQueryString;
pub const errorFromHttpStatus = client.errorFromHttpStatus;
pub const describeError = client.describeError;
pub const isRetryable = client.isRetryable;

// ============================================================================
// Tests
// ============================================================================

test "module imports" {
    _ = client;
}

test "type exports" {
    _ = HttpClient;
    _ = Config;
    _ = Response;
    _ = RequestOptions;
    const ctx = ErrorContext.fromError(Error.NotFound);
    try @import("std").testing.expect(ctx.message.len > 0);
}
