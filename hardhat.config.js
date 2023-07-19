require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.17",
  defaultNetwork: "mantleTestnet",
  networks: {
    localhost: {
      url: "http://127.0.0.1:8545/",
    },
    mantleTestnet: {
      url: "https://rpc.testnet.mantle.xyz/",
      accounts: ["1de8f879576ea64d7cfa74879bfb7486dc5e1a7cfb19d1507fe87c782f9c54b3"],
    },
    mantleMainnet: {
      url: "https://rpc.mantle.xyz/",
      accounts: ["1de8f879576ea64d7cfa74879bfb7486dc5e1a7cfb19d1507fe87c782f9c54b3"],
    }
  }
};
