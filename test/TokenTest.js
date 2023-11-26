
const { expect } = require("chai");

const { loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");


//This is the example test for tokens from hardhat
describe("USDC test token", function () {

  async function deployUsdcTFixture() {

    const [owner, addr1, addr2] = await ethers.getSigners();

    const usdcTest = await ethers.deployContract("TestUSDC");

    await usdcTest.waitForDeployment();

    return { usdcTest, owner, addr1, addr2 };
  }

  describe("Deployment", function () {

    it("Should set the right owner", async function () {
      const { usdcTest, owner } = await loadFixture(deployUsdcTFixture);

      expect(await usdcTest.owner()).to.equal(owner.address);
    });

    it("Should assign the total supply of tokens to the owner", async function () {
      const { usdcTest, owner } = await loadFixture(deployUsdcTFixture);
      const ownerBalance = await usdcTest.balanceOf(owner.address);
      expect(await usdcTest.totalSupply()).to.equal(ownerBalance);
    });

    it("Should assign 1.000.000 tokens to the owner", async function () {
      const { usdcTest, owner } = await loadFixture(deployUsdcTFixture);
      const ownerBalance = await usdcTest.balanceOf(owner.address);
      const initialSupply = ethers.parseUnits("1000000",6);
      expect(initialSupply).to.equal(ownerBalance);
    });
  });

  describe("Transactions", function () {
    it("Should transfer tokens between accounts", async function () {
      const { usdcTest, owner, addr1, addr2 } = await loadFixture(
        deployUsdcTFixture
      );
      
      await expect(
        usdcTest.transfer(addr1.address, 50)
      ).to.changeTokenBalances(usdcTest, [owner, addr1], [-50, 50]);

      await expect(
        usdcTest.connect(addr1).transfer(addr2.address, 50)
      ).to.changeTokenBalances(usdcTest, [addr1, addr2], [-50, 50]);
    });

    it("Should emit Transfer events", async function () {
      const { usdcTest, owner, addr1, addr2 } = await loadFixture(
        deployUsdcTFixture
      );
      await expect(usdcTest.transfer(addr1.address, 50))
        .to.emit(usdcTest, "Transfer")
        .withArgs(owner.address, addr1.address, 50);

      await expect(usdcTest.connect(addr1).transfer(addr2.address, 50))
        .to.emit(usdcTest, "Transfer")
        .withArgs(addr1.address, addr2.address, 50);
    });

    it("Should fail if sender doesn't have enough tokens", async function () {
      const { usdcTest, owner, addr1 } = await loadFixture(
        deployUsdcTFixture
      );
      const initialOwnerBalance = await usdcTest.balanceOf(owner.address);

      await expect(
        usdcTest.connect(addr1).transfer(owner.address, 1)
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");

      expect(await usdcTest.balanceOf(owner.address)).to.equal(
        initialOwnerBalance
      );
    });
  });
});