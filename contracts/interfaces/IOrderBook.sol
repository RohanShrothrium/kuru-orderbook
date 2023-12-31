// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IOrderBook {
    function placeAndExecuteMarketBuy(uint96[] calldata c_prices, uint128 _size) external;
    function placeAndExecuteMarketSell(uint96[] calldata c_prices, uint128 _size) external;
    function claimSellLimitOrder(uint256 _orderId) external;
    function claimBuyLimitOrder(uint256 _orderId) external;
}
