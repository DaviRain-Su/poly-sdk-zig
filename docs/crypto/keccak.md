# Keccak256 哈希

> 以太坊兼容的 Keccak256 哈希实现

## 概述

Keccak256 是以太坊使用的哈希算法，不同于标准 SHA-3（FIPS 202）。本模块封装了 Zig 标准库的 Keccak256 实现。

## 类型

### Hash

32 字节哈希值类型。

```zig
pub const Hash = [32]u8;
```

### Hasher

流式哈希器，支持分块计算。

```zig
pub const Hasher = struct {
    pub fn init() Hasher;
    pub fn update(self: *Hasher, data: []const u8) void;
    pub fn final(self: *Hasher) Hash;
    pub fn finalTo(self: *Hasher, out: *Hash) void;
};
```

## 函数

### keccak256

计算数据的 Keccak256 哈希。

```zig
pub fn keccak256(data: []const u8) Hash
```

**参数**:
- `data`: 要哈希的数据

**返回**: 32 字节哈希值

**示例**:
```zig
const hash = keccak256("hello");
// => 0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8
```

### keccak256Multi

计算多个数据块的 Keccak256 哈希。

```zig
pub fn keccak256Multi(parts: []const []const u8) Hash
```

**参数**:
- `parts`: 数据块数组

**返回**: 32 字节哈希值

**示例**:
```zig
const hash = keccak256Multi(&.{ "Hello", ", ", "World!" });
// 等同于 keccak256("Hello, World!")
```

### toHexString

将哈希值格式化为十六进制字符串。

```zig
pub fn toHexString(hash: *const Hash, buffer: *[66]u8) []const u8
```

**参数**:
- `hash`: 哈希值
- `buffer`: 输出缓冲区（66 字节: "0x" + 64 hex）

**返回**: 格式化的字符串切片

**示例**:
```zig
const hash = keccak256("hello");
var buffer: [66]u8 = undefined;
const hex = toHexString(&hash, &buffer);
// => "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
```

### fromHexString

从十六进制字符串解析哈希值。

```zig
pub fn fromHexString(hex: []const u8) ?Hash
```

**参数**:
- `hex`: 十六进制字符串（可带 0x 前缀）

**返回**: 哈希值，解析失败返回 `null`

**示例**:
```zig
const hash = fromHexString("0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8");
// => [32]u8{...}
```

## 常量

| 常量 | 值 | 描述 |
|------|---|------|
| `HASH_LENGTH` | 32 | 哈希输出长度（字节） |

## 使用示例

### 基本哈希

```zig
const crypto = @import("poly-sdk-zig").crypto;

const hash = crypto.keccak256("Hello, Polymarket!");
```

### 流式哈希

```zig
var hasher = crypto.Hasher.init();
hasher.update("Hello");
hasher.update(", ");
hasher.update("Polymarket!");
const hash = hasher.final();
```

### EIP-712 类型哈希

```zig
const type_string = "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)";
const type_hash = crypto.keccak256(type_string);
// => 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f
```

## 已知哈希值

| 输入 | Keccak256 |
|------|-----------|
| `""` (空) | `0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470` |
| `"hello"` | `0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8` |

## 注意事项

- Keccak256 ≠ SHA3-256（以太坊使用的是原始 Keccak，不是 NIST 标准化的 SHA-3）
- 哈希是确定性的，相同输入总是产生相同输出
- 哈希是单向的，无法从哈希值反推原始数据
