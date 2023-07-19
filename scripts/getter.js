const hre = require("hardhat");
const config = require("../configMantleTestnet.json");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const userAddress = deployer.address;

    // create contract instance of OrderBook from config address
    const positionManager = await hre.ethers.getContractAt("PositionManager", config.positionManagerAddress);

    var positionKey = await positionManager.getPositionKey(userAddress, config.wethAddress);
    console.log(positionKey);

    const position = await positionManager.s_positions(positionKey);
    console.log(position);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
