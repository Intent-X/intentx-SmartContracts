/** @type import('hardhat/config').HardhatUserConfig */

require("@nomicfoundation/hardhat-chai-matchers")
require("@openzeppelin/hardhat-upgrades");

const { INTENTXPRIVATEKEY, COREPRIVATEKEY, APIKEY} = require("./pvkey.js");
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

  defaultNetwork: "blast_mainnet",
  networks : {
    
    base_mainnet: {
      url: 'https://mainnet.base.org',
      chainId : 8453,
      accounts : INTENTXPRIVATEKEY
    },

    blast_mainnet: {
      url: 'https://blast.blockpi.network/v1/rpc/public	',
      chainId : 81457,
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
