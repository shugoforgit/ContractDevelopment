require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545"
    }
    // sepolia: {
    //   url: `https://sepolia.infura.io/v3/${process.env.INFURA_API_KEY}`,
    //   accounts: [process.env.PK]
    // }
  }
};

task("deploy", "Deploy the contracts", async () =>  {
  const signers = await ethers.getSigners();
  const deployer = signers[1];
  console.log("Deploying contracts with the account:", deployer.address);

  // 部署 MetaNodeStake 合约
  const MetaNodeStake = await ethers.getContractFactory("MetaNodeStake");
  
  // 部署参数
  const metaNodeAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // 替换为实际的 MetaNode 代币地址
  const startBlock = await ethers.provider.getBlockNumber() + 100; // 100个区块后开始
  const endBlock = startBlock + 1000000; // 1000000个区块后结束
  const metaNodePerBlock = ethers.parseEther("1"); // 每个区块奖励1个MetaNode

  console.log("Deploying MetaNodeStake proxy...");
  const metaNodeStake = await upgrades.deployProxy(MetaNodeStake, [
    metaNodeAddress,
    startBlock,
    endBlock,
    metaNodePerBlock
  ], { initializer: 'initialize' });

  await metaNodeStake.waitForDeployment();
  console.log("MetaNodeStake deployed to:", await metaNodeStake.getAddress());
});