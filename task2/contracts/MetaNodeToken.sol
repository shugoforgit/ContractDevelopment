// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MetaNodeToken is ERC20 {
    constructor(uint256 _totalSupply) ERC20("MetaNode", "MN") {
        _mint(msg.sender, _totalSupply);
    }
}
