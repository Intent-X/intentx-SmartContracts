// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";


interface IStakedINTX {
    function stakeFor(address _to, uint _intxAmount) external returns ( uint _tokenId) ;
}

contract VestingXINTXAdv is ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {

    using SafeERC20 for IERC20;

    uint constant public PRECISION = 100000;
    
    IERC20 public intx;
    IStakedINTX public xIntx;
    
    mapping(address => uint) public claimableAmount;
    mapping(address => uint) public claimedAmount;
    mapping(address => uint) public start_vesting;
    mapping(address => uint) public vesting_duration;
    
    event Seeded( address operator, address[] users, uint[] amount, uint[] start_vesting, uint[] vesting_duration, uint totalAmount);
    event Claimed(address indexed user, uint amount, uint _tokenId);
    event RemoveSeed( address operator, address[] users, uint[] amount);
    
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

    function setAllocations ( address[] calldata _receivers, uint[] calldata _amounts, uint[] calldata _start_vesting, uint[] calldata _vesting_duration) external onlyOwner {
        uint _amountNeeded = 0;
        uint _len = _receivers.length;
        require(_len == _amounts.length);

        for (uint i = 0; i < _len; i++) {
            claimableAmount[_receivers[i]] += _amounts[i];
            start_vesting[_receivers[i]] += _start_vesting[i];
            vesting_duration[_receivers[i]] += _vesting_duration[i];

            _amountNeeded += _amounts[i];
        }


        intx.safeTransferFrom(_msgSender(), address(this), _amountNeeded);
        emit Seeded( _msgSender(), _receivers, _amounts, _start_vesting, _vesting_duration,  _amountNeeded );
    }


    function removeAllocations ( address[] calldata _receivers, uint[] calldata _amounts) external onlyOwner {
        uint _amountToGive = 0;
        uint _len = _receivers.length;
        require(_len == _amounts.length);

        for (uint i = 0; i < _len; i++) {
            claimableAmount[_receivers[i]] -= _amounts[i];
            
            _amountToGive += _amounts[i];
        }


        intx.safeTransfer(_msgSender(), _amountToGive);
        emit RemoveSeed( _msgSender(), _receivers, _amounts );
    }


    function claim() public nonReentrant {
        require( claimableAmount[_msgSender()] != 0,"This address doesn't have any amount to claim.");
        require( claimedAmount[_msgSender()] < claimableAmount[_msgSender()], "You have already claimed all your allocation" );

        uint START_VESTING = start_vesting[_msgSender()];
        uint VESTING_DURATION = vesting_duration[_msgSender()];

        if (block.timestamp > START_VESTING) {

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

        uint START_VESTING = start_vesting[_user];
        uint VESTING_DURATION = vesting_duration[_user];
        
        if (block.timestamp > START_VESTING ) {

            uint amount = claimableAmount[_user ];

            uint timeElapsed = block.timestamp - START_VESTING;

            if ( timeElapsed > VESTING_DURATION) timeElapsed = VESTING_DURATION;
            
            uint percentToReceive = timeElapsed * PRECISION / VESTING_DURATION;
                
            amountToReceive = (amount * percentToReceive / PRECISION) - claimedAmount[_user ];

        }
    }

    function claimableWithoutCliff( address _user) public view returns (uint amountToReceive) {
        
        uint START_VESTING = start_vesting[_user];
        uint VESTING_DURATION = vesting_duration[_user];

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