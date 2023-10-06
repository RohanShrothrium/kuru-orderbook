// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {IERC20} from "./libraries/IERC20.sol";
import {IAbstractOrderBook} from "./interfaces/IAbstractOrderBook.sol";

abstract contract AbstractOrderBook is IAbstractOrderBook {
    using SafeMath for uint256;

    struct Order {
        address ownerAddress;
        uint96 price;
        uint256 size;
        uint256 acceptableRange;
    }

    struct PricePoint {
        uint256 totalCompletedOrCanceledOrders;
        uint256 totalOrdersAtPrice; // sum of size of all orders placed at the price point
        uint256 executableSize; // market orders that have been executed and can be claimed by limit order owners
    }

    mapping(uint256 => Order) public s_orders;
    mapping(uint256 => PricePoint) public s_buyPricePoints;
    mapping(uint256 => PricePoint) public s_sellPricePoints;

    uint256 public s_orderIdCounter;

    IERC20 immutable tokenA;
    IERC20 immutable tokenB;

    uint256 immutable tokenADecimals;
    uint256 immutable tokenBDecimals;

    uint256 constant sizePrecision = 10**10;
    uint256 constant pricePrecision = 10**2;

    /**
     * @dev Constructor.
     * @param _tokenAAddress Address of the first token used for trading.
     * @param _tokenADecimals Deciimal pricicsion of the first swap token.
     * @param _tokenBAddress Address of the second token used for trading.
     * @param _tokenBDecimals Deciimal pricicsion of the first swap token.
     */
    constructor (address _tokenAAddress, uint256 _tokenADecimals, address _tokenBAddress, uint256 _tokenBDecimals) {
        tokenA = IERC20(_tokenAAddress);
        tokenB = IERC20(_tokenBAddress);

        tokenADecimals = _tokenADecimals;
        tokenBDecimals = _tokenBDecimals;
    }

    /**
     * @dev Adds a buy order to the order book.
     * @param _price Price of the buy order.
     * @param size Size of the buy order.
     */
    function addBuyOrder(uint96 _price, uint256 size) external {
        uint256 _orderId = s_orderIdCounter;
        s_orderIdCounter = _orderId + 1;

        PricePoint storage _pricePoint = s_buyPricePoints[_price];

        _addOrder(_pricePoint, _price, size, _orderId + 1);

        tokenB.transferFrom(msg.sender, address(this), size.mul(_price).mul(10**tokenBDecimals).div(pricePrecision).div(sizePrecision));
    }

    /**
     * @dev Adds a sell order to the order book.
     * @param _price Price of the sell order.
     * @param size Size of the sell order.
     */
    function addSellOrder(uint96 _price, uint256 size) external {
        uint256 _orderId = s_orderIdCounter;
        s_orderIdCounter = _orderId + 1;

        PricePoint storage _pricePoint = s_sellPricePoints[_price];

        _addOrder(_pricePoint, _price, size, _orderId + 1);

        tokenA.transferFrom(msg.sender, address(this), size.mul(10**tokenADecimals).div(sizePrecision));
    }

    /**
     * @dev Internal function to add an order to the order book.
     * @param _pricePoint PricePoint storage object for the order's price point.
     * @param _price Price of the order.
     * @param _size Size of the order.
     */
    function _addOrder(PricePoint storage _pricePoint, uint96 _price, uint256 _size, uint256 _orderId) internal {
        uint256 acceptableRange = _pricePoint.totalOrdersAtPrice;
        s_orders[_orderId] = Order(msg.sender, _price, _size, acceptableRange);

        _pricePoint.totalOrdersAtPrice += _size;
    }

    /**
     * @dev Cancels a sell order.
     * @param _orderId ID of the sell order to cancel.
     */
    function cancelSellOrder(uint256 _orderId) external {
        Order memory _order = s_orders[_orderId];
        
        require(msg.sender == _order.ownerAddress, "OrderBook: Only order owner can cancel order");

        s_sellPricePoints[_order.price].totalCompletedOrCanceledOrders += _order.size;

        delete s_orders[_orderId];

        tokenA.transfer(_order.ownerAddress, _order.size.mul(10**tokenADecimals).div(sizePrecision));
    }

    /**
     * @dev Cancels a buy order.
     * @param _orderId ID of the buy order to cancel.
     */
    function cancelBuyOrder(uint256 _orderId) external {
        Order memory _order = s_orders[_orderId];
        
        require(msg.sender == _order.ownerAddress, "OrderBook: Only order owner can cancel order");

        s_buyPricePoints[_order.price].totalCompletedOrCanceledOrders += _order.size;

        delete s_orders[_orderId];

        tokenB.transfer(_order.ownerAddress, _order.size.mul(_order.price).mul(10**tokenBDecimals).div(pricePrecision).div(sizePrecision));
    }
}
