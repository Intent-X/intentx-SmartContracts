// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/IERC20Upgradeable.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

interface ISymmio {
	function isCallFromInstantLayer() external view returns (bool);
	function adlClose(uint256 quoteId, uint256 amount, uint256 price) external;
}

/// @notice PartyB (solver/hedger) contract that manages positions and executes calls against Symmio
contract SymmioPartyB is Initializable, PausableUpgradeable, AccessControlUpgradeable, UUPSUpgradeable, IERC1271 {
	bytes32 public constant TRUSTED_ROLE = keccak256("TRUSTED_ROLE");
	bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
	bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
	bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");

	// Storage layout matches v0.8.4 SymmioPartyB for upgrade compatibility
	address public symmioAddress; // slot N+0
	mapping(bytes4 => bool) public restrictedSelectors; // slot N+1
	mapping(address => bool) public multicastWhitelist; // slot N+2
	address public signer; // slot N+3 (was _guardCounter in v0.8.4, always 0 after tx)

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/// @notice Initializes the contract with the provided admin and Symmio address
	/// @param admin The address of the default admin role
	/// @param symmioAddress_ The address of the Symmio contract
	function initialize(address admin, address multisig_, address symmioAddress_) public initializer {
		__Pausable_init();
		__AccessControl_init();
		__UUPSUpgradeable_init();

		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(DEFAULT_ADMIN_ROLE, multisig_);
		_grantRole(TRUSTED_ROLE, admin);
		_grantRole(MANAGER_ROLE, admin);
		symmioAddress = symmioAddress_;
	}

	function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

	/// @notice Emitted when an `adlClose` attempt reverts for a quote, including the raw revert data
	/// @dev The raw data is the ABI-encoded revert payload (e.g., `Error(string)` / `Panic(uint256)` / custom error)
	event ADLSkip(uint256 quoteId, uint256 amount, uint256 price, bytes revertData);

	/// @notice Emitted when the Symmio address is updated
	event SetSymmioAddress(address oldSymmioAddress, address newSymmioAddress);

	/// @notice Emitted when a restricted selector is set
	event SetRestrictedSelector(bytes4 selector, bool state);

	/// @notice Emitted when a multicast whitelist address is set
	event SetMulticastWhitelist(address addr, bool state);

	/// @notice Updates the address of the Symmio contract
	/// @param addr The new address of the Symmio contract
	function setSymmioAddress(address addr) external onlyRole(DEFAULT_ADMIN_ROLE) {
		emit SetSymmioAddress(symmioAddress, addr);
		symmioAddress = addr;
	}

	/// @notice Restricts or lifts restrictions on a selector for Party B
	/// @param selector The function selector to set the state for
	/// @param state The state to set for the selector
	function setRestrictedSelector(bytes4 selector, bool state) external onlyRole(DEFAULT_ADMIN_ROLE) {
		restrictedSelectors[selector] = state;
		emit SetRestrictedSelector(selector, state);
	}

	/// @notice Allows or disallows Party B to call a method from a specific contract
	/// @param addr The address to set the state for
	/// @param state The state to set for the address
	function setMulticastWhitelist(address addr, bool state) external onlyRole(MANAGER_ROLE) {
		require(addr != address(this), "SymmioPartyB: Invalid address");
		multicastWhitelist[addr] = state;
		emit SetMulticastWhitelist(addr, state);
	}

	/// @notice Approves an ERC20 token for spending by Symmio
	/// @param token The address of the ERC20 token
	/// @param amount The amount of tokens to approve
	function _approve(address token, uint256 amount) external onlyRole(TRUSTED_ROLE) whenNotPaused {
		require(IERC20Upgradeable(token).approve(symmioAddress, amount), "SymmioPartyB: Not approved");
	}

	/* ──────────────────────────────── ADL ──────────────────────────────── */

	/// @notice Best-effort ADL close for multiple quotes
	/// @dev For each index `i`, attempts `Symmio.adlClose(quoteIds[i], amounts[i], prices[i])`.
	///      Catches per-quote reverts, emits `ADLSkip`, and continues processing the remaining items.
	/// @param quoteIds Quote ids to ADL-close
	/// @param amounts Close amounts per quote (18-decimal precision)
	/// @param prices Execution prices per quote
	function adlClose(uint256[] calldata quoteIds, uint256[] calldata amounts, uint256[] calldata prices) external whenNotPaused {
		uint256 len = quoteIds.length;
		require(amounts.length == len && prices.length == len, "SymmioPartyB: Array length mismatch");
		require(symmioAddress != address(0), "SymmioPartyB: Invalid address");
		require(
			hasRole(MANAGER_ROLE, msg.sender) || hasRole(TRUSTED_ROLE, msg.sender) || ISymmio(symmioAddress).isCallFromInstantLayer(),
			"SymmioPartyB: Invalid access"
		);

		for (uint256 i = 0; i < len; i++) {
			try ISymmio(symmioAddress).adlClose(quoteIds[i], amounts[i], prices[i]) {} catch (bytes memory revertData) {
				emit ADLSkip(quoteIds[i], amounts[i], prices[i], revertData);
			}
		}
	}

	/// @notice Executes a call to a destination address with access control checks
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
					hasRole(MANAGER_ROLE, msg.sender) || hasRole(TRUSTED_ROLE, msg.sender) || ISymmio(symmioAddress).isCallFromInstantLayer(),
					"SymmioPartyB: Invalid access"
				);
			}
		} else {
			require(multicastWhitelist[destAddress], "SymmioPartyB: Destination address is not whitelisted");
			_checkRole(TRUSTED_ROLE, msg.sender);
		}

		(bool success, bytes memory resultData) = destAddress.call{ value: 0 }(callData);
		if (!success) {
			if (resultData.length == 0) revert("SymmioPartyB: Execution reverted");
			assembly {
				revert(add(resultData, 32), mload(resultData))
			}
		}
	}

	/// @notice Executes multiple calls to the Symmio contract
	/// @param _callDatas An array of call data to be used for the calls
	function _call(bytes[] calldata _callDatas) external whenNotPaused {
		for (uint8 i; i < _callDatas.length; i++) _executeCall(symmioAddress, _callDatas[i]);
	}

	/// @notice Executes multiple calls to specified destination addresses
	/// @param destAddresses An array of destination addresses to call
	/// @param _callDatas An array of call data to be used for the calls
	function _multicastCall(address[] calldata destAddresses, bytes[] calldata _callDatas) external whenNotPaused {
		require(destAddresses.length == _callDatas.length, "SymmioPartyB: Array length mismatch");

		for (uint8 i; i < _callDatas.length; i++) _executeCall(destAddresses[i], _callDatas[i]);
	}

	/// @notice Withdraws ERC20 tokens from the contract to the caller
	/// @param token The address of the ERC20 token
	/// @param amount The amount of tokens to withdraw
	function withdrawERC20(address token, uint256 amount) external onlyRole(MANAGER_ROLE) {
		require(IERC20Upgradeable(token).transfer(msg.sender, amount), "SymmioPartyB: Not transferred");
	}

	/// @notice Pauses the contract
	function pause() external onlyRole(PAUSER_ROLE) {
		_pause();
	}

	/// @notice Unpauses the contract
	function unpause() external onlyRole(UNPAUSER_ROLE) {
		_unpause();
	}

	/* ──────────────────── ERC-1271 Implementation ──────────────────── */

	/// @notice Sets the authorized signer for EIP-1271 signature verification
	/// @param _signer Address of the new authorized signer
	function setSigner(address _signer) external onlyRole(SETTER_ROLE) {
		signer = _signer;
	}

	/// @notice Verifies signature validity using the ERC-1271 standard
	/// @param hash Hash of the data that was signed
	/// @param signature Signature bytes to verify
	/// @return magicValue Magic value (0x1626ba7e) if valid, 0xffffffff otherwise
	function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue) {
		magicValue = SignatureChecker.isValidSignatureNow(signer, hash, signature) ? bytes4(0x1626ba7e) : bytes4(0xffffffff);
	}
}