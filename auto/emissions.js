const { ethers, waffle} = require("hardhat");
const fetch = require('node-fetch');

async function main() {
    
    const [keeper] = await ethers.getSigners();
    console.log(`Automating with the account: ${keeper.address}`);

    console.log("")

    // Contract
    COREEMISSIONSKEEPER = await ethers.getContractFactory("CoreEmissionsKeeper");
    COREFEECOLLECTOR = await ethers.getContractFactory("CoreFeeCollector");
    DIAMOND = await ethers.getContractFactory("Diamond");

    coreEmissionsKeeper = "0xd8c1E4eAC58Ee0D9dD2763480ADaEcA43B06Fe67";
    coreEmissionsKeeper = await COREEMISSIONSKEEPER.attach(coreEmissionsKeeper);

    diamond = "0x3d17f073cCb9c3764F105550B0BCF9550477D266";
    diamond = await DIAMOND.attach(diamond);

    coreMaintainer = "0xaF8D3aaDE30AFc654d294649e5745e45FD27A2c6";
    coreFeeCollector = "0x1A5D813aff409a0245F86165552709d70a3ca610";
    coreFeeCollector = await COREFEECOLLECTOR.attach(coreFeeCollector);

    startTimestamp = await coreEmissionsKeeper.startTimestamp();
    startTimestamp = ethers.formatUnits(startTimestamp,"wei");

    currentTimestamp = Math.floor( Date.now() /1000);
    
    timePassed = currentTimestamp-startTimestamp
    daysPassed = Math.floor( timePassed/(60*60*24) )


    if ( !await coreEmissionsKeeper.isRewardMinted(daysPassed) ) {
        await coreEmissionsKeeper.fillCoreTradeRewarder(daysPassed);
        console.log(`Emissions of Day ${daysPassed} given.`)
    }

    lastTime = await coreFeeCollector.lastTime()
    lastTime = parseInt(ethers.formatUnits(lastTime,"wei"));


    if ( lastTime+(60*60*24*6) < currentTimestamp ) {

      amountFees = ethers.parseUnits( await getAmountFees() , "wei");
      lastTotalFeesFromCore = await coreFeeCollector.lastTotalFeesFromCore();

      if( amountFees > lastTotalFeesFromCore ){
        
        allAvailable = await diamond.balanceOf(coreFeeCollector.getAddress())
        fromCore = amountFees - lastTotalFeesFromCore
        toStakers = fromCore * 51n / 100n;
        toMsig = allAvailable - toStakers

        info = {
          "allAvailable" : ethers.formatEther(allAvailable),
          "fromCore" : ethers.formatEther(fromCore),
          "toStakers" : ethers.formatEther(toStakers),
          "toMsig" : ethers.formatEther(toMsig)
        }
        
        console.log( info )

        await coreFeeCollector.fillCoreTradeRewarder(amountFees);
      }
    }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});