// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./interfaces/IPositionManager.sol";
import "./interfaces/IMarginAccount.sol";
import "./interfaces/IOrderBook.sol";

// size is 10**10
// price is 10**2
contract OrderBook is IOrderBook {
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

    uint256[] public s_buyOrdersHeap;
    uint256[] public s_sellOrdersHeap;

    mapping(uint256 => Order) public s_orders;
    mapping(uint256 => PricePoint) public s_buyPricePoints;
    mapping(uint256 => PricePoint) public s_sellPricePoints;

    uint256 public s_orderIdCounter;

    address s_positionManager;
    address s_marginAccount;

    address immutable tokenAddress;

    uint256 constant sizePrecision = 10**10;

    // Event emitted when a user creates a buy limit order
    event LimitBuyCreated(
        address indexed ownerAddress,
        uint96 price,
        uint256 orderId,
        uint256 size
    );

    // Event emitted when a user creates a sell limit order
    event LimitSellCreated(
        address indexed ownerAddress,
        uint96 price,
        uint256 orderId,
        uint256 size
    );

    // Event emitted when a user executes a buy market order
    event MarketBuyExecuted(
        address indexed ownerAddress,
        uint256 size
    );

    // Event emitted when a user executes a sell market order
    event MarketSellExecuted(
        address indexed ownerAddress,
        uint256 size
    );

    // Event emitted when a user cancels a buy limit order
    event LimitBuyCompleted(
        address indexed ownerAddress,
        uint256 orderId,
        uint256 size
    );

    // Event emitted when a user cancels a sell limit order
    event LimitSellCompleted(
        address indexed ownerAddress,
        uint256 orderId,
        uint256 size
    );

    /**
     * @dev Constructor.
     * @param _positionManager Address of the PositionManager contract.
     * @param _marginAccount Address of the MarginAccount contract.
     * @param _tokenAddress Address of the token used for trading.
     */
    constructor (address _positionManager, address _marginAccount, address _tokenAddress) {
        s_marginAccount = _marginAccount;
        s_positionManager = _positionManager;
        tokenAddress = _tokenAddress;
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

        if (_pricePoint.totalOrdersAtPrice == 0) {
            _insertBuyPrice(_price);
        }

        _addOrder(_pricePoint, _price, size, _orderId + 1);

        IMarginAccount(s_marginAccount).lockFunds(msg.sender, tokenAddress);

        emit LimitBuyCreated(msg.sender, _price, _orderId + 1, size);
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

        if (_pricePoint.totalOrdersAtPrice == 0) {
            _insertSellPrice(_price);
        }

        _addOrder(_pricePoint, _price, size, _orderId + 1);

        IMarginAccount(s_marginAccount).lockFunds(msg.sender, tokenAddress);

        emit LimitSellCreated(msg.sender, _price, _orderId + 1, size);
    }

    /**
     * @dev Internal function to add an order to the order book.
     * @param _pricePoint PricePoint storage object for the order's price point.
     * @param _price Price of the order.
     * @param _size Size of the order.
     */
    function _addOrder(PricePoint storage _pricePoint, uint96 _price, uint256 _size, uint256 _orderId) internal {
        uint256 acceptableRange = (_pricePoint.totalOrdersAtPrice == 0)
            ? 0
            : _pricePoint.totalOrdersAtPrice;

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

        IMarginAccount(s_marginAccount).unlockFunds(msg.sender, tokenAddress);

        emit LimitSellCompleted(msg.sender, _orderId, _order.size);
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

        IMarginAccount(s_marginAccount).unlockFunds(msg.sender, tokenAddress);

        emit LimitBuyCompleted(msg.sender, _orderId, _order.size);
    }

    /**
     * @dev Places and executes a market buy order.
     * @param _size Size of the market buy order.
     */
    function placeAndExecuteMarketBuy(uint256 _size, address _user) external {
        require(msg.sender == s_positionManager || msg.sender == _user, "OrderBook: only user or position manager can execute");
        require(_size > 0, "OrderBook: size must be greater than 0");

        // load the first price point into memory
        uint256 _minAsk = s_sellOrdersHeap[0];

        PricePoint memory m_pricePoint = s_sellPricePoints[_minAsk];
        uint256 _volumeAtPricePoint = m_pricePoint.totalOrdersAtPrice - m_pricePoint.totalCompletedOrCanceledOrders - m_pricePoint.executableSize;

        uint256 _priceToPay = 0;
        uint256 _executedSize = 0;

        while (_size >= _volumeAtPricePoint) {
            _priceToPay += _volumeAtPricePoint.mul(_minAsk);
            m_pricePoint.executableSize += _volumeAtPricePoint;
            _size -= _volumeAtPricePoint;
            _executedSize += _volumeAtPricePoint;
            uint256 _heapLength = _popSellOrderHeap();

            // update price point storage variable
            s_sellPricePoints[_minAsk] = m_pricePoint;

            // load the next price point into memory if exists
            if (_heapLength == 0) {
                break;
            }
            _minAsk = s_sellOrdersHeap[0];
            m_pricePoint = s_sellPricePoints[_minAsk];

            _volumeAtPricePoint = m_pricePoint.totalOrdersAtPrice - m_pricePoint.totalCompletedOrCanceledOrders - m_pricePoint.executableSize;
        }

        if (_size > 0 && s_sellOrdersHeap.length > 0) {
            _priceToPay += _size.mul(_minAsk);
            m_pricePoint.executableSize += _size;

            // update overall executed size
            _executedSize += _size;

            // update price point storage variable
            s_sellPricePoints[_minAsk] = m_pricePoint;
        }

        IPositionManager(s_positionManager).increasePosition(_user, tokenAddress, _executedSize, _priceToPay.div(sizePrecision));

        emit MarketBuyExecuted(_user, _executedSize);
    }

    /**
     * @dev Places and executes a market sell order.
     * @param _size Size of the market sell order.
     */
    function placeAndExecuteMarketSell(uint256 _size, address _user) external {
        require(msg.sender == s_positionManager || msg.sender == _user, "OrderBook: only user or position manager can execute");
        require(_size > 0, "OrderBook: size must be greater than 0");
        
        // load the first price point into memory
        uint256 _maxBid = s_buyOrdersHeap[0];

        PricePoint memory m_pricePoint = s_buyPricePoints[_maxBid];
        uint256 _volumeAtPricePoint = m_pricePoint.totalOrdersAtPrice - m_pricePoint.totalCompletedOrCanceledOrders - m_pricePoint.executableSize;
        
        uint256 _priceToPay = 0;
        uint256 _executedSize = 0;

        while (_size > _volumeAtPricePoint) {
            _priceToPay += _volumeAtPricePoint.mul(_maxBid);
            m_pricePoint.executableSize += _volumeAtPricePoint;
            _size -= _volumeAtPricePoint;
            _executedSize += _volumeAtPricePoint;
            uint256 _heapLength = _popBuyOrderHeap();

            // update price point storage variable
            s_buyPricePoints[_maxBid] = m_pricePoint;

            // load the next price point into memory if exists
            if (_heapLength == 0) {
                break;
            }
            _maxBid = s_buyOrdersHeap[0];
            m_pricePoint = s_buyPricePoints[_maxBid];

            _volumeAtPricePoint = m_pricePoint.totalOrdersAtPrice - m_pricePoint.totalCompletedOrCanceledOrders - m_pricePoint.executableSize;
        }

        if (_size > 0 && s_buyOrdersHeap.length > 0) {
            _priceToPay += _size.mul(s_buyOrdersHeap[0]);
            m_pricePoint.executableSize += _size;

            // update overall executed size
            _executedSize += _size;

            // update price point storage variable
            s_buyPricePoints[_maxBid] = m_pricePoint;
        }

        IPositionManager(s_positionManager).decreasePosition(_user, tokenAddress, _executedSize, _priceToPay.div(sizePrecision));

        emit MarketSellExecuted(_user, _executedSize);
    }

    /**
     * @dev Claims a sell limit order.
     * @param _orderId ID of the sell limit order to claim.
     */
    function claimSellLimitOrder(uint256 _orderId) external {
        Order storage _order = s_orders[_orderId];
        require(_order.ownerAddress != address(0), "OrderBook: order doesn't exist");
        require(msg.sender == _order.ownerAddress, "OrderBook: only order owner can claim");

        PricePoint storage _pricePoint = s_sellPricePoints[_order.price];
        require(_order.acceptableRange < _pricePoint.executableSize + _pricePoint.totalCompletedOrCanceledOrders, "OrderBook: order not executable");

        uint256 _executableSize = _pricePoint.executableSize + _pricePoint.totalCompletedOrCanceledOrders - _order.acceptableRange;

        uint256 _sizeToExecute = _executableSize > _order.size
            ? _order.size
            : _executableSize;

        _order.size -= _sizeToExecute;
        _pricePoint.totalCompletedOrCanceledOrders += _sizeToExecute;
        _pricePoint.executableSize -= _sizeToExecute;

        IPositionManager(s_positionManager).decreasePosition(msg.sender, tokenAddress, _sizeToExecute, _sizeToExecute.mul(_order.price).div(sizePrecision));

        if (_order.size == 0) {
            delete s_orders[_orderId];
            IMarginAccount(s_marginAccount).unlockFunds(msg.sender, tokenAddress);
        }

        emit LimitSellCompleted(msg.sender, _orderId, _sizeToExecute);
    }

    /**
     * @dev Claims a buy limit order.
     * @param _orderId ID of the buy limit order to claim.
     */
    function claimBuyLimitOrder(uint256 _orderId) external {
        Order storage _order = s_orders[_orderId];
        require(_order.ownerAddress != address(0), "OrderBook: order doesn't exist");
        require(msg.sender == _order.ownerAddress, "OrderBook: only order owner can claim");

        PricePoint storage _pricePoint = s_buyPricePoints[_order.price];
        require(_order.acceptableRange < _pricePoint.executableSize + _pricePoint.totalCompletedOrCanceledOrders, "OrderBook: order not executable");

        uint256 _executableSize = _pricePoint.executableSize + _pricePoint.totalCompletedOrCanceledOrders - _order.acceptableRange;

        uint256 _sizeToExecute = _executableSize > _order.size
            ? _order.size
            : _executableSize;

        _order.size -= _sizeToExecute;
        _pricePoint.totalCompletedOrCanceledOrders += _sizeToExecute;
        _pricePoint.executableSize -= _sizeToExecute;

        IPositionManager(s_positionManager).increasePosition(msg.sender, tokenAddress, _sizeToExecute, _sizeToExecute.mul(_order.price).div(sizePrecision));

        if (_order.size == 0) {
            delete s_orders[_orderId];
            IMarginAccount(s_marginAccount).unlockFunds(msg.sender, tokenAddress);
        }

        emit LimitBuyCompleted(msg.sender, _orderId, _sizeToExecute);
    }

    /**
     * @dev Internal function to insert a buy price into the buy orders heap.
     * @param _price Price to insert.
     */
    function _insertBuyPrice(uint96 _price) private {
        uint256 idx = s_buyOrdersHeap.length;
        s_buyOrdersHeap.push(_price);

        while (idx > 0) {
            uint256 parentIdx = (idx - 1) / 2;
            if (s_buyOrdersHeap[parentIdx] >= s_buyOrdersHeap[idx]) {
                break;
            }
            (s_buyOrdersHeap[idx], s_buyOrdersHeap[parentIdx]) = (
                s_buyOrdersHeap[parentIdx],
                s_buyOrdersHeap[idx]
            );
            idx = parentIdx;
        }
    }

    /**
     * @dev Internal function to insert a sell price into the sell orders heap.
     * @param _price Price to insert.
     */
    function _insertSellPrice(uint96 _price) private {
        uint256 idx = s_sellOrdersHeap.length;
        s_sellOrdersHeap.push(_price);

        while (idx > 0) {
            uint256 parentIdx = (idx - 1) / 2;
            if (s_sellOrdersHeap[parentIdx] <= s_sellOrdersHeap[idx]) {
                break;
            }
            (s_sellOrdersHeap[idx], s_sellOrdersHeap[parentIdx]) = (
                s_sellOrdersHeap[parentIdx],
                s_sellOrdersHeap[idx]
            );
            idx = parentIdx;
        }
    }

    /**
     * @dev Internal function to remove the top buy order from the buy orders heap.
     */
    function _popBuyOrderHeap() private returns (uint256) {
        uint256 _heapLength = s_buyOrdersHeap.length;
        require(_heapLength >= 1, "OrderBook: No buy orders available");

        s_buyOrdersHeap[0] = s_buyOrdersHeap[_heapLength - 1];
        s_buyOrdersHeap.pop();

        _heapifyBuyOrders(0);

        // returns updated length of the heap
        return _heapLength - 1;
    }

    /**
     * @dev Internal function to remove the top sell order from the sell orders heap.
     */
    function _popSellOrderHeap() private returns (uint256) {
        uint256 _heapLength = s_sellOrdersHeap.length;
        require(_heapLength >= 1, "OrderBook: No sell orders available");

        s_sellOrdersHeap[0] = s_sellOrdersHeap[_heapLength - 1];
        s_sellOrdersHeap.pop();

        _heapifySellOrders(0);

        // returns updated length of the heap
        return _heapLength - 1;
    }

    /**
     * @dev Internal function to heapify the buy orders heap.
     * @param _index Index to start heapifying from.
     */
    function _heapifyBuyOrders(uint256 _index) private {
        uint256 largest = _index;

        while (true) {
            uint256 leftChild = _index * 2 + 1;
            uint256 rightChild = leftChild + 1;

            if (leftChild < s_buyOrdersHeap.length && s_buyOrdersHeap[leftChild] > s_buyOrdersHeap[largest]) {
                largest = leftChild;
            }

            if (rightChild < s_buyOrdersHeap.length && s_buyOrdersHeap[rightChild] > s_buyOrdersHeap[largest]) {
                largest = rightChild;
            }

            if (largest == _index) {
                break;
            }

            (s_buyOrdersHeap[_index], s_buyOrdersHeap[largest]) = (s_buyOrdersHeap[largest], s_buyOrdersHeap[_index]);
            _index = largest;
        }
    }


    /**
     * @dev Internal function to heapify the sell orders heap.
     * @param _index Index to start heapifying from.
     */
    function _heapifySellOrders(uint256 _index) private {
        uint256 smallest = _index;

        while (true) {
            uint256 leftChild = _index * 2 + 1;
            uint256 rightChild = leftChild + 1;

            if (leftChild < s_sellOrdersHeap.length && s_sellOrdersHeap[leftChild] < s_sellOrdersHeap[smallest]) {
                smallest = leftChild;
            }

            if (rightChild < s_sellOrdersHeap.length && s_sellOrdersHeap[rightChild] < s_sellOrdersHeap[smallest]) {
                smallest = rightChild;
            }

            if (smallest == _index) {
                break;
            }

            (s_sellOrdersHeap[_index], s_sellOrdersHeap[smallest]) = (s_sellOrdersHeap[smallest], s_sellOrdersHeap[_index]);
            _index = smallest;
        }
    }

    /**
     * @dev Returns the current price points in the order book.
     * @return The lowest sell price and the highest buy price.
     */
    function pricePoints() external override view returns (uint256, uint256) {
        return (s_sellOrdersHeap[0], s_buyOrdersHeap[0]);
    }
}
