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

    uint public constant DURATION = 1 weeks;
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
    event Claim( address indexed owner, uint amountOut, uint[] indexed tokenIds);

    struct PositionInfo {
        uint tokenId;
        address owner;
        uint balanceOfId;
        uint amountStakedOf;
        uint withdrawableAmountOf;
        uint loyalSince;
        uint boostPercentageOf;
        uint penaltyPercentageOf;
        uint penaltyAmountOf;
        uint pendingReward;
    }


    constructor () { _disableInitializers(); }

    function initialize ( address _intx, address _usdc ) public initializer {
        __ReentrancyGuard_init();
        __ERC721_init( "Staked INTX", "XINTX" );
        __Ownable_init();

        INTX = IERC20(_intx);
        rewardToken = IERC20(_usdc);

        loyaltyDuration = 16 weeks;         // 16 weeks
        maxLoyaltyBoost = 25 * 1e17;        // 2.5x
        maxPenalty = 25 * 1e16;             // 25%
        minPenalty = 5 * 1e15;              // 0.5%

    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                        EXTERNAL VIEW FUNCTIONS, POSITION INFO
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */
    
    function currentExchangeRate() external view returns(uint _exchangeRate) {
        _exchangeRate = _exchangeRateInternal();
    }
    
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

    function tokensOfOwner (address _owner) external view returns (uint[] memory ids) {
        uint len = balanceOf(_owner);
        ids = new uint[](len);
        for (uint i = 0; i < len; i++) {
            ids[i] = tokenOfOwnerByIndex(_owner, i);
        }
    }

    function getPositionInfo (uint _tokenId) external view returns (PositionInfo memory _positionInfo) {
        _positionInfo = _getPositionInfo(_tokenId);
    }

    function getPositionInfo (uint[] calldata _tokenId) external view returns (PositionInfo[] memory _positionInfo) {
        uint len = _tokenId.length;
        _positionInfo = new  PositionInfo[](len);
        for ( uint i; i < len; i++ ) {
            _positionInfo[i] = _getPositionInfo(_tokenId[i]);
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
     * @dev gives all the important info.
     * @param _tokenId the tokenId of the position.
     */
    function _getPositionInfo( uint _tokenId ) internal view returns(PositionInfo memory positionInfo) {

        uint _amount = _amountStakedOf(_tokenId);
        uint _penalty = _penaltyPercentageOf(_tokenId);

        positionInfo.tokenId = _tokenId;
        positionInfo.owner = _ownerOf(_tokenId);
        positionInfo.balanceOfId = balanceOfId[_tokenId];
        positionInfo.amountStakedOf= _amount;
        positionInfo.withdrawableAmountOf = _amount - (_amount * _penalty / P);
        positionInfo.loyalSince = loyalSince[_tokenId];
        positionInfo.boostPercentageOf = _boostPercentageOf( _tokenId );
        positionInfo.penaltyPercentageOf = _penalty;
        positionInfo.penaltyAmountOf = (_amount * _penalty / P);
        positionInfo.pendingReward = _rewards[_tokenId];
    }

    /**
     * @dev Calculates the boost percentage of a position.
     * @param _tokenId the tokenId of the position.
     */
    function _boostPercentageOf( uint _tokenId ) internal view returns(uint boostPercentage) {
        uint _timestamp = loyalSince[_tokenId];
        
        if ( _timestamp == 0 ) return 0;

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

        if ( _timestamp == 0 ) return 0;

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

    function unstake(uint _tokenId) external returns(uint _intxAmountOut) {
        _intxAmountOut = _unstake( _tokenId );
    }

    function split(uint _tokenId, uint[] calldata _splitWeights) external returns ( uint[] memory _tokenIds) {
        _tokenIds = _split( _tokenId, _splitWeights);
    }

    function merge(uint _tokenFrom, uint tokenTo) external {
        _merge(_tokenFrom, tokenTo);
    }

    function add(uint _intxAmount, uint tokenTo) external {
        uint _tokenFrom = _stake( _msgSender(), _msgSender(), _intxAmount );
        _merge(_tokenFrom, tokenTo);
    }

    function unstakePartially(uint _tokenId, uint _xIntxAmountWithdraw) external returns(uint _intxAmountOut, uint _newTokenId) {

        uint _balance = balanceOfId[_tokenId];
        require(_balance > _xIntxAmountWithdraw, "You can't partially withdraw more than you own");

        uint[] memory _splitWeights = new uint[](2);
        _splitWeights[0] = _xIntxAmountWithdraw;
        _splitWeights[1] = _balance - _xIntxAmountWithdraw;

        uint[] memory _tokenIds = _split( _tokenId, _splitWeights);

        _intxAmountOut = _unstake( _tokenIds[0] );
        _newTokenId = _tokenIds[1];

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
        _updateReward(_tokenId);
        
        uint _tokenMinted = _intxAmount * P / _exchangeRate;
        loyalSince[lastTokenId] = block.timestamp;
        balanceOfId[lastTokenId] = _tokenMinted;
        totalXINTX += _tokenMinted;

        totalWeight += _tokenMinted;
        _lastWeightOfTokenId[lastTokenId] = _tokenMinted;

        emit Mint (_from, _to, lastTokenId, _tokenMinted, _intxAmount, totalXINTX, totalWeight);

        return lastTokenId;

    }

    function _unstake( uint _tokenId ) internal nonReentrant returns( uint _intxAmountOut) {
        require(_exists(_tokenId), "This position doesn't exist.");
        address _owner = _ownerOf(_tokenId);
        require(_owner == _msgSender(), "Not your xINTX NFT.");
        
        _updateReward(_tokenId);
        
        uint _amount = balanceOfId[_tokenId];

        uint _weight = _amount * _boostPercentageOf(_tokenId) / P;
        uint _exchangeRate = _exchangeRateInternal();
        uint _intxAmount = (_amount * _exchangeRate / P);
        uint _intxAmountPenalization = _intxAmount * _penaltyPercentageOf(_tokenId) / P ;
        _intxAmountOut = _intxAmount - _intxAmountPenalization;


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
        totalWeight -= _weight;
        INTX.transfer( _owner, _intxAmountOut);

        emit Burn (_owner, _tokenId, _amount,  _intxAmountOut, _intxAmountPenalization, totalXINTX);
    }

    function _split( uint _tokenId, uint[] memory _splitWeights ) internal nonReentrant returns( uint[] memory _tokenIds ) {
        require(_exists(_tokenId), "This position doesn't exist.");
        address _owner = _ownerOf(_tokenId);
        require(_owner == _msgSender(), "Not your xINTX NFT.");
        uint len = _splitWeights.length;
        require(len > 1, "You can't split this XINTX less than 2 times");
        require(len <= 10, "You can't split this XINTX more than 10 times");
        _tokenIds = new uint[](len);
        _updateReward(_tokenId);

        uint _totalWeightSplit = 0;
        uint _originalBalance = balanceOfId[_tokenId];
        uint _originalLoyal = loyalSince[_tokenId];
        uint _originalRewardPerWeightPaid = _rewardPerWeightPaid[_tokenId];

        totalXINTX -= _originalBalance;
        totalWeight -= _lastWeightOfTokenId[_tokenId];

        for (uint i; i < len; i++) {
            _totalWeightSplit += _splitWeights[i];
        }

        for (uint i; i < len; i++) {

            uint splitAmount = (_splitWeights[i] * _originalBalance) / _totalWeightSplit;
            
            require(splitAmount > 0, "Can't split 0 xINTX." );

            lastTokenId++;
            _mint(_owner, lastTokenId);
            _tokenIds[i] = lastTokenId;
            
            loyalSince[lastTokenId] = _originalLoyal;
            balanceOfId[lastTokenId] = splitAmount;
            
            uint _lastWeight = splitAmount * _boostPercentageOf(lastTokenId) / P;
            _lastWeightOfTokenId[lastTokenId] = _lastWeight;
            _rewardPerWeightPaid[lastTokenId] = _originalRewardPerWeightPaid;

            totalXINTX += splitAmount;
            totalWeight += _lastWeight;

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
        require(_owner == _msgSender(), "From NFT isn't your xINTX NFT.");
        require(_owner == _ownerOf(_tokenTo), "To NFT isn't xINTX NFT.");
        _updateReward(_tokenFrom);
        _updateReward(_tokenTo);

        uint _balanceFrom = balanceOfId[_tokenFrom];
        uint _loyalFrom = block.timestamp - loyalSince[_tokenFrom];

        uint _balanceTo = balanceOfId[_tokenTo];
        uint _loyalTo = block.timestamp - loyalSince[_tokenTo];

        uint _balanceNew = _balanceFrom + _balanceTo;
        require(_balanceNew > 0, "Can't make a position with 0 xINTX." );
        uint _loyalNew = (_loyalFrom * _balanceFrom / _balanceNew) + (_loyalTo * _balanceTo / _balanceNew);
        

        balanceOfId[_tokenTo] = _balanceNew;
        loyalSince[_tokenTo] = block.timestamp - _loyalNew;

        uint _newWeight = _balanceNew * _boostPercentageOf(_tokenTo) / P;
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
    function notifyReward( uint _rewardAmount ) external nonReentrant onlyOwner{
        rewardToken.transferFrom( _msgSender(), address(this), _rewardAmount);
        _rewardAmount = _rewardAmount * P;

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
        uint balance = rewardToken.balanceOf(address(this)) * P;
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

    function claim(uint[] calldata _tokenIds) external {

        uint len = _tokenIds.length;
        uint _tokenId;
        address _owner;
        uint _amountOut = pendingRewards[_owner];

        for (uint i; i < len; i++ ) {
            _tokenId = _tokenIds[i];
            require(_exists(_tokenId), "This position doesn't exist.");

            _owner = _ownerOf(_tokenId);
            require(_owner == _msgSender(), "You are not the owner of this position.");

            _updateReward(_tokenId);

            _amountOut += _rewards[_tokenId];
            _rewards[_tokenId] = 0;

        }

        pendingRewards[_owner] = 0;

        rewardToken.transfer( _owner, _amountOut/P);     

        emit Claim( _owner, _amountOut, _tokenIds);
    }

    function updateWeights( uint[] calldata _tokenIds ) external {
        uint len = _tokenIds.length;

        for ( uint i; i < len; i++ ) {
            _updateReward(_tokenIds[i]);
        }
    }
}