# intentx-SmartContracts

Solidity contracts for the IntentX / Carbon stack on top of the SYMM (Symmio) perps protocol. It holds the user-side account contracts (MultiAccount and its PartyA sub-accounts), the Nox solver-side contracts (PartyB, on-chain vault, rebalancer) and the Carbon fee-rebate contract. Deployments target Arbitrum One, Mantle and Base; compiled Hardhat `artifacts/` are committed alongside the sources.

## How it works

`contracts/` contains:

- `MultiAccount.sol` — upgradeable factory that creates per-user `SymmioPartyA` accounts, tracks ownership, and lets an account owner delegate function selectors on a target contract (SYMM Core BUSL-1.1 licensed).
- `SymmioPartyA.sol` — minimal account contract; only the `MULTIACCOUNT_ROLE` may forward `_call` payloads to the Symmio diamond.
- `SymmExecutorUpgradeable.sol` — keeper executor: whitelisted keepers call `_call` / `_call2` on a MultiAccount on behalf of users who delegated access (used for keeper-driven flows such as SL/TP).
- `CarbonFeeRebate.sol` — owner-initialized rebate pool. A trusted Carbon backend signs `(user, amount)` claims; `fill` tops up the pool and `claim` verifies the ECDSA signature and pays out.
- `TestToken.sol` — ERC20 for tests.
- `interfaces/` — `IMultiAccount`, `IOnChainSymmioVault`, `ISymmio`, `ISymmioPartyA`.
- `solver/` — Nox (PartyB / hedger) side:
  - `SymmioPartyB.sol` — UUPS PartyB contract with role-gated `_call` batches against Symmio, restricted selectors, multicast whitelist, ERC-1271 signature support and an `ADLSkip` event for failed `adlClose` attempts.
  - `NoxSolver.sol` (`NoxPartyB`) — earlier PartyB variant with manager/executor/trusted roles and withdrawal addresses.
  - `OnChainSymmioVaultV2.sol` — deposit vault with signed (EIP-712) withdraw requests, a withdrawal period, deposit limit, and `BALANCER_ROLE` / `SETTER_ROLE` / pauser roles; the balancer is set in `initialize`.
  - `TargetRebalancer.sol` — owner-registered PartyBs can `withdrawTo` a target; owner can run an instant rebalance by temporarily changing the Symmio deallocate cooldown.
  - `library/MuonStorage.sol` — Muon signature storage structs.

`hardhat.config.js` compiles with solc 0.8.18 and 0.8.28 (optimizer, 2048 runs), uses `@openzeppelin/hardhat-upgrades` for proxies, and configures Etherscan v2 verification for Arbitrum and Base. `scripts/` and `contracts/apis/` are gitignored, so deploy scripts are not in the repo.

## Running it

npm (no lockfile is committed; `package-lock.json` is gitignored).

```bash
npm install
npx hardhat compile
npx hardhat test
npx hardhat verify --network arbitrumOne <address>
```

Default network is `arbitrumOne`; `mantle` and `base` are also configured.

## Configuration

No `.env.example`. Names read in `hardhat.config.js` via `dotenv`:

- `DEPLOYER_PRIVATE_KEY`
- `ETHERSCAN_API_KEY`
- `ARBITRUM_ONE_RPC_URL`
- `MANTLE_RPC_URL`
- `BASE_RPC_URL`

## Related repos

- `solver-research` — Nox solver that operates `SymmioPartyB` / the vault on-chain.
- `sltp-system-fork` — stop-loss / take-profit keeper that drives `SymmExecutorUpgradeable`.
- `carbon-fee-rebate` — backend that signs claims for `CarbonFeeRebate`.
- `carbon` — Carbon frontend that creates and uses MultiAccount sub-accounts.
- `carbon-aa-wallet-registration-backend` — sub-account registration service.

## Status

Public repo. Last commit 2026-04-22 ("Vault: Add balancer at initializer"); active but low-frequency. OpenZeppelin 4.9 and Hardhat 2.26 are current for that line. The committed `artifacts/` directory should be regenerated rather than hand-edited.
