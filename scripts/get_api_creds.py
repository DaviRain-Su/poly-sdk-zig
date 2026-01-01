#!/usr/bin/env python3
"""
获取 Polymarket API 凭证

使用方法:
1. 安装依赖: pip install py-clob-client
2. 设置环境变量: export POLY_PRIVATE_KEY=your_private_key
3. 运行脚本: python scripts/get_api_creds.py

脚本会自动生成或派生 API 凭证，并输出可直接复制到 .env 文件的格式。
"""

import os
import sys

def main():
    # 检查依赖
    try:
        from py_clob_client.client import ClobClient
    except ImportError:
        print("错误: 请先安装 py-clob-client")
        print("运行: pip install py-clob-client")
        sys.exit(1)
    
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
        print("错误: 请设置 POLY_PRIVATE_KEY 环境变量或在 .env 文件中配置")
        print("")
        print("方法一: 设置环境变量")
        print("  export POLY_PRIVATE_KEY=your_private_key_without_0x")
        print("")
        print("方法二: 在 .env 文件中添加")
        print("  POLY_PRIVATE_KEY=your_private_key_without_0x")
        sys.exit(1)
    
    # 移除 0x 前缀（如果有）
    if private_key.startswith("0x"):
        private_key = private_key[2:]
    
    print("正在连接 Polymarket API...")
    print("")
    
    try:
        # 创建客户端
        client = ClobClient(
            "https://clob.polymarket.com",
            key=private_key,
            chain_id=137,  # Polygon mainnet
        )
        
        print(f"钱包地址: {client.get_address()}")
        print("")
        
        # 获取或创建 API 凭证
        print("正在获取 API 凭证...")
        creds = client.create_or_derive_api_creds()
        
        if creds is None:
            print("错误: 无法获取 API 凭证")
            sys.exit(1)
        
        print("")
        print("=" * 60)
        print("成功获取 API 凭证！")
        print("=" * 60)
        print("")
        print("请将以下内容添加到 .env 文件:")
        print("")
        print(f"POLY_API_KEY={creds.api_key}")
        print(f"POLY_API_SECRET={creds.api_secret}")
        print(f"POLY_API_PASSPHRASE={creds.api_passphrase}")
        print("")
        print("=" * 60)
        print("")
        print("完整 .env 文件示例:")
        print("")
        print(f"POLY_PRIVATE_KEY={private_key}")
        print(f"POLY_API_KEY={creds.api_key}")
        print(f"POLY_API_SECRET={creds.api_secret}")
        print(f"POLY_API_PASSPHRASE={creds.api_passphrase}")
        print("AUTO_TRADER_DRY_RUN=false")
        print("")
        
    except Exception as e:
        print(f"错误: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
