// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import '@openzeppelin/contracts/access/Ownable2Step.sol';

interface SymmCore {
  function setDeallocateCooldown(uint256 deallocateCooldown) external;
  function coolDownsOfMA() external view returns (uint256 deallocateCooldown, uint256, uint256, uint256);
}

interface PartyB {
  function withdrawTo(address _to, uint256 _amount) external;
}

contract TargetRebalancer is Ownable2Step {
  SymmCore immutable symmio;

  // Mapping from partyB to targetAddress to amount
  mapping(address => mapping(address => uint256)) public withdrawalRequests;
  mapping(address => bool) public allowedPartyBs;

  constructor(address symmioAddress) Ownable(msg.sender) {
    symmio = SymmCore(symmioAddress);

    allowedPartyBs[0x939cA7B7DE3BE50b537BFB59586C20Cbe724570b] = true;
    allowedPartyBs[0xD984489f1DB22A0116A7aA493c4910fdA7C6328A] = true;
  }

  function registerPartyB(address partyB) external onlyOwner {
    allowedPartyBs[partyB] = true;
  }

  // Anyone can request a rebalance action
  function rebalance(address targetAddress, uint256 amount) external {
    require(allowedPartyBs[msg.sender], 'Not allowed to request rebalance!');

    withdrawalRequests[msg.sender][targetAddress] = amount;
  }

  // Only owner can execute a rebalance action
  // 1. First the action to be executed is verified against the request
  // 2. Then the cooldown is set to 0 on symmio contracts which requires a controller ROLE to be given to this contract
  // 3. Then the partyB contract is called to execute the withdrawal. The owner verified the code of this partyB
  // contract and can see that it does nothing malicious. Therefore the owner can trust that the symm system is not
  // hurt in any way. At the same time, the partyB contract can also reject the request if they wish to do so.
  // 4. Then the cooldown is set back to the original value.
  function executeInstantRebalance(address partyB, address targetAddress, uint256 amount) external onlyOwner {
    require(withdrawalRequests[partyB][targetAddress] == amount, 'Invalid request!');

    withdrawalRequests[partyB][targetAddress] = 0;

    (uint256 currentCooldown, , , ) = symmio.coolDownsOfMA();
    symmio.setDeallocateCooldown(0);
    PartyB(partyB).withdrawTo(targetAddress, amount);
    symmio.setDeallocateCooldown(currentCooldown);
  }
}