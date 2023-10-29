/** @type import('hardhat/config').HardhatUserConfig */

require('@openzeppelin/hardhat-upgrades');
require("@nomicfoundation/hardhat-chai-matchers")

const { PRIVATEKEY, APIKEY} = require("./pvkey.js");
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          optimizer: {
            enabled : true,
            runs: 2048,
          }
        }
      },
    ]
  },


  networks : {
    
    base_mainnet: {
      url: 'https://mainnet.base.org',
      chainId : 8453,
      accounts : PRIVATEKEY
    },

    /*hardhat: {
      forking: {
        url : 'https://mainnet.base.org',
        chainId : 8453
      }
    },*/
  },

};
