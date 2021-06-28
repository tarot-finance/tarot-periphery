pragma solidity =0.5.16;

import "./PoolToken.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IVaultToken.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./libraries/SafeToken.sol";
import "./libraries/Math.sol";

contract VaultToken is IVaultToken, IUniswapV2Pair, PoolToken {
    using SafeToken for address;

    bool public constant isVaultToken = true;

    IUniswapV2Router01 public router;
    IMasterChef public masterChef;
    address public rewardsToken;
    address public WETH;
    address public token0;
    address public token1;
    uint256 public swapFeeFactor;
    uint256 public pid;
    uint256 public constant REINVEST_BOUNTY = 0.01e18;

    event Reinvest(address indexed caller, uint256 reward, uint256 bounty);

    function _initialize(
        IUniswapV2Router01 _router,
        IMasterChef _masterChef,
        address _rewardsToken,
        uint256 _swapFeeFactor,
        uint256 _pid
    ) external {
        require(factory == address(0), "VaultToken: FACTORY_ALREADY_SET"); // sufficient check
        factory = msg.sender;
        _setName("Tarot Vault Token", "vTAROT");
        WETH = _router.WETH();
        router = _router;
        masterChef = _masterChef;
        swapFeeFactor = _swapFeeFactor;
        pid = _pid;
        (IERC20 _underlying, , , ) = masterChef.poolInfo(_pid);
        underlying = address(_underlying);
        token0 = IUniswapV2Pair(underlying).token0();
        token1 = IUniswapV2Pair(underlying).token1();
        rewardsToken = _rewardsToken;
        rewardsToken.safeApprove(address(router), uint256(-1));
        WETH.safeApprove(address(router), uint256(-1));
        underlying.safeApprove(address(masterChef), uint256(-1));
    }

    /*** PoolToken Overrides ***/

    function _update() internal {
        (uint256 _totalBalance, ) = masterChef.userInfo(pid, address(this));
        totalBalance = _totalBalance;
        emit Sync(totalBalance);
    }

    // this low-level function should be called from another contract
    function mint(address minter)
        external
        nonReentrant
        update
        returns (uint256 mintTokens)
    {
        uint256 mintAmount = underlying.myBalance();
        // handle pools with deposit fees by checking balance before and after deposit
        (uint256 _totalBalanceBefore, ) = masterChef.userInfo(
            pid,
            address(this)
        );
        masterChef.deposit(pid, mintAmount);
        (uint256 _totalBalanceAfter, ) = masterChef.userInfo(
            pid,
            address(this)
        );

        mintTokens = _totalBalanceAfter.sub(_totalBalanceBefore).mul(1e18).div(
            exchangeRate()
        );

        if (totalSupply == 0) {
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            mintTokens = mintTokens.sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY);
        }
        require(mintTokens > 0, "VaultToken: MINT_AMOUNT_ZERO");
        _mint(minter, mintTokens);
        emit Mint(msg.sender, minter, mintAmount, mintTokens);
    }

    // this low-level function should be called from another contract
    function redeem(address redeemer)
        external
        nonReentrant
        update
        returns (uint256 redeemAmount)
    {
        uint256 redeemTokens = balanceOf[address(this)];
        redeemAmount = redeemTokens.mul(exchangeRate()).div(1e18);

        require(redeemAmount > 0, "VaultToken: REDEEM_AMOUNT_ZERO");
        require(redeemAmount <= totalBalance, "VaultToken: INSUFFICIENT_CASH");
        _burn(address(this), redeemTokens);
        masterChef.withdraw(pid, redeemAmount);
        _safeTransfer(redeemer, redeemAmount);
        emit Redeem(msg.sender, redeemer, redeemAmount, redeemTokens);
    }

    /*** Reinvest ***/

    function _optimalDepositA(
        uint256 _amountA,
        uint256 _reserveA,
        uint256 _swapFeeFactor
    ) internal pure returns (uint256) {
        uint256 a = uint256(1000).add(_swapFeeFactor).mul(_reserveA);
        uint256 b = _amountA.mul(1000).mul(_reserveA).mul(4).mul(
            _swapFeeFactor
        );
        uint256 c = Math.sqrt(a.mul(a).add(b));
        uint256 d = uint256(2).mul(_swapFeeFactor);
        return c.sub(a).div(d);
    }

    function approveRouter(address token, uint256 amount) internal {
        if (IERC20(token).allowance(address(this), address(router)) >= amount)
            return;
        token.safeApprove(address(router), uint256(-1));
    }

    function swapExactTokensForTokens(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(tokenIn);
        path[1] = address(tokenOut);
        approveRouter(tokenIn, amount);
        router.swapExactTokensForTokens(amount, 0, path, address(this), now);
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal returns (uint256 liquidity) {
        approveRouter(tokenA, amountA);
        approveRouter(tokenB, amountB);
        (, , liquidity) = router.addLiquidity(
            tokenA,
            tokenB,
            amountA,
            amountB,
            0,
            0,
            address(this),
            now
        );
    }

    function reinvest() external nonReentrant update {
        require(msg.sender == tx.origin);
        // 1. Withdraw all the rewards.
        masterChef.withdraw(pid, 0);
        uint256 reward = rewardsToken.myBalance();
        if (reward == 0) return;
        // 2. Send the reward bounty to the caller.
        uint256 bounty = reward.mul(REINVEST_BOUNTY) / 1e18;
        rewardsToken.safeTransfer(msg.sender, bounty);
        // 3. Convert all the remaining rewards to token0 or token1.
        address tokenA;
        address tokenB;
        if (token0 == rewardsToken || token1 == rewardsToken) {
            (tokenA, tokenB) = token0 == rewardsToken
                ? (token0, token1)
                : (token1, token0);
        } else {
            swapExactTokensForTokens(rewardsToken, WETH, reward.sub(bounty));
            if (token0 == WETH || token1 == WETH) {
                (tokenA, tokenB) = token0 == WETH
                    ? (token0, token1)
                    : (token1, token0);
            } else {
                swapExactTokensForTokens(WETH, token0, WETH.myBalance());
                (tokenA, tokenB) = (token0, token1);
            }
        }
        // 4. Convert tokenA to LP Token underlyings.
        uint256 totalAmountA = tokenA.myBalance();
        assert(totalAmountA > 0);
        (uint256 r0, uint256 r1, ) = IUniswapV2Pair(underlying).getReserves();
        uint256 reserveA = tokenA == token0 ? r0 : r1;
        uint256 swapAmount = _optimalDepositA(
            totalAmountA,
            reserveA,
            swapFeeFactor
        );
        swapExactTokensForTokens(tokenA, tokenB, swapAmount);
        uint256 liquidity = addLiquidity(
            tokenA,
            tokenB,
            totalAmountA.sub(swapAmount),
            tokenB.myBalance()
        );
        // 5. Stake the LP Tokens.
        masterChef.deposit(pid, liquidity);
        emit Reinvest(msg.sender, reward, bounty);
    }

    /*** Mirrored From uniswapV2Pair ***/

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        )
    {
        (reserve0, reserve1, blockTimestampLast) = IUniswapV2Pair(underlying)
        .getReserves();
        // if no token has been minted yet mirror uniswap getReserves
        if (totalSupply == 0) return (reserve0, reserve1, blockTimestampLast);
        // else, return the underlying reserves of this contract
        uint256 _totalBalance = totalBalance;
        uint256 _totalSupply = IUniswapV2Pair(underlying).totalSupply();
        reserve0 = safe112(_totalBalance.mul(reserve0).div(_totalSupply));
        reserve1 = safe112(_totalBalance.mul(reserve1).div(_totalSupply));
        require(
            reserve0 > 100 && reserve1 > 100,
            "VaultToken: INSUFFICIENT_RESERVES"
        );
    }

    function price0CumulativeLast() external view returns (uint256) {
        return IUniswapV2Pair(underlying).price0CumulativeLast();
    }

    function price1CumulativeLast() external view returns (uint256) {
        return IUniswapV2Pair(underlying).price1CumulativeLast();
    }

    /*** Utilities ***/

    function safe112(uint256 n) internal pure returns (uint112) {
        require(n < 2**112, "VaultToken: SAFE112");
        return uint112(n);
    }
}
