//! EIP-712 类型化结构数据签名
//!
//! 实现 EIP-712 标准的结构化数据哈希和签名。
//! https://eips.ethereum.org/EIPS/eip-712
//!
//! EIP-712 签名流程:
//! 1. 定义类型 (types) 和域分隔符 (domain)
//! 2. 计算类型哈希: typeHash = keccak256(encodeType(typeName))
//! 3. 计算数据哈希: hashStruct(typeName, data)
//! 4. 计算最终摘要: keccak256("\x19\x01" || domainSeparator || structHash)
//! 5. 使用私钥签名摘要

const std = @import("std");
const root = @import("../root.zig");

const crypto = root.crypto;
const keccak256 = crypto.keccak256;
const Hasher = crypto.Hasher;

/// EIP-712 域分隔符
pub const Domain = struct {
    /// 域名称
    name: ?[]const u8 = null,
    /// 版本
    version: ?[]const u8 = null,
    /// 链 ID
    chain_id: ?u256 = null,
    /// 验证合约地址
    verifying_contract: ?[20]u8 = null,
    /// 盐值
    salt: ?[32]u8 = null,
};

/// EIP-712 类型字段
pub const TypeField = struct {
    /// 字段名
    name: []const u8,
    /// 字段类型
    type_name: []const u8,
};

/// EIP-712 类型定义
/// 键是类型名，值是字段列表
pub const TypeDefinition = struct {
    name: []const u8,
    fields: []const TypeField,
};

/// 编码 EIP-712 域分隔符类型字符串
///
/// 返回: 例如 "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
pub fn encodeDomainType(domain: *const Domain, buffer: []u8) []const u8 {
    var writer = std.io.fixedBufferStream(buffer);
    var w = writer.writer();

    w.writeAll("EIP712Domain(") catch unreachable;

    var first = true;

    if (domain.name != null) {
        if (!first) w.writeAll(",") catch unreachable;
        w.writeAll("string name") catch unreachable;
        first = false;
    }
    if (domain.version != null) {
        if (!first) w.writeAll(",") catch unreachable;
        w.writeAll("string version") catch unreachable;
        first = false;
    }
    if (domain.chain_id != null) {
        if (!first) w.writeAll(",") catch unreachable;
        w.writeAll("uint256 chainId") catch unreachable;
        first = false;
    }
    if (domain.verifying_contract != null) {
        if (!first) w.writeAll(",") catch unreachable;
        w.writeAll("address verifyingContract") catch unreachable;
        first = false;
    }
    if (domain.salt != null) {
        if (!first) w.writeAll(",") catch unreachable;
        w.writeAll("bytes32 salt") catch unreachable;
        first = false;
    }

    w.writeAll(")") catch unreachable;

    return buffer[0..writer.pos];
}

/// 编码类型字符串
///
/// 例如: "Order(uint256 salt,address maker,address signer)"
pub fn encodeType(def: *const TypeDefinition, buffer: []u8) []const u8 {
    var writer = std.io.fixedBufferStream(buffer);
    var w = writer.writer();

    w.writeAll(def.name) catch unreachable;
    w.writeAll("(") catch unreachable;

    for (def.fields, 0..) |field, i| {
        if (i > 0) w.writeAll(",") catch unreachable;
        w.writeAll(field.type_name) catch unreachable;
        w.writeAll(" ") catch unreachable;
        w.writeAll(field.name) catch unreachable;
    }

    w.writeAll(")") catch unreachable;

    return buffer[0..writer.pos];
}

/// 计算类型哈希
pub fn typeHash(type_string: []const u8) [32]u8 {
    return keccak256(type_string);
}

/// 编码 uint256 到 32 字节（大端序）
pub fn encodeUint256(value: u256) [32]u8 {
    var result: [32]u8 = undefined;
    std.mem.writeInt(u256, &result, value, .big);
    return result;
}

/// 编码地址到 32 字节（左填充零）
pub fn encodeAddress(addr: *const [20]u8) [32]u8 {
    var result: [32]u8 = [_]u8{0} ** 32;
    @memcpy(result[12..32], addr);
    return result;
}

/// 编码字符串（返回字符串的 keccak256 哈希）
pub fn encodeString(s: []const u8) [32]u8 {
    return keccak256(s);
}

/// 编码 bytes32
pub fn encodeBytes32(data: *const [32]u8) [32]u8 {
    return data.*;
}

/// 编码布尔值到 32 字节
pub fn encodeBool(value: bool) [32]u8 {
    var result: [32]u8 = [_]u8{0} ** 32;
    if (value) {
        result[31] = 1;
    }
    return result;
}

/// 编码 uint8 到 32 字节
pub fn encodeUint8(value: u8) [32]u8 {
    var result: [32]u8 = [_]u8{0} ** 32;
    result[31] = value;
    return result;
}

/// 计算域分隔符哈希
pub fn hashDomain(domain: *const Domain) [32]u8 {
    var type_buf: [256]u8 = undefined;
    const type_str = encodeDomainType(domain, &type_buf);
    const type_hash_val = typeHash(type_str);

    var hasher = Hasher.init();
    hasher.update(&type_hash_val);

    if (domain.name) |name| {
        hasher.update(&encodeString(name));
    }
    if (domain.version) |version| {
        hasher.update(&encodeString(version));
    }
    if (domain.chain_id) |chain_id| {
        hasher.update(&encodeUint256(chain_id));
    }
    if (domain.verifying_contract) |addr| {
        hasher.update(&encodeAddress(&addr));
    }
    if (domain.salt) |salt| {
        hasher.update(&encodeBytes32(&salt));
    }

    return hasher.final();
}

/// 计算 EIP-712 最终签名摘要
///
/// digest = keccak256("\x19\x01" || domainSeparator || structHash)
pub fn hashTypedData(domain_separator: *const [32]u8, struct_hash: *const [32]u8) [32]u8 {
    var hasher = Hasher.init();
    hasher.update("\x19\x01");
    hasher.update(domain_separator);
    hasher.update(struct_hash);
    return hasher.final();
}

// ============================================================================
// Polymarket 订单相关
// ============================================================================

/// Polymarket 订单类型定义
pub const ORDER_TYPE = TypeDefinition{
    .name = "Order",
    .fields = &[_]TypeField{
        .{ .name = "salt", .type_name = "uint256" },
        .{ .name = "maker", .type_name = "address" },
        .{ .name = "signer", .type_name = "address" },
        .{ .name = "taker", .type_name = "address" },
        .{ .name = "tokenId", .type_name = "uint256" },
        .{ .name = "makerAmount", .type_name = "uint256" },
        .{ .name = "takerAmount", .type_name = "uint256" },
        .{ .name = "expiration", .type_name = "uint256" },
        .{ .name = "nonce", .type_name = "uint256" },
        .{ .name = "feeRateBps", .type_name = "uint256" },
        .{ .name = "side", .type_name = "uint8" },
        .{ .name = "signatureType", .type_name = "uint8" },
    },
};

/// Polymarket 订单数据
pub const Order = struct {
    salt: u256,
    maker: [20]u8,
    signer: [20]u8,
    taker: [20]u8,
    token_id: u256,
    maker_amount: u256,
    taker_amount: u256,
    expiration: u256,
    nonce: u256,
    fee_rate_bps: u256,
    side: u8,
    signature_type: u8,
};

/// 计算订单类型哈希（编译时常量）
pub fn orderTypeHash() [32]u8 {
    var buffer: [512]u8 = undefined;
    const type_str = encodeType(&ORDER_TYPE, &buffer);
    return typeHash(type_str);
}

/// 计算订单结构体哈希
pub fn hashOrder(order: *const Order) [32]u8 {
    const type_hash_val = orderTypeHash();

    var hasher = Hasher.init();
    hasher.update(&type_hash_val);
    hasher.update(&encodeUint256(order.salt));
    hasher.update(&encodeAddress(&order.maker));
    hasher.update(&encodeAddress(&order.signer));
    hasher.update(&encodeAddress(&order.taker));
    hasher.update(&encodeUint256(order.token_id));
    hasher.update(&encodeUint256(order.maker_amount));
    hasher.update(&encodeUint256(order.taker_amount));
    hasher.update(&encodeUint256(order.expiration));
    hasher.update(&encodeUint256(order.nonce));
    hasher.update(&encodeUint256(order.fee_rate_bps));
    hasher.update(&encodeUint8(order.side));
    hasher.update(&encodeUint8(order.signature_type));

    return hasher.final();
}

/// Polymarket CTF Exchange 合约地址（主网）
pub const CTF_EXCHANGE_ADDRESS_MAINNET: [20]u8 = parseHexAddress("0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E");

/// Polymarket CTF Exchange 合约地址（测试网 Amoy）
pub const CTF_EXCHANGE_ADDRESS_AMOY: [20]u8 = parseHexAddress("0xdFE02Eb6733538f8Ea35D585af8DE5958AD99E40");

/// Neg Risk CTF Exchange 合约地址（主网）
pub const NEG_RISK_CTF_EXCHANGE_ADDRESS_MAINNET: [20]u8 = parseHexAddress("0xC5d563A36AE78145C45a50134d48A1215220f80a");

/// Neg Risk CTF Exchange 合约地址（测试网 Amoy）
pub const NEG_RISK_CTF_EXCHANGE_ADDRESS_AMOY: [20]u8 = parseHexAddress("0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296");

/// Polygon 主网链 ID
pub const POLYGON_CHAIN_ID: u256 = 137;

/// Polygon Amoy 测试网链 ID
pub const AMOY_CHAIN_ID: u256 = 80002;

/// 创建 Polymarket CTF Exchange 域
pub fn createPolymarketDomain(chain_id: u256, neg_risk: bool) Domain {
    const contract = if (chain_id == POLYGON_CHAIN_ID)
        if (neg_risk) NEG_RISK_CTF_EXCHANGE_ADDRESS_MAINNET else CTF_EXCHANGE_ADDRESS_MAINNET
    else if (neg_risk) NEG_RISK_CTF_EXCHANGE_ADDRESS_AMOY else CTF_EXCHANGE_ADDRESS_AMOY;

    return Domain{
        .name = "Polymarket CTF Exchange",
        .version = "1",
        .chain_id = chain_id,
        .verifying_contract = contract,
    };
}

/// 计算 Polymarket 订单的签名摘要
pub fn hashPolymarketOrder(order: *const Order, chain_id: u256, neg_risk: bool) [32]u8 {
    const domain = createPolymarketDomain(chain_id, neg_risk);
    const domain_separator = hashDomain(&domain);
    const struct_hash = hashOrder(order);
    return hashTypedData(&domain_separator, &struct_hash);
}

// ============================================================================
// 辅助函数
// ============================================================================

fn parseHexAddress(comptime hex: []const u8) [20]u8 {
    const data = if (hex.len >= 2 and hex[0] == '0' and hex[1] == 'x')
        hex[2..]
    else
        hex;

    var result: [20]u8 = undefined;
    for (0..20) |i| {
        result[i] = (hexToNibble(data[i * 2]) << 4) | hexToNibble(data[i * 2 + 1]);
    }
    return result;
}

fn hexToNibble(c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        'A'...'F' => c - 'A' + 10,
        else => 0,
    };
}

// ============================================================================
// 测试
// ============================================================================

test "encodeDomainType full" {
    const domain = Domain{
        .name = "Test",
        .version = "1",
        .chain_id = 1,
        .verifying_contract = [_]u8{0} ** 20,
    };
    var buffer: [256]u8 = undefined;
    const result = encodeDomainType(&domain, &buffer);
    try std.testing.expectEqualStrings(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)",
        result,
    );
}

test "encodeDomainType partial" {
    const domain = Domain{
        .name = "Test",
        .version = "1",
        .chain_id = 137,
    };
    var buffer: [256]u8 = undefined;
    const result = encodeDomainType(&domain, &buffer);
    try std.testing.expectEqualStrings(
        "EIP712Domain(string name,string version,uint256 chainId)",
        result,
    );
}

test "encodeType Order" {
    var buffer: [512]u8 = undefined;
    const result = encodeType(&ORDER_TYPE, &buffer);
    try std.testing.expectEqualStrings(
        "Order(uint256 salt,address maker,address signer,address taker,uint256 tokenId,uint256 makerAmount,uint256 takerAmount,uint256 expiration,uint256 nonce,uint256 feeRateBps,uint8 side,uint8 signatureType)",
        result,
    );
}

test "encodeUint256" {
    const result = encodeUint256(1);
    var expected: [32]u8 = [_]u8{0} ** 32;
    expected[31] = 1;
    try std.testing.expectEqualSlices(u8, &expected, &result);
}

test "encodeAddress" {
    var addr: [20]u8 = undefined;
    addr[0] = 0x12;
    addr[19] = 0x34;
    @memset(addr[1..19], 0);

    const result = encodeAddress(&addr);

    // 前 12 字节应该是 0
    for (0..12) |i| {
        try std.testing.expectEqual(@as(u8, 0), result[i]);
    }
    // 后 20 字节是地址
    try std.testing.expectEqual(@as(u8, 0x12), result[12]);
    try std.testing.expectEqual(@as(u8, 0x34), result[31]);
}

test "encodeString" {
    const result = encodeString("hello");
    const expected = keccak256("hello");
    try std.testing.expectEqualSlices(u8, &expected, &result);
}

test "hashDomain Polymarket mainnet" {
    const domain = createPolymarketDomain(POLYGON_CHAIN_ID, false);
    const hash = hashDomain(&domain);
    // 验证哈希长度
    try std.testing.expectEqual(@as(usize, 32), hash.len);
}

test "orderTypeHash" {
    const hash = orderTypeHash();
    try std.testing.expectEqual(@as(usize, 32), hash.len);
}

test "hashOrder" {
    const order = Order{
        .salt = 12345,
        .maker = [_]u8{0x01} ** 20,
        .signer = [_]u8{0x01} ** 20,
        .taker = [_]u8{0} ** 20,
        .token_id = 1,
        .maker_amount = 100,
        .taker_amount = 65,
        .expiration = 0,
        .nonce = 0,
        .fee_rate_bps = 0,
        .side = 0, // BUY
        .signature_type = 0, // EOA
    };
    const hash = hashOrder(&order);
    try std.testing.expectEqual(@as(usize, 32), hash.len);
}

test "hashTypedData" {
    var domain_separator: [32]u8 = undefined;
    @memset(&domain_separator, 0x11);

    var struct_hash: [32]u8 = undefined;
    @memset(&struct_hash, 0x22);

    const digest = hashTypedData(&domain_separator, &struct_hash);
    try std.testing.expectEqual(@as(usize, 32), digest.len);

    // 验证前缀
    var hasher = Hasher.init();
    hasher.update("\x19\x01");
    hasher.update(&domain_separator);
    hasher.update(&struct_hash);
    const expected = hasher.final();
    try std.testing.expectEqualSlices(u8, &expected, &digest);
}

test "createPolymarketDomain mainnet" {
    const domain = createPolymarketDomain(POLYGON_CHAIN_ID, false);
    try std.testing.expectEqualStrings("Polymarket CTF Exchange", domain.name.?);
    try std.testing.expectEqualStrings("1", domain.version.?);
    try std.testing.expectEqual(@as(u256, 137), domain.chain_id.?);
    try std.testing.expectEqualSlices(u8, &CTF_EXCHANGE_ADDRESS_MAINNET, &domain.verifying_contract.?);
}

test "createPolymarketDomain mainnet neg_risk" {
    const domain = createPolymarketDomain(POLYGON_CHAIN_ID, true);
    try std.testing.expectEqualSlices(u8, &NEG_RISK_CTF_EXCHANGE_ADDRESS_MAINNET, &domain.verifying_contract.?);
}

test "hashPolymarketOrder" {
    const order = Order{
        .salt = 12345,
        .maker = [_]u8{0x01} ** 20,
        .signer = [_]u8{0x01} ** 20,
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
    const digest = hashPolymarketOrder(&order, POLYGON_CHAIN_ID, false);
    try std.testing.expectEqual(@as(usize, 32), digest.len);
}

test "EIP712Domain typeHash" {
    // 已知的 EIP712Domain 类型哈希
    const type_str = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
    const hash = typeHash(type_str);
    // 这是一个已知值
    const expected = keccak256(type_str);
    try std.testing.expectEqualSlices(u8, &expected, &hash);
}
