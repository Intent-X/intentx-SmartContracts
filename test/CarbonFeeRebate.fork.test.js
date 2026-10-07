const { expect } = require("chai");
const { ethers, network } = require("hardhat");
const {
  impersonateAccount,
  mine,
  setBalance,
} = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

// defaultNetwork is arbitrumOne: refuse to run anywhere but the local fork, or before() would deploy to mainnet.
if (network.name !== "hardhat") {
  throw new Error(
    `Run on the Arbitrum fork: npx hardhat test --network hardhat (got --network ${network.name})`
  );
}

// Upgrades the live proxy in place on a fork of Arbitrum and deposits into the live Symmio diamond,
// so a pass means the upgrade works against real state.
const PROXY = "0xaCfB4534b415f80B2697e6F1232c1B6F699AD496";
const PROXY_ADMIN = "0x325B3BD53cff3C8A164adEd416a715C48A160764";
const SYMMIO = "0x8F06459f184553e5d04F07F868720BDaCAB39395";
const ACCOUNT_MANAGER = "0x5560266516865cD55460f3aB94C61D78E48d3d92";
const USDC = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";

const IMPLEMENTATION_SLOT =
  "0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc";
// Initializable flags, Ownable._owner, carbonTrustedAddress, rebateToken, totalReward.
const STATE_SLOTS = [0n, 51n, 101n, 102n, 103n];

const USDC_DECIMALS_TO_18 = 10n ** 12n;
const usdc = (n) => BigInt(Math.round(n * 1e6));

const proxyAdminAbi = [
  "function owner() view returns (address)",
  "function upgradeAndCall(address proxy, address implementation, bytes data) payable",
];
const accountManagerAbi = [
  "function addAccount(string name) returns (address[])",
  "function getAccounts(address user, uint256 start, uint256 size) view returns ((address accountAddress, string name)[])",
];
const symmioAbi = ["function balanceOf(address user) view returns (uint256)"];
const erc20Abi = [
  "function balanceOf(address) view returns (uint256)",
  "function allowance(address owner, address spender) view returns (uint256)",
];

async function impersonate(address) {
  await impersonateAccount(address);
  await setBalance(address, 10n ** 18n);
  return ethers.getSigner(address);
}

const readSlot = (slot) => ethers.provider.getStorage(PROXY, slot);

describe("CarbonFeeRebate upgrade: claimAndDeposit", function () {
  this.timeout(600_000);

  const trustedSigner = ethers.Wallet.createRandom();
  const symmio = new ethers.Contract(SYMMIO, symmioAbi, ethers.provider);
  const usdcToken = new ethers.Contract(USDC, erc20Abi, ethers.provider);

  let rebate;
  let stateBefore;
  let newImplementation;
  let timestamp = 1_700_000_000;

  async function voucher(user, cumulativeAmount, signer = trustedSigner) {
    const ts = timestamp++;
    const hash = ethers.solidityPackedKeccak256(
      ["address", "uint256", "uint256"],
      [user, cumulativeAmount, ts]
    );
    return { ts, signature: await signer.signMessage(ethers.getBytes(hash)) };
  }

  async function newUserWithAccount() {
    const userAddress = ethers.Wallet.createRandom().address;
    const user = await impersonate(userAddress);
    const manager = new ethers.Contract(
      ACCOUNT_MANAGER,
      accountManagerAbi,
      user
    );
    await (await manager.addAccount("rebate-test")).wait();
    const [created] = await manager.getAccounts(userAddress, 0, 1);
    return { user, userAddress, account: created.accountAddress };
  }

  before(async function () {
    // Hardhat has no hardfork history for Arbitrum, so nothing can execute at the fork block itself
    // ("No known hardfork for execution on historical block"); a locally mined block runs on the local hardfork.
    await mine();
    stateBefore = await Promise.all(STATE_SLOTS.map(readSlot));

    const proxyAdmin = new ethers.Contract(
      PROXY_ADMIN,
      proxyAdminAbi,
      ethers.provider
    );
    const adminOwner = await impersonate(await proxyAdmin.owner());
    const implementation = await ethers.deployContract("CarbonFeeRebate");
    newImplementation = await implementation.getAddress();
    await (
      await proxyAdmin
        .connect(adminOwner)
        .upgradeAndCall(PROXY, newImplementation, "0x")
    ).wait();

    rebate = await ethers.getContractAt("CarbonFeeRebate", PROXY);
    const rebateOwner = await impersonate(await rebate.owner());
    await (
      await rebate
        .connect(rebateOwner)
        .setCarbonTrustedAddress(trustedSigner.address)
    ).wait();
  });

  it("points the proxy at the new implementation and keeps every existing storage value", async function () {
    const implSlot = await readSlot(IMPLEMENTATION_SLOT);
    expect(ethers.getAddress("0x" + implSlot.slice(26))).to.equal(
      newImplementation
    );

    const stateAfter = await Promise.all(STATE_SLOTS.map(readSlot));
    // Slot 101 (carbonTrustedAddress) is rotated to the test signer in before(); everything else is untouched.
    expect(stateAfter.filter((_, i) => STATE_SLOTS[i] !== 101n)).to.deep.equal(
      stateBefore.filter((_, i) => STATE_SLOTS[i] !== 101n)
    );
    expect(await rebate.rebateToken()).to.equal(USDC);
  });

  it("deposits the rebate into the caller's Symmio account instead of the wallet", async function () {
    const { user, userAddress, account } = await newUserWithAccount();
    const amount = usdc(5);
    const { ts, signature } = await voucher(userAddress, amount);

    const accountBefore = await symmio.balanceOf(account);
    const walletBefore = await usdcToken.balanceOf(userAddress);
    const rebateBefore = await usdcToken.balanceOf(PROXY);

    await expect(
      rebate
        .connect(user)
        .claimAndDeposit(userAddress, amount, ts, signature, account)
    )
      .to.emit(rebate, "Claim")
      .withArgs(userAddress, anyValue, amount);

    expect(await symmio.balanceOf(account)).to.equal(
      accountBefore + amount * USDC_DECIMALS_TO_18
    );
    expect(await usdcToken.balanceOf(userAddress)).to.equal(walletBefore);
    expect(await usdcToken.balanceOf(PROXY)).to.equal(rebateBefore - amount);
    expect(await rebate.claimed(userAddress)).to.equal(amount);
    expect(await usdcToken.allowance(PROXY, SYMMIO)).to.equal(0n);
  });

  it("does nothing when the same voucher is replayed", async function () {
    const { user, userAddress, account } = await newUserWithAccount();
    const amount = usdc(1);
    const { ts, signature } = await voucher(userAddress, amount);

    await (
      await rebate
        .connect(user)
        .claimAndDeposit(userAddress, amount, ts, signature, account)
    ).wait();
    const accountAfterFirst = await symmio.balanceOf(account);

    await expect(
      rebate
        .connect(user)
        .claimAndDeposit(userAddress, amount, ts, signature, account)
    ).not.to.emit(rebate, "Claim");
    expect(await symmio.balanceOf(account)).to.equal(accountAfterFirst);
    expect(await rebate.claimed(userAddress)).to.equal(amount);
  });

  it("shares the cumulative claimed amount with claim(), which still pays the wallet", async function () {
    const { user, userAddress, account } = await newUserWithAccount();

    const first = await voucher(userAddress, usdc(3));
    const walletBefore = await usdcToken.balanceOf(userAddress);
    await (
      await rebate
        .connect(user)
        .claim(userAddress, usdc(3), first.ts, first.signature)
    ).wait();
    expect(await usdcToken.balanceOf(userAddress)).to.equal(
      walletBefore + usdc(3)
    );

    const second = await voucher(userAddress, usdc(5));
    const accountBefore = await symmio.balanceOf(account);
    await (
      await rebate
        .connect(user)
        .claimAndDeposit(
          userAddress,
          usdc(5),
          second.ts,
          second.signature,
          account
        )
    ).wait();

    expect(await symmio.balanceOf(account)).to.equal(
      accountBefore + usdc(2) * USDC_DECIMALS_TO_18
    );
    expect(await rebate.claimed(userAddress)).to.equal(usdc(5));
  });

  it("rejects an account owned by someone else", async function () {
    const { user, userAddress } = await newUserWithAccount();
    const { account: otherAccount } = await newUserWithAccount();
    const { ts, signature } = await voucher(userAddress, usdc(1));

    await expect(
      rebate
        .connect(user)
        .claimAndDeposit(userAddress, usdc(1), ts, signature, otherAccount)
    ).to.be.revertedWith("Not your account");
  });

  it("rejects an address that is not an account", async function () {
    const { user, userAddress } = await newUserWithAccount();
    const { ts, signature } = await voucher(userAddress, usdc(1));

    await expect(
      rebate
        .connect(user)
        .claimAndDeposit(
          userAddress,
          usdc(1),
          ts,
          signature,
          ethers.Wallet.createRandom().address
        )
    ).to.be.revertedWith("Not your account");
  });

  it("rejects a caller that is not the voucher's user", async function () {
    const { userAddress, account } = await newUserWithAccount();
    const { user: stranger } = await newUserWithAccount();
    const { ts, signature } = await voucher(userAddress, usdc(1));

    await expect(
      rebate
        .connect(stranger)
        .claimAndDeposit(userAddress, usdc(1), ts, signature, account)
    ).to.be.revertedWith("Not your claim");
  });

  it("rejects a voucher not signed by the trusted address", async function () {
    const { user, userAddress, account } = await newUserWithAccount();
    const { ts, signature } = await voucher(
      userAddress,
      usdc(1),
      ethers.Wallet.createRandom()
    );

    await expect(
      rebate
        .connect(user)
        .claimAndDeposit(userAddress, usdc(1), ts, signature, account)
    ).to.be.revertedWith("Signer =! Trusted. ");
  });
});
