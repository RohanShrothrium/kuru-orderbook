const hre = require("hardhat");
const config  = require("../configMantleTestnet.json");

async function main() {
    const marginAccount = await hre.ethers.getContractAt("MarginAccount", config.marginAccountAddress);
    // approve usdc to MarginAccount from deployer
    const usdcContract = await hre.ethers.getContractAt("contracts/libraries/IERC20.sol:IERC20", config.usdcAddress);
    var receipt = await usdcContract.approve(
        config.marginAccountAddress,
        90000000,
    );
    await receipt.wait();

    // deposit usdc to MarginAccount
    var receipt = await marginAccount.deposit(90000000, config.wethAddress);
    await receipt.wait();
}


main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
