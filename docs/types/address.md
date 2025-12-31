# Address 类型

## 概述

`Address` 是以太坊地址类型，存储 20 字节（160 位）数据，支持 EIP-55 校验和验证。

## 源文件

`src/types/address.zig`

## 用法

```zig
const types = @import("poly-sdk-zig").types;
const Address = types.Address;

// 从十六进制字符串创建（支持 EIP-55 校验和验证）
const addr = try Address.fromHex("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045");

// 跳过校验和验证
const addr2 = try Address.fromHexUnchecked("0xd8da6bf26964af9d7eed9e03e53415d37aa96045");

// 从原始字节创建
var bytes: [20]u8 = undefined;
const addr3 = Address.fromBytes(bytes);

// 输出（自动使用 EIP-55 格式）
std.debug.print("{f}", .{addr});  // "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"

// 转换为小写
const lower = addr.toLowerHex();  // "0xd8da6bf26964af9d7eed9e03e53415d37aa96045"

// 转换为校验和格式
const checksummed = addr.toChecksumHex();  // "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
```

## EIP-55 校验和

EIP-55 使用混合大小写来编码校验和信息：

1. 将地址转换为小写十六进制
2. 对小写地址进行 Keccak256 哈希
3. 如果哈希的第 i 位 >= 8，则将第 i 个字符大写

**校验和验证规则**：
- 全小写地址：不验证校验和（`0xd8da6bf26964...`）
- 全大写地址：不验证校验和（`0xD8DA6BF26964...`）
- 混合大小写：验证校验和，失败返回 `error.InvalidChecksum`

## API

### 创建

| 方法 | 描述 |
|------|------|
| `fromHex(hex)` | 从十六进制字符串创建，验证校验和 |
| `fromHexUnchecked(hex)` | 从十六进制字符串创建，跳过校验和验证 |
| `fromBytes(bytes)` | 从 [20]u8 创建 |
| `fromSlice(slice)` | 从切片创建 |

### 转换

| 方法 | 描述 |
|------|------|
| `toBytes()` | 返回 [20]u8 |
| `asSlice()` | 返回 []const u8 |
| `toLowerHex()` | 返回 [42]u8 小写十六进制 |
| `toChecksumHex()` | 返回 [42]u8 EIP-55 格式 |

### 比较

| 方法 | 描述 |
|------|------|
| `eql(other)` | 相等比较 |
| `compare(other)` | 字典序比较 |
| `isZero()` | 是否为零地址 |

### 常量

| 常量 | 描述 |
|------|------|
| `ZERO` | 零地址（0x0000...0000） |

## 错误

| 错误 | 描述 |
|------|------|
| `InvalidAddressLength` | 地址长度不是 40 字符 |
| `InvalidHexCharacter` | 包含非法十六进制字符 |
| `InvalidChecksum` | EIP-55 校验和验证失败 |

## JSON 序列化

地址序列化为带引号的 EIP-55 格式字符串：

```json
"0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"
```

## 测试

```bash
zig test src/types/address.zig
# All 15 tests passed
```

## 相关

- [EIP-55 规范](https://eips.ethereum.org/EIPS/eip-55)
- [Decimal 类型](./decimal.md)
- [UUID 类型](./uuid.md)
