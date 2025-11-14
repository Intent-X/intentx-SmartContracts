// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

interface MultiAccount {

    function delegatedAccesses( address account, address target, bytes4 selector ) external view returns ( bool );

    function _call ( address account, bytes[] memory _callDatas ) external;

}

contract SymmExecutorUpgradeable is OwnableUpgradeable, PausableUpgradeable {
    
    
    MultiAccount public multiAccount;
    bytes4 public constant requestToClosePositionSelector = bytes4(keccak256(bytes("requestToClosePosition(uint256,uint256,uint256,uint8,uint256)")));

    mapping( address => bool ) public isKeeper;


    event keeperAdded ( address indexed keeper );
    event keeperRemoved( address indexed keeper );
    event executed( address indexed keeper, address indexed account, bytes[] _callDatas);

    constructor() {
        _disableInitializers();
    }

    function initialize( address _multiAccount ) public initializer {
        __Ownable_init();
        __Pausable_init();

        multiAccount = MultiAccount(_multiAccount);
    }

    modifier onlyKeeper() {
        require( isKeeper[msg.sender], "This address isn't a keeper" );
        _;
    }

    function pauseExecution() external onlyOwner{
        _pause();
    }

    function unpauseExecution() external onlyOwner{
        _unpause();
    }

    function addKeeper( address _who ) external onlyOwner {
        require( !isKeeper[_who], "This address is already a keeper." );
        isKeeper[_who] = true;

        emit keeperAdded( _who );

    }

    function removeKeeper(address _who ) external onlyOwner {
        require( isKeeper[_who], "This address isn't a keeper." );
        isKeeper[_who] = false;

        emit keeperRemoved( _who );
    }

    function _call( address account, bytes[] memory _callDatas ) external onlyKeeper whenNotPaused {
        multiAccount._call( account, _callDatas );

        emit executed( _msgSender(), account, _callDatas);

    }

    function _call2( MultiAccount _multiAccount, address account, bytes[] memory _callDatas ) external onlyKeeper whenNotPaused {
        _multiAccount._call( account, _callDatas );

        emit executed( _msgSender(), account, _callDatas);

    }
    
    function hasDelegated( address account ) external view returns(bool) {
        return multiAccount.delegatedAccesses( account, address(this), requestToClosePositionSelector);
    }

    function hasDelegated( address account, bytes4 selector ) external view returns(bool) {
        return multiAccount.delegatedAccesses( account, address(this), selector);
    }

    function hasDelegated( address account, bytes4[] calldata selector ) external view returns(bool[] memory _hasDelegated ) {
        uint _len = selector.length;
        _hasDelegated = new bool[](_len);

        for (uint i = 0; i < _len; i++) {
            _hasDelegated[i] = multiAccount.delegatedAccesses( account, address(this), selector[i]);
        }
    }


}