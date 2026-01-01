#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "eth-account",
#     "poly-eip712-structs",
# ]
# ///
"""
EIP-712 签名调试工具

用于对比 Zig 实现和 Python 实现的 EIP-712 签名。
输出详细的中间哈希值，便于调试。
"""

import os
import sys
import time

from eth_account import Account
from eth_utils import keccak
from poly_eip712_structs import make_domain, EIP712Struct, Address, String, Uint


def main():
    # 获取私钥
    private_key = os.environ.get("POLY_PRIVATE_KEY")

    if not private_key:
        # 尝试从 .env 文件读取
        env_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), ".env")
        if os.path.exists(env_file):
            with open(env_file) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("POLY_PRIVATE_KEY="):
                        private_key = line.split("=", 1)[1].strip()
                        break

    if not private_key:
        print("请设置 POLY_PRIVATE_KEY 环境变量")
        sys.exit(1)

    # 确保有 0x 前缀
    if not private_key.startswith("0x"):
        private_key = "0x" + private_key

    # 创建账户
    account = Account.from_key(private_key)
    address = account.address

    print("=" * 70)
    print("EIP-712 签名调试")
    print("=" * 70)
    print("")
    print(f"地址: {address}")
    print("")

    # 使用固定的时间戳和 nonce 便于对比
    # 可以通过命令行参数指定时间戳: python debug_eip712.py 1767236442
    if len(sys.argv) > 1:
        timestamp = int(sys.argv[1])
    else:
        timestamp = int(time.time())
    nonce = 0
    chain_id = 137
    message = "This message attests that I control the given wallet"

    print(f"Timestamp: {timestamp}")
    print(f"Nonce: {nonce}")
    print(f"Chain ID: {chain_id}")
    print(f"Message: {message}")
    print("")

    # 定义 ClobAuth 结构
    class ClobAuth(EIP712Struct):
        address = Address()
        timestamp = String()
        nonce = Uint()  # 默认是 uint256
        message = String()

    # 创建域
    domain = make_domain(name="ClobAuthDomain", version="1", chainId=chain_id)

    # 创建消息
    clob_auth = ClobAuth(
        address=address,
        timestamp=str(timestamp),
        nonce=nonce,
        message=message,
    )

    print("-" * 70)
    print("域 (Domain)")
    print("-" * 70)
    print(f"  name: ClobAuthDomain")
    print(f"  version: 1")
    print(f"  chainId: {chain_id}")
    print("")

    # 计算域类型哈希
    domain_type_str = domain.encode_type()
    domain_type_hash = domain.type_hash()
    print(f"域类型字符串: {domain_type_str}")
    print(f"域类型哈希: 0x{domain_type_hash.hex()}")
    print("")

    # 计算域分隔符哈希
    domain_hash = domain.hash_struct()
    print(f"域分隔符哈希 (domain separator): 0x{domain_hash.hex()}")
    print("")

    print("-" * 70)
    print("消息结构 (ClobAuth)")
    print("-" * 70)
    print(f"  address: {address}")
    print(f'  timestamp: "{timestamp}"')
    print(f"  nonce: {nonce}")
    print(f'  message: "{message}"')
    print("")

    # 计算消息类型哈希
    clob_auth_type_str = clob_auth.encode_type()
    clob_auth_type_hash = clob_auth.type_hash()
    print(f"ClobAuth 类型字符串: {clob_auth_type_str}")
    print(f"ClobAuth 类型哈希: 0x{clob_auth_type_hash.hex()}")
    print("")

    # 编码各字段
    print("字段编码:")
    # address 编码
    addr_encoded = keccak(bytes.fromhex(address[2:].lower().zfill(40)))
    print(f"  address (keccak256 of bytes): {address[2:].lower().zfill(40)}")

    # 地址的 ABI 编码是左填充零到 32 字节
    addr_abi = bytes.fromhex(address[2:]).rjust(32, b"\x00")
    print(f"  address ABI 编码: 0x{addr_abi.hex()}")

    # timestamp 编码 (keccak256 of string)
    timestamp_hash = keccak(text=str(timestamp))
    print(f'  timestamp (keccak256 of "{timestamp}"): 0x{timestamp_hash.hex()}')

    # nonce 编码 (uint256)
    nonce_encoded = nonce.to_bytes(32, byteorder="big")
    print(f"  nonce (uint256): 0x{nonce_encoded.hex()}")

    # message 编码 (keccak256 of string)
    message_hash = keccak(text=message)
    print(f'  message (keccak256 of "{message}"): 0x{message_hash.hex()}')
    print("")

    # 计算结构体哈希
    struct_hash = clob_auth.hash_struct()
    print(f"结构体哈希 (struct hash): 0x{struct_hash.hex()}")
    print("")

    # 计算可签名字节
    signable = clob_auth.signable_bytes(domain)
    print(f"可签名字节 (signable bytes): 0x{signable.hex()}")
    print(f"  长度: {len(signable)} bytes")
    print(f"  前缀: 0x{signable[:2].hex()} (应该是 1901)")
    print("")

    # 计算最终摘要
    digest = keccak(signable)
    print(f"签名摘要 (digest): 0x{digest.hex()}")
    print("")

    # 签名 - 使用 unsafe_sign_hash 直接签名摘要
    signed = account.unsafe_sign_hash(digest)
    r = hex(signed.r)[2:].zfill(64)
    s = hex(signed.s)[2:].zfill(64)
    v = hex(signed.v)[2:].zfill(2)
    signature = f"0x{r}{s}{v}"

    print("-" * 70)
    print("签名结果")
    print("-" * 70)
    print(f"r: 0x{r}")
    print(f"s: 0x{s}")
    print(f"v: {signed.v}")
    print(f"完整签名: {signature}")
    print("")

    print("-" * 70)
    print("HTTP Headers")
    print("-" * 70)
    print(f"POLY_ADDRESS: {address}")
    print(f"POLY_SIGNATURE: {signature}")
    print(f"POLY_TIMESTAMP: {timestamp}")
    print(f"POLY_NONCE: {nonce}")
    print("")

    print("-" * 70)
    print("curl 命令")
    print("-" * 70)
    print(f"""curl -s -X GET 'https://clob.polymarket.com/auth/derive-api-key' \\
  -H 'Accept: application/json' \\
  -H 'Content-Type: application/json' \\
  -H 'POLY_ADDRESS: {address}' \\
  -H 'POLY_SIGNATURE: {signature}' \\
  -H 'POLY_TIMESTAMP: {timestamp}' \\
  -H 'POLY_NONCE: {nonce}'""")
    print("")


if __name__ == "__main__":
    main()
