const hre = require("hardhat");
const config = require("../configMantleTestnet.json");

async function main() {
    // create contract instance of OrderBook from config address
    const orderBook = await hre.ethers.getContractAt("OrderBook", config.orderBookAddress);

    // claim limit orders for orderId
    var tx = await orderBook.claimBuyLimitOrder(
        8,
    );

    const receipt = await tx.wait();

    console.log("Gas used: " + receipt.cumulativeGasUsed);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
