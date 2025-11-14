// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.18;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CarbonFeeRebate is OwnableUpgradeable {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // Constants and state variables
    address public carbonTrustedAddress; // Carbon Trusted Address
    address public rebateToken; // Carbon Trusted Address
    uint public totalReward;

    mapping(address => uint256) public claimed; // Mapping of user's claimed balance.

    // Events
    event Reward(uint256 timestamp, uint256 amount);
    event Claim(address indexed user, uint256 timestamp, uint256 amount);
    event SetCarbonTrustedAddress(address indexed carbonTrustedAddress);

    // Errors

    error DayNotFinished();
    error InvalidSignature();

    /// @notice Initialize the contract
    function initialize(
        address _carbonTrustedAddress,
        address _rebateToken
    ) public initializer {
        __Ownable_init();
        

        carbonTrustedAddress = _carbonTrustedAddress;
        rebateToken = _rebateToken;

        emit SetCarbonTrustedAddress(_carbonTrustedAddress);
    }

    function getClaimedBalances( address[] calldata addresses ) external view returns( uint[] memory claimedAmounts ) {
        uint len = addresses.length;
        claimedAmounts = new uint[](len);

        for ( uint i = 0; i < len; i++ ) {
            claimedAmounts[i] = claimed[ addresses[i] ];
        }
    }

    /// @notice Set the reward token
    /// @param _carbonTrustedAddress address of the new Carbon Trusted Backend
    function setCarbonTrustedAddress(address _carbonTrustedAddress) external onlyOwner() {
        carbonTrustedAddress = _carbonTrustedAddress;
        emit SetCarbonTrustedAddress(_carbonTrustedAddress);
    }

    /// @notice Fill reward for a given day from the token contract
    /// @param _amount amount of reward to fill
    function fill(uint256 _amount) external payable {
        IERC20(rebateToken).transferFrom(msg.sender, address(this), _amount);
        totalReward += _amount;
        emit Reward(block.timestamp, _amount);
    }

    function claim(
        address _user,
        uint256 _amountRebate,
        uint256 _timestamp,
        bytes memory signature
    ) external {
        require( msg.sender == _user, "Not your claim");
        require( carbonTrustedAddress != address(0), "Carbon Trusted Address not set yet.");

        if ( _amountRebate > claimed[msg.sender] ) {
            
            bytes32 messageHash = getMessageHash( _user, _amountRebate, _timestamp);
            bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

            require( recoverSigner(ethSignedMessageHash, signature) == carbonTrustedAddress, "Signer =! Trusted. ");
            
            uint256 withdrawableAmount = _amountRebate - claimed[msg.sender];
            claimed[msg.sender] = _amountRebate;

            IERC20(rebateToken).transfer(_user, withdrawableAmount);

            emit Claim(msg.sender, block.timestamp , withdrawableAmount);
        }
    }

    function getMessageHash(
        address _user,
        uint _amountCarbon,
        uint _timestamp
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _amountCarbon, _timestamp));
    }

    function getEthSignedMessageHash(bytes32 _messageHash)
        public
        pure
        returns (bytes32)
    {
        return
            keccak256(
                abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
            );
    }


    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature)
        public
        pure
        returns (address)
    {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig)
        public
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

}