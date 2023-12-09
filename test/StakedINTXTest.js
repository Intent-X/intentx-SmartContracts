
const { expect } = require("chai");

const { loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");


//This is the example test for tokens from hardaht
describe("StakedINTX upgradeable contract", function () {


  upgrades.silenceWarnings();

  async function deploysFixture() {

    const [owner, addr1, addr2] = await ethers.getSigners();

    const IntxUpgradeable = await ethers.getContractFactory("IntxUpgradeable")
    const intxToken = await upgrades.deployProxy( IntxUpgradeable, [], { initializer: "initialize", kind: "transparent", unsafeAllow: "constructor"} );
    await intxToken.waitForDeployment();

    const testUSDC = await ethers.deployContract("TestUSDC");
    await testUSDC.waitForDeployment();

    const StakedINTX = await ethers.getContractFactory("StakedINTX")
    const stakedINTX = await upgrades.deployProxy( StakedINTX, [await intxToken.getAddress(),await testUSDC.getAddress()], { initializer: "initialize", kind: "transparent", unsafeAllow: "constructor"} );
    await stakedINTX.waitForDeployment();

    return { stakedINTX, intxToken, testUSDC, owner, addr1, addr2};
  }

  describe("Deployment", function () {

    
    it("Should set the right owner", async function () {
      const { stakedINTX, intxToken, testUSDC, owner, addr1, addr2} = await loadFixture(deploysFixture);

      expect(await stakedINTX.owner()).to.equal(owner.address);
    });

    it("Initial constants should be correct.", async function () {
      const { stakedINTX, intxToken, testUSDC, owner, addr1, addr2} = await loadFixture(deploysFixture);
      
      const initialExchangeRate = await stakedINTX.currentExchangeRate();
      const loyaltyDuration = await stakedINTX.loyaltyDuration();
      const maxLoyaltyBoost = await stakedINTX.maxLoyaltyBoost();
      const maxPenalty = await stakedINTX.maxPenalty();
      const minPenalty = await stakedINTX.minPenalty();
      
      expect(ethers.parseUnits("1",18)).to.equal(initialExchangeRate);
      expect( ethers.parseUnits("9676800",0) ).to.equal(loyaltyDuration);
      expect(ethers.parseUnits("25",17)).to.equal(maxLoyaltyBoost);
      expect(ethers.parseUnits("25",16)).to.equal(maxPenalty);
      expect(ethers.parseUnits("5",15)).to.equal(minPenalty);
      
    });

    it("Staking test.", async function () {
      const { stakedINTX, intxToken, testUSDC, owner, addr1, addr2} = await loadFixture(deploysFixture);
      
      const amount = ethers.parseUnits("100000",18);
      
      await intxToken.approve( await stakedINTX.getAddress(), amount );
      let tx = await stakedINTX.stake(amount);
      let receipt = await tx.wait();
      //console.log( receipt.gasUsed );
      const timeStamp = (await ethers.provider.getBlock("latest")).timestamp

      const balanceOfOwner = await stakedINTX.balanceOf( owner.address );
      const firstTokenId = await stakedINTX.lastTokenId();

      /*const boostPercentageOf = await stakedINTX.boostPercentageOf(firstTokenId);
      const penaltyPercentageOf = await stakedINTX.penaltyPercentageOf(firstTokenId);
      const amountStakedOf = await stakedINTX.amountStakedOf(firstTokenId);
      const withdrawableAmountOf = await stakedINTX.withdrawableAmountOf(firstTokenId);
      const penaltyAmountOf = await stakedINTX.penaltyAmountOf(firstTokenId);
      const balanceOfId = await stakedINTX.balanceOfId(firstTokenId);
      const loyalSince = await stakedINTX.loyalSince(firstTokenId);*/

      const { 
        tokenId,
        ownerOfToken,
        balanceOfId,
        amountStakedOf,
        withdrawableAmountOf,
        loyalSince,
        boostPercentageOf,
        penaltyPercentageOf,
        penaltyAmountOf,
        pendingReward,
    } = await stakedINTX["getPositionInfo (uint _tokenId)"](firstTokenId);

      expect( ethers.parseUnits("1",0) ).to.equal(balanceOfOwner);

      expect( ethers.parseUnits("1",18) ).to.equal(boostPercentageOf);
      expect( ethers.parseUnits("25",16) ).to.equal(penaltyPercentageOf);
      expect( amount ).to.equal(amountStakedOf);
      expect( ethers.parseUnits("75000",18) ).to.equal(withdrawableAmountOf);
      expect( ethers.parseUnits("25000",18) ).to.equal(penaltyAmountOf);
      expect( amount ).to.equal(balanceOfId);
      expect( timeStamp ).to.equal(loyalSince);


      
    });
  });

});