# MetaNodeStake - 质押挖矿合约

基于OpenZeppelin的可升级质押挖矿智能合约，支持ETH和ERC20代币质押。

## 功能特性

- **多资产质押**: 支持ETH和ERC20代币质押
- **灵活奖励**: 基于区块的奖励分发机制
- **权限管理**: 基于角色的访问控制
- **可升级**: 使用UUPS代理模式
- **安全提取**: 防挤兑的延迟提取机制

## 合约架构

- `MetaNodeStake.sol` - 主质押合约
- `MetaNodeToken.sol` - 奖励代币合约

## 快速开始

### 安装依赖
```bash
npm install
```

### 编译合约
```bash
npx hardhat compile
```

### 运行测试
```bash
npx hardhat test
```

### 部署合约
```bash
npx hardhat run scripts/deploy.js
```

## 主要功能

- `depositETH()` - ETH质押
- `deposit(pid, amount)` - ERC20代币质押
- `unstake(pid, amount)` - 发起解质押请求
- `withdraw(pid)` - 提取解锁的资产
- `claim(pid)` - 领取奖励
- `addPool()` - 添加新的质押池（管理员）

## 许可证

MIT