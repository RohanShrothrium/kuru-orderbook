const hre = require("hardhat");
const config = require("../configMantleTestnet.json");

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const userAddress = deployer.address;

    // create contract instance of OrderBook from config address
    const orderBook = await hre.ethers.getContractAt("OrderBook", config.orderBookAddress);

    var receipt = await orderBook.placeAndExecuteMarketSell(
        3*10**9,
        userAddress,
    );
    await receipt.wait();
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
