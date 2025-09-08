// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract MetaNodeStake is 
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;
    using Address for address;
    using Math for uint256;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    uint256 public constant ETH_PID = 0;

    struct Pool {
        // 质押代币的地址
        address poolAddress;
        // 权重
        uint256 poolWeight;
        // 最低质押金额
        uint256 minDepositAmount;
        // 最后一次更新的块高度
        uint256 lastRewardBlock;
        // 每个token可以分到的奖励
        uint256 accMetaNodePerST;
        // 质押总量
        uint256 stTokenAmount;
        // 防止提取挤兑 提取的时候需要等待多少个块
        uint256 unstakeLockedBlocks;
    }

    struct UnstakeRequest {
        uint256 amount;
        uint256 unlockBlock;
    }

    struct User {
        uint256 amount; // 质押金额
        uint256 finishedMetaNode; // 已经获得的奖励 累计
        uint256 pendingMetaNode; // 待领取的奖励
        UnstakeRequest[] requests;
    }

    Pool[] public pools;
    
    uint256 public startBlock;
    uint256 public endBlock;
    uint256 public metaNodePerBlock; // 每个区块的奖励数

    bool public withdrawPaused;
    bool public claimPaused;

    uint256 public totalWeight;

    IERC20 public MetaNode;

    mapping(uint256 => mapping(address => User)) public users;

    modifier checkPid(uint256 _pid) {
        require(_pid < pools.length, "Invalid pid");
        _;
    }

    modifier whenNotWithdrawPaused() {
        require(!withdrawPaused, "Withdraw is paused");
        _;
    }

    modifier whenNotClaimPaused() {
        require(!claimPaused, "Claim is paused");
        _;
    }


    function initialize(
        address _metaNodeAddress,
        uint256 _startBlock,
        uint256 _endBlock,
        // 每个区块产生的奖励数
        uint256 _metaNodePerBlock
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
        
        setMetaNode(_metaNodeAddress);

        startBlock = _startBlock;
        endBlock = _endBlock;
        metaNodePerBlock = _metaNodePerBlock;
    }

    function updatePool(uint256 _pid, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        pools[_pid].minDepositAmount = _minDepositAmount;
        pools[_pid].unstakeLockedBlocks = _unstakeLockedBlocks;
    }

    function setMetaNodePerBlock(uint256 _metaNodePerBlock) public onlyRole(ADMIN_ROLE) {
        metaNodePerBlock = _metaNodePerBlock;
    }

    function setStartBlock(uint256 _startBlock) public onlyRole(ADMIN_ROLE) {
        require(_startBlock <= endBlock, "Start block must be greater than current start block");
        startBlock = _startBlock;
    }
    
    function setEndBlock(uint256 _endBlock) public onlyRole(ADMIN_ROLE) {
        require(_endBlock >= startBlock, "End block must be greater than current end block");
        endBlock = _endBlock;
    }

    function poolLength() public view returns (uint256) {
        return pools.length;
    }

    function pendingMetaNode(uint256 _pid, address _user) public view checkPid(_pid) returns (uint256) {
        return pendingMetaNodeByBlockNumber(_pid, _user, block.number);
    }
    
    function pendingMetaNodeByBlockNumber(uint256 _pid, address _user, uint256 _blockNumber) public view checkPid(_pid) returns (uint256) {
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][_user];

        uint256 accMetaNodePerST = pool_.accMetaNodePerST;
        uint256 stSupply = pool_.stTokenAmount;

        if (_blockNumber > pool_.lastRewardBlock) {
            uint256 multiplier = getMultiplier(_blockNumber, pool_.lastRewardBlock);
            uint256 MetaNodeForPool = multiplier * pool_.poolWeight / totalWeight; //  按权重 池子所分配到的全部metanode数量
            accMetaNodePerST = accMetaNodePerST + MetaNodeForPool * (1 ether) / stSupply; // 按质押比例分配metanode
        }

        return user_.amount * accMetaNodePerST / (1 ether) - user_.finishedMetaNode + user_.pendingMetaNode;
    }

    function pauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(!withdrawPaused, "Withdraw is already paused");
        withdrawPaused = true;
    }

    function pauseClaim() public onlyRole(ADMIN_ROLE) {
        require(!claimPaused, "Claim is already paused");
        claimPaused = true;
    }

    function unpauseWithdraw() public onlyRole(ADMIN_ROLE) {
        require(withdrawPaused, "Withdraw is not paused");
        withdrawPaused = false;
    }

    function unpauseClaim() public onlyRole(ADMIN_ROLE) {
        require(claimPaused, "Claim is not paused");
        claimPaused = false;
    }
    
    function _authorizeUpgrade(address _newImplementation) 
        internal 
        override 
        onlyRole(UPGRADER_ROLE) 
    {}

    function setMetaNode(address _metaNodeAddress) public onlyRole(ADMIN_ROLE) {
        MetaNode = IERC20(_metaNodeAddress);
    }

    function setPoolWeight(uint256 _pid, uint256 _poolWeight, bool _withUpdate) public onlyRole(ADMIN_ROLE) checkPid(_pid) {
        require(_poolWeight > 0, "Pool weight must be greater than 0");

        if (_withUpdate) {
            massUpdatePools();
        }

        totalWeight = totalWeight - pools[_pid].poolWeight + _poolWeight;
        pools[_pid].poolWeight = _poolWeight;
    }

    function stakingBalance(uint256 _pid, address _user) public view checkPid(_pid) returns (uint256) {
        return users[_pid][_user].amount;
    }

    function massUpdatePools() public {
        uint256 length = pools.length;
        for (uint256 i = 0; i < length; i++) {
            updatePool(i);
        }
    }

    function addPool(address _poolAddress, uint256 _poolWeight, uint256 _minDepositAmount, uint256 _unstakeLockedBlocks) public onlyRole(ADMIN_ROLE) {
        if (pools.length > 0) {
            require(_poolAddress != address(0), "Pool address cannot be zero");
        } else {
            require(_poolAddress == address(0), "Pool address cannot be zero");
        }

        uint256 lastBlock = block.number > startBlock ? block.number : startBlock;
        totalWeight += _poolWeight;

        pools.push(Pool({
            poolAddress: _poolAddress,
            poolWeight: _poolWeight,
            minDepositAmount: _minDepositAmount,
            lastRewardBlock: lastBlock,
            accMetaNodePerST: 0,
            stTokenAmount: 0,
            unstakeLockedBlocks: _unstakeLockedBlocks
        }));
    }

    function depositETH() public payable {
        Pool storage pool_ = pools[ETH_PID];
        require(pool_.poolAddress == address(0x0), "ETH staking is full");
        
        uint256 _amount = msg.value;
        require(_amount >= pool_.minDepositAmount, "Amount must be greater than min deposit amount");

        _deposit(ETH_PID, _amount);
    }

    function deposit(uint256 _pid, uint256 _amount) public checkPid(_pid) {
        require(_pid != 0, "deposit not support ETH staking");
        Pool storage pool_ = pools[_pid];
        require(_amount > pool_.minDepositAmount, "Amount must be greater than min deposit amount");
        if (_amount > 0) {
            IERC20(pool_.poolAddress).safeTransferFrom(msg.sender, address(this), _amount);
        }

        _deposit(_pid, _amount);
    }

    function _deposit(uint256 _pid, uint256 _amount) internal checkPid(_pid) {
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][msg.sender];

        updatePool(_pid);

        if (user_.amount > 0) {
            (bool succ1, uint256 accSTAmount) = user_.amount.tryMul(pool_.accMetaNodePerST);
            require(succ1, "AccSTAmount overflow");

            (bool succ2, uint256 pendingMetaNode) = accSTAmount.trySub(user_.finishedMetaNode);
            require(succ2, "Pending overflow");

            if (pendingMetaNode > 0) {
                (bool succ3, uint256 pendingMetaNode_) = pendingMetaNode.tryAdd(user_.pendingMetaNode);
                require(succ3, "PendingMetaNode overflow");
                user_.pendingMetaNode = pendingMetaNode_;
            }
        }

        if (_amount > 0) {
            (bool succ4, uint256 userAmount) = _amount.tryAdd(user_.amount);
            require(succ4, "UserAmount overflow");
            user_.amount = userAmount;
        }

        (bool succ5, uint256 stTokenAmount) = _amount.tryAdd(pool_.stTokenAmount);
        require(succ5, "StTokenAmount overflow");
        pool_.stTokenAmount = stTokenAmount;

        (bool succ6, uint256 finishedMetaNode) = user_.amount.tryMul(pool_.accMetaNodePerST);
        require(succ6, "AccMetaNodePerST overflow");

        (succ6, finishedMetaNode) = finishedMetaNode.tryDiv(1 ether);
        require(succ6, "AccMetaNodePerST overflow");
        user_.finishedMetaNode = finishedMetaNode;
    }

    function updatePool(uint256 _pid) internal checkPid(_pid) {
        Pool storage pool_ = pools[_pid];

        if (block.number <= pool_.lastRewardBlock) {
            return;
        }

        (bool succ, uint256 totalMetaNode) = getMultiplier(block.number, pool_.lastRewardBlock).tryMul(pool_.poolWeight);
        require(succ, "Multiplier overflow");

        (succ, totalMetaNode) = totalMetaNode.tryDiv(totalWeight);
        require(succ, "MetaNodePerST overflow");
        
        uint256 stSupply = pool_.stTokenAmount;
        if (stSupply > 0) {
            (bool succ2, uint256 totalMetaNode_) = totalMetaNode.tryMul(1 ether);
            require(succ, "TotalMetaNode overflow");

            (succ2, totalMetaNode_) = totalMetaNode_.tryDiv(stSupply);
            require(succ2, "MetaNodePerST overflow");

            (bool succ3, uint256 accMetaNodePerST_) = pool_.accMetaNodePerST.tryAdd(totalMetaNode_);
            require(succ3, "AccMetaNodePerST overflow");
            pool_.accMetaNodePerST = accMetaNodePerST_;    
        }

        pool_.lastRewardBlock = block.number;
    }

    function getMultiplier(uint256 _lastBlock, uint256 _startBlock) public view returns (uint256 multiplier) {
        require(_lastBlock >= _startBlock, "Last block must be greater than start block");
        if (_lastBlock > endBlock) {_lastBlock = endBlock;}
        if (_startBlock < startBlock) {_startBlock = startBlock;}

        require(_startBlock < _lastBlock, "Start block must be less than last block");
        bool succ;
        (succ, multiplier) = (_lastBlock - _startBlock).tryMul(metaNodePerBlock);
        require(succ, "Multiplier overflow");
    }

    function unstake(uint256 _pid, uint256 _amount) public checkPid(_pid) {
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][msg.sender];

        require(_amount <= user_.amount, "Amount must be greater than user amount");

        updatePool(_pid);

        uint256 pendingMetaNode_ = user_.amount * pool_.accMetaNodePerST / (1 ether) - user_.finishedMetaNode;

        if (pendingMetaNode_ > 0) {
            user_.pendingMetaNode += pendingMetaNode_;
        }

        if (_amount > 0) {
            user_.amount -= _amount;
            user_.requests.push(UnstakeRequest({
                amount: _amount,
                unlockBlock: block.number + pool_.unstakeLockedBlocks
            }));
        }

        pool_.stTokenAmount -= _amount;
        user_.finishedMetaNode = user_.amount * pool_.accMetaNodePerST / (1 ether);
    }

    function withdraw(uint256 _pid) public checkPid(_pid) whenNotWithdrawPaused {
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][msg.sender];

        uint256 pendingWithdram_ = 0;
        uint256 popNum_ = 0;
        for (uint256 i = 0; i < user_.requests.length; i++) {
            if (user_.requests[i].unlockBlock > block.number) {
                break;
            }

            pendingWithdram_ += user_.requests[i].amount;
            popNum_++;
        }

        for (uint256 i = 0; i < user_.requests.length - popNum_; i++) {
            user_.requests[i] = user_.requests[i + popNum_];
        }

        for (uint256 i = 0; i < popNum_; i++) {
            user_.requests.pop();
        }

        if (pendingWithdram_ > 0) {
            if (pool_.poolAddress == address(0x0)) {
                _safeETHTransfer(msg.sender, pendingWithdram_);
            } else {
                IERC20(pool_.poolAddress).safeTransfer(msg.sender, pendingWithdram_);
            }
        }
    }

    function withdrawAmount(uint256 _pid, address _user) public view checkPid(_pid) returns (uint256 requestAmount, uint256 pendingWithdrawAmount) {
        User storage user_ = users[_pid][_user];

        for (uint256 i = 0; i < user_.requests.length; i++) {
            if (user_.requests[i].unlockBlock < block.number) {
                pendingWithdrawAmount += user_.requests[i].amount;
            }

            requestAmount += user_.requests[i].amount;
        }
    }

    function claim(uint256 _pid) public checkPid(_pid) whenNotClaimPaused {
        Pool storage pool_ = pools[_pid];
        User storage user_ = users[_pid][msg.sender];

        updatePool(_pid);

        uint256 pendingMetaNode_ = user_.amount * pool_.accMetaNodePerST / (1 ether) - user_.finishedMetaNode + user_.pendingMetaNode;

        if (pendingMetaNode_ > 0) {
            user_.pendingMetaNode = 0;
            _safeMetaNodeTransfer(msg.sender, pendingMetaNode_);
        }

        user_.finishedMetaNode = user_.amount * pool_.accMetaNodePerST / (1 ether);
    }

    function _safeETHTransfer(address _to, uint256 _amount) internal {
        (bool succ, bytes memory data) = address(_to).call{value: _amount}("");
        require(succ, "ETH transfer failed");

        if (data.length > 0) {
            require(
                abi.decode(data, (bool)),
                "ETH transfer operation did not succeed"
            );
        }
    }

    function _safeMetaNodeTransfer(address _to, uint256 _amount) internal {
        uint256 MetaNodeBal = MetaNode.balanceOf(address(this));

        if (_amount > MetaNodeBal) {
            MetaNode.transfer(_to, MetaNodeBal);
        } else {
            MetaNode.transfer(_to, _amount);
        }
    }
}