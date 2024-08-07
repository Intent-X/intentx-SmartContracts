// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract IntentXMinigame is OwnableUpgradeable {
    using ECDSA for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Constants and state variables
    address public intentxTrustedAddress; // IntentX Trusted Address
    uint public startTimestamp;
    uint public totalReward;

    mapping(address => uint256) public claimed; // Mapping of user's claimed balance per day. claimed[user][day] = amount

    // Events
    event Reward(uint256 timestamp, uint256 amount);
    event Claim(address indexed user, uint256 timestamp, uint256 amount);
    event SetIntentXTrustedAddress(address indexed intentxTrustedAddress);

    // Errors

    error DayNotFinished();
    error InvalidSignature();

    /// @notice Initialize the contract
    function initialize(
        address _intentxTrustedAddress
    ) public initializer {
        __Ownable_init();

        intentxTrustedAddress = _intentxTrustedAddress;
        startTimestamp = block.timestamp;

        emit SetIntentXTrustedAddress(_intentxTrustedAddress);
    }

    /// @notice Set the reward token
    /// @param _intentxTrustedAddress address of the new IntentX Trusted Backend
    function setIntentxTrustedAddress(address _intentxTrustedAddress) external onlyOwner() {
        intentxTrustedAddress = _intentxTrustedAddress;
        emit SetIntentXTrustedAddress(_intentxTrustedAddress);
    }

    /// @notice Fill reward for a given day from the token contract
    /// @param _amount amount of reward to fill
    function fill(uint256 _amount) external payable {
        require(_amount == msg.value, "Not enough amount sent");
        totalReward += _amount;
        emit Reward(block.timestamp, _amount);
    }

    function claim(
        address payable _user,
        uint256 _amountMnt,
        uint256 _timestamp,
        bytes memory signature
    ) external {
        require(block.timestamp >= startTimestamp, "NOT STARTED");
        require( msg.sender == _user, "Not your claim");
        require( intentxTrustedAddress != address(0), "IntentX Trusted Address not set yet.");

        if ( _amountMnt > claimed[msg.sender] ) {
            
            bytes32 messageHash = getMessageHash( _user, _amountMnt, _timestamp);
            bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

            require( recoverSigner(ethSignedMessageHash, signature) == intentxTrustedAddress, "Signer =! Trusted. ");
            
            uint256 withdrawableAmount = _amountMnt - claimed[msg.sender];
            claimed[msg.sender] = _amountMnt;

            bool success = _user.send(withdrawableAmount);
            require(success, "MNT Transfer failed");

            emit Claim(msg.sender, block.timestamp , withdrawableAmount);
        }
    }

    function getMessageHash(
        address _user,
        uint _amountIntentX,
        uint _timestamp
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _amountIntentX, _timestamp));
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