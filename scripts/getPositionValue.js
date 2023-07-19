const hre = require("hardhat");
const config = require("../configMantleTestnet.json");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const userAddress = deployer.address;

    // create contract instance of PositionManager from config address
    const positionManager = await hre.ethers.getContractAt("PositionManager", config.positionManagerAddress);

    const _positionValue = await positionManager.positionValue(userAddress, config.wethAddress);
    console.log(_positionValue);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
