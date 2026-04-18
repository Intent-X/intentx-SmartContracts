/** @type import('hardhat/config').HardhatUserConfig */

require("@openzeppelin/hardhat-upgrades");
require("@nomicfoundation/hardhat-toolbox");

require("dotenv").config();

const {
  DEPLOYER_PRIVATE_KEY,
  ETHERSCAN_API_KEY,

  ARBITRUM_ONE_RPC_URL,
  MANTLE_RPC_URL,
  BASE_RPC_URL,
} = process.env;


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

  sourcify: {
    enabled: false
  },

  networks: {
    arbitrumOne: {
      url:
        ARBITRUM_ONE_RPC_URL || "",
      chainId: 42161,
      accounts: [DEPLOYER_PRIVATE_KEY],
    },
    mantle: {
      url:
        MANTLE_RPC_URL || "",
      chainId: 5000,
      accounts: [DEPLOYER_PRIVATE_KEY],
    },
    base: {
      url:
        BASE_RPC_URL || "",
      chainId: 8453,
      accounts: [DEPLOYER_PRIVATE_KEY],
    },
  },

  defaultNetwork: "arbitrumOne",

  verify: {
    etherscan: {
      apiKey: ETHERSCAN_API_KEY || "",
    },
  },
  
  etherscan: {
    apiKey: ETHERSCAN_API_KEY || "",
    customChains: [
      {
        network: "arbitrumOne",
        chainId: 42161,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=42161",
          browserURL: "https://arbiscan.io",
        },
      },
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.etherscan.io/v2/api?chainid=8453",
          browserURL: "https://basescan.org",
        },
      },
    ],
  },
};
