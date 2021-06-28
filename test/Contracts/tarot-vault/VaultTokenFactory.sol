pragma solidity =0.5.16;

import "./VaultToken.sol";
import "./interfaces/IMasterChef.sol";
import "./interfaces/IVaultTokenFactory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Router01.sol";

contract VaultTokenFactory is IVaultTokenFactory {
    address public router;
    address public masterChef;
    address public rewardsToken;
    uint256 public swapFeeFactor;

    mapping(uint256 => address) public getVaultToken;
    address[] public allVaultTokens;

    event VaultTokenCreated(
        uint256 indexed pid,
        address vaultToken,
        uint256 vaultTokenIndex
    );

    constructor(
        address _router,
        address _masterChef,
        address _rewardsToken,
        uint256 _swapFeeFactor
    ) public {
        require(
            _swapFeeFactor >= 900 && _swapFeeFactor <= 1000,
            "VaultTokenFactory: INVALID_FEE_FACTOR"
        );
        router = _router;
        masterChef = _masterChef;
        rewardsToken = _rewardsToken;
        swapFeeFactor = _swapFeeFactor;
    }

    function allVaultTokensLength() external view returns (uint256) {
        return allVaultTokens.length;
    }

    function createVaultToken(uint256 pid)
        external
        returns (address vaultToken)
    {
        require(
            getVaultToken[pid] == address(0),
            "VaultTokenFactory: PID_EXISTS"
        );
        bytes memory bytecode = type(VaultToken).creationCode;
        assembly {
            vaultToken := create2(0, add(bytecode, 32), mload(bytecode), pid)
        }
        VaultToken(vaultToken)._initialize(
            IUniswapV2Router01(router),
            IMasterChef(masterChef),
            rewardsToken,
            swapFeeFactor,
            pid
        );
        getVaultToken[pid] = vaultToken;
        allVaultTokens.push(vaultToken);
        emit VaultTokenCreated(pid, vaultToken, allVaultTokens.length);
    }
}
