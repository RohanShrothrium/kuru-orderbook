// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IAbstractOrderBook {
    function addBuyOrder(uint96 _price, uint256 size) external;
    function addSellOrder(uint96 _price, uint256 size) external;
    function cancelSellOrder(uint256 _orderId) external;
    function cancelBuyOrder(uint256 _orderId) external;
}
