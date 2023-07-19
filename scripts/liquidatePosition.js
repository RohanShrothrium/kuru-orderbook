const hre = require("hardhat");
const config = require("../config.json");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const userAddress = deployer.address;

    // create contract instance of PositionManager from config address
    const positionManager = await hre.ethers.getContractAt("PositionManager", config.positionManagerAddress);

    var tx = await positionManager.liquidatePosition(userAddress, config.wethAddress);
    const receipt = await tx.wait();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
