/** @type import('hardhat/config').HardhatUserConfig */

require("@nomicfoundation/hardhat-chai-matchers")
require("@openzeppelin/hardhat-upgrades");

//tdly = require("@tenderly/hardhat-tenderly");
//tdly.setup();

const { INTENTXPRIVATEKEY, INTENTXPRIVATEKEYTEST, INTENTXAUTOPRIVATEKEY, APIKEY} = require("./pvkey.js");

module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.18",
        settings: {
          optimizer: {
            enabled : true,
            runs: 2048,
          }
        }
      },
    ]
  },

  tenderly: {
    username: "intentxdev",
    project: "intentxsmartcontracts",
 
    // Contract visible only in Tenderly.
    // Omitting or setting to `false` makes it visible to the whole world.
    // Alternatively, admin-rpc verification visibility using
    // an environment variable `TENDERLY_PRIVATE_VERIFICATION`.
    privateVerification: true,
  },

  etherscan: {
    apiKey: {
      mantle: APIKEY,
    },
    customChains: [
      {
        network: "mantle",
        chainId: 5000,
        urls: {
          apiURL: "https://api.mantlescan.xyz/api",
          browserURL: "https://mantlescan.xyz"
        }
      }
    ]
  },

  defaultNetwork: "mantle_mainnet",
  networks : {
    
    base_mainnet: {
      url: 'https://mainnet.base.org',
      chainId : 8453,
      accounts : [INTENTXPRIVATEKEY]
    },

    blast_mainnet: {
      url: 'https://blast.blockpi.network/v1/rpc/public',
      chainId : 81457,
      accounts : [INTENTXPRIVATEKEY]
    },

    bsc_mainnet: {
      url: 'https://bsc-dataseed1.defibit.io',
      chainId : 56,
      accounts : [INTENTXPRIVATEKEY]
    },

    mantle_mainnet: {
      url: 'https://rpc.mantle.xyz',
      chainId : 5000,
      //accounts : INTENTXPRIVATEKEYTEST
      accounts : [INTENTXPRIVATEKEY, INTENTXAUTOPRIVATEKEY]
    },

    /*hardhat: {
      forking: {
        url : 'https://mainnet.base.org',
        chainId : 8453
      }
    },*/
  },

};
