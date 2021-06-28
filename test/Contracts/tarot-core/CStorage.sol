pragma solidity =0.5.16;

contract CStorage {
    address public borrowable0;
    address public borrowable1;
    address public tarotPriceOracle;
    uint256 public safetyMarginSqrt = 1.58113883e18; //safetyMargin: 250%
    uint256 public liquidationIncentive = 1.04e18; //4%
}
