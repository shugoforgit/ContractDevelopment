// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

contract Meme {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    address public owner;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // 税费部分：从每次转账中收取税费
    uint256 public constant TOTAL_TAX_RATE = 500; // 5%总税费

    // 免税地址
    mapping (address => bool) private _isExcludedFromFees;

    // 单笔交易最大额度  每日交易限制次数
    uint256 public maxTradeAmount;
    uint256 public maxTradeCount;

    struct UserTransactionRecord {
        uint256 amount;
        uint256 count;
        uint256 lastTradeTime;
    }
    mapping(address => UserTransactionRecord) public userRecords;

    // 豁免地址列表（不受限制）
    mapping(address => bool) public isExempted;


    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    

    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _totalSupply) {
        name = _name; // 代币名称
        symbol = _symbol; // 代币符号
        decimals = _decimals; // 代币小数位
        totalSupply = _totalSupply; // 代币总量
        owner = msg.sender; // 代币所有者
        balanceOf[msg.sender] = totalSupply; // 代币所有者持有代币数量

        maxTradeAmount = 100000000;
        maxTradeCount = 100;
    }

    function transfer(address to, uint256 value) public returns (bool success) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        require(to != address(0), "Invalid address");
        require(value > 0, "Invalid value");
        _validateTransactionLimits(msg.sender, value);
        _checkAndUpdateRecords(msg.sender, value);

        // 税费处理
        uint256 taxFee = value * TOTAL_TAX_RATE / 10000;
        uint256 transferAmount = value - taxFee;

        // 转账处理
        balanceOf[msg.sender] -= transferAmount;
        balanceOf[to] += transferAmount;
        emit Transfer(msg.sender, to, transferAmount);
        return true;
    }
    
    function approve(address spender, uint256 value) public returns (bool success) {
        require(spender != address(0), "Invalid address");
        require(value > 0, "Invalid value");
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    
    function transferFrom(address from, address to, uint256 value) public returns (bool success) {
        require(value <= balanceOf[from] && value <= allowance[from][msg.sender], "Insufficient balance");
        require(to != address(0), "Invalid address");
        require(value > 0, "Invalid value");
        _validateTransactionLimits(from, value);
        _checkAndUpdateRecords(from, value);

        uint256 taxFee;
        // 免税
        if (!(_isExcludedFromFees[from] || _isExcludedFromFees[to])) {
            taxFee = value * TOTAL_TAX_RATE / 10000;
        } else {
            taxFee = 0;
        }

        // 如果有税，将税费存入合约地址
        if (taxFee > 0) {
            balanceOf[address(this)] += taxFee;
        }

        // 税费处理
        uint256 transferAmount = value - taxFee;

        // 转账处理
        balanceOf[from] -= value;
        balanceOf[to] += transferAmount;
        allowance[from][msg.sender] -= value;
        emit Transfer(from, to, value);
        return true;
    }

    // 添加免税地址
    function addExcludedFromFees(address account) public returns (bool success) {
        require(msg.sender == owner, "Only owner can add excluded from fees");
        _isExcludedFromFees[account] = true;
        return true;
    }
    
    // 移除免税地址
    function removeExcludedFromFees(address account) public returns (bool success) {
        require(msg.sender == owner, "Only owner can remove excluded from fees");
        _isExcludedFromFees[account] = false;
        return true;
    }

    // 获取当前日期（UTC时间）
    function getCurrentDate() public view returns (uint256) {
        return block.timestamp / 1 days;
    }

    // 交易限制
    function _checkAndUpdateRecords(address user, uint256 amount) internal {
        uint256 currentDate = getCurrentDate();
        UserTransactionRecord storage record = userRecords[user];

        // 如果是新的一天，重置计数器和总量
        if (record.lastTradeTime != currentDate) {
            record.count = 0;
            record.amount = 0;
            record.lastTradeTime = currentDate;
        }

        // 更新记录
        record.count += 1;
        record.amount += amount;
    }

    // 验证交易限制
    // 管理员功能：设置/取消豁免地址
    function setExemption(address user, bool exempt) external {
        require(msg.sender == owner, "Only owner can set exemption");
        _isExcludedFromFees[user] = exempt;
    }
    
    function _validateTransactionLimits(address sender, uint256 amount) internal view {
        // 如果发送者是豁免地址，跳过检查
        if (isExempted[sender]) {
            return;
        }

        UserTransactionRecord memory record = userRecords[sender];
        uint256 currentDate = getCurrentDate();

        // 检查记录日期是否为今天，如果不是，计数器和总量应该为0
        uint256 currentCount = (record.lastTradeTime == currentDate) 
            ? record.count : 0;
        uint256 currentVolume = (record.lastTradeTime == currentDate)
            ? record.amount : 0;

        require(currentCount + 1 <= maxTradeCount, "Daily transaction count limit exceeded");
        require(currentVolume + amount <= maxTradeAmount, "Daily transaction volume limit exceeded");
    }

    
    function mint(address to, uint256 value) public returns (bool success) {
        require(msg.sender == owner, "Only owner can mint");
        require(to != address(0), "Invalid address");
        require(value > 0, "Invalid value");
        balanceOf[to] += value;
        totalSupply += value;
        emit Transfer(address(0), to, value);
        return true;
    }

    // 销毁代币，只有owner可以销毁
    function burn(uint256 value) public returns (bool success) {
        require(msg.sender == owner, "Only owner can burn");
        require(balanceOf[msg.sender] >= value && value > 0, "Insufficient balance");
        require(value > 0, "Invalid value");
        balanceOf[msg.sender] -= value;
        totalSupply -= value;
        emit Transfer(msg.sender, address(0), value);
        return true;
    }

    // 获取某个地址拥有的代币数量
    function getBalanceOf(address account) public view returns (uint256) {
        return balanceOf[account];
    }

    // 获取当前代币总量
    function getTotalSupply() public view returns (uint256) {
        return totalSupply;
    }

    // 获取某个地址的免税状态
    function getIsExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }
}