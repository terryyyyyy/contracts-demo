# Polymarket LMSR 部署完整指南

## 🎯 核心问题回答

### ConditionalTokens 是否只需要部署一次？

**✅ 是的！ConditionalTokens 是全局基础设施合约，每个链只需要部署一次。**

类比理解：
- ConditionalTokens = Uniswap V2 Factory（全局基础设施）
- 每个市场 = Uniswap V2 Pair（独立合约）

一个 ConditionalTokens 可以服务无数个市场。

---

## 📁 文件结构

```
contracts-demo/
├── LMSR_DEPLOYMENT_GUIDE.md      # 完整部署指南
├── QUICK_START.md                # 5分钟快速开始
├── README_LMSR.md                # 本文档
├── scripts/
│   ├── deploy-conditionaltokens.js  # 部署 ConditionalTokens
│   └── create-market.js             # 创建 LMSR 市场
├── deployments/                   # 部署配置
│   └── polygon.json               # Polygon 网络配置
└── contracts/
    └── polymarket/
        ├── conditional-tokens-contracts/
        └── conditional-tokens-market-makers/
```

---

## 🚀 快速开始

### 方案 A：使用已部署的 ConditionalTokens（推荐）

```bash
# Polygon 上已有部署，直接使用
export CONDITIONAL_TOKENS=0x4D97DCd97eC945f40cF65F87097ACe5EA0476045

# 创建你的第一个市场（50万 funding）
COLLATERAL_TOKEN=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174 \
FUNDING=500000000000 \
npx hardhat run scripts/create-market.js --network polygon
```

### 方案 B：完整部署流程

```bash
# 1. 部署 ConditionalTokens（仅首次）
npx hardhat run scripts/deploy-conditionaltokens.js --network yourNetwork

# 2. 创建市场
npx hardhat run scripts/create-market.js --network yourNetwork
```

---

## 📖 文档导航

### 新手入门
👉 **先读这个**：[QUICK_START.md](./QUICK_START.md)
- 5分钟快速部署
- 概念解释
- 常见问题

### 完整参考
👉 **深度了解**：[LMSR_DEPLOYMENT_GUIDE.md](./LMSR_DEPLOYMENT_GUIDE.md)
- 详细部署步骤
- 参数配置详解
- 架构说明
- 最佳实践

---

## 🔑 关键参数

### funding 参数（50万个抵押物）

```javascript
// 对于 USDC (6位小数)
const funding = "500000000000"; // 50万 * 10^6

// 实际效果
funding = 500,000
LMSR b ≈ 721,500  // 对于 2 结果市场
= 超高流动性，价格非常稳定
```

### 不同规模推荐

| 抵押物 | funding | 使用场景 |
|-------|---------|---------|
| 1万 | `10000000000` | 测试/小规模 |
| 10万 | `100000000000` | 中等市场 |
| **50万** | **`500000000000`** | **你的场景 ⭐** |
| 100万 | `1000000000000` | 大机构 |

---

## 🏗️ 部署架构

```
┌─────────────────────────────────────┐
│  ConditionalTokens (全局基础设施)   │
│  地址: 0x4D97...6045                │
│  部署: 1次/链                       │
└─────────────────────────────────────┘
              │
              ├─ Condition 1: "Bitcoin $100k?"
              │  ├─ Market A (LMSR, 50万)
              │  └─ Market B (LMSR, 100万)
              │
              ├─ Condition 2: "ETH $5k?"
              │  └─ Market C (LMSR, 20万)
              │
              └─ ... (无限市场)
```

---

## ✅ 部署检查清单

### ConditionalTokens
- [ ] 确认目标链是否已有 ConditionalTokens
- [ ] 如果没有，先部署 ConditionalTokens
- [ ] 保存部署地址到配置

### 依赖库
- [ ] 部署 Fixed192x64Math 库
- [ ] 部署 LMSRMarketMakerFactory

### 创建市场
- [ ] 准备条件（prepareCondition）
- [ ] 批准抵押物代币
- [ ] 设置 funding = 50万
- [ ] 调用 createLMSRMarketMaker
- [ ] 验证市场状态

---

## 📊 已知部署地址

### Polygon (Polymarket)
```
ConditionalTokens: 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045
```

### Mainnet (Gnosis)
```
ConditionalTokens: 0xC59b0e4De5F1248C1140964E0fF287B192407E0C
```

### xDai (Gnosis)  
```
ConditionalTokens: 0xCeAfDD6bc0bEF976fdCd1112955828E00543c0Ce
```

---

## 🔧 环境准备

### 1. 安装依赖
```bash
npm install
```

### 2. 配置网络
在 `hardhat.config.js` 中添加你的网络配置：

```javascript
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.5.1", // ConditionalTokens 使用 0.5.1
      },
      {
        version: "0.8.9", // 其他合约
      },
    ],
  },
  networks: {
    polygon: {
      url: process.env.POLYGON_RPC || "https://polygon-rpc.com",
      accounts: [process.env.PRIVATE_KEY],
    },
  },
};
```

### 3. 设置环境变量
```bash
# .env 文件
PRIVATE_KEY=your_private_key
POLYGON_RPC=https://polygon-rpc.com
COLLATERAL_TOKEN=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174
```

---

## 🎓 重要概念

### ConditionalTokens 的作用
- 管理所有条件（conditions）
- 处理仓位分割（split）和合并（merge）
- 处理结果兑换（redeem）
- 类似于 ERC1155 标准的条件化实现

### LMSR 的优势
- **信息聚合**：价格反映市场共识
- **流动性提供**：即使没有人持有对家头寸也能交易
- **激励机制**：正确的交易者获得收益

### funding 的作用
- 决定市场深度（liquidity depth）
- 越大 = 流动性越强，价格波动越小
- **50万 = 极高的流动性**

---

## 🐛 常见问题

### Q: ConditionalTokens 可以部署多次吗？
A: 可以，但不推荐。应该使用已部署的全局实例。

### Q: 50万个抵押物如何设置？
A: `funding = "500000000000"` （根据代币精度调整）

### Q: 需要每次部署工厂吗？
A: 不需要。工厂可以重复使用创建多个市场。

### Q: 可以用不同的抵押物吗？
A: 可以！任意 ERC20 代币都可以作为抵押物。

---

## 📞 获取帮助

1. 查看 [QUICK_START.md](./QUICK_START.md) 快速入门
2. 阅读 [LMSR_DEPLOYMENT_GUIDE.md](./LMSR_DEPLOYMENT_GUIDE.md) 详细指南
3. 参考 Polymarket 官方文档
4. 查看代码注释

---

## 🎉 开始你的部署

```bash
# 1. 快速创建市场（使用已有基础设施）
npx hardhat run scripts/create-market.js --network polygon

# 2. 查看部署结果
cat deployments/polygon.json

# 3. 完成！
```

祝部署顺利！ 🚀

