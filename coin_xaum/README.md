# XAUM Coin Deployment and Usage Guide

这是一个 Sui 区块链上的 XAUM 代币合约，支持任何人铸造代币（用于测试目的）。

# # Contract Features

- **代币符号**: XAUM
- **代币名称**: XAUM Token
- **小数位数**: 9
- **铸造权限**: 任何人都可以铸造（测试版本）
- **共享对象**: GlobalMintCap 作为共享对象，允许多人访问

# # Preconditions

1. 安装 Sui CLI
2. 配置 Sui 客户端并连接到网络（testnet/devnet）
3. 确保有足够的 SUI 用于支付 gas 费用
4. 安装 `jq` 和 `bc` 工具（用于 JSON 解析和数学计算）

# # Usage Method

# Deploy the contract and mint the token

```bash
# Deploy the contract and mint the default number of tokens to the currently active address
./deploy_and_mint.sh

# Deploy the contract and mint the specified quantity of tokens to the designated address
./deploy_and_mint.sh 0x123...abc 5000000000000

# Designated network
./deploy_and_mint.sh 0x123...abc 5000000000000 testnet
```

**参数说明**：
- `recipient_address`（可选）：接收代币的地址，默认为当前活跃地址
- `amount`（可选）：铸造数量（原始单位，包含9位小数），默认为 1000000000000（1000 XAUM）
- `network`（可选）：网络名称，默认为 testnet

# 2. Only mint tokens (the contract has been deployed)

```bash
# Read the deployment information from the deployment_info.json file and cast it
./mint_tokens.sh

# Manually specify the parameters for casting
./mint_tokens.sh [package_id] [global_mint_cap_id] [recipient_address] [amount]
```

**示例**：
```bash
./mint_tokens.sh 0xabc123... 0xdef456... 0x789ghi... 2000000000000
```

# # Document Description

- `coin_xaum.move`: 主合约文件
- `Move.toml`: Move 包配置文件
- `deploy_and_mint.sh`: 部署和铸造脚本
- `mint_tokens.sh`: 仅铸造脚本
- `deployment_info.json`: 部署信息文件（自动生成）

# # Deployment Information file

部署成功后，会生成 `deployment_info.json` 文件，包含以下信息：

```json
{
  "packageId": "0x...",
  "globalMintCapId": "0x...",
  "network": "testnet",
  "deploymentTime": "2024-01-01T12:00:00Z",
  "lastMintedCoinId": "0x...",
  "lastMintRecipient": "0x...",
  "lastMintAmount": "1000000000000",
  "lastMintTime": "2024-01-01T12:05:00Z"
}
```

# # Manual Operation

# View the contract object

```bash
# View package information
sui client object <package_id>

# View the GlobalMintCap object
sui client object <global_mint_cap_id>

# View the minted tokens
sui client object <coin_object_id>
```

# Manually call the mint method

```bash
sui client call \
  --package <package_id> \
  --module coin_xaum \
  --function mint \
  --args <global_mint_cap_id> <amount> <recipient_address> \
  --gas-budget 10000000
```

# Check the address balance

```bash
# View all objects at the specified address
sui client gas --owner <address>

# Or view all objects
sui client objects <address>
```

# # Precautions

1. **测试用途**: 这个合约允许任何人铸造代币，仅用于测试目的
2. **Gas 费用**: 确保账户有足够的 SUI 支付交易费用
3. **网络**: 确认连接到正确的网络（testnet/devnet/mainnet）
4. **数量单位**: 铸造数量使用原始单位（包含9位小数），1 XAUM = 1000000000 原始单位

# # Troubleshooting

1. **构建失败**: 检查 Move.toml 配置和网络连接
2. **部署失败**: 确认 gas 预算足够（建议 100000000）
3. **铸造失败**: 检查 GlobalMintCap 对象 ID 是否正确
4. **工具缺失**: 安装 `jq` 和 `bc` 工具

# # Sample operation process

```bash
# 1. Enter the contract directory
cd contracts/coin_xaum

# 2. Deploy the contract and mint the token
./deploy_and_mint.sh

# 3. Re-cast to another address
./mint_tokens.sh 0x123...abc 5000000000000

# 4. View the deployment information
cat deployment_info.json

# 5. Check the balance
sui client gas --owner $(sui client active-address)
```