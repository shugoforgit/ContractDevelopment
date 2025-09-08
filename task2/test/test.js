const { ethers, upgrades } = require("hardhat");
const { expect } = require("chai");

describe("MetaNodeStake Contract Tests", function () {
    let metaNodeStake;
    let metaNode;
    let owner, user1, user2;

    beforeEach(async function () {
        // 获取签名者
        const signers = await ethers.getSigners();
        owner = signers[0]; // 使用第一个账户作为owner（部署者）
        user1 = signers[1]; // 第2个账户作为用户
        user2 = signers[2]; // 第3个账户作为用户
        
        // 部署 MetaNode 代币合约
        const MetaNodeToken = await ethers.getContractFactory("MetaNodeToken");
        metaNode = await MetaNodeToken.deploy(ethers.parseEther("1000000"));
        await metaNode.waitForDeployment();
        
        // 部署 MetaNodeStake 合约
        const MetaNodeStake = await ethers.getContractFactory("MetaNodeStake");
        const startBlock = await ethers.provider.getBlockNumber() + 10;
        const endBlock = startBlock + 1000000;
        const metaNodePerBlock = ethers.parseEther("1");
        
        metaNodeStake = await upgrades.deployProxy(MetaNodeStake, [
            await metaNode.getAddress(),
            startBlock,
            endBlock,
            metaNodePerBlock
        ], { initializer: 'initialize' });
        
        await metaNodeStake.waitForDeployment();
        
        // 给合约转移一些代币用于奖励
        await metaNode.transfer(await metaNodeStake.getAddress(), ethers.parseEther("100000"));
        
        // 添加ETH池（池子ID为0）
        await metaNodeStake.addPool(
            "0x0000000000000000000000000000000000000000", // ETH池地址为0
            ethers.parseEther("100"), // 权重
            ethers.parseEther("0.01"), // 最小质押金额 0.01 ETH
            100 // 解质押锁定100个区块
        );
        
        console.log("MetaNodeStake deployed to:", await metaNodeStake.getAddress());
        console.log("MetaNode deployed to:", await metaNode.getAddress());
        console.log("Owner address:", owner.address);
    });

    describe("合约基本连接验证", function () {
        it("应该验证合约地址存在代码", async function () {
            const contractAddress = await metaNodeStake.getAddress();
            const code = await ethers.provider.getCode(contractAddress);
            console.log("Contract code exists:", code !== "0x");
            console.log("Code length:", code.length);
            expect(code).to.not.equal("0x");
        });

        it("应该能够获取合约基本参数", async function () {
            try {
                const poolLength = await metaNodeStake.poolLength();
                const startBlock = await metaNodeStake.startBlock();
                const endBlock = await metaNodeStake.endBlock();
                const metaNodePerBlock = await metaNodeStake.metaNodePerBlock();
                
                console.log("Pool length:", poolLength.toString());
                console.log("Start block:", startBlock.toString());
                console.log("End block:", endBlock.toString());
                console.log("MetaNode per block:", ethers.formatEther(metaNodePerBlock));
                
                expect(poolLength).to.be.a('bigint');
                expect(startBlock).to.be.a('bigint');
                expect(endBlock).to.be.a('bigint');
                expect(metaNodePerBlock).to.be.a('bigint');
            } catch (error) {
                console.log("Error calling contract functions:", error.message);
                
                // 尝试直接调用验证合约是否响应
                try {
                    const contractAddress = await metaNodeStake.getAddress();
                    const result = await ethers.provider.call({
                        to: contractAddress,
                        data: "0x081e3eda" // poolLength() 函数选择器
                    });
                    console.log("Direct call result:", result);
                } catch (directError) {
                    console.log("Direct call also failed:", directError.message);
                }
                
                throw error;
            }
        });
    });

    describe("池子管理", function () {
        it("应该能够添加新的质押池", async function () {
            try {
                const initialPoolLength = await metaNodeStake.poolLength();
                console.log("Initial pool length:", initialPoolLength.toString());
                
                // 添加一个测试代币池（ETH池已在beforeEach中添加）
                const testTokenAddress = "0x1234567890123456789012345678901234567890";
                const poolWeight = ethers.parseEther("100");
                const minDepositAmount = ethers.parseEther("1");
                const unstakeLockedBlocks = 100;
                
                await metaNodeStake.connect(owner).addPool(
                    testTokenAddress,
                    poolWeight,
                    minDepositAmount,
                    unstakeLockedBlocks
                );
                
                const newPoolLength = await metaNodeStake.poolLength();
                expect(newPoolLength).to.equal(initialPoolLength + 1n);
                
                console.log("Successfully added new pool, new length:", newPoolLength.toString());
            } catch (error) {
                console.log("Error in pool management test:", error.message);
                throw error;
            }
        });
    });

    describe("ETH 质押功能", function () {
        it("应该能够质押 ETH", async function () {
            try {
                const depositAmount = ethers.parseEther("0.1");
                
                // 检查池子0（ETH池）
                const pool = await metaNodeStake.pools(0);
                console.log("Pool 0 address:", pool.poolAddress);
                console.log("Min deposit amount:", ethers.formatEther(pool.minDepositAmount));
                
                // 检查用户余额
                const userBalance = await ethers.provider.getBalance(user1.address);
                console.log("User1 balance:", ethers.formatEther(userBalance));
                
                // 质押 ETH
                const tx = await metaNodeStake.connect(user1).depositETH({ 
                    value: depositAmount 
                });
                await tx.wait();
                
                // 检查用户质押余额
                const balance = await metaNodeStake.stakingBalance(0, user1.address);
                expect(balance).to.equal(depositAmount);
                
                console.log("Successfully deposited ETH:", ethers.formatEther(balance));
            } catch (error) {
                console.log("Error in ETH staking test:", error.message);
                throw error;
            }
        });
    });

    describe("奖励计算", function () {
        it("应该能够计算待领取的奖励", async function () {
            try {
                // 检查用户的待领取奖励（池子0）
                const pendingReward = await metaNodeStake.pendingMetaNode(0, user1.address);
                console.log("Pending reward for user1:", ethers.formatEther(pendingReward));
                
                expect(pendingReward).to.be.a('bigint');
            } catch (error) {
                console.log("Error in reward calculation test:", error.message);
                throw error;
            }
        });
    });

    describe("权限控制", function () {
        it("应该验证管理员权限", async function () {
            try {
                const ADMIN_ROLE = await metaNodeStake.ADMIN_ROLE();
                const hasAdminRole = await metaNodeStake.hasRole(ADMIN_ROLE, owner.address);
                
                expect(hasAdminRole).to.be.true;
                console.log("Owner has admin role:", hasAdminRole);
                console.log("Admin role hash:", ADMIN_ROLE);
            } catch (error) {
                console.log("Error in admin role test:", error.message);
                throw error;
            }
        });

        it("非管理员不应该能够添加池子", async function () {
            try {
                await expect(
                    metaNodeStake.connect(user1).addPool(
                        "0x1234567890123456789012345678901234567890",
                        ethers.parseEther("100"),
                        ethers.parseEther("1"),
                        100
                    )
                ).to.be.reverted;
                
                console.log("Non-admin correctly prevented from adding pool");
            } catch (error) {
                console.log("Error in non-admin test:", error.message);
                throw error;
            }
        });
    });
});