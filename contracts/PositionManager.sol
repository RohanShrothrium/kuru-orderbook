// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

import "./interfaces/IOrderBook.sol";
import "./interfaces/IMarginAccount.sol";

// size is 10**10
// price is 10**2
// price feed is 10**8
contract PositionManager {
    using SafeMath for uint256;
    struct Position {
        int256 size;
        int256 entryFundingRate;
        int256 amountToPay;
    }

    address public gov;

    mapping(bytes32 => Position) public s_positions;

    mapping(address => int256) public s_cumulativeFundingRates;
    mapping(address => uint256) public s_lastFundingTimes;
    mapping(address => address) public s_oracles;
    mapping(address => bytes32) public s_pythOracleIds;

    mapping(address => address) s_orderBookMap;
    address public marginAccount;

    IPyth pyth;

    // constants
    uint256 constant FUNDING_INTERVAL = 1 hours;
    int256 constant PRICE_TO_USDC = 10**4;
    int256 constant PRICE_TO_PRICE_FEED = 10**6;
    int256 constant SIZE_PRECISSION = 10**10;
    int256 constant MAX_LVG = 50;

    constructor(address _marginAccount, address _pythAddress) {
        marginAccount = _marginAccount;
        pyth = IPyth(_pythAddress);
    
        gov = msg.sender;
    }

    function setMarginAccount(address _marginAccount) external {
        _onlyGov();
        marginAccount = _marginAccount;
    }

    function addOrderBook(address _orderBook, address _indexToken) external {
        _onlyGov();
        s_orderBookMap[_indexToken] = _orderBook;
    }

    function addPythOracle(bytes32 _id, address _indexToken) external {
        _onlyGov();
        s_pythOracleIds[_indexToken] = _id;
    }

    function updateFundingRate(address _indexToken) external {
        if (s_lastFundingTimes[_indexToken].add(FUNDING_INTERVAL) > block.timestamp) {
            return;
        }

        s_lastFundingTimes[_indexToken] = block.timestamp.div(FUNDING_INTERVAL).mul(FUNDING_INTERVAL);

        PythStructs.Price memory _pythPrice =  pyth.getPrice(s_pythOracleIds[_indexToken]);
        int256 _indexPrice = _pythPrice.price;

        (uint256 _bid, uint256 _ask) = IOrderBook(s_orderBookMap[_indexToken]).pricePoints();

        _updateFundingRate(int256(_bid), int256(_ask), _indexPrice / PRICE_TO_PRICE_FEED, _indexToken);
    }

    function _updateFundingRate(int256 _bid, int256 _ask, int256 _indexPrice, address _indexToken) public {
        int _signedIntToAdd = _bid > _indexPrice ? _bid - _indexPrice : _indexPrice - _ask;
        s_cumulativeFundingRates[_indexToken] += _signedIntToAdd;
    }

    function getPositionKey(address user, address token) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(user, token));
    }


    function increasePosition(
        address _user,
        address _indexToken,
        uint256 _size,
        uint256 _priceToPay
    ) external {
        // load funding and position data into memory
        bytes32 _positionKey = getPositionKey(_user, _indexToken);
        Position memory m_position = s_positions[_positionKey];
        int256 _fundingRate = s_cumulativeFundingRates[_indexToken];

        // calculate funding fee and deduct from margin account
        int256 _fundingFee = m_position.size == 0 ? int256(0) : _fundingRate - m_position.entryFundingRate;
        uint256 _userMargin = IMarginAccount(marginAccount).updateFundingFee(_user, _indexToken, _fundingFee * PRICE_TO_USDC);

        // update entry funding rate for the position
        m_position.entryFundingRate = _fundingRate;

        // validate if user margin supports the update to position
        validateMargin(_positionKey, _indexToken, int256(_userMargin) / PRICE_TO_USDC, int256(_size));

        // update position
        m_position.size += int256(_size);
        m_position.amountToPay += int256(_priceToPay);

        // update position in storage
        s_positions[_positionKey] = m_position;
    }

    function decreasePosition(
        address _user,
        address _indexToken,
        uint256 _size,
        uint256 _priceToPay
    ) external {
        // load funding and position data into memory
        bytes32 _positionKey = getPositionKey(_user, _indexToken);
        Position memory m_position = s_positions[_positionKey];
        int256 _fundingRate = s_cumulativeFundingRates[_indexToken];

        // calculate funding fee and deduct from margin account
        int256 _fundingFee = m_position.size == 0 ? int256(0) : _fundingRate - m_position.entryFundingRate;
        uint256 _userMargin = IMarginAccount(marginAccount).updateFundingFee(_user, _indexToken, _fundingFee * PRICE_TO_USDC);

        // update entry funding rate for the position
        m_position.entryFundingRate = _fundingRate;

        // validate if user margin supports the update to position
        validateMargin(_positionKey, _indexToken, int256(_userMargin) / PRICE_TO_USDC, int256(_size));

        // update position
        m_position.size -= int256(_size);
        m_position.amountToPay -= int256(_priceToPay);

        // Clean up the position if the size becomes zero
        if (m_position.size == 0) {
            delete s_positions[_positionKey];
            return;
        }

        // update position in storage
        s_positions[_positionKey] = m_position;
    }

    function positionValue(
        address _user,
        address _indexToken
    ) external view returns (int256) {
        bytes32 _positionKey = getPositionKey(_user, _indexToken);
        Position memory _position = s_positions[_positionKey];

        PythStructs.Price memory _pythPrice =  pyth.getPrice(s_pythOracleIds[_indexToken]);
        int256 _indexPrice = _pythPrice.price;

        return (_position.size * _indexPrice) / SIZE_PRECISSION / PRICE_TO_PRICE_FEED - _position.amountToPay;
    }

    function liquidatePosition(
        address _user,
        address _indexToken
    ) external {
        bytes32 _positionKey = getPositionKey(_user, _indexToken);

        // load funding and position data into memory
        Position memory m_position = s_positions[_positionKey];
        int256 _fundingRate = s_cumulativeFundingRates[_indexToken];

        // assert statements
        require(m_position.size != 0, "Position does not exist");

        // calculate funding fee and deduct from margin account
        int256 _fundingFee = _fundingRate - m_position.entryFundingRate;
        uint256 _userMargin = IMarginAccount(marginAccount).updateFundingFee(_user, _indexToken, _fundingFee * PRICE_TO_USDC);

        PythStructs.Price memory _pythPrice =  pyth.getPrice(s_pythOracleIds[_indexToken]);
        int256 _indexPrice = _pythPrice.price;

        int256 _positionValue = (m_position.size * _indexPrice) / SIZE_PRECISSION / PRICE_TO_PRICE_FEED - m_position.amountToPay;

        require(_positionValue < 0, "Position is not liquidatable");
        require(int256(_userMargin) + _positionValue < (m_position.size * _indexPrice) / SIZE_PRECISSION / PRICE_TO_PRICE_FEED / MAX_LVG, "Position is not liquidatable");
        
        // TODO: liquidate position by adding market orders to the orderbook
        if (m_position.size > 0) {
            IOrderBook(s_orderBookMap[_indexToken]).placeAndExecuteMarketSell(uint256(m_position.size), _user);
        } else {
            IOrderBook(s_orderBookMap[_indexToken]).placeAndExecuteMarketBuy(uint256(-m_position.size), _user);
        }
    }

    function validateMargin(
        bytes32 _positionKey,
        address _indexToken,
        int256 _userMargin,
        int256 _size
    ) public view {
        Position memory _position = s_positions[_positionKey];

        PythStructs.Price memory _pythPrice =  pyth.getPrice(s_pythOracleIds[_indexToken]);
        int256 _indexPrice = _pythPrice.price;

        int256 _positionValue = (_position.size * _indexPrice) / SIZE_PRECISSION / PRICE_TO_PRICE_FEED - _position.amountToPay;

        int256 _updatedSize = _position.size + _size;

        require((_userMargin + _positionValue) * MAX_LVG > (_updatedSize * _indexPrice) / SIZE_PRECISSION / PRICE_TO_PRICE_FEED, "insufficiant margin to create position");
    }

    /**
     * @dev Restricts function access to the governing body.
     */
    function _onlyGov() public view {
        require(msg.sender == gov, "only gov can call this function");
    }
}
