// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";


interface IStakedINTX {
    function stakeFor(address _to, uint _intxAmount) external returns ( uint _tokenId) ;
}

contract VestingXINTX is ReentrancyGuardUpgradeable, OwnableUpgradeable {

    uint constant public PRECISION = 10000;
    uint public START_VESTING;
    uint public VESTING_DURATION;
    uint private totalAmountNeeded;

    bool public allowChange;
    bool public allowOwnerChange;

    bool public seeded;
    
    IERC20 public intx;
    IStakedINTX public xIntx;

    
    
    mapping(address => uint) public claimableAmount;
    mapping(address => uint) public claimedAmount;
    
    event AllocationSet(address indexed user, uint amount);
    event AllocationChanged( address changedBy, address indexed _oldAddress, address indexed _newAddress);
    event Claimed(address indexed user, uint amount, uint _tokenId);
    event Seeded( address operator, uint amount);

    constructor () { _disableInitializers(); }

    function initialize(
            address _intx,
            address _xIntx,
            uint _startVesting,
            uint _vestingDuration,
            address[] calldata _receivers,
            uint[] calldata _amounts,
            bool _allowChange,
            bool _allowOwnerChange
        ) public initializer {
        
        __ReentrancyGuard_init();
        __Ownable_init();


        intx = IERC20(_intx);
        xIntx = IStakedINTX(_xIntx);


        START_VESTING = _startVesting;
        VESTING_DURATION = _vestingDuration;


        uint _len = _receivers.length;

        require(_len == _amounts.length);

        for (uint i = 0; i < _len; i++) {
            claimableAmount[_receivers[i]] += _amounts[i];
            totalAmountNeeded += _amounts[i];
            emit AllocationSet(_receivers[i], _amounts[i]);
        }

        allowChange = _allowChange;
        allowOwnerChange = _allowOwnerChange;

    }

    function deposit() external onlyOwner {
        require(!seeded, "Vesting Contract Already seeded with initial amount.");

        intx.transferFrom(_msgSender(), address(this), totalAmountNeeded);
        intx.approve(address(xIntx), type(uint256).max);

        seeded = true;
        
        emit Seeded( _msgSender(), totalAmountNeeded );
    }

    function changeReceiver( address _newAddress) external {
        require( allowChange, "This vesting contract doesn't allow you to change the receiver address" );
        require( _newAddress != address(0), "New allocation receiver can't be the 0x0000... address");

        address _oldAddress = _msgSender();
        require( claimableAmount[_oldAddress] != 0, "You don't have any allocation.");
        require( claimableAmount[_newAddress] == 0, "The new address already has a vesting amount.");
        require( claimedAmount[_oldAddress] < claimableAmount[_oldAddress], "You have already claimed all your allocation." );
        
        claimableAmount[ _newAddress ] = claimableAmount[ _oldAddress ];
        claimedAmount[_newAddress] = claimedAmount[_oldAddress];

        claimableAmount[ _oldAddress ] = 0;
        claimedAmount[_oldAddress] = 0;

        emit AllocationChanged( _msgSender(), _oldAddress, _newAddress);
    }

    function changeReceiverOwner( address _oldAddress, address _newAddress ) external onlyOwner {
        require( allowOwnerChange );

        require( claimableAmount[_oldAddress] != 0, "Old address doesn't have any allocation.");
        require( claimedAmount[_oldAddress] < claimableAmount[_oldAddress], "You have already claimed all your allocation." );
        
        // _newAddress will be address(0) when we just want to delete this user allocation.
        if ( _newAddress != address(0) ) {
            require( claimableAmount[_newAddress] == 0, "The new address already has a vesting amount.");
            claimableAmount[ _newAddress ] = claimableAmount[ _oldAddress ];
            claimedAmount[_newAddress] = claimedAmount[_oldAddress];
        } else {
            uint amountLeft = claimableAmount[ _oldAddress ] - claimedAmount[_oldAddress];
            intx.transfer(_msgSender(), amountLeft);
        }

        claimableAmount[ _oldAddress ] = 0;
        claimedAmount[_oldAddress] = 0;

        emit AllocationChanged( _msgSender(), _oldAddress, _newAddress);
    }

    function claim() public nonReentrant {
        require(claimableAmount[_msgSender()] != 0,"This address doesn't have any amount to claim.");
        require(seeded, "Vesting Contract hasn't been seeded yet.");
        require( claimedAmount[_msgSender()] < claimableAmount[_msgSender()], "You have already claimed all your allocation" );

        if (block.timestamp > START_VESTING) {

            uint amount = claimableAmount[_msgSender()];

            uint timeElapsed = block.timestamp - START_VESTING;

            if ( timeElapsed > VESTING_DURATION) timeElapsed = VESTING_DURATION;
            
            uint percentToReceive = timeElapsed * PRECISION / VESTING_DURATION;
                
            uint amountToReceive = (amount * percentToReceive / PRECISION) - claimedAmount[_msgSender()];

            if ( amountToReceive > 0) {
                claimedAmount[_msgSender()] += amountToReceive;
                uint _tokenId = xIntx.stakeFor(_msgSender(), amountToReceive);
                emit Claimed( _msgSender(), amountToReceive, _tokenId);
            }
        }
    }

}