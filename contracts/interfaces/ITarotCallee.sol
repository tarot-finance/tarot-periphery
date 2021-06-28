pragma solidity >=0.5.0;

interface ITarotCallee {
    function tarotBorrow(address sender, address borrower, uint borrowAmount, bytes calldata data) external;
    function tarotRedeem(address sender, uint redeemAmount, bytes calldata data) external;
}