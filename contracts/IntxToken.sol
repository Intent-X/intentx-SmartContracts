//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";


contract IntxToken is ERC20BurnableUpgradeable, ERC20PermitUpgradeable {
    
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("IntentX Token", "INTX");
        __ERC20Permit_init("IntentX_Token");
        
        _mint( _msgSender(), 100_000_000 * 10**decimals());
    }
}