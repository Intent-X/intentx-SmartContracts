//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract TestUSDC is ERC20, Ownable {
    
    constructor() ERC20("Test USDC", "USDCt") {
        _mint( owner() , 1_000_000 * 10**decimals() );
    }

        
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}