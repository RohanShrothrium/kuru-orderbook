// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {IERC20} from "./libraries/IERC20.sol";
import {IAbstractOrderBook} from "./interfaces/IAbstractOrderBook.sol";

abstract contract AbstractOrderBook is IAbstractOrderBook {
    struct Order {
        address ownerAddress;
        uint96 price;
        uint128 size;
        uint128 acceptableRange;
        bool isBuy;
    }

    struct PricePoint {
        uint128 totalCompletedOrCanceledOrders;
        uint128 totalOrdersAtPrice; // sum of size of all orders placed at the price point
        uint128 executableSize; // market orders that have been executed and can be claimed by limit order owners
    }

    event OrderCreated(
        uint256 orderId,
        address owner,
        uint96 price,
        uint128 size,
        uint128 acceptableRange,
        bool isBuy
    );

    event OrderUpdated(
        uint256 orderId,
        address owner,
        uint96 price,
        uint128 size,
        uint128 acceptableRange,
        bool isBuy
    );

    event OrdersCompletedOrCanceled(
        uint256[] orderId
    );

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
    function addBuyOrder(uint96 _price, uint128 size) external {
        uint256 _orderId = s_orderIdCounter;
        s_orderIdCounter = _orderId + 1;

        PricePoint storage _pricePoint = s_buyPricePoints[_price];

        uint128 _acceptableRange = _addOrder(_pricePoint, _price, size, _orderId + 1, true);

        tokenB.transferFrom(msg.sender, address(this), ((((size * _price) * 10**tokenBDecimals) / pricePrecision) / sizePrecision));

        emit OrderCreated(_orderId, msg.sender, _price, size, _acceptableRange, true);
    }

    /**
     * @dev Adds a sell order to the order book.
     * @param _price Price of the sell order.
     * @param size Size of the sell order.
     */
    function addSellOrder(uint96 _price, uint128 size) external {
        uint256 _orderId = s_orderIdCounter;
        s_orderIdCounter = _orderId + 1;

        PricePoint storage _pricePoint = s_sellPricePoints[_price];

        uint128 _acceptableRange = _addOrder(_pricePoint, _price, size, _orderId + 1, false);

        tokenA.transferFrom(msg.sender, address(this), ((size * 10**tokenADecimals) / sizePrecision));

        emit OrderCreated(_orderId, msg.sender, _price, size, _acceptableRange, false);
    }

    /**
     * @dev Internal function to add an order to the order book.
     * @param _pricePoint PricePoint storage object for the order's price point.
     * @param _price Price of the order.
     * @param _size Size of the order.
     */
    function _addOrder(PricePoint storage _pricePoint, uint96 _price, uint128 _size, uint256 _orderId, bool _isBuy) internal returns(uint128) {
        uint128 acceptableRange = _pricePoint.totalOrdersAtPrice;
        s_orders[_orderId] = Order(msg.sender, _price, _size, acceptableRange, _isBuy);

        _pricePoint.totalOrdersAtPrice += _size;

        return acceptableRange;
    }

    /**
     * @dev Cancels multiple orders in a batch.
     * @param _orderIds Array of order IDs to cancel.
     * @param _isBuy Array of bools representing if an order is a buy order
     */
    function batchCancelOrders(uint256[] memory _orderIds, bool[] memory _isBuy) external {
        for (uint256 i = 0; i < _orderIds.length; i++) {
            _isBuy[i] ? _cancelBuyOrder(_orderIds[i]) : _cancelSellOrder(_orderIds[i]);
        }

        emit OrdersCompletedOrCanceled(_orderIds);
    }

    /**
     * @dev Internal helper function to cancel a single buy order.
     * @param _orderId ID of the buy order to cancel.
     */
    function _cancelBuyOrder(uint256 _orderId) internal {
        Order memory _order = s_orders[_orderId];
        
        require(_order.isBuy, "OrderBook: Cancelling sell order");
        require(msg.sender == _order.ownerAddress, "OrderBook: Only order owner can cancel order");

        s_buyPricePoints[_order.price].totalCompletedOrCanceledOrders += _order.size;

        delete s_orders[_orderId];

        tokenB.transfer(_order.ownerAddress, ((((_order.size * _order.price) * 10**tokenBDecimals) / pricePrecision) / sizePrecision));
    }

    /**
     * @dev Internal helper function to cancel a single sell order.
     * @param _orderId ID of the sell order to cancel.
     */
    function _cancelSellOrder(uint256 _orderId) internal {
        Order memory _order = s_orders[_orderId];
        
        require(!_order.isBuy, "OrderBook: Cancelling buy order");
        require(msg.sender == _order.ownerAddress, "OrderBook: Only order owner can cancel order");

        s_sellPricePoints[_order.price].totalCompletedOrCanceledOrders += _order.size;

        delete s_orders[_orderId];

        tokenA.transfer(_order.ownerAddress, (_order.size * 10**tokenADecimals) / sizePrecision);
    }

    /**
     * @dev Places multiple limit buy orders in a single function call.
     * @param _prices Array of prices for the buy orders.
     * @param _sizes Array of sizes for the buy orders.
     */
    function placeMultipleBuyOrders(uint96[] memory _prices, uint128[] memory _sizes) external {
        require(_prices.length == _sizes.length, "OrderBook: Prices and sizes array length must match");

        for (uint256 i = 0; i < _prices.length; i++) {
            this.addBuyOrder(_prices[i], _sizes[i]);
        }
    }

    /**
     * @dev Places multiple limit sell orders in a single function call.
     * @param _prices Array of prices for the sell orders.
     * @param _sizes Array of sizes for the sell orders.
     */
    function placeMultipleSellOrders(uint96[] memory _prices, uint128[] memory _sizes) external {
        require(_prices.length == _sizes.length, "OrderBook: Prices and sizes array length must match");

        for (uint256 i = 0; i < _prices.length; i++) {
            this.addSellOrder(_prices[i], _sizes[i]);
        }
    }

    /**
     * @dev Replaces prices of existing orders
     * @param _orderIds list of orderIds that has to be updated
     * @param _price new price that has to be set
     */
    function replaceOrders(
        uint256[] calldata _orderIds,
        uint96[] calldata _price
    ) external {
        for (uint256 i = 0; i < _orderIds.length; i++) {
            Order storage order = s_orders[_orderIds[i]];

            require(msg.sender == order.ownerAddress, "OrderBook: Only order owner can update order");

            PricePoint storage newPricePoint = order.isBuy ? s_buyPricePoints[_price[i]] : s_sellPricePoints[_price[i]];
            PricePoint storage oldPricePoint = order.isBuy ? s_buyPricePoints[order.price] : s_sellPricePoints[order.price];

            // update new price point
            oldPricePoint.totalCompletedOrCanceledOrders += order.size;

            // update existing order variables
            order.acceptableRange = newPricePoint.totalOrdersAtPrice;
            order.price = _price[i];

            // update new price point
            newPricePoint.totalOrdersAtPrice += order.size;

            emit OrderUpdated(_orderIds[i], msg.sender, _price[i], order.size, order.acceptableRange, order.isBuy);
        }
    }
}
