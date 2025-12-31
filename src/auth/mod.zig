//! 认证模块
//!
//! 提供 Polymarket API 认证功能，包括：
//! - L1 认证：EIP-712 签名，用于 API Key 管理
//! - L2 认证：HMAC-SHA256 签名，用于常规 API 请求
//! - API 凭证管理
//!
//! ## 认证级别
//!
//! | 级别 | 描述 | 用途 |
//! |------|------|------|
//! | L0 | 无认证 | 公共只读 API |
//! | L1 | EIP-712 签名 | 创建/派生 API Key |
//! | L2 | HMAC-SHA256 | 所有需要认证的 API |
//!
//! ## 快速开始
//!
//! ```zig
//! const poly = @import("poly-sdk-zig");
//! const auth = poly.auth;
//!
//! // 创建钱包
//! const wallet = try poly.Wallet.fromPrivateKeyHex("0x...");
//!
//! // 创建 L1 认证器
//! const l1 = auth.L1Auth.init(&wallet, .{ .chain_id = 137 });
//!
//! // 生成 L1 Header
//! const header = try l1.generateHeader();
//! const http_headers = header.toHttpHeaders();
//!
//! // 使用 API 凭证
//! var creds = try auth.ApiCreds.fromJson(allocator, json_response);
//! defer creds.deinit();
//!
//! // 创建 L2 认证器
//! const l2 = auth.L2Auth.init(&creds);
//!
//! // 生成 L2 Header
//! const l2_header = try l2.generateHeader(.{
//!     .method = "POST",
//!     .path = "/order",
//!     .body = order_json,
//! });
//! ```

const std = @import("std");

/// API 凭证
pub const api_creds = @import("api_creds.zig");

/// 认证 Header 类型
pub const headers = @import("headers.zig");

/// L1 认证（EIP-712）
pub const l1 = @import("l1.zig");

/// L2 认证（HMAC-SHA256）
pub const l2 = @import("l2.zig");

// ============================================================================
// 便捷类型导出
// ============================================================================

/// API 凭证类型
pub const ApiCreds = api_creds.ApiCreds;

/// API 凭证错误
pub const ApiCredsError = api_creds.ApiCredsError;

/// L1 认证 Header
pub const L1PolyHeader = headers.L1PolyHeader;

/// L2 认证 Header
pub const L2PolyHeader = headers.L2PolyHeader;

/// L1 认证器
pub const L1Auth = l1.L1Auth;

/// L1 认证选项
pub const L1AuthOptions = l1.L1AuthOptions;

/// L1 认证错误
pub const L1AuthError = l1.L1AuthError;

// L1 常量
pub const L1_AUTH_MESSAGE = l1.L1_AUTH_MESSAGE;
pub const CLOB_AUTH_DOMAIN_NAME = l1.CLOB_AUTH_DOMAIN_NAME;
pub const CLOB_AUTH_DOMAIN_VERSION = l1.CLOB_AUTH_DOMAIN_VERSION;
pub const CLOB_AUTH_TYPE = l1.CLOB_AUTH_TYPE;
pub const clobAuthTypeHash = l1.clobAuthTypeHash;

/// L2 认证器
pub const L2Auth = l2.L2Auth;

/// L2 认证请求选项
pub const L2AuthRequestOptions = l2.L2AuthRequestOptions;

/// L2 认证错误
pub const L2AuthError = l2.L2AuthError;

// L2 辅助函数
pub const buildSignatureMessage = l2.buildSignatureMessage;

// ============================================================================
// 测试
// ============================================================================

test "auth module exports" {
    const root = @import("../root.zig");

    // 创建钱包
    const wallet = try root.Wallet.fromPrivateKeyHex(
        "0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318",
    );

    // 测试 L1Auth
    const l1_auth = L1Auth.init(&wallet, .{ .chain_id = 137 });
    try std.testing.expectEqual(@as(u64, 137), l1_auth.getChainId());

    // 测试生成 Header
    const header = try l1_auth.generateHeaderWithNonce(12345);
    try std.testing.expect(header.getAddress().len == 42);
    try std.testing.expect(header.getSignature().len == 132);
}

test "auth module ApiCreds" {
    const allocator = std.testing.allocator;

    const json =
        \\{"apiKey":"test-key","secret":"test-secret","passphrase":"test-pass"}
    ;

    var creds = try ApiCreds.fromJson(allocator, json);
    defer creds.deinit();

    try std.testing.expectEqualStrings("test-key", creds.getApiKey());
}

test "auth module L2Auth" {
    const allocator = std.testing.allocator;

    var creds = try ApiCreds.init(
        allocator,
        "test-key",
        "test-secret",
        "test-pass",
    );
    defer creds.deinit();

    const l2_auth = L2Auth.init(&creds);
    try std.testing.expectEqualStrings("test-key", l2_auth.getApiKey());

    // 测试生成 Header
    const header = try l2_auth.generateHeaderWithTimestamp(.{
        .method = "GET",
        .path = "/test",
        .body = null,
    }, 1704067200);

    try std.testing.expectEqualStrings("1704067200", header.getTimestamp());
    try std.testing.expectEqual(@as(usize, 44), header.getSignature().len);
}

test "auth module constants" {
    try std.testing.expectEqualStrings(
        "This message attests that I control the given wallet",
        L1_AUTH_MESSAGE,
    );
    try std.testing.expectEqualStrings("ClobAuthDomain", CLOB_AUTH_DOMAIN_NAME);
    try std.testing.expectEqualStrings("1", CLOB_AUTH_DOMAIN_VERSION);
}

test "all submodules" {
    _ = @import("api_creds.zig");
    _ = @import("headers.zig");
    _ = @import("l1.zig");
    _ = @import("l2.zig");
}
