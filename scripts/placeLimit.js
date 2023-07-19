const hre = require("hardhat");
const config = require("../configMantleTestnet.json");

async function main() {
    // create contract instance of OrderBook from config address
    const orderBook = await hre.ethers.getContractAt("OrderBook", config.orderBookAddress);

    // loop over 50 and place limit orders
    for (let i = 0; i < 10; i++) {
        var tx = await orderBook.addBuyOrder(
            180000 + (i * 100),
            10**9,
        );
        const receipt = await tx.wait();

        console.log("Gas used: " + receipt.cumulativeGasUsed);
    }
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
