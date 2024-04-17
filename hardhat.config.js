/** @type import('hardhat/config').HardhatUserConfig */

require("@nomicfoundation/hardhat-chai-matchers")
require("@openzeppelin/hardhat-upgrades");

const { INTENTXPRIVATEKEY, APIKEY} = require("./pvkey.js");

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

  etherscan: {
    apiKey: {
      mantle: APIKEY,
    },
    customChains: [
      {
        network: "mantle",
        chainId: 5000,
        urls: {
          apiURL: "https://explorer.mantle.xyz/api",
          browserURL: "https://explorer.mantle.xyz"
        }
      }
    ]
  },

  defaultNetwork: "mantle_mainnet",
  networks : {
    
    base_mainnet: {
      url: 'https://mainnet.base.org',
      chainId : 8453,
      accounts : INTENTXPRIVATEKEY
    },

    blast_mainnet: {
      url: 'https://blast.blockpi.network/v1/rpc/public',
      chainId : 81457,
      accounts : INTENTXPRIVATEKEY
    },

    bsc_mainnet: {
      url: 'https://bsc-dataseed1.defibit.io',
      chainId : 56,
      accounts : INTENTXPRIVATEKEY
    },

    mantle_mainnet: {
      url: 'https://mantle-rpc.publicnode.com	',
      chainId : 5000,
      accounts : INTENTXPRIVATEKEY
    },

    /*hardhat: {
      forking: {
        url : 'https://mainnet.base.org',
        chainId : 8453
      }
    },*/
  },

};
