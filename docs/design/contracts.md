# 合约配置

本文档记录 Polymarket 在 Polygon 网络上的合约地址和配置信息。

**来源**: [py-clob-client/config.py](https://github.com/Polymarket/py-clob-client/blob/main/py_clob_client/config.py)

---

## 目录

1. [网络配置](#网络配置)
2. [Polygon 主网 (Chain ID: 137)](#polygon-主网-chain-id-137)
3. [Polygon Amoy 测试网 (Chain ID: 80002)](#polygon-amoy-测试网-chain-id-80002)
4. [Token Allowances 设置](#token-allowances-设置)
5. [合约 ABI](#合约-abi)

---

## 网络配置

| 网络 | Chain ID | RPC URL | 状态 |
|------|----------|---------|------|
| Polygon Mainnet | 137 | `https://polygon-rpc.com` | 生产环境 |
| Polygon Amoy | 80002 | - | 测试环境 |

---

## Polygon 主网 (Chain ID: 137)

### 标准市场配置

```zig
const POLYGON_CONFIG = ContractConfig{
    .exchange = "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E",
    .collateral = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",  // USDC
    .conditional_tokens = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045",
};
```

| 合约 | 地址 | 说明 |
|------|------|------|
| CTF Exchange | `0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E` | 订单匹配交易所 |
| USDC (Collateral) | `0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174` | ERC20 抵押品代币 |
| Conditional Tokens | `0x4D97DCd97eC945f40cF65F87097ACe5EA0476045` | ERC1155 条件代币 |

### Neg Risk 市场配置

用于负风险市场（如多选项市场）：

```zig
const POLYGON_NEG_RISK_CONFIG = ContractConfig{
    .exchange = "0xC5d563A36AE78145C45a50134d48A1215220f80a",
    .collateral = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174",  // USDC
    .conditional_tokens = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045",
};
```

| 合约 | 地址 | 说明 |
|------|------|------|
| Neg Risk CTF Exchange | `0xC5d563A36AE78145C45a50134d48A1215220f80a` | 负风险订单匹配 |
| Neg Risk Adapter | `0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296` | 负风险适配器 |

---

## Polygon Amoy 测试网 (Chain ID: 80002)

### 标准市场配置

```zig
const AMOY_CONFIG = ContractConfig{
    .exchange = "0xdFE02Eb6733538f8Ea35D585af8DE5958AD99E40",
    .collateral = "0x9c4e1703476e875070ee25b56a58b008cfb8fa78",
    .conditional_tokens = "0x69308FB512518e39F9b16112fA8d994F4e2Bf8bB",
};
```

### Neg Risk 市场配置

```zig
const AMOY_NEG_RISK_CONFIG = ContractConfig{
    .exchange = "0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296",
    .collateral = "0x9c4e1703476e875070ee25b56a58b008cfb8fa78",
    .conditional_tokens = "0x69308FB512518e39F9b16112fA8d994F4e2Bf8bB",
};
```

---

## Token Allowances 设置

在使用 MetaMask 或 EOA 钱包交易前，必须先设置 Token Allowances。

### 需要授权的合约

使用 Email/Magic 钱包时无需手动设置，系统会自动处理。

**USDC 授权** (ERC20 approve):

| 合约 | 地址 | 说明 |
|------|------|------|
| CTF Exchange | `0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E` | 标准市场 |
| Neg Risk Exchange | `0xC5d563A36AE78145C45a50134d48A1215220f80a` | 负风险市场 |
| Neg Risk Adapter | `0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296` | 负风险适配器 |

**CTF 授权** (ERC1155 setApprovalForAll):

同样需要授权给上述三个合约。

### 授权代码示例

#### Python 示例

```python
from web3 import Web3
from web3.constants import MAX_INT

# 合约地址
USDC_ADDRESS = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"
CTF_ADDRESS = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045"

# 需要授权的交易所
EXCHANGES = [
    "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E",  # CTF Exchange
    "0xC5d563A36AE78145C45a50134d48A1215220f80a",  # Neg Risk Exchange
    "0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296",  # Neg Risk Adapter
]

# USDC 授权 (ERC20)
for exchange in EXCHANGES:
    usdc.functions.approve(exchange, MAX_INT).transact()

# CTF 授权 (ERC1155)
for exchange in EXCHANGES:
    ctf.functions.setApprovalForAll(exchange, True).transact()
```

#### Zig 示例 (计划)

```zig
const ContractConfig = struct {
    exchange: []const u8,
    collateral: []const u8,
    conditional_tokens: []const u8,
};

pub fn getContractConfig(chain_id: u64, neg_risk: bool) !ContractConfig {
    return switch (chain_id) {
        137 => if (neg_risk) POLYGON_NEG_RISK_CONFIG else POLYGON_CONFIG,
        80002 => if (neg_risk) AMOY_NEG_RISK_CONFIG else AMOY_CONFIG,
        else => error.InvalidChainId,
    };
}
```

---

## 合约 ABI

### ERC20 Approve (USDC)

```json
{
    "name": "approve",
    "type": "function",
    "inputs": [
        {"name": "spender", "type": "address"},
        {"name": "amount", "type": "uint256"}
    ],
    "outputs": [{"name": "", "type": "bool"}]
}
```

### ERC1155 SetApprovalForAll (CTF)

```json
{
    "name": "setApprovalForAll",
    "type": "function",
    "inputs": [
        {"name": "operator", "type": "address"},
        {"name": "approved", "type": "bool"}
    ],
    "outputs": []
}
```

### 获取余额

```json
{
    "name": "balanceOf",
    "type": "function",
    "inputs": [{"name": "account", "type": "address"}],
    "outputs": [{"name": "", "type": "uint256"}]
}
```

---

## Zig 实现计划

### types/contracts.zig

```zig
//! Polymarket 合约配置

const std = @import("std");

/// 合约配置
pub const ContractConfig = struct {
    /// 订单匹配交易所
    exchange: [42]u8,
    /// 抵押品代币 (USDC)
    collateral: [42]u8,
    /// 条件代币 (ERC1155)
    conditional_tokens: [42]u8,
};

/// 链 ID
pub const Chain = enum(u64) {
    polygon = 137,
    amoy = 80002,
};

/// Polygon 主网配置
pub const POLYGON_MAINNET = ContractConfig{
    .exchange = "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E".*,
    .collateral = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174".*,
    .conditional_tokens = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045".*,
};

/// Polygon 主网 Neg Risk 配置
pub const POLYGON_MAINNET_NEG_RISK = ContractConfig{
    .exchange = "0xC5d563A36AE78145C45a50134d48A1215220f80a".*,
    .collateral = "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174".*,
    .conditional_tokens = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045".*,
};

/// Neg Risk Adapter 地址
pub const NEG_RISK_ADAPTER = "0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296";

/// 获取合约配置
pub fn getConfig(chain: Chain, neg_risk: bool) ContractConfig {
    return switch (chain) {
        .polygon => if (neg_risk) POLYGON_MAINNET_NEG_RISK else POLYGON_MAINNET,
        .amoy => if (neg_risk) AMOY_NEG_RISK else AMOY_MAINNET,
    };
}
```

---

## 参考链接

- [Polymarket 合约文档](https://docs.polymarket.com/)
- [py-clob-client config.py](https://github.com/Polymarket/py-clob-client/blob/main/py_clob_client/config.py)
- [agents polymarket.py](https://github.com/Polymarket/agents/blob/main/agents/polymarket/polymarket.py)
- [Token Allowances 设置示例](https://gist.github.com/poly-rodr/44313920481de58d5a3f6d1f8226bd5e)

---

## 更新日志

| 日期 | 变更 |
|------|------|
| 2024-12-31 | 初始版本，从官方仓库提取合约配置 |
