// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";


interface IStakedINTX {
    function stakeFor(address _to, uint _intxAmount) external returns ( uint _tokenId) ;
}

contract PublicSaleINTX is ReentrancyGuardUpgradeable, Ownable2StepUpgradeable {

    using SafeERC20 for IERC20;

    uint constant public PRECISION = 10000;
    uint public instantPercentage;
    uint public START_SALE;
    uint public START_VESTING;
    uint public VESTING_DURATION;
    address public multisig;

    bool public allowChange;

    uint public totalAllocation;
    uint public totalToRaise;
    uint public totalRaised;
    uint public minBuy;
    bool public seeded;
    uint public totalClaimable;
    
    IERC20 public intx;
    IERC20 public raiseToken;
    IStakedINTX public xIntx;

    mapping(address => uint) public claimableAmount;
    mapping(address => uint) public claimedAmount;
    
    event AllocationChanged( address changedBy, address indexed _oldAddress, address indexed _newAddress);
    event Claimed(address indexed user, uint amount, uint _tokenId);
    event Seeded( address operator, uint amount);
    event Withdraw( address operator, address _to, uint amount);
    event WithdrawUnallocatedIntx( address operator, address _to, uint amount);
    event Bought( address indexed user, uint usdcAmount, uint intxAmount, uint intxAmountTotal);

    constructor () { _disableInitializers(); }

    function initialize(
            address _intx,
            address _raiseToken,
            address _xIntx,
            address _multisig,
            uint _startSale,
            uint _saleDuration
        ) public initializer {
        
        __ReentrancyGuard_init();
        __Ownable2Step_init();

        require ( _intx != address(0), "Can't use 0x address");
        require ( _raiseToken != address(0), "Can't use 0x address");
        require ( _xIntx != address(0), "Can't use 0x address");
        require ( _multisig != address(0), "Can't use 0x address");
        
        intx = IERC20(_intx);
        raiseToken = IERC20(_raiseToken);
        xIntx = IStakedINTX(_xIntx);
        multisig = _multisig;

        START_SALE = _startSale;
        START_VESTING = _startSale + _saleDuration;
        VESTING_DURATION = 182 days;      // 6 months
        instantPercentage = PRECISION/2;       // 50%

        totalAllocation = 2_000_000 * 10**18;     // 2 000 000 INTX
        totalToRaise = 400_000 * 10**6;           // 400 000 USDC

        minBuy = 10 * 10**6;

        allowChange = true;

    }

    function deposit() external onlyOwner {
        require(!seeded, "Vesting Contract Already seeded with initial amount.");

        intx.safeTransferFrom(_msgSender(), address(this), totalAllocation);
        intx.approve(address(xIntx), type(uint256).max);

        seeded = true;
        
        emit Seeded( _msgSender(), totalAllocation );
    }

    function withdraw() external onlyOwner {
        
        uint _amount = raiseToken.balanceOf(address(this));
        require( _amount > 0, "Not enough raiseToken to withdraw");
        raiseToken.safeTransfer(multisig, _amount);

        emit Withdraw( _msgSender(), multisig, _amount );
    }

    function withdrawUnallocatedIntx() external onlyOwner {
        require( block.timestamp >= START_VESTING, "Sale hasn't ended yet.");
        
        uint _amount = totalAllocation - totalClaimable;
        require( _amount > 0, "Not enough Intx to withdraw");
        intx.safeTransfer(multisig, _amount);

        emit WithdrawUnallocatedIntx( _msgSender(), multisig, _amount );
    }

    function buy( uint _amount ) external {
        require( totalRaised <= totalToRaise, "All Raise have been filled");
        require( block.timestamp <= START_VESTING, "Sale has ended.");
        require( block.timestamp >= START_SALE, "Sale hasn't started yet.");
        require( _amount >= minBuy, "You can't invest less than 10 USDC." );
        require(seeded, "Vesting Contract hasn't been seeded yet.");

        if ( _amount + totalRaised > totalToRaise ) {
            _amount = totalToRaise - totalRaised;
        }

        raiseToken.safeTransferFrom(_msgSender(), address(this), _amount);
        totalRaised += _amount;

        uint amountOwed = totalAllocation * _amount / totalToRaise;
        totalClaimable += amountOwed;
        claimableAmount[_msgSender()] += amountOwed;

        emit Bought( _msgSender(), _amount, amountOwed, claimableAmount[_msgSender()]);
    }

    function changeReceiver( address _newAddress) external {
        require( block.timestamp >= START_VESTING, "Vesting hasn't started yet.");
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


    function claim() public nonReentrant {
        require( block.timestamp >= START_VESTING, "Vesting hasn't started yet.");
        require( claimableAmount[_msgSender()] != 0,"This address doesn't have any amount to claim.");
        require( claimedAmount[_msgSender()] < claimableAmount[_msgSender()], "You have already claimed all your allocation" );

        if (block.timestamp > START_VESTING) {

            uint instantAmount = claimableAmount[_msgSender()] * instantPercentage / PRECISION;
            uint amount = claimableAmount[_msgSender()] * (PRECISION - instantPercentage) / PRECISION;


            uint timeElapsed = block.timestamp - START_VESTING;

            if ( timeElapsed > VESTING_DURATION) timeElapsed = VESTING_DURATION;
            
            uint percentToReceive = timeElapsed * PRECISION / VESTING_DURATION;
                
            uint amountToReceive = instantAmount + (amount * percentToReceive / PRECISION) - claimedAmount[_msgSender()];

            if ( amountToReceive > 0) {
                claimedAmount[_msgSender()] += amountToReceive;
                uint _tokenId = xIntx.stakeFor(_msgSender(), amountToReceive);
                emit Claimed( _msgSender(), amountToReceive, _tokenId);
            }
        }
    }

    function renounceOwnership() public virtual override onlyOwner {}
    
}