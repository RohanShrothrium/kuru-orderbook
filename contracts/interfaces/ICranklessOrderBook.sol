// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ICranklessOrderBook {
    function placeAndExecuteMarketBuy(
        uint96[] calldata c_prices,
        uint128 _size,
        bool _isFillOrKill
    ) external returns (uint128);

    function placeAndExecuteMarketSell(
        uint96[] calldata c_prices,
        uint128 _size,
        bool _isFillOrKill
    ) external returns (uint128);

    function placeAggressivelimitSell(
        uint96[] calldata c_order_ids,
        uint128 _size,
        uint96 _price
    ) external;

    function placeAggressivelimitBuy(
        uint96[] calldata c_order_ids,
        uint128 _size,
        uint96 _price
    ) external;
}
