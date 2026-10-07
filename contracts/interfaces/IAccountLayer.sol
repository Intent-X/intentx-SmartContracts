// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

interface IAccountLayer {
	/// @notice Owner of a sub-account, virtual account or legacy MultiAccount account (address(0) if unknown)
	function ownerOf(address account) external view returns (address);
}
