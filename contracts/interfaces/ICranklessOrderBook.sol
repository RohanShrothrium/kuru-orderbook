// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface ICranklessOrderBook {
    function placeAndExecuteMarketBuy(uint96[] calldata c_prices, uint256 _size) external;
    function placeAndExecuteMarketSell(uint96[] calldata c_prices, uint256 _size) external;
}
