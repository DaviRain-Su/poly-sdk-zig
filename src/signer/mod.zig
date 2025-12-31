//! 签名模块
//!
//! 提供以太坊签名相关功能，包括：
//! - 钱包管理（私钥、公钥、地址）
//! - EIP-191 个人消息签名
//! - EIP-712 类型化结构数据签名
//! - Polymarket 订单签名
//!
//! ## 快速开始
//!
//! ```zig
//! const signer = @import("poly-sdk-zig").signer;
//!
//! // 创建钱包
//! const wallet = try signer.Wallet.fromPrivateKeyHex("0x...");
//!
//! // 签名消息
//! const sig = try wallet.signMessage("Hello");
//!
//! // 签名 Polymarket 订单
//! const order = signer.eip712.Order{ ... };
//! const digest = signer.eip712.hashPolymarketOrder(&order, 137, false);
//! const order_sig = try wallet.sign(&digest);
//! ```

const std = @import("std");

/// 钱包模块
pub const wallet = @import("wallet.zig");

/// EIP-712 类型化数据签名模块
pub const eip712 = @import("eip712.zig");

// ============================================================================
// 便捷类型导出
// ============================================================================

/// 钱包类型
pub const Wallet = wallet.Wallet;

/// 钱包错误
pub const WalletError = wallet.WalletError;

// EIP-712 类型
pub const Domain = eip712.Domain;
pub const TypeField = eip712.TypeField;
pub const TypeDefinition = eip712.TypeDefinition;
pub const Order = eip712.Order;

// EIP-712 常量
pub const ORDER_TYPE = eip712.ORDER_TYPE;
pub const CTF_EXCHANGE_ADDRESS_MAINNET = eip712.CTF_EXCHANGE_ADDRESS_MAINNET;
pub const CTF_EXCHANGE_ADDRESS_AMOY = eip712.CTF_EXCHANGE_ADDRESS_AMOY;
pub const NEG_RISK_CTF_EXCHANGE_ADDRESS_MAINNET = eip712.NEG_RISK_CTF_EXCHANGE_ADDRESS_MAINNET;
pub const NEG_RISK_CTF_EXCHANGE_ADDRESS_AMOY = eip712.NEG_RISK_CTF_EXCHANGE_ADDRESS_AMOY;
pub const POLYGON_CHAIN_ID = eip712.POLYGON_CHAIN_ID;
pub const AMOY_CHAIN_ID = eip712.AMOY_CHAIN_ID;

// EIP-712 函数
pub const encodeDomainType = eip712.encodeDomainType;
pub const encodeType = eip712.encodeType;
pub const typeHash = eip712.typeHash;
pub const encodeUint256 = eip712.encodeUint256;
pub const encodeAddress = eip712.encodeAddress;
pub const encodeString = eip712.encodeString;
pub const encodeBytes32 = eip712.encodeBytes32;
pub const encodeBool = eip712.encodeBool;
pub const encodeUint8 = eip712.encodeUint8;
pub const hashDomain = eip712.hashDomain;
pub const hashTypedData = eip712.hashTypedData;
pub const orderTypeHash = eip712.orderTypeHash;
pub const hashOrder = eip712.hashOrder;
pub const createPolymarketDomain = eip712.createPolymarketDomain;
pub const hashPolymarketOrder = eip712.hashPolymarketOrder;

// ============================================================================
// 测试
// ============================================================================

test "signer module exports" {
    // 验证钱包类型可访问
    const w = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");
    var buffer: [42]u8 = undefined;
    _ = w.getAddressLowerHex(&buffer);

    // 验证 EIP-712 类型可访问
    const domain = createPolymarketDomain(POLYGON_CHAIN_ID, false);
    _ = hashDomain(&domain);

    // 验证订单类型可访问
    const order = Order{
        .salt = 1,
        .maker = [_]u8{0} ** 20,
        .signer = [_]u8{0} ** 20,
        .taker = [_]u8{0} ** 20,
        .token_id = 1,
        .maker_amount = 100,
        .taker_amount = 50,
        .expiration = 0,
        .nonce = 0,
        .fee_rate_bps = 0,
        .side = 0,
        .signature_type = 0,
    };
    _ = hashOrder(&order);
}

test "wallet and eip712 integration" {
    // 创建钱包
    const w = try Wallet.fromPrivateKeyHex("0x4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318");

    // 创建订单
    const order = Order{
        .salt = 12345,
        .maker = w.address_bytes,
        .signer = w.address_bytes,
        .taker = [_]u8{0} ** 20,
        .token_id = 1,
        .maker_amount = 100,
        .taker_amount = 65,
        .expiration = 0,
        .nonce = 0,
        .fee_rate_bps = 0,
        .side = 0,
        .signature_type = 0,
    };

    // 计算订单摘要
    const digest = hashPolymarketOrder(&order, POLYGON_CHAIN_ID, false);

    // 签名
    const signature = try w.sign(&digest);

    // 验证
    try std.testing.expect(w.verify(&digest, &signature));
}

test "all submodules" {
    _ = @import("wallet.zig");
    _ = @import("eip712.zig");
}
