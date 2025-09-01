const { expect } = require("chai"); // 引入 Chai 断言库的 expect 风格
const { ethers } = require("hardhat"); // 引入 Hardhat 的 ethers 插件，用于和以太坊交互

describe("Meme", function () {
  let user1 = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
  let user2 = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";
  let meme;
  let owner, addr1, addr2;

  beforeEach(async () => {
    [owner, addr1, addr2] = await ethers.getSigners();
    const Meme = await ethers.getContractFactory("Meme");
    meme = await Meme.deploy("aoligei", "alg", 18, 100000000);
    await meme.waitForDeployment();
  });

  it("should get the balance of the contract", async () => {
    expect(await meme.getBalanceOf(owner.address)).to.equal(100000000);
  });

  it("should transfer tokens correctly", async () => {
    await meme.transfer(addr1.address, 1000);
    expect(await meme.getBalanceOf(addr1.address)).to.equal(950); // 扣除5%税费
  });

  it("should approve and transferFrom tokens", async () => {
    await meme.approve(addr1.address, 2000);
    expect(await meme.allowance(owner.address, addr1.address)).to.equal(2000);
    
    await meme.connect(addr1).transferFrom(owner.address, addr2.address, 1000);
    expect(await meme.getBalanceOf(addr2.address)).to.equal(950); // 扣除5%税费
  });

  it("should allow owner to mint tokens", async () => {
    const initialSupply = await meme.getTotalSupply();
    await meme.mint(addr1.address, 5000);
    expect(await meme.getBalanceOf(addr1.address)).to.equal(5000);
    expect(await meme.getTotalSupply()).to.equal(initialSupply + BigInt(5000));
  });

  it("should allow owner to burn tokens", async () => {
    const initialSupply = await meme.getTotalSupply();
    await meme.burn(1000);
    expect(await meme.getTotalSupply()).to.equal(initialSupply - BigInt(1000));
  });

  it("should manage excluded from fees addresses", async () => {
    await meme.addExcludedFromFees(addr1.address);
    expect(await meme.getIsExcludedFromFees(addr1.address)).to.equal(true);
    
    await meme.removeExcludedFromFees(addr1.address);
    expect(await meme.getIsExcludedFromFees(addr1.address)).to.equal(false);
  });
});// 引入所需的库和工具

describe("LiquidityPool", function () {
  let liquidityPool;
  let meme;
  let owner, addr1, addr2;

  beforeEach(async () => {
    [owner, addr1, addr2] = await ethers.getSigners();
    
    // 首先部署 Meme 代币合约
    const Meme = await ethers.getContractFactory("Meme");
    meme = await Meme.deploy("aoligei", "alg", 18, 100000000);
    await meme.waitForDeployment();
    
    // 然后部署 LiquidityPool 合约
    const LiquidityPool = await ethers.getContractFactory("LiquidityPool");
    liquidityPool = await LiquidityPool.deploy(await meme.getAddress());
    await liquidityPool.waitForDeployment();
  });

  it("should deploy with correct meme token address", async () => {
    expect(await liquidityPool.memeToken()).to.equal(await meme.getAddress());
    expect(await liquidityPool.owner()).to.equal(owner.address);
  });

  it("should add liquidity correctly", async () => {
    // 给 LiquidityPool 授权代币
    await meme.approve(await liquidityPool.getAddress(), 10000);
    
    // 添加流动性
    await liquidityPool.addLiquidity(5000, { value: ethers.parseEther("1") });
    
    const [ethReserve, tokenReserve, totalShares] = await liquidityPool.getPoolInfo();
    expect(ethReserve).to.equal(ethers.parseEther("1"));
    expect(tokenReserve).to.equal(5000);
    expect(totalShares).to.equal(ethers.parseEther("1"));
  });

  it("should remove liquidity correctly", async () => {
    // 先添加流动性
    await meme.approve(await liquidityPool.getAddress(), 10000);
    await liquidityPool.addLiquidity(5000, { value: ethers.parseEther("1") });
    
    const initialEthBalance = await ethers.provider.getBalance(owner.address);
    const initialTokenBalance = await meme.getBalanceOf(owner.address);
    
    // 移除部分流动性
    const sharesToRemove = ethers.parseEther("0.5");
    await liquidityPool.removeLiquidity(sharesToRemove);
    
    const [ethReserve, tokenReserve] = await liquidityPool.getPoolInfo();
    expect(ethReserve).to.equal(ethers.parseEther("0.5"));
    expect(tokenReserve).to.equal(2500);
  });

  it("should swap ETH for tokens correctly", async () => {
    // 先添加流动性
    await meme.approve(await liquidityPool.getAddress(), 10000);
    await liquidityPool.addLiquidity(10000, { value: ethers.parseEther("2") });
    
    const initialTokenBalance = await meme.getBalanceOf(addr1.address);
    
    // 用户1进行ETH换Token交易
    await liquidityPool.connect(addr1).swapETHForToken({ value: ethers.parseEther("0.1") });
    
    const finalTokenBalance = await meme.getBalanceOf(addr1.address);
    expect(finalTokenBalance).to.be.gt(initialTokenBalance);
  });

  it("should swap tokens for ETH correctly", async () => {
    // 先添加流动性
    await meme.approve(await liquidityPool.getAddress(), 10000);
    await liquidityPool.addLiquidity(10000, { value: ethers.parseEther("2") });
    
    // 给addr1一些代币
    await meme.transfer(addr1.address, 1000);
    
    // addr1授权并进行Token换ETH交易
    await meme.connect(addr1).approve(await liquidityPool.getAddress(), 500);
    
    const initialEthBalance = await ethers.provider.getBalance(addr1.address);
    await liquidityPool.connect(addr1).swapTokenForETH(500);
    const finalEthBalance = await ethers.provider.getBalance(addr1.address);
    
    expect(finalEthBalance).to.be.gt(initialEthBalance - ethers.parseEther("0.01")); // 减去gas费用的估计
  });

  it("should get swap price preview correctly", async () => {
    // 先添加流动性
    await meme.approve(await liquidityPool.getAddress(), 10000);
    await liquidityPool.addLiquidity(10000, { value: ethers.parseEther("1") });
    
    // 获取交换价格预览
    const ethToTokenPrice = await liquidityPool.getSwapPrice(ethers.parseEther("0.1"), true);
    const tokenToEthPrice = await liquidityPool.getSwapPrice(1000, false);
    
    expect(ethToTokenPrice).to.be.gt(0);
    expect(tokenToEthPrice).to.be.gt(0);
  });
});