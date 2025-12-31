# UUID 类型

## 概述

`UUID` 是通用唯一标识符类型，存储 16 字节（128 位）数据。支持 UUID v4（随机生成）格式，用于订单 ID、交易 ID 等。

## 源文件

`src/types/uuid.zig`

## 用法

```zig
const types = @import("poly-sdk-zig").types;
const UUID = types.UUID;

// 从字符串解析（标准格式）
const id = try UUID.fromString("550e8400-e29b-41d4-a716-446655440000");

// 从字符串解析（紧凑格式）
const id2 = try UUID.fromString("550e8400e29b41d4a716446655440000");

// 生成随机 UUID v4
const random = UUID.v4();

// 输出
std.debug.print("{f}", .{id});  // "550e8400-e29b-41d4-a716-446655440000"

// 转换为字符串
const str = id.toString();      // "550e8400-e29b-41d4-a716-446655440000"
const compact = id.toCompactString();  // "550e8400e29b41d4a716446655440000"

// 获取版本和变体
const version = random.getVersion();  // 4
const variant = random.getVariant();  // 1 (RFC 4122)
```

## UUID v4 格式

UUID v4 是随机生成的，除了以下位：
- 第 6 字节高 4 位：版本号（4）
- 第 8 字节高 2 位：变体（10 二进制，表示 RFC 4122）

标准格式：`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`
- `x` = 随机十六进制
- `4` = 版本号
- `y` = 8, 9, a, 或 b（变体位）

## API

### 创建

| 方法 | 描述 |
|------|------|
| `fromString(str)` | 从字符串解析（支持带/不带连字符） |
| `fromBytes(bytes)` | 从 [16]u8 创建 |
| `fromSlice(slice)` | 从切片创建 |
| `v4()` | 生成随机 UUID v4 |
| `v4WithRandom(random)` | 使用指定随机源生成 |

### 转换

| 方法 | 描述 |
|------|------|
| `toBytes()` | 返回 [16]u8 |
| `asSlice()` | 返回 []const u8 |
| `toString()` | 返回 [36]u8 标准格式 |
| `toCompactString()` | 返回 [32]u8 紧凑格式 |

### 元信息

| 方法 | 描述 |
|------|------|
| `getVersion()` | 返回 UUID 版本（v4 返回 4） |
| `getVariant()` | 返回变体（0-3） |

### 比较

| 方法 | 描述 |
|------|------|
| `eql(other)` | 相等比较 |
| `compare(other)` | 字典序比较 |
| `isNil()` | 是否为 nil UUID |

### 常量

| 常量 | 描述 |
|------|------|
| `NIL` | Nil UUID（全零） |

## 错误

| 错误 | 描述 |
|------|------|
| `InvalidUUIDLength` | 字符串长度不是 32 或 36 |
| `InvalidUUIDFormat` | 连字符位置错误 |
| `InvalidHexCharacter` | 包含非法十六进制字符 |

## JSON 序列化

UUID 序列化为带引号的标准格式字符串：

```json
"550e8400-e29b-41d4-a716-446655440000"
```

## 变体说明

| 值 | 描述 |
|----|------|
| 0 | NCS 向后兼容（保留） |
| 1 | RFC 4122（标准） |
| 2 | Microsoft 向后兼容（保留） |
| 3 | 未来使用（保留） |

## 测试

```bash
zig test src/types/uuid.zig
# All 15 tests passed
```

## 相关

- [RFC 4122 - UUID 规范](https://tools.ietf.org/html/rfc4122)
- [Address 类型](./address.md)
- [Decimal 类型](./decimal.md)
