import {HardhatUserConfig} from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@openzeppelin/hardhat-upgrades";
import * as dotenv from "dotenv";

dotenv.config();

const config: HardhatUserConfig = {
  networks: process.env.RPC_URL ? {
    base: {
      url: process.env.RPC_URL,
      accounts: process.env.PRIVATEKEY_DEPLOYER ? [process.env.PRIVATEKEY_DEPLOYER] : [],
    },
  } : {},

  etherscan: {
    apiKey: process.env.ETHERSCAN_APIKEY || ""
  },


  solidity: {
    compilers: [
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 5000,
          },
        },
      }
    ],
  },
};

export default config;
