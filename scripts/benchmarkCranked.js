const hre = require("hardhat");
const config = require("../config.json");
const fs = require("fs");

async function main() {
    const usdcContract = await hre.ethers.getContractAt("contracts/libraries/IERC20.sol:IERC20", config.usdcAddress);
    var tx = await usdcContract.approve(
        config.orderBookAddress,
        10**10,
    );
    await tx.wait();

    const wbtcContract = await hre.ethers.getContractAt("contracts/libraries/IERC20.sol:IERC20", config.wbtcAddress);
    var tx = await wbtcContract.approve(
        config.orderBookAddress,
        10**10,
    );
    await tx.wait();

    // create contract instance of OrderBook from config address
    const orderBook = await hre.ethers.getContractAt("OrderBook", config.orderBookAddress);

    // loop over 100 and place limit orders
    // prices: 1800, 1801, 1802, ... ,1899
    console.log("=============================================")
    console.log("                   LIMIT                     ")
    console.log("=============================================")
    const placeLimitGas = {};
    for (let i = 0; i < 100; i++) {
        var tx = await orderBook.addBuyOrder(
            180000 + (i * 100),
            10**8,
        );
        const receipt = await tx.wait();

        console.log("Gas used: " + receipt.cumulativeGasUsed);
        placeLimitGas[i] = receipt.cumulativeGasUsed.toString();
    }

    // cancel last 10 orders
    // price points that exist: 1810, 1811, ... , 1899
    console.log("=============================================")
    console.log("                   CANCEL                    ")
    console.log("=============================================")
    const cancelLimitGas = {};
    for (let i = 0; i < 10; i++) {
        var tx = await orderBook.cancelBuyOrder(
            i+1
        );
        const receipt = await tx.wait();

        console.log("Gas used: " + receipt.cumulativeGasUsed);
        cancelLimitGas[i] = receipt.cumulativeGasUsed.toString();
    }

    // place 10 limit orders at a price point that already existis.
    // price points that exist: 1810, 1811, ... , 1899
    console.log("=============================================")
    console.log("               EXISTING LIMIT                ")
    console.log("=============================================")
    const placeLimitExistingGas = {};
    for (let i = 0; i < 10; i++) {
        var tx = await orderBook.addBuyOrder(
            181100,
            10**8,
        );
        const receipt = await tx.wait();

        console.log("Gas used: " + receipt.cumulativeGasUsed);
        placeLimitExistingGas[i] = receipt.cumulativeGasUsed.toString();
    }

    // place 10 market orders that iterates over a single price point.
    // price points that exist: 1810, 1811, ... , 1889
    console.log("=============================================")
    console.log("              SINGLE PP MARKET               ")
    console.log("=============================================")
    const placeMarketSingleGas = {};
    for (let i = 0; i < 10; i++) {
        var tx = await orderBook.placeAndExecuteMarketSell(
            [189900 - i*100],
            10**8,
        );
        const receipt = await tx.wait();

        console.log("Gas used: " + receipt.cumulativeGasUsed);
        placeMarketSingleGas[i] = receipt.cumulativeGasUsed.toString();
    }

    // place 10 market orders that iterates over two price points.
    // price points that exist: 1810, 1811, ... , 1869
    console.log("=============================================")
    console.log("                TWO PP MARKET                ")
    console.log("=============================================")
    const placeMarketTwoGas = {};
    for (let i = 0; i < 20; i = i + 2) {
        var tx = await orderBook.placeAndExecuteMarketSell(
            [188900 - i*100, 188900 - (i+1)*100],
            2*10**8,
        );
        const receipt = await tx.wait();

        console.log("Gas used: " + receipt.cumulativeGasUsed);
        placeMarketTwoGas[i] = receipt.cumulativeGasUsed.toString();
    }

    // place 10 market orders that iterates over three price points.
    // price points that exist: 1810, 1811, ... , 1839
    console.log("=============================================")
    console.log("              THRESS PP MARKET               ")
    console.log("=============================================")
    const placeMarketThreeGas = {};
    for (let i = 0; i < 30; i = i + 3) {
        var tx = await orderBook.placeAndExecuteMarketSell(
            [186900 - i*100, 186900 - (i+1)*100, 186900 - (i+2)*100],
            3*10**8,
        );
        const receipt = await tx.wait();

        console.log("Gas used: " + receipt.cumulativeGasUsed);
        placeMarketThreeGas[i] = receipt.cumulativeGasUsed.toString();
    }

    // place 10 market orders that iterates over two price points.
    // price points that exist: 1810, 1811, ... , 1839
    console.log("=============================================")
    console.log("                 CLAIM LIMIT                 ")
    console.log("=============================================")
    const claimLimitGas = {};
    for (let i = 100; i > 80; i--) {
        var tx = await orderBook.claimBuyLimitOrder(
            i,
        );
        const receipt = await tx.wait();

        console.log("Gas used: " + receipt.cumulativeGasUsed);
        claimLimitGas[i] = receipt.cumulativeGasUsed.toString();
    }


    fs.writeFileSync("crankedOrderBook.json", JSON.stringify({
        placeLimitGas,
        cancelLimitGas,
        placeLimitExistingGas,
        placeMarketSingleGas,
        placeMarketTwoGas,
        placeMarketThreeGas,
        claimLimitGas
    }));
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
