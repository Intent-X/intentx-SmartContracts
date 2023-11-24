//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library Math {
    function max(uint a, uint b) internal pure returns (uint) {
        return a >= b ? a : b;
    }
    function min(uint a, uint b) internal pure returns (uint) {
        return a < b ? a : b;
    }
}

contract StakedINTX is ReentrancyGuardUpgradeable, ERC721EnumerableUpgradeable, OwnableUpgradeable {


    uint public constant WEEK = 60*60*24*7;
    uint public constant DURATION = 60*60*24*7;
    uint public constant P = 1e18; // PRECISSION
    uint constant initialExchangeRate = 1e18;

    uint public lastTokenId;
    uint public totalXINTX;

    uint public loyaltyDuration;
    uint public maxLoyaltyBoost;
    uint public maxPenalty;
    uint public minPenalty;

    uint public lastUpdateTime;
    uint public periodFinish;
    uint public rewardRate;
    uint private rewardPerWeightStored;
    uint private totalWeight;

    IERC20 public INTX;
    IERC20 public rewardToken;

    mapping(uint => uint) public loyalSince;
    mapping(uint => uint) public balanceOfId;
    mapping(uint => uint) private _lastWeightOfTokenId;
    mapping(uint => uint) private _rewardPerWeightPaid;
    mapping(uint => uint) private _rewards;
    mapping(address => uint) private pendingRewards;

    event Mint (address indexed from, address indexed to, uint indexed tokenId, uint amountMinted, uint amountIntxIn, uint totalXINTXNew, uint newTotalWeight);
    event Burn (address indexed owner, uint indexed tokenId, uint amountBurned, uint amountIntxOut, uint amountIntxPenalized, uint totalXINTXNew);
    event Split (address indexed owner, uint indexed tokenIdFrom, uint tokenIdTo, uint balanceSplitted);
    event Merge (address indexed owner, uint indexed tokenIdFrom, uint tokenIdTo, uint newBalance, uint newLoyalSince);
    event RewardAdded (uint rewardAdded);

    constructor () { _disableInitializers(); }

    function initialize ( address _intx, address _usdc ) public initializer {
        __ReentrancyGuard_init();
        __ERC721_init( "Staked INTX", "XINTX" );
        __Ownable_init();

        INTX = IERC20(_intx);
        rewardToken = IERC20(_usdc);

        loyaltyDuration = WEEK * 16;        // 16 weeks
        maxLoyaltyBoost = 25*10**17;        // 2.5x
        maxPenalty = 25*10**16;             // 25%
        minPenalty = 5*10**15;              // 0.5%

    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                        EXTERNAL VIEW FUNCTIONS, POSITION INFO
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */
    
    /**
     * @notice Calculates the boost percentage of a position.
     * @param _tokenId the tokenId of the position.
     */
    function boostPercentageOf( uint _tokenId) external view returns(uint boostPercentage) {
        if (_exists(_tokenId)) {
            boostPercentage = _boostPercentageOf(_tokenId);
        }
    }

    /**
     * @notice Calculates the penalty percentage of a position.
     * @param _tokenId the tokenId of the position.
     */
    function penaltyPercentageOf( uint _tokenId) external view returns(uint penaltyPercentage) {
        if (_exists(_tokenId)) {
            penaltyPercentage = _penaltyPercentageOf(_tokenId);
        }
    }

    /**
     * @notice Calculates the amount of INTX staked that a position has.
     * @param _tokenId the tokenId of the position.
     */
    function amountStakedOf( uint _tokenId) external view returns(uint amount) {
        if (_exists(_tokenId)) {
            amount = _amountStakedOf(_tokenId);
        }
    }
    
    /**
     * @notice Calculates the amount of INTX that a position will give when unstaked (having in mind the penalty).
     * @param _tokenId the tokenId of the position.
     */
    function withdrawableAmountOf( uint _tokenId) external view returns(uint withdrawableAmount ) {
        uint _amount = _amountStakedOf(_tokenId);
        uint _penalty = _penaltyPercentageOf(_tokenId);
        if (_amount > 0) {
            withdrawableAmount = _amount - (_amount * _penalty / P);
        }
    }

    /**
     * @notice Calculates the amount of INTX that would be penalized from a position when unstaked.
     * @param _tokenId the tokenId of the position.
     */
    function penaltyAmountOf( uint _tokenId) public view returns(uint penaltyAmount ) {
        uint _amount = _amountStakedOf(_tokenId);
        uint _penalty = _penaltyPercentageOf(_tokenId);
        if (_amount > 0) {
            penaltyAmount = _amount * _penalty / P;
        }
    }
    
    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                        INTERNAL VIEW FUNCTIONS, POSITION INFO
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /**
     * @dev Calculates the boost percentage of a position.
     * @param _tokenId the tokenId of the position.
     */
    function _boostPercentageOf( uint _tokenId ) internal view returns(uint boostPercentage) {
        uint _timestamp = loyalSince[_tokenId];
        uint _timeStaked = block.timestamp - _timestamp;

        if ( _timeStaked > loyaltyDuration ) _timeStaked = loyaltyDuration;

        boostPercentage = P + (( _timeStaked * P/loyaltyDuration ) * (maxLoyaltyBoost - P) / P);
    }
    
    /**
     * @dev Calculates the penalty percentage of a position.
     * @param _tokenId the tokenId of the position.
     */
    function _penaltyPercentageOf( uint _tokenId ) internal view returns(uint penaltyPercentage) {
        uint _timestamp = loyalSince[_tokenId];
        uint _timeStaked = block.timestamp - _timestamp;

        if ( _timeStaked > loyaltyDuration ) _timeStaked = loyaltyDuration;

        penaltyPercentage = maxPenalty - ( ( _timeStaked * P/loyaltyDuration ) * maxPenalty / P);

        if ( penaltyPercentage < minPenalty) penaltyPercentage = minPenalty;
    }

    /**
     * @dev Calculates the amount of INTX staked that a position has.
     * @param _tokenId the tokenId of the position.
     */
    function _amountStakedOf( uint _tokenId) internal view returns(uint amount) {

        uint _balance = balanceOfId[_tokenId];

        uint _exchangeRate = _exchangeRateInternal();

        amount = _balance * _exchangeRate / P;
    }

    /**
     * @dev Gets balance of INTX of this contract.
     */
    function _getCurrentIntxBalance() internal view returns (uint) {
        return INTX.balanceOf(address(this));
    }

    /**
     * @dev Calculates the exchange rate from INTX to xINTX.
     */
    function _exchangeRateInternal() internal view virtual returns (uint) {
        if (totalXINTX == 0) {
            // This is the first time to mint, so current exchange rate is equal to initial exchange rate.
            return initialExchangeRate;
        } else {
            // exchangeRate = (intxBalance / total
            return _getCurrentIntxBalance() * P / totalXINTX;
        }
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                        EXTERNAL FUNCTIONS, INTERACTION POSITIONS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    function stake(uint _intxAmount) external returns(uint _tokenId) {
        _tokenId = _stake( _msgSender(), _msgSender(), _intxAmount );
    }

    function stakeFor(address _to, uint _intxAmount) external returns (uint _tokenId) {
        _tokenId = _stake( _msgSender(), _to, _intxAmount );
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                        INTERNAL FUNCTIONS, INTERACTION POSITIONS
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    function _stake(address _from, address _to, uint _intxAmount) internal nonReentrant returns (uint _tokenId) {
        require(_intxAmount > 0, "Can't stake 0 intX." );

        uint _exchangeRate = _exchangeRateInternal();

        INTX.transferFrom( _from, address(this), _intxAmount);

        lastTokenId++;
        _mint(_to, lastTokenId);
        
        uint _tokenMinted = _intxAmount * P / _exchangeRate;
        loyalSince[lastTokenId] = block.timestamp;
        balanceOfId[lastTokenId] = _tokenMinted;
        totalXINTX += _tokenMinted;

        totalWeight += _tokenMinted;
        _lastWeightOfTokenId[lastTokenId] = _tokenMinted;

        emit Mint (_from, _to, lastTokenId, _tokenMinted, _intxAmount, totalXINTX, totalWeight);

        return lastTokenId;

    }

    function _unstake( uint _tokenId ) internal nonReentrant {
        require(_exists(_tokenId), "This position doesn't exist.");
        address _owner = _ownerOf(_tokenId);
        require(_owner == _msgSender(), "Not your xINTX NFT.");
        
        
        uint _amount = balanceOfId[_tokenId];

        uint _weight = _amount * _boostPercentageOf(_tokenId) / P;
        uint _exchangeRate = _exchangeRateInternal();
        uint _intxAmount = (_amount * _exchangeRate / P);
        uint _intxAmountPenalization = _intxAmount * _penaltyPercentageOf(_tokenId) / P ;
        uint _intxAmountOut = _intxAmount - _intxAmountPenalization;


        delete loyalSince[_tokenId];
        delete balanceOfId[_tokenId];
        delete _lastWeightOfTokenId[_tokenId];
        delete _rewardPerWeightPaid[_tokenId];
        if ( _rewards[_tokenId] > 0 ) {
            pendingRewards[_owner] += _rewards[_tokenId];
        }
        delete _rewards[_tokenId];
        _burn( _tokenId );


        totalXINTX -= _amount;
        INTX.transfer( _owner, _intxAmountOut);
        totalWeight -= _weight;

        emit Burn (_owner, _tokenId, _amount,  _intxAmountOut, _intxAmountPenalization, totalXINTX);
    }

    function _split( uint _tokenId, uint[] calldata _weights ) internal nonReentrant {
        require(_exists(_tokenId), "This position doesn't exist.");
        address _owner = _ownerOf(_tokenId);
        require(_owner == _msgSender(), "Not your xINTX NFT.");
        uint len = _weights.length;
        require(len > 1, "You can't split this XINTX less than 2 times");
        require(len <= 10, "You can't split this XINTX more than 10 times");
        

        uint _totalWeightSplit = 0;
        uint _originalBalance = balanceOfId[_tokenId];
        uint _originalLoyal = loyalSince[_tokenId];

        for (uint i; i < len; i++) {
            _totalWeightSplit +=_weights[i];
        }

        for (uint i; i < len; i++) {

            uint splitAmount = (_weights[i] * _originalBalance) / _totalWeightSplit;
            
            require(splitAmount > 0, "Can't split 0 xINTX." );

            lastTokenId++;
            _mint(_owner, lastTokenId);
            
            loyalSince[lastTokenId] = _originalLoyal;
            balanceOfId[lastTokenId] = splitAmount;
            
            _lastWeightOfTokenId[lastTokenId] = splitAmount * _boostPercentageOf(lastTokenId) / P;

            emit Split(_owner, _tokenId, lastTokenId, splitAmount);
        }

        delete loyalSince[_tokenId];
        delete balanceOfId[_tokenId];
        delete _lastWeightOfTokenId[_tokenId];
        delete _rewardPerWeightPaid[_tokenId];
        if ( _rewards[_tokenId] > 0 ) {
            pendingRewards[_owner] += _rewards[_tokenId];
        }
        delete _rewards[_tokenId];
        _burn( _tokenId );

    }


    function _merge( uint _tokenFrom, uint _tokenTo ) internal nonReentrant {
        require(_exists(_tokenFrom), "This position doesn't exist.");
        require(_exists(_tokenTo), "This position doesn't exist.");
        address _owner = _ownerOf(_tokenFrom);
        require(_owner == _msgSender(), "Not your xINTX NFT.");
        require(_owner == _ownerOf(_tokenTo), "Not your xINTX NFT.");

        uint _balanceFrom = balanceOfId[_tokenFrom];
        uint _loyalFrom = block.timestamp - loyalSince[_tokenFrom];

        uint _balanceTo = balanceOfId[_tokenTo];
        uint _loyalTo = block.timestamp - loyalSince[_tokenTo];

        uint _balanceNew = _balanceFrom + _balanceTo;
        require(_balanceNew > 0, "Can't make a position with 0 xINTX." );
        uint _loyalNew = (_loyalFrom * _balanceFrom / _balanceNew) + (_loyalTo * _balanceTo / _balanceNew);
        uint _newWeight = _balanceNew * _boostPercentageOf(_tokenTo) / P;
        

        balanceOfId[_tokenTo] = _balanceNew;
        loyalSince[_tokenTo] = block.timestamp - _loyalNew;
        _lastWeightOfTokenId[_tokenTo] = _newWeight;


        delete loyalSince[_tokenFrom];
        delete balanceOfId[_tokenFrom];
        delete _lastWeightOfTokenId[_tokenFrom];
        delete _rewardPerWeightPaid[_tokenFrom];
        if ( _rewards[_tokenFrom] > 0 ) {
            pendingRewards[_owner] += _rewards[_tokenFrom];
        }
        delete _rewards[_tokenFrom];
        _burn( _tokenFrom );


        emit Merge (_owner, _tokenFrom, _tokenTo, _balanceNew, block.timestamp - _loyalNew);
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    REWARDS CALCULATION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    /**
     * @dev Receives reward in USDC and makes calculations for the distribution
     * @param _rewardAmount the amount of USDC that will be distributed
     */
    function notifyReward( uint _rewardAmount ) external nonReentrant {
        rewardToken.transferFrom( _msgSender(), address(this), _rewardAmount);
        //_rewardAmount = _rewardAmount * P;

        if (block.timestamp >= periodFinish) {
            rewardRate = _rewardAmount / DURATION;
        } else {
            uint remaining = periodFinish - block.timestamp;
            uint leftover = remaining * rewardRate;
            rewardRate = (_rewardAmount + leftover) / DURATION;
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.

        //uint balance = rewardToken.balanceOf(address(this)) * P;
        uint balance = rewardToken.balanceOf(address(this));
        require(rewardRate <= balance / DURATION, "Provided reward too high");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + DURATION;
        emit RewardAdded(_rewardAmount/P);
    }

    ///@dev last time reward
    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, periodFinish);
    }

    function _updateReward(uint _tokenId) private {
        rewardPerWeightStored = rewardPerWeight();
        lastUpdateTime = lastTimeRewardApplicable();
        if (_tokenId != 0) {
            _rewards[_tokenId] = earned(_tokenId);

            uint _newWeight = balanceOfId[_tokenId] * _boostPercentageOf(_tokenId) / P;
            totalWeight -= _lastWeightOfTokenId[_tokenId] + _newWeight;

            _lastWeightOfTokenId[_tokenId] = _newWeight;
            _rewardPerWeightPaid[_tokenId] = rewardPerWeightStored;
        }
    }

    ///@notice  reward for a single weight
    function rewardPerWeight() public view returns (uint) {	
        if (totalWeight == 0) {	
            return rewardPerWeightStored;	
        } else {
            require(totalWeight > 0, "Incorrect weight");	
            
            //time past without reward
            uint _timeDiff = lastTimeRewardApplicable() - lastUpdateTime;
            return rewardPerWeightStored + ( _timeDiff * rewardRate * 1e18 / totalWeight );	
        }	
    }

    ///@notice earned rewards for nft
    function earned(uint _tokenId) public view returns (uint) {
        uint currentTokenWeight = balanceOfId[_tokenId] * _boostPercentageOf(_tokenId) / P;
        uint averageTokenWeight = ( _lastWeightOfTokenId[_tokenId] + currentTokenWeight) / 2;


        return
            ((averageTokenWeight * (rewardPerWeight() - _rewardPerWeightPaid[_tokenId]) ) / 1e18) +
            _rewards[_tokenId];
    }
}