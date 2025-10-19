// SDPX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract SystemToken is ERC20 {
    constructor(address[] memory _daoMembers) ERC20("Professional", "PROFI"){
        uint256 totalSupply = 100000 * 10**decimals();
        uint256 sharePerMember = totalSupply / _daoMembers.length;
        uint256 remainder = totalSupply % _daoMembers.length; // остаток

        // распределение токенов между участниками
        for (uint256 i = 0; i < _daoMembers.length; i++) {
            _mint(_daoMembers[i], sharePerMember);
        }

        // Остаток минтим на первый адрес участника ДАО (минты суммируются)
        if (remainder > 0) {
            _mint(_daoMembers[0], remainder);
        }
    }

    function decimals() public pure override returns (uint8) {
        return 12;
    }
}
