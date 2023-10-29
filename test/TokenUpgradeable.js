
const { expect } = require("chai");

const { loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");


//This is the example test for tokens from hardaht
describe("INTX upgradeable contract", function () {


  upgrades.silenceWarnings();

  async function deployIntxFixture() {

    const [owner, addr1, addr2] = await ethers.getSigners();

    const INTX = await ethers.getContractFactory("IntxUpgradeable")
    const intxToken = await upgrades.deployProxy( INTX, [], { initializer: "initialize", kind: "transparent", unsafeAllow: "constructor"} );

    await intxToken.waitForDeployment();

    return { intxToken, owner, addr1, addr2 };
  }

  describe("Deployment", function () {

    /*
    it("Should set the right owner", async function () {
      const { intxToken, owner } = await loadFixture(deployIntxFixture);

      expect(await intxToken.owner()).to.equal(owner.address);
    });*/

    it("Should assign the total supply of tokens to the deployer", async function () {
      const { intxToken, owner } = await loadFixture(deployIntxFixture);
      const ownerBalance = await intxToken.balanceOf(owner.address);
      expect(await intxToken.totalSupply()).to.equal(ownerBalance);
    });

    it("Should assign 100.000.000 tokens to the deployer", async function () {
      const { intxToken, owner } = await loadFixture(deployIntxFixture);
      const ownerBalance = await intxToken.balanceOf(owner.address);
      const initialSupply = ethers.parseUnits("100000000","ether");
      expect(initialSupply).to.equal(ownerBalance);
    });
  });

  describe("Transactions", function () {
    it("Should transfer tokens between accounts", async function () {
      const { intxToken, owner, addr1, addr2 } = await loadFixture(
        deployIntxFixture
      );
      
      await expect(
        intxToken.transfer(addr1.address, 50)
      ).to.changeTokenBalances(intxToken, [owner, addr1], [-50, 50]);

      await expect(
        intxToken.connect(addr1).transfer(addr2.address, 50)
      ).to.changeTokenBalances(intxToken, [addr1, addr2], [-50, 50]);
    });

    it("Should emit Transfer events", async function () {
      const { intxToken, owner, addr1, addr2 } = await loadFixture(
        deployIntxFixture
      );
      await expect(intxToken.transfer(addr1.address, 50))
        .to.emit(intxToken, "Transfer")
        .withArgs(owner.address, addr1.address, 50);

      await expect(intxToken.connect(addr1).transfer(addr2.address, 50))
        .to.emit(intxToken, "Transfer")
        .withArgs(addr1.address, addr2.address, 50);
    });

    it("Should fail if sender doesn't have enough tokens", async function () {
      const { intxToken, owner, addr1 } = await loadFixture(
        deployIntxFixture
      );
      const initialOwnerBalance = await intxToken.balanceOf(owner.address);

      await expect(
        intxToken.connect(addr1).transfer(owner.address, 1)
      ).to.be.revertedWith("ERC20: transfer amount exceeds balance");

      expect(await intxToken.balanceOf(owner.address)).to.equal(
        initialOwnerBalance
      );
    });
  });
});