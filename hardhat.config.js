/** @type import('hardhat/config').HardhatUserConfig */

require("@nomicfoundation/hardhat-chai-matchers")
require("@openzeppelin/hardhat-upgrades");

//tdly = require("@tenderly/hardhat-tenderly");
//tdly.setup();

const { INTENTXPRIVATEKEY, INTENTXAUTOPRIVATEKEY, MANTLE_API_KEY,ARB_API_KEY,BASE_API_KEY,BLAST_API_KEY, BSC_API_KEY} = require("./pvkey.js");

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
      mantle: MANTLE_API_KEY,
      base: BASE_API_KEY,
      arbitrum: ARB_API_KEY,
      blast: BLAST_API_KEY,
      bsc: BSC_API_KEY
    },
    customChains: [
      {
        network: "mantle",
        chainId: 5000,
        urls: {
          apiURL: `https://api.mantlescan.xyz/api?apiKey=${MANTLE_API_KEY}`,
          browserURL: "https://mantlescan.xyz"
        }
      },
      {
				network: "base",
				chainId: 8453,
				urls: {
					apiURL: `https://api.basescan.org/api?apiKey=${BASE_API_KEY}`,
					browserURL: "https://basescan.org",
				},
			},
			{
				network: "arbitrum",
				chainId: 42161,
				urls: {
					apiURL: `https://api.arbiscan.io/api?apiKey=${ARB_API_KEY}`,
					browserURL: "https://arbiscan.io",
				},
			},
      {
				network: "blast",
				chainId: 81457,
				urls: {
					apiURL: `https://api.blastscan.io/api?apiKey=${BLAST_API_KEY}`,
					browserURL: "https://blastscan.io",
				},
			},
      {
				network: "bsc",
				chainId: 56,
				urls: {
					apiURL: `https://api.bscscan.com/api?apikey=${BSC_API_KEY}`,
					browserURL: "https://bscscan.com",
				},
			}
    ]
  },

  defaultNetwork: "mantle",
  networks : {
    
    base: {
      url: 'https://mainnet.base.org',
      chainId : 8453,
      accounts : [INTENTXPRIVATEKEY]
    },

    arbitrum: {
			url: "https://1rpc.io/arb	",
      chainId : 42161,
			accounts: [INTENTXPRIVATEKEY],
		},

    blast: {
      url: 'https://blast.blockpi.network/v1/rpc/public',
      chainId : 81457,
      accounts : [INTENTXPRIVATEKEY]
    },

    bsc: {
      url: 'https://bsc-dataseed1.defibit.io',
      chainId : 56,
      accounts : [INTENTXPRIVATEKEY]
    },

    mantle: {
      url: 'https://rpc.mantle.xyz',
      chainId : 5000,
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
