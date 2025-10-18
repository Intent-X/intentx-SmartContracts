// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "./library/MuonStorage.sol";

interface ISymmioDiamond {
	function getNextQuoteId() external view returns (uint256);

	// Lock quote
	function lockQuote(uint256 quoteId, SingleUpnlSig memory upnlSig) external;

    // Allocations
    function allocateForPartyB(uint256 amount, address partyA) external;

	function deallocateForPartyB(uint256 amount, address partyA, SingleUpnlSig memory upnlSig) external;

	function transferAllocation(uint256 amount, address origin, address recipient, SingleUpnlSig memory upnlSig) external;

	function depositToReserveVault(uint256 amount, address partyB) external;

	function withdrawFromReserveVault(uint256 amount) external;
}