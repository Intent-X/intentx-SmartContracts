//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";


contract IntxUpgradeable is ERC20Upgradeable {
    
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("IntentX Token", "INTX");
        
        _mint( _msgSender(), 100_000_000 * 10**decimals());
    }
}