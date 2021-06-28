pragma solidity >=0.5.0;

interface IBorrowTracker {
    function trackBorrow(
        address borrower,
        uint256 borrowBalance,
        uint256 borrowIndex
    ) external;
}
