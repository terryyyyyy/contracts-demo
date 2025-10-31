# 🚀 快速开始 - 5分钟部署你的第一个 LMSR 市场

## 核心回答：ConditionalTokens 只需要部署一次！

### ✅ 是的，ConditionalTokens 是全局基础设施合约

**关键理解**：
- ConditionalTokens 就像是 Uniswap 的 Factory 合约
- **整个链上只需要部署一次**
- 所有市场都共享同一个 ConditionalTokens 实例
- 你创建 100 个市场 = 100 个 LMSRMarketMaker，但只有 1 个 ConditionalTokens

---

## 🎯 两种部署场景

### 场景 1：使用已部署的 ConditionalTokens（推荐）

如果你的目标链已有部署（如 Polygon、Mainnet），直接使用即可：

```javascript
// Polygon 上 Polymarket 使用的地址
const CONDITIONAL_TOKENS = "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045";
```

**已知部署地址**：
- **Polygon**: `0x4D97DCd97eC945f40cF65F87097ACe5EA0476045` (Polymarket)
- **Mainnet**: `0xC59b0e4De5F1248C1140964E0fF287B192407E0C` (Gnosis)
- **xDai**: `0xCeAfDD6bc0bEF976fdCd1112955828E00543c0Ce` (Gnosis)

### 场景 2：自行部署 ConditionalTokens

**什么时候需要自己部署？**
- 新的 L2/侧链
- 测试网络（本地/测试网）
- 想要完全控制基础设施

---

## 📝 完整部署清单

### 步骤 1：ConditionalTokens（仅首次部署）

**如果目标链已部署**：
```bash
# 跳过此步骤，直接在配置中使用现有地址
```

**如果需要部署**：
```bash
npx hardhat run scripts/deploy-conditionaltokens.js --network polygon
```

### 步骤 2：部署依赖和工厂

**这一步每次设置都需要执行**（除非使用已有工厂）：

```bash
# 1. 部署 Fixed192x64Math 库
npx hardhat run scripts/deploy-math-lib.js --network polygon

# 2. 部署 LMSRMarketMakerFactory  
npx hardhat run scripts/deploy-lmsr-factory.js --network polygon
```

### 步骤 3：创建你的第一个市场

```bash
# 创建市场（50万 funding）
npx hardhat run scripts/create-market.js --network polygon
```

或使用环境变量自定义：

```bash
COLLATERAL_TOKEN=0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174 \
FUNDING=500000000000 \
npx hardhat run scripts/create-market.js --network polygon
```

---

## ⚙️ 配置说明

### funding 参数详解

你问到的 **50万个抵押物**，应该这样配置：

```javascript
// 对于 USDC (6位小数)
const funding = ethers.utils.parseUnits("500000", 6);
// = "500000000000"

// 实际影响
// - funding = 500,000
// - LMSR 的 b = funding / ln(2) ≈ 721,500  
// - 超高流动性，价格非常稳定
```

### 完整示例

```javascript
// 创建市场配置
const marketConfig = {
  // 条件设置
  oracle: "0xYourOracleAddress",           // Oracle 地址
  question: "Will Bitcoin reach $100k?",   // 市场问题
  outcomes: 2,                              // YES/NO
  
  // 市场设置
  collateral: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC
  funding: "500000000000",                  // 50万 USDC
  fee: 0,                                   // 0% 手续费
  whitelist: "0x0000000000000000000000000000000000000000", // 无白名单
};
```

---

## 🧪 验证部署

### 检查市场状态

```bash
npx hardhat run scripts/test-market.js --network polygon
```

输出示例：
```
当前价格:
YES: 0.5  (50%)
NO: 0.5   (50%)

购买 1000 个 YES 的成本: 1000000000

市场状态:
资金池: 500000000000
手续费: 0%
状态: Running
```

---

## 📊 完整架构图

```
ConditionalTokens (全局, 1个)
    │
    ├─ Condition 1: "Bitcoin $100k?" (YES/NO)
    │     ├── Market A (LMSR, funding=500k)
    │     └── Market B (LMSR, funding=1M)
    │
    ├─ Condition 2: "Ethereum $5k?" (YES/NO)
    │     └── Market C (LMSR, funding=200k)
    │
    └─ Condition N...
```

---

## 💡 最佳实践

### 1. 选择合适的抵押物
```javascript
// 推荐：稳定币
USDC: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"  // Polygon USDC
DAI:  "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063"   // Polygon DAI

// 也可以：原生代币包装
WETH: "0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270"  // Polygon WETH
```

### 2. funding 选择建议
- **小市场** (<10万): 适合早期测试
- **中市场** (10-50万): 一般应用
- **大市场** (50万+): 适合高流动性需求 ⭐️
- **超大市场** (100万+): 机构级应用

### 3. Oracle 设置
```javascript
// Oracle 可以是：
// 1. 你的地址
oracle: deployer.address

// 2. 多签钱包
oracle: "0xMultiSigAddress"

// 3. 预言机合约
oracle: "0xOracleContract"
```

---

## 🔧 故障排查

### 问题 1：ConditionalTokens 已存在
```
⚠️  警告: ConditionalTokens 已在此网络部署
现有地址: 0x4D97DCd97eC945f40cF65F87097ACe5EA0476045
```
**解决**：直接用现有地址，不要重复部署。

### 问题 2：Gas 不足
```
Error: insufficient funds for gas
```
**解决**：增加账户余额，或降低 funding 金额测试。

### 问题 3：条件已存在
```
require(payoutNumerators[conditionId].length == 0, "condition already prepared")
```
**解决**：使用不同的 oracle/questionId 组合。

---

## 📚 完整文档

详细文档请查看：**[LMSR_DEPLOYMENT_GUIDE.md](./LMSR_DEPLOYMENT_GUIDE.md)**

---

## ✅ 检查清单

部署前确认：

- [ ] 目标链上是否有 ConditionalTokens？
  - [ ] 有 → 直接使用现有地址
  - [ ] 无 → 先部署 ConditionalTokens
- [ ] 已部署 Fixed192x64Math 库？
- [ ] 已部署 LMSRMarketMakerFactory？
- [ ] 有足够的抵押物代币余额？
- [ ] 代币已批准给 Factory？

---

## 🎉 总结

**关键概念**：
1. ✅ ConditionalTokens = 全局基础设施（1个/链）
2. ✅ LMSRMarketMaker = 独立市场（可以创建无数个）
3. ✅ funding = 500,000 → b ≈ 721,500（极高流动性）
4. ✅ 50万个抵押物 → 设置 funding = "500000000000"（根据小数位调整）

**快速命令**：
```bash
# 使用现有基础设施
export CONDITIONAL_TOKENS=0x4D97DCd97eC945f40cF65F87097ACe5EA0476045
export FUNDING=500000000000

# 直接创建市场
npx hardhat run scripts/create-market.js --network polygon
```

现在就试试创建你的第一个市场吧！ 🚀

