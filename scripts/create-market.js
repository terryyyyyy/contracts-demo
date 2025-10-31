const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

/**
 * 创建 LMSR 预测市场
 * 
 * 使用示例:
 * npx hardhat run scripts/create-market.js --network polygon
 */
async function main() {
  console.log("=".repeat(60));
  console.log("🎯 创建 LMSR 预测市场");
  console.log("=".repeat(60));

  // 加载配置
  const configPath = path.join(__dirname, "../deployments", `${hre.network.name}.json`);
  if (!fs.existsSync(configPath)) {
    throw new Error(`❌ 配置文件不存在: ${configPath}\n请先运行: npx hardhat run scripts/deploy-conditionaltokens.js --network ${hre.network.name}`);
  }

  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  console.log("✅ 加载配置:", configPath);

  // 获取部署者地址
  const [deployer] = await hre.ethers.getSigners();
  console.log("\n👤 部署者:", deployer.address);
  
  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log("💰 余额:", hre.ethers.utils.formatEther(balance), "ETH");

  // ===== 配置参数 =====
  console.log("\n⚙️  配置参数:");
  
  // 🔴 请修改这些参数！
  const MARKET_CONFIG = {
    // 抵押物代币地址
    collateralToken: process.env.COLLATERAL_TOKEN || "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // Polygon USDC
    
    // Oracle 地址（可以是你的地址）
    oracle: process.env.ORACLE_ADDRESS || deployer.address,
    
    // 问题描述
    question: process.env.MARKET_QUESTION || "Will Bitcoin reach $100k by 2025?",
    
    // 结果数量（2 = YES/NO）
    outcomeSlotCount: parseInt(process.env.OUTCOMES || "2"),
    
    // 手续费 (18 位精度，1000000000000000000 = 100%)
    fee: process.env.FEE ? parseInt(process.env.FEE) : 0,
    
    // 白名单地址（0x0 表示不使用白名单）
    whitelist: process.env.WHITELIST || "0x0000000000000000000000000000000000000000",
    
    // 初始资金（根据代币精度调整）
    // 50万 USDC (6位小数) = 500000 * 10^6 = 500000000000
    fundingAmount: process.env.FUNDING || "500000000000",
  };

  console.log(JSON.stringify(MARKET_CONFIG, null, 2));

  // 获取合约实例
  const factory = await hre.ethers.getContractAt(
    "LMSRMarketMakerFactory",
    config.lmsrFactory,
    deployer
  );

  const conditionalTokens = await hre.ethers.getContractAt(
    "ConditionalTokens",
    config.conditionalTokens,
    deployer
  );

  const collateralToken = await hre.ethers.getContractAt(
    "ERC20",
    MARKET_CONFIG.collateralToken,
    deployer
  );

  // 检查代币余额
  const decimals = await collateralToken.decimals();
  const balance_token = await collateralToken.balanceOf(deployer.address);
  const funding = MARKET_CONFIG.fundingAmount;
  
  console.log(`\n💵 代币余额: ${hre.ethers.utils.formatUnits(balance_token, decimals)}`);
  console.log(`🎁 需要资金: ${hre.ethers.utils.formatUnits(funding, decimals)}`);
  
  if (BigInt(balance_token) < BigInt(funding)) {
    throw new Error("❌ 代币余额不足！");
  }

  // 1. 检查并批准代币
  console.log("\n📋 步骤 1: 批准代币转账...");
  const allowance = await collateralToken.allowance(deployer.address, factory.address);
  if (BigInt(allowance) < BigInt(funding)) {
    const approveTx = await collateralToken.approve(factory.address, funding);
    console.log("⏳ 等待批准确认...");
    await approveTx.wait();
    console.log("✅ 代币已批准");
  } else {
    console.log("✅ 已有足够的批准额度");
  }

  // 2. 准备条件
  console.log("\n📋 步骤 2: 准备条件...");
  const questionId = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes(MARKET_CONFIG.question));
  
  // 检查条件是否已存在
  try {
    const outcomeSlotCount_existing = await conditionalTokens.getOutcomeSlotCount(
      hre.ethers.utils.keccak256(
        hre.ethers.utils.defaultAbiCoder.encode(
          ["address", "bytes32", "uint256"],
          [MARKET_CONFIG.oracle, questionId, MARKET_CONFIG.outcomeSlotCount]
        )
      )
    );
    
    if (outcomeSlotCount_existing > 0) {
      console.log("⚠️  条件已存在，跳过准备步骤");
    }
  } catch (e) {
    // 条件不存在，准备新条件
    const prepareTx = await conditionalTokens.prepareCondition(
      MARKET_CONFIG.oracle,
      questionId,
      MARKET_CONFIG.outcomeSlotCount
    );
    console.log("⏳ 等待条件准备...");
    await prepareTx.wait();
    console.log("✅ 条件已准备");
  }

  // 3. 计算 conditionId
  const conditionId = hre.ethers.utils.keccak256(
    hre.ethers.utils.defaultAbiCoder.encode(
      ["address", "bytes32", "uint256"],
      [MARKET_CONFIG.oracle, questionId, MARKET_CONFIG.outcomeSlotCount]
    )
  );
  console.log("\n📋 条件ID:", conditionId);

  // 4. 创建市场
  console.log("\n📋 步骤 3: 创建 LMSR 市场...");
  console.log("⏳ 提交交易... (这可能需要几分钟)");
  
  const createTx = await factory.createLMSRMarketMaker(
    conditionalTokens.address,
    MARKET_CONFIG.collateralToken,
    [conditionId],
    MARKET_CONFIG.fee,
    MARKET_CONFIG.whitelist,
    funding,
    {
      gasLimit: 5000000, // 增加 gas limit
    }
  );
  
  console.log("⏳ 等待交易确认...");
  const receipt = await createTx.wait();
  console.log("✅ 交易确认，区块:", receipt.blockNumber);

  // 5. 提取市场地址
  const event = receipt.events.find(e => e.event === "LMSRMarketMakerCreation");
  if (!event) {
    throw new Error("❌ 无法找到 LMSRMarketMakerCreation 事件");
  }
  
  const marketAddress = event.args.lmsrMarketMaker;
  
  console.log("\n" + "=".repeat(60));
  console.log("🎉 市场创建成功！");
  console.log("=".repeat(60));
  console.log("📍 市场地址:", marketAddress);
  console.log("🔗 查看:", `https://${getExplorer(hre.network.name)}/address/${marketAddress}`);
  console.log("📊 条件ID:", conditionId);
  console.log("💰 初始资金:", hre.ethers.utils.formatUnits(funding, decimals));
  console.log("=".repeat(60));

  // 6. 保存配置
  config.markets = config.markets || [];
  config.markets.push({
    market: marketAddress,
    conditionId: conditionId,
    collateral: MARKET_CONFIG.collateralToken,
    funding: funding,
    question: MARKET_CONFIG.question,
    outcomeSlotCount: MARKET_CONFIG.outcomeSlotCount,
    createdAt: new Date().toISOString(),
  });

  fs.writeFileSync(
    configPath,
    JSON.stringify(config, null, 2)
  );

  console.log("\n💾 配置已保存");

  // 7. 验证市场
  console.log("\n📋 步骤 4: 验证市场...");
  const market = await hre.ethers.getContractAt("LMSRMarketMaker", marketAddress, deployer);
  
  const marketFunding = await market.funding();
  const marketFee = await market.fee();
  const marketStage = await market.stage(); // 0=Running, 1=Paused, 2=Closed
  
  console.log("💰 市场资金:", hre.ethers.utils.formatUnits(marketFunding, decimals));
  console.log("💸 手续费:", marketFee.toString(), "%");
  console.log("⚡ 状态:", ["Running", "Paused", "Closed"][marketStage]);

  // 检查初始价格（应该是 50/50）
  if (MARKET_CONFIG.outcomeSlotCount === 2) {
    const priceYES = await market.calcMarginalPrice(0);
    const priceNO = await market.calcMarginalPrice(1);
    console.log("💹 YES 价格:", hre.ethers.utils.formatEther(priceYES));
    console.log("💹 NO 价格:", hre.ethers.utils.formatEther(priceNO));
  }

  console.log("\n" + "=".repeat(60));
  console.log("✨ 完成！市场已可以交易");
  console.log("=".repeat(60));
}

function getExplorer(networkName) {
  const explorers = {
    mainnet: "etherscan.io",
    polygon: "polygonscan.com",
    sepolia: "sepolia.etherscan.io",
    goerli: "goerli.etherscan.io",
    mumbai: "mumbai.polygonscan.com",
  };
  return explorers[networkName] || "etherscan.io";
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ 创建市场失败:");
    console.error(error);
    process.exit(1);
  });

