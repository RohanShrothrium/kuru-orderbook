// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IOrderBook {
    function pricePoints() external returns (uint256, uint256);
    function placeAndExecuteMarketBuy(uint256 _size, address _user) external;
    function placeAndExecuteMarketSell(uint256 _size, address _user) external;
}
