// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import "./DAO.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WrapToken is ERC20 {
    uint256 private _totalSupply = 20000000 * 10**decimals();

    constructor() ERC20("RTKCoin", "RTK") {
        _mint(address(this), _totalSupply);
    }

    function decimals() public pure override returns (uint8) {
        return 12;
    }

    function buyTokensEth() external payable {
        uint256 amount = msg.value / 1 ether;
        _transfer(address(this), msg.sender, amount);
    }

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) public override returns (bool) {
        _transfer(_from, _to, _amount);
        return true;
    }
}
