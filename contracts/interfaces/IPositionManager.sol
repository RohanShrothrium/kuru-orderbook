// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0; 

interface IPositionManager {
    function increasePosition(
        address _user,
        address _indexToken,
        uint256 _size,
        uint256 _priceToPay
    ) external;

    function decreasePosition(
        address _user,
        address _indexToken,
        uint256 _size,
        uint256 _priceToPay
    ) external;
}
