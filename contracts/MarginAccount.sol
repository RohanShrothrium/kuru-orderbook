// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libraries/IERC20.sol";

import "./interfaces/IMarginAccount.sol";

contract MarginAccount is IMarginAccount {
    // Mapping to store user balances for different positions
    mapping(bytes32 => uint256) public balances;
    
    // Mapping to store locked funds for each user
    mapping(address => uint256) public lockedFunds;

    // ERC20 token used for transactions
    IERC20 public usdcToken;

    // Address of the governing body
    address public gov;

    // Address of the position manager contract
    address public positionManager;

    // Mapping to store the order book address for each index token
    mapping(address => address) orderBookMap;

    // Penalty amount for insufficient funds
    uint256 insufficiantFundsPenalty;

    // Event emitted when a user deposits funds
    event Deposit(address indexed user, uint256 amount);

    // Event emitted when a user withdraws funds
    event Withdraw(address indexed user, uint256 amount);

    /**
     * @dev Constructor.
     * @param _usdcToken Address of the USDC token contract.
     */
    constructor(address _usdcToken) {
        usdcToken = IERC20(_usdcToken);
        gov = msg.sender;
    }

    /**
     * @dev Adds an order book address for an index token.
     * Only the governing body can call this function.
     * @param _orderBook Address of the order book contract.
     * @param _indexToken Address of the index token.
     */
    function addOrderBook(address _orderBook, address _indexToken) external {
        _onlyGov();
        orderBookMap[_indexToken] = _orderBook;
    }

    /**
     * @dev Sets the position manager adderss.
     * Only the governing body can call this function.
     * @param _positionManager updated address.
     */
    function setPositionManager(address _positionManager) external {
        _onlyGov();
        positionManager = _positionManager;
    }

    /**
     * @dev Generates a unique key for a user's position.
     * @param _user Address of the user.
     * @param _token Address of the token.
     * @return Unique key for the position.
     */
    function getPositionKey(address _user, address _token) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _token));
    }

    /**
     * @dev Allows a user to deposit funds into their margin account.
     * The user must approve the contract to transfer the funds on their behalf.
     * @param _amount Amount to deposit.
     * @param _indexToken Address of the index token.
     */
    function deposit(uint256 _amount, address _indexToken) external {
        require(_amount > 0, "MarginAccount: Amount must be greater than zero");
        require(
            usdcToken.transferFrom(msg.sender, address(this), _amount),
            "MarginAccount: TransferFrom failed"
        );

        balances[getPositionKey(msg.sender, _indexToken)] += _amount;
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @dev Allows a user to withdraw funds from their margin account.
     * @param _amount Amount to withdraw.
     * @param _indexToken Address of the index token.
     */
    function withdraw(uint256 _amount, address _indexToken) external {
        require(_amount > 0, "MarginAccount: Amount must be greater than zero");
        // TODO: update this with validation with position PnL
        require(_amount <= balances[getPositionKey(msg.sender, _indexToken)], "MarginAccount: Insufficient balance");

        balances[getPositionKey(msg.sender, _indexToken)] -= _amount;
        require(usdcToken.transfer(msg.sender, _amount), "MarginAccount: Transfer failed");

        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @dev Locks funds in a user's margin account.
     * Only the associated order book contract can call this function.
     * @param _user Address of the user.
     * @param _indexToken Address of the index token.
     */
    function lockFunds(address _user, address _indexToken) external override {
        require(msg.sender == orderBookMap[_indexToken], "MarginAccount: only order book can make this call");
        require(balances[getPositionKey(_user, _indexToken)] > insufficiantFundsPenalty, "MarginAccount: insufficient funds");

        lockedFunds[_user] += insufficiantFundsPenalty;
        balances[getPositionKey(_user, _indexToken)] -= insufficiantFundsPenalty;
    }

    /**
     * @dev Unlocks previously locked funds in a user's margin account.
     * Only the associated order book contract can call this function.
     * @param _user Address of the user.
     * @param _indexToken Address of the index token.
     */
    function unlockFunds(address _user, address _indexToken) external override {
        require(msg.sender == orderBookMap[_indexToken], "MarginAccount: only order book can make this call");
        require(lockedFunds[_user] >= insufficiantFundsPenalty, "MarginAccount: insufficient funds");

        lockedFunds[_user] -= insufficiantFundsPenalty;
        balances[getPositionKey(_user, _indexToken)] += insufficiantFundsPenalty;
    }

    /**
     * @dev Updates the funding fee for a user's position.
     * Only the position manager contract can call this function.
     * @param _user Address of the user.
     * @param _indexToken Address of the index token.
     * @param _fundingFee Funding fee to be applied (positive or negative).
     * @return Updated balance after applying the funding fee.
     */
    function updateFundingFee(address _user, address _indexToken, int256 _fundingFee) external override returns (uint256) {
        require(msg.sender == positionManager, "MarginAccount: only position manager can make this call");

        bytes32 _balanceKey = getPositionKey(_user, _indexToken);
        if (_fundingFee <= 0) {
            balances[_balanceKey] += uint256(-_fundingFee);
        } else {
            // Instead of this, you need to liquidate user positions
            require(balances[_balanceKey] > uint256(_fundingFee), "MarginAccount: insufficient funds");

            balances[_balanceKey] -= uint256(_fundingFee);
        }

        return balances[_balanceKey];
    }

    /**
     * @dev Changes the governing body address.
     * Only the current governing body can call this function.
     * @param newGov Address of the new governing body.
     */
    function changeGov(address newGov) external {
        _onlyGov();
        require(newGov != address(0), "MarginAccount: Gov cannot be zero address");
        gov = newGov;
    }

    /**
     * @dev Restricts function access to the governing body.
     */
    function _onlyGov() private view {
        require(msg.sender == gov, "MarginAccount: Only gov can call this function");
    }
}
