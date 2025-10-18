/** @type import('hardhat/config').HardhatUserConfig */

require("@openzeppelin/hardhat-upgrades");
require("@nomicfoundation/hardhat-toolbox");


require('dotenv').config()

const INTENTXPRIVATEKEY = process.env.INTENTXPRIVATEKEY
const INTENTXAUTOPRIVATEKEY = process.env.INTENTXAUTOPRIVATEKEY

const ETH_API_KEY = process.env.ETH_API_KEY

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
      {
        version: "0.8.28",
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
      mantle: ETH_API_KEY,
      base: ETH_API_KEY,
      arbitrum: ETH_API_KEY,
      blast: ETH_API_KEY,
      bsc: ETH_API_KEY,
      bera: ETH_API_KEY
    },
    customChains: [
      {
        network: "mantle",
        chainId: 5000,
        urls: {
          apiURL: `https://api.etherscan.io/v2/api?chainid=5000&apiKey=${ETH_API_KEY}`,
          browserURL: "https://mantlescan.xyz"
        }
      },
      {
				network: "base",
				chainId: 8453,
				urls: {
					apiURL: `https://api.etherscan.io/v2/api?chainid=8453&apiKey=${ETH_API_KEY}`,
					browserURL: "https://basescan.org",
				},
			},
      {
				network: "bera",
				chainId: 80094,
				urls: {
					apiURL: `https://api.etherscan.io/v2/api?chainid=80094&apiKey=${ETH_API_KEY}`,
					browserURL: "https://berascan.com",
				},
			},
			{
				network: "arbitrum",
				chainId: 42161,
				urls: {
					apiURL: `https://api.etherscan.io/v2/api?chainid=42161&apiKey=${ETH_API_KEY}`,
					browserURL: "https://arbiscan.io",
				},
			},
      {
				network: "blast",
				chainId: 81457,
				urls: {
					apiURL: `https://api.etherscan.io/v2/api?chainid=81457&apiKey=${ETH_API_KEY}`,
					browserURL: "https://blastscan.io",
				},
			},
      {
				network: "bsc",
				chainId: 56,
				urls: {
					apiURL: `https://api.etherscan.io/v2/api?chainid=56&apiKey=${ETH_API_KEY}`,
					browserURL: "https://bscscan.com",
				},
			}
    ]
  },

  defaultNetwork: "base",
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
      url: 'https://rpc.blast.io',
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
    bera: {
      url: 'https://rpc.berachain.com',
      chainId : 80094,
      accounts : [INTENTXPRIVATEKEY]
    },
  },

};
