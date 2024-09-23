// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";


interface IStakedINTX {
    function stakeFor(address _to, uint _intxAmount) external returns ( uint _tokenId) ;
}

contract TradingCompetitionClaim is ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {

    using SafeERC20 for IERC20;

    
    IERC20 public intx;
    IStakedINTX public xIntx;
    
    mapping(address => uint) public mntClaimableAmount;
    mapping(address => uint) public mntClaimedAmount;

    mapping(address => uint) public intxClaimableAmount;
    mapping(address => uint) public intxClaimedAmount;
    
    event MntClaimed(address indexed user, uint amount);
    event IntxClaimed(address indexed user, uint amount, uint _tokenId);
    event Seeded( address operator, address[] users, uint[] mntAmount, uint[] intxAmount ,  uint totalAmountMnt, uint totalAmountIntx);

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

    function setAllocations ( address[] calldata _receivers, uint[] calldata _mntAmounts, uint[] calldata _intxAmounts) external onlyOwner payable {
        uint _mntAamountNeeded = 0;
        uint _intxAamountNeeded = 0;

        uint _len = _receivers.length;
        require(_len == _mntAmounts.length);
        require(_len == _intxAmounts.length);

        for (uint i = 0; i < _len; i++) {
            mntClaimableAmount[_receivers[i]] += _mntAmounts[i];
            intxClaimableAmount[_receivers[i]] += _intxAmounts[i];

            _mntAamountNeeded += _mntAmounts[i];
            _intxAamountNeeded += _intxAmounts[i];
        }

        require(msg.value == _mntAamountNeeded, "Not enough MNT provided");

        intx.safeTransferFrom(_msgSender(), address(this), _intxAamountNeeded);
        emit Seeded( _msgSender(), _receivers, _mntAmounts, _intxAmounts, _mntAamountNeeded, _intxAamountNeeded );
    }
    

    function claim() public nonReentrant {
        require((mntClaimableAmount[_msgSender()] != 0) || (intxClaimableAmount[_msgSender()] != 0),"This address doesn't have any amount to claim.");
        require( (mntClaimedAmount[_msgSender()] < mntClaimableAmount[_msgSender()]) || (intxClaimedAmount[_msgSender()] < intxClaimableAmount[_msgSender()]), "You have already claimed all your allocation" );

        uint mntToClaim = mntClaimableAmount[ _msgSender() ] - mntClaimedAmount[ _msgSender() ];
        uint intxToClaim = intxClaimableAmount[ _msgSender() ] - intxClaimedAmount[ _msgSender() ];

        mntClaimedAmount[_msgSender()] += mntToClaim;
        intxClaimedAmount[_msgSender()] += intxToClaim;

        if ( mntToClaim > 0) {
            address payable _user = payable(_msgSender());
            bool success = _user.send(mntToClaim);
            require(success, "Transfer failed");

            emit MntClaimed( _msgSender(), mntToClaim);
        }

        if ( intxToClaim > 0) {
            intx.approve(address(xIntx), intxToClaim);
            uint _tokenId = xIntx.stakeFor(_msgSender(), intxToClaim);

            emit IntxClaimed( _msgSender(), intxToClaim, _tokenId);
        }
        
    }


    function claimableNow( address _user) public view returns (uint _mntToClaim, uint _intxToClaim) {

        _mntToClaim = mntClaimableAmount[ _user ] - mntClaimedAmount[ _user ];
        _intxToClaim = intxClaimableAmount[ _user ] - intxClaimedAmount[ _user ];

    }

    function renounceOwnership() public virtual override onlyOwner {}
    
}