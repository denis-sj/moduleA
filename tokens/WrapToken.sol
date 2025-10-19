// SDPX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WrapToken is ERC20 {
    uint256 constant _totalSupply = 20000000 * 10 ** 12;

    constructor() ERC20("RTKCoin", "RTK") {
        _mint(address(this), _totalSupply);
    }

    function decimals() public pure override returns (uint8) {
        return 12;
    }

    function buyTokens() external payable {
        require(msg.value > 0, "You are not ETH");

        // price token
        uint256 amount = (msg.value * 10**decimals()) / 1 ether; 
        
        require(balanceOf(address(this)) >= amount, "not enough RTK in reserve");

        _transfer(address(this), msg.sender, amount);

        emit TokensPurchased(msg.sender, amount, msg.value);
    }

    event TokensPurchased(
        address indexed buyer,
        uint256 amount,
        uint256 ethPaid
    );
}
