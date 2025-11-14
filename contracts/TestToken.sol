//SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";


contract TestToken is ERC20BurnableUpgradeable, ERC20PermitUpgradeable, OwnableUpgradeable {
    
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("Test Token", "TEST");
        __ERC20Permit_init("Test_token");
        __Ownable_init();
        
        _mint( _msgSender(), 100_000 * 10**decimals());
    }

    function mint(address to, uint256 amount) public virtual onlyOwner {
        _mint(to, amount);
    }
}