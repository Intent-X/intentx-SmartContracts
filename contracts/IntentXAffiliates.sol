// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.18;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract IntentXAffiliates is OwnableUpgradeable {

    using SafeERC20 for IERC20;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20 public usdt;

    // Constants and state variables
    address public intentxTrustedAddress; // IntentX Trusted Address
    uint public totalReward;

    mapping(address => uint256) public claimed; // Mapping of user's claimed balance.

    // Events
    event Reward(uint256 timestamp, uint256 amount);
    event Claim(address indexed user, uint256 timestamp, uint256 amount);
    event SetIntentXTrustedAddress(address indexed intentxTrustedAddress);

    // Errors

    error DayNotFinished();
    error InvalidSignature();

    /// @notice Initialize the contract
    function initialize(
        address _intentxTrustedAddress,
        address _usdt
    ) public initializer {
        __Ownable_init();

        intentxTrustedAddress = _intentxTrustedAddress;

        usdt = IERC20(_usdt);

        emit SetIntentXTrustedAddress(_intentxTrustedAddress);
    }

    function getClaimedBalances( address[] calldata addresses ) external view returns( uint[] memory claimedAmounts ) {
        uint len = addresses.length;
        claimedAmounts = new uint[](len);

        for ( uint i = 0; i < len; i++ ) {
            claimedAmounts[i] = claimed[ addresses[i] ];
        }
    }

    /// @notice Set the reward token
    /// @param _intentxTrustedAddress address of the new IntentX Trusted Backend
    function setIntentxTrustedAddress(address _intentxTrustedAddress) external onlyOwner() {
        intentxTrustedAddress = _intentxTrustedAddress;
        emit SetIntentXTrustedAddress(_intentxTrustedAddress);
    }


    function fill(uint256 _amount) external {
        usdt.safeTransferFrom(_msgSender(), address(this), _amount);
        totalReward += _amount;
        emit Reward(block.timestamp, _amount);
    }

    function claim(
        address payable _user,
        uint256 _amountUsdt,
        uint256 _timestamp,
        bytes memory signature
    ) external {
        require( msg.sender == _user, "Not your claim");
        require( intentxTrustedAddress != address(0), "IntentX Trusted Address not set yet.");

        if ( _amountUsdt > claimed[msg.sender] ) {
            
            bytes32 messageHash = getMessageHash( _user, _amountUsdt, _timestamp);
            bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

            require( recoverSigner(ethSignedMessageHash, signature) == intentxTrustedAddress, "Signer =! Trusted. ");
            
            uint256 withdrawableAmount = _amountUsdt - claimed[msg.sender];
            claimed[msg.sender] = _amountUsdt;

            if ( withdrawableAmount > 0) {
                usdt.safeTransfer(_msgSender(), withdrawableAmount);
                emit Claim(msg.sender, block.timestamp , withdrawableAmount);
            }
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