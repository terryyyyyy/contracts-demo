# LMSR 最小化部署指南

## 📋 核心概念

### ConditionalTokens 的本质
**ConditionalTokens 是一个全局基础设施合约**，类似于 Uniswap Factory 的角色：
- ✅ **全链共享**：整个平台只有一个实例
- ✅ **多市场共用**：所有 AMM 市场都使用同一个 ConditionalTokens
- ✅ **只部署一次**：在每个链上部署一次即可

### 架构关系
```
ConditionalTokens (全局基础设施)
    ├── Market 1 (LMSR AMM)
    ├── Market 2 (LMSR AMM)  
    ├── Market 3 (Fixed Product AMM)
    └── ...
```

每个市场都是独立部署的 AMM 合约，但共享同一个 ConditionalTokens 基础设施。

## 🎯 部署场景

### 场景 A: 使用现有 ConditionalTokens（推荐）
如果你的目标链（如 Polygon）已经有部署好的 ConditionalTokens，直接使用即可。

#### Polygon 上的已知地址
- ConditionalTokens (Polymarket): `0x4D97DCd97eC945f40cF65F87097ACe5EA0476045`

### 场景 B: 自行部署 ConditionalTokens
对于新链或测试环境，需要先部署 ConditionalTokens。

---

## 🚀 完整部署流程

### 第一步：部署 ConditionalTokens（仅首次）

```bash
# 1. 部署 ConditionalTokens 合约
npx hardhat run scripts/deploy-conditionaltokens.js --network yourNetwork
```

**部署脚本示例** (`scripts/deploy-conditionaltokens.js`):

```javascript
const hre = require("hardhat");

async function main() {
  console.log("部署 ConditionalTokens...");
  
  // 读取 ConditionalTokens 合约
  const ConditionalTokens = await hre.ethers.getContractFactory("ConditionalTokens");
  
  // 部署合约
  const conditionalTokens = await ConditionalTokens.deploy();
  await conditionalTokens.deployed();
  
  console.log("✅ ConditionalTokens 已部署到:");
  console.log(conditionalTokens.address);
  
  // 保存地址到配置文件
  const fs = require('fs');
  const config = {
    network: hre.network.name,
    conditionalTokens: conditionalTokens.address,
    deployedAt: new Date().toISOString()
  };
  
  fs.writeFileSync(
    `deployments/${hre.network.name}.json`,
    JSON.stringify(config, null, 2)
  );
  
  console.log(`配置已保存到 deployments/${hre.network.name}.json`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

**部署后输出**：
```
✅ ConditionalTokens 已部署到:
0x1234567890123456789012345678901234567890
```

---

### 第二步：部署依赖库和工厂

#### 2.1 部署 Fixed192x64Math 库

```javascript
// scripts/deploy-math-lib.js
const hre = require("hardhat");

async function main() {
  console.log("部署 Fixed192x64Math...");
  
  // 注意：这是一个库合约，需要特殊处理
  const Fixed192x64Math = await hre.ethers.getContractFactory("Fixed192x64Math");
  const mathLib = await Fixed192x64Math.deploy();
  await mathLib.deployed();
  
  console.log("✅ Fixed192x64Math 已部署到:", mathLib.address);
  
  return mathLib.address;
}

main().then(() => process.exit(0)).catch(console.error);
```

#### 2.2 部署 LMSRMarketMakerFactory

```javascript
// scripts/deploy-lmsr-factory.js
const hre = require("hardhat");

async function main() {
  console.log("部署 LMSRMarketMakerFactory...");
  
  // 读取配置
  const config = require(`./deployments/${hre.network.name}.json`);
  
  // 部署工厂合约
  const LMSRMarketMakerFactory = await hre.ethers.getContractFactory(
    "LMSRMarketMakerFactory"
  );
  
  const factory = await LMSRMarketMakerFactory.deploy();
  await factory.deployed();
  
  console.log("✅ LMSRMarketMakerFactory 已部署到:", factory.address);
  
  // 更新配置
  config.lmsrFactory = factory.address;
  config.deployedAt = new Date().toISOString();
  
  fs.writeFileSync(
    `deployments/${hre.network.name}.json`,
    JSON.stringify(config, null, 2)
  );
  
  return factory.address;
}

main().then(() => process.exit(0)).catch(console.error);
```

---

### 第三步：创建你的第一个市场

```javascript
// scripts/create-lmsr-market.js
const hre = require("hardhat");

async function main() {
  // 读取配置
  const config = require(`./deployments/${hre.network.name}.json`);
  
  // 获取合约实例
  const factory = await hre.ethers.getContractAt(
    "LMSRMarketMakerFactory",
    config.lmsrFactory
  );
  
  const conditionalTokens = await hre.ethers.getContractAt(
    "ConditionalTokens",
    config.conditionalTokens
  );
  
  // ⚙️ 配置参数
  const COLLATERAL_TOKEN = "0x..."; // 你的 ERC20 代币地址
  const WHITELIST = "0x0000000000000000000000000000000000000000"; // 不使用白名单
  const FEE = 0; // 0% 手续费
  const FUNDING = hre.ethers.utils.parseUnits("500000", 6); // 50万 USDC (6位小数)
  
  // Oracle 和 Question ID
  const oracle = "0xYourOracleAddress";
  const questionId = hre.ethers.utils.id("Will Bitcoin reach $100k by 2025?");
  const outcomeSlotCount = 2; // YES/NO
  
  // 1. 先准备条件
  console.log("准备条件...");
  const tx1 = await conditionalTokens.prepareCondition(
    oracle,
    questionId,
    outcomeSlotCount
  );
  await tx1.wait();
  console.log("✅ 条件已准备");
  
  // 2. 计算 conditionId
  const conditionId = hre.ethers.utils.keccak256(
    hre.ethers.utils.defaultAbiCoder.encode(
      ["address", "bytes32", "uint256"],
      [oracle, questionId, outcomeSlotCount]
    )
  );
  
  // 3. 创建市场
  console.log("创建 LMSR 市场...");
  const tx2 = await factory.createLMSRMarketMaker(
    conditionalTokens.address,
    COLLATERAL_TOKEN,
    [conditionId],
    FEE,
    WHITELIST,
    FUNDING,
    { gasLimit: 5000000 }
  );
  
  const receipt = await tx2.wait();
  
  // 从事件中提取市场地址
  const event = receipt.events.find(e => e.event === "LMSRMarketMakerCreation");
  const marketAddress = event.args.lmsrMarketMaker;
  
  console.log("✅ LMSR 市场已创建:");
  console.log("市场地址:", marketAddress);
  console.log("条件ID:", conditionId);
  console.log("初始资金:", FUNDING.toString());
  
  // 保存配置
  config.markets = config.markets || [];
  config.markets.push({
    market: marketAddress,
    conditionId: conditionId,
    createdAt: new Date().toISOString()
  });
  
  fs.writeFileSync(
    `deployments/${hre.network.name}.json`,
    JSON.stringify(config, null, 2)
  );
}

main().then(() => process.exit(0)).catch(console.error);
```

---

## 📊 部署配置示例

### 配置文件：`deployments/polygon.json`

```json
{
  "network": "polygon",
  "conditionalTokens": "0x4D97DCd97eC945f40cF65F87097ACe5EA0476045",
  "lmsrFactory": "0xYourFactoryAddress",
  "mathLib": "0xYourMathLibAddress",
  "markets": [
    {
      "market": "0xMarketAddress1",
      "conditionId": "0x...",
      "collateral": "USDC",
      "createdAt": "2024-01-15T10:30:00.000Z"
    }
  ],
  "deployedAt": "2024-01-15T10:00:00.000Z"
}
```

---

## 💰 funding 参数配置指南

### 50万抵押物的配置
对于 **50万个抵押物**（例如 USDC），建议配置：

```javascript
const FUNDING = ethers.utils.parseUnits("500000", 6); // USDC 有 6 位小数

// 等价于
const FUNDING = "500000000000"; // 500,000 * 10^6
```

### 实际效果
- `funding = 500,000` → LMSR 的 `b ≈ 721,500` (对于 2 结果市场)
- 提供**极高的流动性**，适合大额交易
- 价格波动**极小**

### 不同规模的推荐值

| 抵押物数量 | funding 值 | 适用场景 |
|-----------|-----------|---------|
| 1万 | `10000000000` | 小规模市场 |
| 10万 | `100000000000` | 中等市场 |
| 50万 | `500000000000` | 大额交易市场 ⭐ |
| 100万 | `1000000000000` | 机构级市场 |

---

## 🧪 测试你的部署

### 创建测试脚本：`scripts/test-market.js`

```javascript
const hre = require("hardhat");

async function main() {
  const config = require(`./deployments/${hre.network.name}.json`);
  const market = config.markets[0]; // 第一个市场
  
  // 获取合约实例
  const lmsrMarket = await hre.ethers.getContractAt(
    "LMSRMarketMaker",
    market.market
  );
  
  // 1. 检查当前价格（应该接近 0.5 for YES）
  const priceYES = await lmsrMarket.calcMarginalPrice(0);
  const priceNO = await lmsrMarket.calcMarginalPrice(1);
  
  console.log("当前价格:");
  console.log("YES:", hre.ethers.utils.formatEther(priceYES));
  console.log("NO:", hre.ethers.utils.formatEther(priceNO));
  
  // 2. 计算购买成本（买入 1000 个 YES）
  const buyAmount = [1000, 0]; // [YES, NO]
  const netCost = await lmsrMarket.calcNetCost(buyAmount);
  
  console.log("\n购买 1000 个 YES 的成本:", netCost.toString());
  
  // 3. 检查市场状态
  const funding = await lmsrMarket.funding();
  const fee = await lmsrMarket.fee();
  const stage = await lmsrMarket.stage(); // 0=Running, 1=Paused, 2=Closed
  
  console.log("\n市场状态:");
  console.log("资金池:", funding.toString());
  console.log("手续费:", fee.toString() + "%");
  console.log("状态:", ["Running", "Paused", "Closed"][stage]);
}

main().then(() => process.exit(0)).catch(console.error);
```

---

## ⚠️ 重要注意事项

### 1. ConditionalTokens 是单例
- ✅ 每个链只有一个 ConditionalTokens 实例
- ✅ 所有市场共享这个实例
- ❌ 不要为每个市场部署新的 ConditionalTokens

### 2. 条件准备
- 每个市场需要在 ConditionalTokens 上先调用 `prepareCondition()`
- 同一个条件可以被多个市场使用

### 3. 抵押物选择
- 可以使用任意 ERC20 代币
- 推荐使用稳定币（USDC、DAI）
- 确保代币有足够的流动性

### 4. Gas 成本
- ConditionalTokens 部署：~3M gas
- LMSRMarketMakerFactory 部署：~4M gas  
- 创建新市场：~2-3M gas

---

## 📚 参考资料

### 官方文档
- [ConditionalTokens 文档](https://docs.gnosis.io/conditionaltokens/)
- [LMSR 算法说明](https://en.wikipedia.org/wiki/Logarithmic_market_scoring_rule)

### 已部署的合约地址
- **Polygon**: ConditionalTokens `0x4D97DCd97eC945f40cF65F87097ACe5EA0476045`
- **Mainnet**: ConditionalTokens `0xC59b0e4De5F1248C1140964E0fF287B192407E0C`
- **xDai**: ConditionalTokens `0xCeAfDD6bc0bEF976fdCd1112955828E00543c0Ce`

---

## 🎉 总结

**部署 Checklist**:
- [ ] 检查目标链上是否已有 ConditionalTokens
- [ ] 如果没有，部署 ConditionalTokens（一次性）
- [ ] 部署 Fixed192x64Math 库
- [ ] 部署 LMSRMarketMakerFactory
- [ ] 准备条件（prepareCondition）
- [ ] 创建第一个市场（50万 funding）
- [ ] 测试市场功能

**关键数字**：
- ConditionalTokens：**1个/链**
- 工厂合约：**1个**  
- 市场数量：**无限制**
- 推荐 funding：**500,000** (50万)

---

有问题请参考代码注释或查阅官方文档！ 🚀

