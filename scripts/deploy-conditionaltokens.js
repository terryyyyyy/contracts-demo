const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

/**
 * 部署 ConditionalTokens 合约
 * 这是一个全局基础设施合约，每个链只需要部署一次
 */
async function main() {
  console.log("=".repeat(60));
  console.log("🚀 开始部署 ConditionalTokens...");
  console.log(`📍 网络: ${hre.network.name}`);
  console.log("=".repeat(60));

  // 确保 deployments 目录存在
  const deploymentsDir = path.join(__dirname, "../deployments");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
    console.log("✅ 创建 deployments 目录");
  }

  // 检查是否已经部署过
  const configPath = path.join(deploymentsDir, `${hre.network.name}.json`);
  if (fs.existsSync(configPath)) {
    const existingConfig = JSON.parse(fs.readFileSync(configPath, "utf8"));
    if (existingConfig.conditionalTokens) {
      console.log("\n⚠️  警告: ConditionalTokens 已在此网络部署");
      console.log(`现有地址: ${existingConfig.conditionalTokens}`);
      console.log("\n继续部署会覆盖现有配置。");
      
      // 在生产环境跳过部署
      if (hre.network.name === "mainnet" || hre.network.name === "polygon") {
        console.log("❌ 为防止误操作，请手动删除配置文件后再部署");
        process.exit(1);
      }
    }
  }

  console.log("\n📝 读取 ConditionalTokens 合约...");
  
  // 注意：ConditionalTokens 使用 Solidity 0.5.1
  // 你需要确保 hardhat 配置支持这个版本
  const ConditionalTokens = await hre.ethers.getContractFactory("ConditionalTokens");
  
  console.log("⏳ 部署合约中...");
  const conditionalTokens = await ConditionalTokens.deploy();
  await conditionalTokens.deployed();
  
  console.log("\n✅ ConditionalTokens 部署成功!");
  console.log("📦 合约地址:", conditionalTokens.address);
  console.log("🔗 查看合约:", `https://${getExplorer(hre.network.name)}/address/${conditionalTokens.address}`);

  // 验证部署
  console.log("\n🔍 验证部署...");
  const code = await hre.ethers.provider.getCode(conditionalTokens.address);
  if (code === "0x") {
    throw new Error("❌ 合约代码为空，部署失败");
  }
  console.log("✅ 合约代码验证成功");

  // 保存配置
  const config = {
    network: hre.network.name,
    chainId: (await hre.ethers.provider.getNetwork()).chainId,
    conditionalTokens: conditionalTokens.address,
    deployedBy: await hre.ethers.provider.getSigner().getAddress(),
    deployedAt: new Date().toISOString(),
    markets: []
  };
  
  fs.writeFileSync(
    configPath,
    JSON.stringify(config, null, 2)
  );
  
  console.log(`\n💾 配置已保存到: ${configPath}`);

  console.log("\n" + "=".repeat(60));
  console.log("🎉 部署完成！");
  console.log("=".repeat(60));
  console.log("\n📋 下一步：");
  console.log("1. 部署 Fixed192x64Math 库");
  console.log("2. 部署 LMSRMarketMakerFactory");
  console.log("3. 创建你的第一个市场");
  console.log("\n运行: npx hardhat run scripts/deploy-math-lib.js --network " + hre.network.name);
  console.log("=".repeat(60));
}

function getExplorer(networkName) {
  const explorers = {
    mainnet: "etherscan.io",
    polygon: "polygonscan.com",
    sepolia: "sepolia.etherscan.io",
    goerli: "goerli.etherscan.io",
    mumbai: "mumbai.polygonscan.com",
    avalanche: "snowtrace.io",
  };
  return explorers[networkName] || "etherscan.io";
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ 部署失败:");
    console.error(error);
    process.exit(1);
  });

