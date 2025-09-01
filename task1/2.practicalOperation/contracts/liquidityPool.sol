// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract LiquidityPool {
    address public owner;
    address public memeToken;
    
    // 池子储备
    uint256 public ethReserve;
    uint256 public tokenReserve;
    
    // 流动性提供者份额
    mapping(address => uint256) public liquidityShares;
    uint256 public totalShares;


    event AddLiquidity(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 shares);
    event RemoveLiquidity(address indexed provider, uint256 ethAmount, uint256 tokenAmount, uint256 shares);
    event Swap(address indexed user, uint256 ethIn, uint256 tokenOut, uint256 tokenIn, uint256 ethOut);
    
    constructor(address _memeToken) {
        owner = msg.sender;
        memeToken = _memeToken;
    }
    
    // 添加流动性
    function addLiquidity(uint256 tokenAmount) external payable {
        require(msg.value > 0 && tokenAmount > 0, "Invalid amounts");
        
        uint256 ethAmount = msg.value;
        uint256 shares;
        
        if (totalShares == 0) {
            // 首次添加流动性
            shares = ethAmount;
        } else {
            // 按比例添加流动性
            uint256 ethShare = (ethAmount * totalShares) / ethReserve;
            uint256 tokenShare = (tokenAmount * totalShares) / tokenReserve;
            shares = ethShare < tokenShare ? ethShare : tokenShare;
        }
        
        // 转移代币到合约
        IERC20(memeToken).transferFrom(msg.sender, address(this), tokenAmount);
        
        // 更新储备和份额
        ethReserve += ethAmount;
        tokenReserve += tokenAmount;
        liquidityShares[msg.sender] += shares;
        totalShares += shares;
        
        emit AddLiquidity(msg.sender, ethAmount, tokenAmount, shares);
    }
    
    // 移除流动性
    function removeLiquidity(uint256 shares) external {
        require(shares > 0 && liquidityShares[msg.sender] >= shares, "Invalid shares");
        
        uint256 ethAmount = (shares * ethReserve) / totalShares;
        uint256 tokenAmount = (shares * tokenReserve) / totalShares;
        
        // 更新储备和份额
        ethReserve -= ethAmount;
        tokenReserve -= tokenAmount;
        liquidityShares[msg.sender] -= shares;
        totalShares -= shares;
        
        // 转移资产给用户
        payable(msg.sender).transfer(ethAmount);
        IERC20(memeToken).transfer(msg.sender, tokenAmount);
        
        emit RemoveLiquidity(msg.sender, ethAmount, tokenAmount, shares);
    }
    
    // ETH 换 Token
    function swapETHForToken() external payable {
        require(msg.value > 0, "Invalid ETH amount");
        require(ethReserve > 0 && tokenReserve > 0, "No liquidity");
        
        uint256 ethIn = msg.value;
        // 简单的 x*y=k 公式，收取 0.3% 手续费
        uint256 ethInWithFee = ethIn * 997;
        uint256 tokenOut = (ethInWithFee * tokenReserve) / (ethReserve * 1000 + ethInWithFee);
        
        require(tokenOut > 0 && tokenOut < tokenReserve, "Invalid swap");
        
        // 更新储备
        ethReserve += ethIn;
        tokenReserve -= tokenOut;
        
        // 转移代币给用户
        IERC20(memeToken).transfer(msg.sender, tokenOut);
        
        emit Swap(msg.sender, ethIn, tokenOut, 0, 0);
    }
    
    // Token 换 ETH
    function swapTokenForETH(uint256 tokenIn) external {
        require(tokenIn > 0, "Invalid token amount");
        require(ethReserve > 0 && tokenReserve > 0, "No liquidity");
        
        // 简单的 x*y=k 公式，收取 0.3% 手续费
        uint256 tokenInWithFee = tokenIn * 997;
        uint256 ethOut = (tokenInWithFee * ethReserve) / (tokenReserve * 1000 + tokenInWithFee);
        
        require(ethOut > 0 && ethOut < ethReserve, "Invalid swap");
        
        // 转移代币到合约
        IERC20(memeToken).transferFrom(msg.sender, address(this), tokenIn);
        
        // 更新储备
        tokenReserve += tokenIn;
        ethReserve -= ethOut;
        
        // 转移 ETH 给用户
        payable(msg.sender).transfer(ethOut);
        
        emit Swap(msg.sender, 0, 0, tokenIn, ethOut);
    }
    
    // 获取交换价格预览
    function getSwapPrice(uint256 amountIn, bool ethToToken) external view returns (uint256) {
        if (ethReserve == 0 || tokenReserve == 0) return 0;
        
        uint256 amountInWithFee = amountIn * 997;
        
        if (ethToToken) {
            return (amountInWithFee * tokenReserve) / (ethReserve * 1000 + amountInWithFee);
        } else {
            return (amountInWithFee * ethReserve) / (tokenReserve * 1000 + amountInWithFee);
        }
    }
    
    // 获取池子状态
    function getPoolInfo() external view returns (uint256, uint256, uint256) {
        return (ethReserve, tokenReserve, totalShares);
    }
}