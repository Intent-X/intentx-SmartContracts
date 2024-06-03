// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";


interface IStakedINTX {
    function stakeFor(address _to, uint _intxAmount) external returns ( uint _tokenId) ;
}

contract VestingXINTX is ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {

    using SafeERC20 for IERC20;

    uint constant public PRECISION = 100000;
    uint public START_VESTING;
    uint public VESTING_DURATION;
    uint public NO_CLAIM_DURATION;
    
    IERC20 public intx;
    IStakedINTX public xIntx;
    
    mapping(address => uint) public claimableAmount;
    mapping(address => uint) public claimedAmount;
    
    event Seeded( address operator, address[] users, uint[] amount,  uint totalAmount);
    event AllocationChanged( address changedBy, address indexed _oldAddress, address indexed _newAddress, uint amountClaimable, uint amountClaimed);
    event Claimed(address indexed user, uint amount, uint _tokenId);

    constructor () { _disableInitializers(); }

    function initialize(
            address _intx,
            address _xIntx,
            uint _startVesting,
            uint _vestingDuration,
            uint _noClaimDuration
        ) public initializer {
        
        __ReentrancyGuard_init();
        __Ownable2Step_init();

        require ( _intx != address(0), "Can't use 0x address");
        require ( _xIntx != address(0), "Can't use 0x address");

        intx = IERC20(_intx);
        xIntx = IStakedINTX(_xIntx);

        START_VESTING = _startVesting;
        VESTING_DURATION = _vestingDuration;
        NO_CLAIM_DURATION = _noClaimDuration;

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


    function changeReceiver( address _oldAddress, address _newAddress ) external onlyOwner {
        require( claimableAmount[_oldAddress] != 0, "Old address doesn't have any allocation.");
        require( claimedAmount[_oldAddress] < claimableAmount[_oldAddress], "This user has already claimed all your allocation." );
        
        // _newAddress will be address(0) when we just want to delete this user allocation.
        if ( _newAddress != address(0) ) {
            require( claimableAmount[_newAddress] == 0, "The new address already has a vesting amount.");
            claimableAmount[ _newAddress ] = claimableAmount[ _oldAddress ];
            claimedAmount[_newAddress] = claimedAmount[_oldAddress];
        } else {
            uint amountLeft = claimableAmount[ _oldAddress ] - claimedAmount[_oldAddress];
            intx.safeTransfer( _msgSender(), amountLeft);
        }

        claimableAmount[ _oldAddress ] = 0;
        claimedAmount[_oldAddress] = 0;

        emit AllocationChanged( _msgSender(), _oldAddress, _newAddress, claimableAmount[ _newAddress ], claimedAmount[ _newAddress ]);
    }

    function claim() public nonReentrant {
        require( claimableAmount[_msgSender()] != 0,"This address doesn't have any amount to claim.");
        require( claimedAmount[_msgSender()] < claimableAmount[_msgSender()], "You have already claimed all your allocation" );

        if (block.timestamp > START_VESTING + NO_CLAIM_DURATION) {

            uint amount = claimableAmount[_msgSender()];

            uint timeElapsed = block.timestamp - START_VESTING;

            if ( timeElapsed > VESTING_DURATION) timeElapsed = VESTING_DURATION;
            
            uint percentToReceive = timeElapsed * PRECISION / VESTING_DURATION;
                
            uint amountToReceive = (amount * percentToReceive / PRECISION) - claimedAmount[_msgSender()];

            if ( amountToReceive > 0) {
                claimedAmount[_msgSender()] += amountToReceive;
                intx.approve(address(xIntx), amountToReceive);
                uint _tokenId = xIntx.stakeFor(_msgSender(), amountToReceive);
                emit Claimed( _msgSender(), amountToReceive, _tokenId);
            }
        }
    }

    function claimableNow( address _user) public view returns (uint amountToReceive) {

        if (block.timestamp > START_VESTING + NO_CLAIM_DURATION) {

            uint amount = claimableAmount[_user ];

            uint timeElapsed = block.timestamp - START_VESTING;

            if ( timeElapsed > VESTING_DURATION) timeElapsed = VESTING_DURATION;
            
            uint percentToReceive = timeElapsed * PRECISION / VESTING_DURATION;
                
            amountToReceive = (amount * percentToReceive / PRECISION) - claimedAmount[_user ];

        }
    }

    function claimableWithoutCliff( address _user) public view returns (uint amountToReceive) {

        if ( block.timestamp > START_VESTING ) {

            uint amount = claimableAmount[_user ];

            uint timeElapsed = block.timestamp - START_VESTING;

            if ( timeElapsed > VESTING_DURATION) timeElapsed = VESTING_DURATION;
            
            uint percentToReceive = timeElapsed * PRECISION / VESTING_DURATION;
                
            amountToReceive = (amount * percentToReceive / PRECISION) - claimedAmount[_user ];

        }
    }

    function renounceOwnership() public virtual override onlyOwner {}
    
}