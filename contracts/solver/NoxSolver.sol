// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./ISymmioPartyA.sol";
import "./ISymmioDiamond.sol";
import "./library/MuonStorage.sol";
// ATTENTION: ONLY APPEND GLOBAL VARIABLES UPON UPGRADE

contract NoxPartyB is UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    address public symmioAddress;
    address private withdrawalAddress;
	address private ledgerMultiSigWithdrawalAddress;
	address private deploymentVariable;

	bytes32 public constant TRUSTED_ROLE = keccak256("TRUSTED_ROLE");
	bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

	mapping(bytes4 => bool) public restrictedSelectors;
	mapping(address => bool) public multicastWhitelist;

    constructor() {
        _disableInitializers();
    }

	function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

	/**
	 * @dev Initializes the contract with the provided admins, withdrawal address and Symmio address.
	 * @param admin The address of the admin / owner, only admin can upgrade contract.
	 * @param managers The managers can call all contract functions, including withdrawing funds.
	 * @param trusted The trusted addresses can call trading functionalities.
     * @param withdrawalAddress_ The address whitelisted for withdrawal of funds.
	 * @param symmioAddress_ The address of the Symmio contract.
	 */
	function initialize(address admin, address[] memory managers, address[] memory trusted, address withdrawalAddress_, address ledgerMultiSigWithdrawalAddress_, address symmioAddress_) public initializer {
        __UUPSUpgradeable_init();
		__Pausable_init();
		__AccessControl_init();

        symmioAddress = symmioAddress_;
        withdrawalAddress = withdrawalAddress_;
		ledgerMultiSigWithdrawalAddress = ledgerMultiSigWithdrawalAddress_;

		_grantRole(DEFAULT_ADMIN_ROLE, admin);

        for (uint8 i; i < managers.length; i++) {
            _grantRole(TRUSTED_ROLE, managers[i]);
            _grantRole(MANAGER_ROLE, managers[i]);
        }

		for (uint8 i; i < trusted.length; i++) {
            _grantRole(TRUSTED_ROLE, trusted[i]);
        }
	}

	/**
	 * @dev Emitted when the Symmio address is updated.
	 * @param oldSymmioAddress The address of the old Symmio contract.
	 * @param newSymmioAddress The address of the new Symmio contract.
	 */
	event SetSymmioAddress(address oldSymmioAddress, address newSymmioAddress);

	/**
	 * @dev Emitted when a restricted selector is set.
	 * @param selector The function selector.
	 * @param state The state of the selector.
	 */
	event SetRestrictedSelector(bytes4 selector, bool state);

	/**
	 * @dev Emitted when a multicast whitelist address is set.
	 * @param addr The address added to the whitelist.
	 * @param state The state of the whitelist address.
	 */
	event SetMulticastWhitelist(address addr, bool state);

	/**
	 * @dev Executes a call to a destination address with the provided call data.
	 * @param destAddress The destination address to call.
	 * @param callData The call data to be used for the call.
	 */
	function _executeCall(address destAddress, bytes memory callData) internal {
		require(destAddress != address(0), "SymmioPartyB: Invalid address");
		require(callData.length >= 4, "SymmioPartyB: Invalid call data");

		if (destAddress == symmioAddress) {
			bytes4 functionSelector;
			assembly {
				functionSelector := mload(add(callData, 0x20))
			}
			if (restrictedSelectors[functionSelector]) {
				_checkRole(MANAGER_ROLE, msg.sender);
			} else {
				require(
					hasRole(MANAGER_ROLE, msg.sender) || 
					hasRole(TRUSTED_ROLE, msg.sender) || 
					hasRole(EXECUTOR_ROLE, msg.sender), 
					"SymmioPartyB: Invalid access"
				);
			}
		} else {
			require(multicastWhitelist[destAddress], "SymmioPartyB: Destination address is not whitelisted");
			_checkRole(TRUSTED_ROLE, msg.sender);
		}

		 (bool success, bytes memory returndata) = destAddress.call{value: 0}(callData);

		if (!success) {
			if (returndata.length > 0) {
				// Reenviar literalmente el motivo de error del contrato destino
				assembly {
					let size := mload(returndata)
					revert(add(returndata, 32), size)
				}
			} else {
				revert("SymmioPartyB: Execution reverted");
			}
		}
	}

	/**
	 * @dev Executes multiple calls to the Symmio contract.
	 * @param _callDatas An array of call data to be used for the calls.
	 */
	function _call(bytes[] calldata _callDatas) external whenNotPaused{
		for (uint8 i; i < _callDatas.length; i++) _executeCall(symmioAddress, _callDatas[i]);
	}

	/**
	 * @dev Executes multiple calls to specified destination addresses.
	 * @param destAddresses An array of destination addresses to call.
	 * @param _callDatas An array of call data to be used for the calls.
	 */
	function _multicastCall(address[] calldata destAddresses, bytes[] calldata _callDatas) external whenNotPaused onlyRole(EXECUTOR_ROLE) {
		require(destAddresses.length == _callDatas.length, "SymmioPartyB: Array length mismatch");

		for (uint8 i; i < _callDatas.length; i++) _executeCall(destAddresses[i], _callDatas[i]);
	}

	/**
	 * @dev Approves an ERC20 token for spending by Symmio.
	 * @param token The address of the ERC20 token.
	 * @param amount The amount of tokens to approve.
	 */
	function _approve(address token, uint256 amount) external onlyRole(TRUSTED_ROLE) whenNotPaused {
		require(IERC20(token).approve(symmioAddress, amount), "SymmioPartyB: Not approved");
	}

	/**
	 * @dev Withdraws ERC20 tokens from the contract to the caller.
     * @param targetAddress The address to withdraw to.
	 * @param token The address of the ERC20 token.
	 * @param amount The amount of tokens to withdraw.
	 */
	function withdrawERC20(address targetAddress, address token, uint256 amount) external onlyRole(MANAGER_ROLE) {
        require(targetAddress == withdrawalAddress || targetAddress == ledgerMultiSigWithdrawalAddress, "Invalid target withdrawal Address!");
		require(IERC20(token).transfer(targetAddress, amount), "SymmioPartyB: Not transferred");
	}

	/**
	 * @dev Pauses the contract.
	 */
	function pause() external onlyRole(MANAGER_ROLE) {
		_pause();
	}

	/**
	 * @dev Unpauses the contract.
	 */
	function unpause() external onlyRole(MANAGER_ROLE) {
		_unpause();
	}

	/**
	 * @dev Updates the address of the Symmio contract.
	 * @param addr The new address of the Symmio contract.
	 */
	function setSymmioAddress(address addr) external onlyRole(MANAGER_ROLE) {
		emit SetSymmioAddress(symmioAddress, addr);
		symmioAddress = addr;
	}

	/**
	 * @dev Restricts or lifts restrictions on a selector for Party B..
	 * @param selector The function selector to set the state for.
	 * @param state The state to set for the selector.
	 */
	function setRestrictedSelector(bytes4 selector, bool state) external onlyRole(MANAGER_ROLE) {
		restrictedSelectors[selector] = state;
		emit SetRestrictedSelector(selector, state);
	}

	/**
	 * @dev Allows or disallows Party B to call a method from a specific contract.
	 * @param addr The address to set the state for.
	 * @param state The state to set for the address.
	 */
	function setMulticastWhitelist(address addr, bool state) external onlyRole(MANAGER_ROLE) {
		require(addr != address(this), "SymmioPartyB: Invalid address");
		multicastWhitelist[addr] = state;
		emit SetMulticastWhitelist(addr, state);
	}

	function grantTrustedRole(address addr) external onlyRole(MANAGER_ROLE) {
		_grantRole(TRUSTED_ROLE, addr);
	}

    // Instant Action Wrappers
    function sendAndLockInstantOpenPositionWithReserveVault(address multiAccount, address partyA, bytes[] memory sendQuoteCalldata, uint256 allocationAmount, SingleUpnlSig calldata sig) external onlyRole(EXECUTOR_ROLE) {
        ISymmioPartyA(multiAccount)._call(partyA, sendQuoteCalldata);
        uint256 quoteId = ISymmioDiamond(symmioAddress).getNextQuoteId();
        _allocateAndLockWithReserveVault(quoteId, partyA, allocationAmount, sig);
    }

    function _allocateAndLockWithReserveVault(uint256 quoteId, address partyA, uint256 allocationAmount, SingleUpnlSig calldata sig) internal virtual {
        if (allocationAmount > 0) {
            ISymmioDiamond(symmioAddress).withdrawFromReserveVault(allocationAmount);
            ISymmioDiamond(symmioAddress).allocateForPartyB(allocationAmount, partyA);
        }
        ISymmioDiamond(symmioAddress).lockQuote(quoteId, sig);
    }

    

}