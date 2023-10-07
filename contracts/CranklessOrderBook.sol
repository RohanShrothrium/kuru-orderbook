// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {ICranklessOrderBook} from "./interfaces/ICranklessOrderBook.sol";

import {AbstractOrderBook} from "./AbstractOrderBook.sol";

// size is 10**10
// price is 10**2
contract CranklessOrderBook is AbstractOrderBook, ICranklessOrderBook {
    using SafeMath for uint256;

    constructor(
        address _tokenAAddress,
        uint256 _tokenADecimals,
        address _tokenBAddress,
        uint256 _tokenBDecimals
    )
        AbstractOrderBook(
            _tokenAAddress,
            _tokenADecimals,
            _tokenBAddress,
            _tokenBDecimals
        )
    {}

    /**
     * @dev Places and executes a market buy order.
     * @param _size Size of the market buy order.
     */
    function placeAndExecuteMarketBuy(
        uint96[] calldata c_order_ids,
        uint256 _size
    ) external override {
        uint256 _orderIndex = 0;
        Order memory _order = s_orders[c_order_ids[_orderIndex]];
        PricePoint memory m_pricePoint = s_buyPricePoints[_order.price];

        uint256 _executedSize = 0;

        require(_order.acceptableRange <= m_pricePoint.totalCompletedOrCanceledOrders, "OrderBook: order not executable");

        while (_size > _order.size && _orderIndex < c_order_ids.length) {
            _executedSize += _order.size;
            _size -= _order.size;
            m_pricePoint.totalCompletedOrCanceledOrders += _order.size;

            uint256 _existinPrice = _order.price;

            // TODO: Transfer tokens to limit order.
            tokenB.transferFrom(
                msg.sender,
                _order.ownerAddress,
                _amountPayable(_order.size, _order.price)
            );

            _order.size = 0;
            s_orders[c_order_ids[_orderIndex]] = _order;

            _orderIndex += 1;
            _order = s_orders[c_order_ids[_orderIndex]];
            if (_existinPrice != _order.price) {
                s_buyPricePoints[_existinPrice] = m_pricePoint;
                m_pricePoint = s_buyPricePoints[_order.price];
            }
        }
        
        if (_size > 0 && _orderIndex < c_order_ids.length) {
            m_pricePoint.totalCompletedOrCanceledOrders += _size;
            _executedSize += _size;

            // TODO: Transfer tokens to limit order.
            tokenB.transferFrom(
                msg.sender,
                _order.ownerAddress,
                _amountPayable(_size, _order.price)
            );

            _order.size -= _size;
            s_orders[c_order_ids[_orderIndex]] = _order;
            s_buyPricePoints[_order.price] = m_pricePoint;
        }

        tokenA.transfer(
            msg.sender,
            _executedSize.mul(10 ** tokenADecimals).div(sizePrecision)
        );
    }

    /**
     * internal helper function to get payable amount
     * @param _size size of token
     * @param _price conversion price from A to B
     */
    function _amountPayable(uint256 _size, uint256 _price) internal view returns (uint256) {
        return _size.mul(_price).mul(10 ** tokenBDecimals).div(pricePrecision).div(sizePrecision);
    }

    /**
     * @dev Places and executes a market sell order.
     * @param _size Size of the market sell order.
     */
    function placeAndExecuteMarketSell(
        uint96[] calldata c_order_ids,
        uint256 _size
    ) external {
        uint256 _orderIndex = 0;
        Order memory _order = s_orders[c_order_ids[_orderIndex]];
        PricePoint memory m_pricePoint = s_sellPricePoints[_order.price];

        uint256 _priceToGet = 0;

        require(_order.acceptableRange <= m_pricePoint.totalCompletedOrCanceledOrders, "OrderBook: order not executable");

        while (_size > _order.size && _orderIndex < c_order_ids.length) {
            _priceToGet += _order.size.mul(_order.price);
            _size -= _order.size;
            m_pricePoint.totalCompletedOrCanceledOrders += _order.size;

            uint256 _existinPrice = _order.price;

            // TODO: Transfer tokens to limit order.
            tokenA.transferFrom(
                msg.sender,
                _order.ownerAddress,
                _order.size.mul(10 ** tokenADecimals).div(sizePrecision)
            );

            _order.size = 0;
            s_orders[c_order_ids[_orderIndex]] = _order;

            _orderIndex += 1;
            _order = s_orders[c_order_ids[_orderIndex]];
            if (_existinPrice != _order.price) {
                s_sellPricePoints[_existinPrice] = m_pricePoint;
                m_pricePoint = s_sellPricePoints[_order.price];
            }
        }
        
        if (_size > 0 && _orderIndex < c_order_ids.length) {
            m_pricePoint.totalCompletedOrCanceledOrders += _size;
            _priceToGet += _size.mul(_order.price);

            // TODO: Transfer tokens to limit order.
            tokenA.transferFrom(
                msg.sender,
                _order.ownerAddress,
                _size.mul(10 ** tokenADecimals).div(sizePrecision)
            );

            _order.size -= _size;
            s_orders[c_order_ids[_orderIndex]] = _order;
            s_sellPricePoints[_order.price] = m_pricePoint;
        }

        tokenB.transfer(
            msg.sender,
            _priceToGet.mul(10 ** tokenBDecimals).div(pricePrecision).div(sizePrecision)
        );
    }
}
