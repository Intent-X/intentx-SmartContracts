// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";


interface IStakedINTX {
    function stakeFor(address _to, uint _intxAmount) external returns ( uint _tokenId) ;
}

contract ICOClaimXINTX is ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {

    using SafeERC20 for IERC20;

    IERC20 public intx;
    IStakedINTX public xIntx;
    
    mapping(address => uint) public claimableAmount;
    mapping(address => uint) public claimedAmount;
    
    event Claimed(address indexed user, uint amount, uint _tokenId);
    event Seeded( address operator, address[] users, uint[] amount,  uint totalAmount);

    constructor () { _disableInitializers(); }

    function initialize(
            address _intx,
            address _xIntx
        ) public initializer {
        
        __ReentrancyGuard_init();
        __Ownable2Step_init();

        require ( _intx != address(0), "Can't use 0x address");
        require ( _xIntx != address(0), "Can't use 0x address");

        intx = IERC20(_intx);
        xIntx = IStakedINTX(_xIntx);

    }

    function setAllocations ( address[] calldata _receivers, uint[] calldata _amounts) external onlyOwner {
        uint _amountNeeded = 0;
        uint _len = _receivers.length;
        require(_len == _amounts.length);

        for (uint i = 0; i < _len; i++) {
            claimableAmount[_receivers[i]] += _amounts[i];
            _amountNeeded += _amounts[i];
        }


        intx.safeTransferFrom(_msgSender(), address(this), _amountNeeded);
        emit Seeded( _msgSender(), _receivers, _amounts, _amountNeeded );
    }
    

    function claim() public nonReentrant {
        require( claimableAmount[_msgSender()] != 0,"This address doesn't have any amount to claim.");

        uint allocation = claimableAmount[ _msgSender() ];

        uint toClaim = allocation - claimedAmount[ _msgSender() ];

        if ( toClaim > 0) {
            claimedAmount[ _msgSender() ] += toClaim;

            intx.approve(address(xIntx), toClaim);
            uint _tokenId = xIntx.stakeFor(_msgSender(), toClaim);

            emit Claimed( _msgSender(), toClaim, _tokenId);
        }
        
    }


    function claimableNow( address _user) public view returns (uint toClaim) {

        uint allocation = claimableAmount[ _user ];

        toClaim = allocation - claimedAmount[ _user ];
    }

    function renounceOwnership() public virtual override onlyOwner {}
    
}