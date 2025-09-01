# Meme Token 与流动性池项目

这是一个基于 Hardhat 的 DeFi 项目，包含带税费机制的 Meme 代币合约和 DEX 流动性池合约。

## 合约功能

### Meme Token (ERC20)
- ✅ 基础 ERC20 功能（转账、授权等）
- ✅ 5% 转账税费机制
- ✅ 免税地址管理
- ✅ 日交易限额控制
- ✅ 铸币/销毁功能

### LiquidityPool (DEX)
- ✅ 添加/移除流动性
- ✅ ETH ⇄ Token 交换功能
- ✅ 0.3% 交易手续费
- ✅ AMM 自动做市机制

## 快速开始

### 1. 安装依赖
```bash
npm install
```

### 2. 启动本地节点
```bash
npx hardhat node
```

### 3. 部署合约
```bash
# 部署到本地网络
npx hardhat deploy --network localhost

# 部署到测试网（需配置 .env）
npx hardhat deploy --network sepolia
```

### 4. 运行测试
```bash
# 运行所有测试
npx hardhat test

# 生成 Gas 报告
REPORT_GAS=true npx hardhat test
```

## 环境配置

创建 `.env` 文件：
```
INFURA_API_KEY=your_infura_key
PK=your_private_key
```

## 合约交互示例

部署后可通过 Hardhat Console 与合约交互：
```bash
npx hardhat console --network localhost
```

```javascript
// 获取合约实例
const meme = await ethers.getContractAt("Meme", "CONTRACT_ADDRESS");
const pool = await ethers.getContractAt("LiquidityPool", "CONTRACT_ADDRESS");

// 代币操作
await meme.transfer("ADDRESS", ethers.parseUnits("100", 18));
await meme.approve("POOL_ADDRESS", ethers.parseUnits("1000", 18));

// 流动性操作
await pool.addLiquidity(ethers.parseUnits("1000", 18), { value: ethers.parseEther("1") });
await pool.swapETHForToken({ value: ethers.parseEther("0.1") });
```

## 项目结构
```
├── contracts/          # 智能合约
│   ├── meme.sol        # Meme 代币合约
│   └── liquidityPool.sol # 流动性池合约
├── test/               # 测试文件
├── hardhat.config.js   # Hardhat 配置
└── README.md          # 项目说明
```
