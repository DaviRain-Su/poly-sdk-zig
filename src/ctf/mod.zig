//! Conditional Token Framework (CTF) 合约交互
//!
//! 提供 Polymarket 的 Split 和 Merge 功能：
//! - Split: 将 USDC 拆分成 YES + NO 代币
//! - Merge: 将 YES + NO 代币合并成 USDC
//!
//! 合约地址：
//! - CTF (ERC1155): 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045
//! - USDC (ERC20): 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
//!

const std = @import("std");
const http = @import("../http/mod.zig");
const keccak = @import("../crypto/keccak.zig");
const ecdsa = @import("../crypto/ecdsa.zig");
const Wallet = @import("../signer/wallet.zig").Wallet;

/// CTF 合约地址（Polygon 主网）
pub const CTF_ADDRESS = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045";

/// USDC 合约地址（Polygon 主网）
pub const USDC_ADDRESS = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174";

/// CTF Exchange 地址（用于授权）
pub const CTF_EXCHANGE = "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E";

/// Neg Risk CTF Exchange
pub const NEG_RISK_CTF_EXCHANGE = "0xC5d563A36AE78145C45a50134d48A1215220f80a";

/// 默认 RPC URL
pub const DEFAULT_RPC_URL = "https://polygon-rpc.com";

/// CTF 客户端
pub const CtfClient = struct {
    allocator: std.mem.Allocator,
    wallet: *const Wallet,
    rpc_url: []const u8,
    chain_id: u64,

    const Self = @This();

    /// 初始化 CTF 客户端
    pub fn init(
        allocator: std.mem.Allocator,
        wallet: *const Wallet,
        options: struct {
            rpc_url: []const u8 = DEFAULT_RPC_URL,
            chain_id: u64 = 137, // Polygon mainnet
        },
    ) Self {
        return Self{
            .allocator = allocator,
            .wallet = wallet,
            .rpc_url = options.rpc_url,
            .chain_id = options.chain_id,
        };
    }

    /// 获取 USDC 余额
    pub fn getUsdcBalance(self: *Self, address: []const u8) !u256 {
        // ERC20 balanceOf(address) function selector: 0x70a08231
        var calldata: [68]u8 = undefined;
        @memcpy(calldata[0..4], &[_]u8{ 0x70, 0xa0, 0x82, 0x31 });
        // 填充地址（32字节，左侧补零）
        @memset(calldata[4..36], 0);
        _ = hexToBytes(address[2..], calldata[16..36]) catch return error.InvalidAddress;

        const result = try self.ethCall(USDC_ADDRESS, &calldata);
        defer self.allocator.free(result);

        return parseU256(result);
    }

    /// 获取 USDC 授权额度（CTF 合约）
    pub fn getUsdcAllowance(self: *Self, owner: []const u8) !u256 {
        // ERC20 allowance(address,address) function selector: 0xdd62ed3e
        var calldata: [68]u8 = undefined;
        @memcpy(calldata[0..4], &[_]u8{ 0xdd, 0x62, 0xed, 0x3e });
        // owner 地址
        @memset(calldata[4..36], 0);
        const owner_start = if (owner.len >= 2 and owner[0] == '0' and owner[1] == 'x') @as(usize, 2) else 0;
        _ = hexToBytes(owner[owner_start..], calldata[16..36]) catch return error.InvalidAddress;
        // spender 地址 (CTF 合约)
        @memset(calldata[36..56], 0);
        _ = hexToBytes(CTF_ADDRESS[2..], calldata[48..68]) catch return error.InvalidAddress;

        const result = try self.ethCall(USDC_ADDRESS, &calldata);
        defer self.allocator.free(result);

        return parseU256(result);
    }

    /// 获取条件代币余额
    pub fn getCtfBalance(self: *Self, address: []const u8, token_id: []const u8) !u256 {
        // ERC1155 balanceOf(address,uint256) function selector: 0x00fdd58e
        var calldata: [68]u8 = undefined;
        @memcpy(calldata[0..4], &[_]u8{ 0x00, 0xfd, 0xd5, 0x8e });
        // 地址
        @memset(calldata[4..36], 0);
        _ = hexToBytes(address[2..], calldata[16..36]) catch return error.InvalidAddress;
        // Token ID
        _ = try self.parseTokenId(token_id, calldata[36..68]);

        const result = try self.ethCall(CTF_ADDRESS, &calldata);
        defer self.allocator.free(result);

        return parseU256(result);
    }

    /// Split: 将 USDC 拆分成 YES + NO
    ///
    /// 参数:
    /// - condition_id: 市场的 condition ID
    /// - amount: 要拆分的 USDC 数量（以最小单位计，1 USDC = 1e6）
    ///
    /// 返回拆分的股数
    pub fn split(
        self: *Self,
        condition_id: []const u8,
        amount: u64,
    ) !SplitResult {
        // splitPosition 函数签名:
        // splitPosition(IERC20 collateralToken, bytes32 parentCollectionId, bytes32 conditionId, uint256[] partition, uint256 amount)
        // 函数选择器: 0x72ce4275

        // 构建 calldata - 使用固定大小的缓冲区
        // 需要: 4 (selector) + 8 * 32 (参数) = 260 字节
        var calldata: [512]u8 = undefined;
        var pos: usize = 0;

        // 函数选择器
        @memcpy(calldata[pos..][0..4], &[_]u8{ 0x72, 0xce, 0x42, 0x75 });
        pos += 4;

        // collateralToken (USDC 地址，32 字节)
        @memset(calldata[pos..][0..12], 0);
        _ = hexToBytes(USDC_ADDRESS[2..], calldata[pos + 12 ..][0..20]) catch return error.InvalidAddress;
        pos += 32;

        // parentCollectionId (bytes32, 全0)
        @memset(calldata[pos..][0..32], 0);
        pos += 32;

        // conditionId (bytes32)
        const cid_start = if (condition_id.len >= 2 and condition_id[0] == '0' and condition_id[1] == 'x') @as(usize, 2) else 0;
        _ = hexToBytes(condition_id[cid_start..], calldata[pos..][0..32]) catch return error.InvalidConditionId;
        pos += 32;

        // partition offset (指向动态数组的偏移量)
        self.writeU256(calldata[pos..][0..32], 160); // 5 * 32 = 160
        pos += 32;

        // amount (uint256)
        self.writeU256(calldata[pos..][0..32], amount);
        pos += 32;

        // partition 数组 (长度 + 数据)
        // 对于二元市场，partition = [1, 2] 表示 YES 和 NO
        self.writeU256(calldata[pos..][0..32], 2); // 数组长度
        pos += 32;
        self.writeU256(calldata[pos..][0..32], 1); // YES index
        pos += 32;
        self.writeU256(calldata[pos..][0..32], 2); // NO index
        pos += 32;

        // 发送交易
        const tx_hash = try self.sendTransaction(CTF_ADDRESS, calldata[0..pos], 0);

        return SplitResult{
            .tx_hash = tx_hash,
            .shares = amount, // Split 的股数等于 USDC 数量
        };
    }

    /// Merge: 将 YES + NO 合并成 USDC
    ///
    /// 参数:
    /// - condition_id: 市场的 condition ID
    /// - amount: 要合并的股数
    ///
    /// 返回获得的 USDC 数量
    pub fn merge(
        self: *Self,
        condition_id: []const u8,
        amount: u64,
    ) !MergeResult {
        // mergePositions 函数签名:
        // mergePositions(IERC20 collateralToken, bytes32 parentCollectionId, bytes32 conditionId, uint256[] partition, uint256 amount)
        // 函数选择器: 0xd47e8113

        // 需要: 4 (selector) + 8 * 32 (参数) = 260 字节
        var calldata: [512]u8 = undefined;
        var pos: usize = 0;

        // 函数选择器
        @memcpy(calldata[pos..][0..4], &[_]u8{ 0xd4, 0x7e, 0x81, 0x13 });
        pos += 4;

        // collateralToken (USDC 地址)
        @memset(calldata[pos..][0..12], 0);
        _ = hexToBytes(USDC_ADDRESS[2..], calldata[pos + 12 ..][0..20]) catch return error.InvalidAddress;
        pos += 32;

        // parentCollectionId (全0)
        @memset(calldata[pos..][0..32], 0);
        pos += 32;

        // conditionId
        const cid_start = if (condition_id.len >= 2 and condition_id[0] == '0' and condition_id[1] == 'x') @as(usize, 2) else 0;
        _ = hexToBytes(condition_id[cid_start..], calldata[pos..][0..32]) catch return error.InvalidConditionId;
        pos += 32;

        // partition offset
        self.writeU256(calldata[pos..][0..32], 160);
        pos += 32;

        // amount
        self.writeU256(calldata[pos..][0..32], amount);
        pos += 32;

        // partition 数组
        self.writeU256(calldata[pos..][0..32], 2);
        pos += 32;
        self.writeU256(calldata[pos..][0..32], 1);
        pos += 32;
        self.writeU256(calldata[pos..][0..32], 2);
        pos += 32;

        const tx_hash = try self.sendTransaction(CTF_ADDRESS, calldata[0..pos], 0);

        return MergeResult{
            .tx_hash = tx_hash,
            .usdc_received = amount, // Merge 获得的 USDC 等于股数
        };
    }

    /// 授权 USDC 给 CTF 合约
    pub fn approveUsdc(self: *Self, amount: u256) ![]const u8 {
        // approve(address,uint256) selector: 0x095ea7b3
        var calldata: [68]u8 = undefined;
        @memcpy(calldata[0..4], &[_]u8{ 0x09, 0x5e, 0xa7, 0xb3 });
        // CTF 地址
        @memset(calldata[4..24], 0);
        _ = hexToBytes(CTF_ADDRESS[2..], calldata[16..36]) catch return error.InvalidAddress;
        // amount
        self.writeU256Big(calldata[36..68], amount);

        return try self.sendTransaction(USDC_ADDRESS, &calldata, 0);
    }

    /// 授权 CTF Exchange 操作 ERC1155 代币
    /// 这是卖出 CTF 代币所必需的
    pub fn setApprovalForAll(self: *Self, operator: []const u8, approved: bool) ![]const u8 {
        // setApprovalForAll(address,bool) selector: 0xa22cb465
        var calldata: [68]u8 = undefined;
        @memcpy(calldata[0..4], &[_]u8{ 0xa2, 0x2c, 0xb4, 0x65 });
        // operator address
        @memset(calldata[4..24], 0);
        const op_start = if (operator.len >= 2 and operator[0] == '0' and operator[1] == 'x') @as(usize, 2) else 0;
        _ = hexToBytes(operator[op_start..], calldata[16..36]) catch return error.InvalidAddress;
        // approved (bool as uint256)
        @memset(calldata[36..68], 0);
        calldata[67] = if (approved) 1 else 0;

        return try self.sendTransaction(CTF_ADDRESS, &calldata, 0);
    }

    /// 检查是否已授权 CTF Exchange
    pub fn isApprovedForAll(self: *Self, owner: []const u8, operator: []const u8) !bool {
        // isApprovedForAll(address,address) selector: 0xe985e9c5
        var calldata: [68]u8 = undefined;
        @memcpy(calldata[0..4], &[_]u8{ 0xe9, 0x85, 0xe9, 0xc5 });
        // owner
        @memset(calldata[4..24], 0);
        const owner_start = if (owner.len >= 2 and owner[0] == '0' and owner[1] == 'x') @as(usize, 2) else 0;
        _ = hexToBytes(owner[owner_start..], calldata[16..36]) catch return error.InvalidAddress;
        // operator
        @memset(calldata[36..56], 0);
        const op_start = if (operator.len >= 2 and operator[0] == '0' and operator[1] == 'x') @as(usize, 2) else 0;
        _ = hexToBytes(operator[op_start..], calldata[48..68]) catch return error.InvalidAddress;

        const result = try self.ethCall(CTF_ADDRESS, &calldata);
        defer self.allocator.free(result);

        // 返回值是 bool，非零即为 true
        const value = try parseU256(result);
        return value != 0;
    }

    /// 等待交易确认
    /// 返回 true 表示交易成功，false 表示失败
    pub fn waitForTransaction(self: *Self, tx_hash: []const u8, max_attempts: u32) !bool {
        var attempts: u32 = 0;
        while (attempts < max_attempts) : (attempts += 1) {
            const receipt = self.getTransactionReceipt(tx_hash) catch |err| {
                if (err == error.ReceiptNotFound) {
                    // 交易还未被打包，继续等待
                    std.Thread.sleep(2 * std.time.ns_per_s);
                    continue;
                }
                return err;
            };

            // 检查 status（1 = 成功，0 = 失败）
            return receipt.status == 1;
        }
        return error.TransactionTimeout;
    }

    /// 获取交易回执
    fn getTransactionReceipt(self: *Self, tx_hash: []const u8) !TransactionReceipt {
        var request_body = try std.ArrayList(u8).initCapacity(self.allocator, 256);
        defer request_body.deinit(self.allocator);

        try request_body.writer(self.allocator).print(
            \\{{"jsonrpc":"2.0","method":"eth_getTransactionReceipt","params":["{s}"],"id":1}}
        , .{tx_hash});

        var client = http.HttpClient.init(self.allocator, .{
            .base_url = self.rpc_url,
        });
        defer client.deinit();

        const json_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        var response = try client.post("", request_body.items, .{
            .headers = &json_headers,
        });
        defer response.deinit();

        // 解析响应
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response.body, .{}) catch {
            return error.JsonParseError;
        };
        defer parsed.deinit();

        if (parsed.value.object.get("error")) |_| {
            return error.RpcError;
        }

        if (parsed.value.object.get("result")) |result| {
            if (result == .null) {
                return error.ReceiptNotFound;
            }

            const obj = result.object;
            const status_str = obj.get("status").?.string;
            const status = try std.fmt.parseInt(u8, status_str[2..], 16);

            // 如果交易失败，打印更多信息
            if (status == 0) {
                std.debug.print("  ⚠️ 交易失败详情:\n", .{});
                if (obj.get("gasUsed")) |gas| {
                    std.debug.print("    Gas Used: {s}\n", .{gas.string});
                }
                if (obj.get("revertReason")) |reason| {
                    std.debug.print("    Revert Reason: {s}\n", .{reason.string});
                }
                std.debug.print("    请在 Polygonscan 查看详情: https://polygonscan.com/tx/{s}\n", .{tx_hash});
            }

            return TransactionReceipt{
                .status = status,
            };
        }

        return error.NoResult;
    }

    // ========== 内部辅助函数 ==========

    fn ethCall(self: *Self, to: []const u8, data: []const u8) ![]u8 {
        var request_body = try std.ArrayList(u8).initCapacity(self.allocator, 512);
        defer request_body.deinit(self.allocator);

        // 构建 JSON-RPC 请求
        try request_body.writer(self.allocator).print(
            \\{{"jsonrpc":"2.0","method":"eth_call","params":[{{"to":"{s}","data":"0x
        , .{to});

        // 添加 hex 编码的 data
        for (data) |byte| {
            try request_body.writer(self.allocator).print("{x:0>2}", .{byte});
        }

        try request_body.appendSlice(self.allocator, "\"}, \"latest\"], \"id\":1}");

        // 发送请求
        var client = http.HttpClient.init(self.allocator, .{
            .base_url = self.rpc_url,
        });
        defer client.deinit();

        const json_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        var response = try client.post("", request_body.items, .{
            .headers = &json_headers,
        });
        defer response.deinit();

        // 解析响应
        return try self.parseRpcResult(response.body);
    }

    fn sendTransaction(self: *Self, to: []const u8, data: []const u8, value: u64) ![]const u8 {
        // 获取 nonce
        const nonce = try self.getNonce();

        // 获取 gas price
        const gas_price = try self.getGasPrice();

        // 估算 gas
        const gas_limit: u64 = 300000; // 固定 gas limit

        // 构建交易
        const tx = Transaction{
            .nonce = nonce,
            .gas_price = gas_price,
            .gas_limit = gas_limit,
            .to = to,
            .value = value,
            .data = data,
            .chain_id = self.chain_id,
        };

        // 签名交易
        const signed_tx = try self.signTransaction(tx);
        defer self.allocator.free(signed_tx);

        // 发送交易
        return try self.sendRawTransaction(signed_tx);
    }

    fn getNonce(self: *Self) !u64 {
        const address = self.wallet.getAddressChecksumHex();

        var request_body = try std.ArrayList(u8).initCapacity(self.allocator, 256);
        defer request_body.deinit(self.allocator);

        try request_body.writer(self.allocator).print(
            \\{{"jsonrpc":"2.0","method":"eth_getTransactionCount","params":["{s}","pending"],"id":1}}
        , .{address});

        var client = http.HttpClient.init(self.allocator, .{
            .base_url = self.rpc_url,
        });
        defer client.deinit();

        const json_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        var response = try client.post("", request_body.items, .{
            .headers = &json_headers,
        });
        defer response.deinit();

        const result = try self.parseRpcResult(response.body);
        defer self.allocator.free(result);

        return try std.fmt.parseInt(u64, result[2..], 16);
    }

    fn getGasPrice(self: *Self) !u64 {
        const request_body =
            \\{"jsonrpc":"2.0","method":"eth_gasPrice","params":[],"id":1}
        ;

        var client = http.HttpClient.init(self.allocator, .{
            .base_url = self.rpc_url,
        });
        defer client.deinit();

        const gas_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        var response = try client.post("", request_body, .{
            .headers = &gas_headers,
        });
        defer response.deinit();

        const result = try self.parseRpcResult(response.body);
        defer self.allocator.free(result);

        // 添加 20% 的 buffer
        const base_price = try std.fmt.parseInt(u64, result[2..], 16);
        return base_price * 120 / 100;
    }

    fn signTransaction(self: *Self, tx: Transaction) ![]u8 {
        // RLP 编码交易（用于签名）
        var rlp_buf: [1024]u8 = undefined;
        const rlp_len = try self.rlpEncode(&rlp_buf, tx);

        // 计算交易哈希
        const tx_hash = keccak.keccak256(rlp_buf[0..rlp_len]);

        // 签名 (private_key 是 Secret 包装的，需要 reveal)
        const signature = try self.wallet.private_key.reveal().sign(&tx_hash);

        // 构建签名后的交易
        var signed_buf: [1024]u8 = undefined;
        const signed_len = try self.rlpEncodeWithSignature(&signed_buf, tx, signature);

        const result = try self.allocator.alloc(u8, signed_len);
        @memcpy(result, signed_buf[0..signed_len]);
        return result;
    }

    fn sendRawTransaction(self: *Self, signed_tx: []const u8) ![]const u8 {
        var request_body = try std.ArrayList(u8).initCapacity(self.allocator, 1024);
        defer request_body.deinit(self.allocator);

        try request_body.appendSlice(self.allocator, "{\"jsonrpc\":\"2.0\",\"method\":\"eth_sendRawTransaction\",\"params\":[\"0x");

        for (signed_tx) |byte| {
            try request_body.writer(self.allocator).print("{x:0>2}", .{byte});
        }

        try request_body.appendSlice(self.allocator, "\"],\"id\":1}");

        var client = http.HttpClient.init(self.allocator, .{
            .base_url = self.rpc_url,
        });
        defer client.deinit();

        const tx_headers = [_]std.http.Header{
            .{ .name = "Content-Type", .value = "application/json" },
        };
        var response = try client.post("", request_body.items, .{
            .headers = &tx_headers,
        });
        defer response.deinit();

        return try self.parseRpcResult(response.body);
    }

    fn parseRpcResult(self: *Self, response: []const u8) ![]u8 {
        // 简单的 JSON 解析，提取 "result" 字段
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch {
            return error.JsonParseError;
        };
        defer parsed.deinit();

        if (parsed.value.object.get("error")) |_| {
            std.debug.print("RPC Error: {s}\n", .{response});
            return error.RpcError;
        }

        if (parsed.value.object.get("result")) |result| {
            const str = result.string;
            const copy = try self.allocator.alloc(u8, str.len);
            @memcpy(copy, str);
            return copy;
        }

        return error.NoResult;
    }

    fn parseTokenId(self: *Self, token_id: []const u8, out: []u8) !void {
        _ = self;
        @memset(out, 0);
        const start = if (token_id.len >= 2 and token_id[0] == '0' and token_id[1] == 'x') @as(usize, 2) else 0;
        const hex_len = token_id.len - start;
        const byte_len = hex_len / 2;
        const offset = 32 - byte_len;
        _ = hexToBytes(token_id[start..], out[offset..]) catch return error.InvalidTokenId;
    }

    fn writeU256(self: *Self, out: *[32]u8, value: anytype) void {
        _ = self;
        @memset(out, 0);
        var v: u256 = @intCast(value);
        var i: usize = 32;
        while (v > 0 and i > 0) {
            i -= 1;
            out[i] = @truncate(v);
            v >>= 8;
        }
    }

    fn writeU256Big(self: *Self, out: *[32]u8, value: u256) void {
        _ = self;
        var v = value;
        var i: usize = 32;
        while (i > 0) {
            i -= 1;
            out[i] = @truncate(v);
            v >>= 8;
        }
    }

    fn rlpEncode(self: *Self, out: *[1024]u8, tx: Transaction) !usize {
        _ = self;
        var items_buf: [512]u8 = undefined;
        var items_len: usize = 0;

        // nonce
        items_len += rlpEncodeIntBuf(items_buf[items_len..], tx.nonce);
        // gas price
        items_len += rlpEncodeIntBuf(items_buf[items_len..], tx.gas_price);
        // gas limit
        items_len += rlpEncodeIntBuf(items_buf[items_len..], tx.gas_limit);
        // to
        items_len += try rlpEncodeAddressBuf(items_buf[items_len..], tx.to);
        // value
        items_len += rlpEncodeIntBuf(items_buf[items_len..], tx.value);
        // data
        items_len += rlpEncodeBytesBuf(items_buf[items_len..], tx.data);
        // v, r, s for EIP-155
        items_len += rlpEncodeIntBuf(items_buf[items_len..], tx.chain_id);
        items_buf[items_len] = 0x80; // empty r
        items_len += 1;
        items_buf[items_len] = 0x80; // empty s
        items_len += 1;

        // 计算列表前缀
        var pos: usize = 0;
        if (items_len < 56) {
            out[0] = @as(u8, @intCast(0xc0 + items_len));
            pos = 1;
        } else {
            const len_bytes = bytesNeeded(items_len);
            out[0] = @as(u8, @intCast(0xf7 + len_bytes));
            pos = 1;
            pos += writeBigEndian(out[pos..], items_len, len_bytes);
        }
        @memcpy(out[pos..][0..items_len], items_buf[0..items_len]);
        return pos + items_len;
    }

    fn rlpEncodeWithSignature(self: *Self, out: *[1024]u8, tx: Transaction, sig: ecdsa.Signature) !usize {
        _ = self;
        var items_buf: [512]u8 = undefined;
        var items_len: usize = 0;

        // nonce
        items_len += rlpEncodeIntBuf(items_buf[items_len..], tx.nonce);
        // gas price
        items_len += rlpEncodeIntBuf(items_buf[items_len..], tx.gas_price);
        // gas limit
        items_len += rlpEncodeIntBuf(items_buf[items_len..], tx.gas_limit);
        // to
        items_len += try rlpEncodeAddressBuf(items_buf[items_len..], tx.to);
        // value
        items_len += rlpEncodeIntBuf(items_buf[items_len..], tx.value);
        // data
        items_len += rlpEncodeBytesBuf(items_buf[items_len..], tx.data);
        // v (EIP-155: v = chain_id * 2 + 35 + recovery_id)
        const v = tx.chain_id * 2 + 35 + sig.v;
        items_len += rlpEncodeIntBuf(items_buf[items_len..], v);
        // r
        items_len += rlpEncodeBytesBuf(items_buf[items_len..], &sig.r);
        // s
        items_len += rlpEncodeBytesBuf(items_buf[items_len..], &sig.s);

        // 列表前缀
        var pos: usize = 0;
        if (items_len < 56) {
            out[0] = @as(u8, @intCast(0xc0 + items_len));
            pos = 1;
        } else {
            const len_bytes = bytesNeeded(items_len);
            out[0] = @as(u8, @intCast(0xf7 + len_bytes));
            pos = 1;
            pos += writeBigEndian(out[pos..], items_len, len_bytes);
        }
        @memcpy(out[pos..][0..items_len], items_buf[0..items_len]);
        return pos + items_len;
    }
};

/// Split 结果
pub const SplitResult = struct {
    tx_hash: []const u8,
    shares: u64,
};

/// Merge 结果
pub const MergeResult = struct {
    tx_hash: []const u8,
    usdc_received: u64,
};

/// 交易回执
pub const TransactionReceipt = struct {
    status: u8, // 1 = success, 0 = failed
};

/// 交易结构
const Transaction = struct {
    nonce: u64,
    gas_price: u64,
    gas_limit: u64,
    to: []const u8,
    value: u64,
    data: []const u8,
    chain_id: u64,
};

// ========== 辅助函数 ==========

fn hexToBytes(hex: []const u8, out: []u8) !usize {
    if (hex.len % 2 != 0) return error.InvalidHexLength;
    if (hex.len / 2 > out.len) return error.BufferTooSmall;

    var i: usize = 0;
    while (i < hex.len / 2) : (i += 1) {
        const high = hexCharToNibble(hex[i * 2]) orelse return error.InvalidHexChar;
        const low = hexCharToNibble(hex[i * 2 + 1]) orelse return error.InvalidHexChar;
        out[i] = (@as(u8, high) << 4) | @as(u8, low);
    }
    return i;
}

fn hexCharToNibble(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

fn parseU256(hex: []const u8) !u256 {
    const start: usize = if (hex.len >= 2 and hex[0] == '0' and hex[1] == 'x') 2 else 0;
    var result: u256 = 0;
    for (hex[start..]) |c| {
        const nibble = hexCharToNibble(c) orelse return error.InvalidHex;
        result = (result << 4) | nibble;
    }
    return result;
}

fn bytesNeeded(value: anytype) usize {
    if (value == 0) return 1;
    var v: u256 = @intCast(value);
    var count: usize = 0;
    while (v > 0) {
        count += 1;
        v >>= 8;
    }
    return count;
}

fn writeBigEndian(out: []u8, value: anytype, bytes: usize) usize {
    var v: u256 = @intCast(value);
    var i: usize = bytes;
    while (i > 0) {
        i -= 1;
        out[i] = @truncate(v);
        v >>= 8;
    }
    return bytes;
}

fn rlpEncodeIntBuf(out: []u8, value: anytype) usize {
    if (value == 0) {
        out[0] = 0x80;
        return 1;
    }

    const val: u256 = @intCast(value);
    const bytes_needed = bytesNeeded(val);

    if (bytes_needed == 1 and val < 128) {
        out[0] = @as(u8, @intCast(val));
        return 1;
    } else {
        out[0] = @as(u8, @intCast(0x80 + bytes_needed));
        _ = writeBigEndian(out[1..], val, bytes_needed);
        return 1 + bytes_needed;
    }
}

fn rlpEncodeBytesBuf(out: []u8, data: []const u8) usize {
    // 跳过前导零
    var start: usize = 0;
    while (start < data.len and data[start] == 0) {
        start += 1;
    }
    const trimmed = data[start..];

    if (trimmed.len == 0) {
        out[0] = 0x80;
        return 1;
    } else if (trimmed.len == 1 and trimmed[0] < 128) {
        out[0] = trimmed[0];
        return 1;
    } else if (trimmed.len < 56) {
        out[0] = @as(u8, @intCast(0x80 + trimmed.len));
        @memcpy(out[1..][0..trimmed.len], trimmed);
        return 1 + trimmed.len;
    } else {
        const len_bytes = bytesNeeded(trimmed.len);
        out[0] = @as(u8, @intCast(0xb7 + len_bytes));
        const written = writeBigEndian(out[1..], trimmed.len, len_bytes);
        @memcpy(out[1 + written ..][0..trimmed.len], trimmed);
        return 1 + written + trimmed.len;
    }
}

fn rlpEncodeAddressBuf(out: []u8, addr: []const u8) !usize {
    var addr_bytes: [20]u8 = undefined;
    const start = if (addr.len >= 2 and addr[0] == '0' and addr[1] == 'x') @as(usize, 2) else 0;
    _ = hexToBytes(addr[start..], &addr_bytes) catch return error.InvalidAddress;

    out[0] = 0x80 + 20;
    @memcpy(out[1..21], &addr_bytes);
    return 21;
}

// ========== 测试 ==========

test "hexToBytes" {
    var out: [20]u8 = undefined;
    const len = try hexToBytes("4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E", &out);
    try std.testing.expectEqual(@as(usize, 20), len);
}

test "parseU256" {
    const result = try parseU256("0x64");
    try std.testing.expectEqual(@as(u256, 100), result);
}
