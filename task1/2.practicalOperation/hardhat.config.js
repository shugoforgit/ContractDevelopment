require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.28",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545"
    },
    sepolia: {
      url: `https://sepolia.infura.io/v3/${process.env.INFURA_API_KEY}`,
      accounts: [process.env.PK]
    }
  }
};

task("deploy", "Deploy the contracts", async () =>  {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying contracts with the account:", deployer.address);

  const Meme = await ethers.getContractFactory("Meme");
  const meme = await Meme.deploy("aoligei", "alg", 18, 1000000000);
  await meme.waitForDeployment();
  console.log("Meme deployed to:", await meme.getAddress());
});