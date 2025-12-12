// SPDX-License-Identifier: MIT

pragma solidity ^0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ["0x5B38Da6a701c568545dCfcB03FcB875f56beddC4"]

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

    function transferFrom(address _from, address _to, uint256 _amount) public override returns(bool) {
        _transfer(_from, _to, _amount);
        return true;
    }
}
