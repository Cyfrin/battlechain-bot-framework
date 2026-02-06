// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "./AttackBase.sol";
import "./interfaces/aave/IAaveV3.sol";
import "./interfaces/aave/IAaveV2.sol";
import "./interfaces/balancer/IBalancerV2.sol";
import "./interfaces/uniswap/IUniswapV3.sol";
import "./interfaces/uniswap/IUniswapV2.sol";
import "./interfaces/maker/IMaker.sol";

abstract contract FlashLoanProvider{

    enum Provider {
        AAVE_V3,
        AAVE_V2,
        BALANCER,
        UNISWAP_V3,
        UNISWAP_V2,
        MAKER
    }

    struct FlashLoanParams {
        Provider provider;
        address[] tokens;
        uint256[] amounts;
        bytes userData;
    }

    address public aaveV3Pool;
    address public aaveV2Pool;
    address public balancerVault;
    address public makerDssFlash;

    // ============ Execution State ============
    bool internal _inFlashLoan;

    error InvalidProvider();
    error FlashLoanFailed();
    error NotInFlashLoan();

    // ============ Flash Loan Execution ============

    function _executeFlashLoan(
        address target,
        FlashLoanParams memory params
    ) internal {
        _inFlashLoan = true;

        if (params.provider == Provider.AAVE_V3) {
            _executeAaveV3FlashLoan(params);
        } else if (params.provider == Provider.AAVE_V2) {
            _executeAaveV2FlashLoan(params);
        } else if (params.provider == Provider.BALANCER) {
            _executeBalancerFlashLoan(params);
        } else if (params.provider == Provider.UNISWAP_V3) {
            _executeUniswapV3FlashLoan(params);
        } else if (params.provider == Provider.UNISWAP_V2) {
            _executeUniswapV2FlashLoan(params);
        } else if (params.provider == Provider.MAKER) {
            _executeMakerFlashLoan(params);
        } else {
            revert InvalidProvider();
        }

        _inFlashLoan = false;
    }

    // ============ Provider-Specific Execution ============

    function _executeAaveV3FlashLoan(FlashLoanParams memory params) internal {
        uint256[] memory modes = new uint256[](params.tokens.length);

        ILendingPoolV3(aaveV3Pool).flashLoan(
            address(this),
            params.tokens,
            params.amounts,
            modes,
            address(this),
            params.userData,
            0 // referral code
        );
    }

    function _executeAaveV2FlashLoan(FlashLoanParams memory params) internal {
        uint256[] memory modes = new uint256[](params.tokens.length);

        ILendingPoolV2(aaveV2Pool).flashLoan(
            address(this),
            params.tokens,
            params.amounts,
            modes,
            address(this),
            params.userData,
            0
        );
    }

    function _executeBalancerFlashLoan(FlashLoanParams memory params) internal {
        IBalancerVault(balancerVault).flashLoan(
            address(this),
            params.tokens,
            params.amounts,
            params.userData
        );
    }

    function _executeUniswapV3FlashLoan(FlashLoanParams memory params) internal {
        // Pool address should be encoded in userData
        (address pool, uint256 amount0, uint256 amount1) = abi.decode(
            params.userData,
            (address, uint256, uint256)
        );

        IUniswapV3Pool(pool).flash(
            address(this),
            amount0,
            amount1,
            params.userData
        );
    }

    function _executeUniswapV2FlashLoan(FlashLoanParams memory params) internal {
        // For Uniswap V2, we use swap with callback
        (address pair, uint256 amount0, uint256 amount1) = abi.decode(
            params.userData,
            (address, uint256, uint256)
        );

        IUniswapV2Pair(pair).swap(
            amount0,
            amount1,
            address(this),
            params.userData
        );
    }

    function _executeMakerFlashLoan(FlashLoanParams memory params) internal {
        require(params.tokens.length == 1, "Maker: single token only");

        IDssFlash(makerDssFlash).flashLoan(
            address(this),
            params.tokens[0],
            params.amounts[0],
            params.userData
        );
    }

    // ============ Callbacks ============

    // Aave V3 callback
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == aaveV3Pool || msg.sender == aaveV2Pool, "Invalid caller");
        require(initiator == address(this), "Invalid initiator");

        _onFlashLoan(assets, amounts, premiums, params);

        // Approve repayment
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(assets[i]).approve(msg.sender, amounts[i] + premiums[i]);
        }

        return true;
    }

    // Balancer callback
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external {
        require(msg.sender == balancerVault, "Invalid caller");

        _onFlashLoan(tokens, amounts, feeAmounts, userData);

        // Repay
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(balancerVault, amounts[i] + feeAmounts[i]);
        }
    }

    // Uniswap V3 callback
    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata data
    ) external {
        (address pool,,) = abi.decode(data, (address, uint256, uint256));
        require(msg.sender == pool, "Invalid caller");

        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        uint256[] memory fees = new uint256[](2);
        fees[0] = fee0;
        fees[1] = fee1;

        // Get amounts from pool state or data
        uint256[] memory amounts = new uint256[](2);
        // ... decode from data

        _onFlashLoan(tokens, amounts, fees, data);

        // Repay
        if (fee0 > 0) IERC20(token0).transfer(pool, amounts[0] + fee0);
        if (fee1 > 0) IERC20(token1).transfer(pool, amounts[1] + fee1);
    }

    // Uniswap V2 callback
    function uniswapV2Call(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        require(sender == address(this), "Invalid sender");

        (address pair,,) = abi.decode(data, (address, uint256, uint256));
        require(msg.sender == pair, "Invalid caller");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();

        address[] memory tokens = new address[](2);
        tokens[0] = token0;
        tokens[1] = token1;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount0;
        amounts[1] = amount1;

        // Calculate fees (0.3%)
        uint256[] memory fees = new uint256[](2);
        fees[0] = (amount0 * 3) / 997 + 1;
        fees[1] = (amount1 * 3) / 997 + 1;

        _onFlashLoan(tokens, amounts, fees, data);

        // Repay
        if (amount0 > 0) IERC20(token0).transfer(pair, amount0 + fees[0]);
        if (amount1 > 0) IERC20(token1).transfer(pair, amount1 + fees[1]);
    }

    // Maker callback (ERC3156)
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external returns (bytes32) {
        require(msg.sender == makerDssFlash, "Invalid caller");
        require(initiator == address(this), "Invalid initiator");

        address[] memory tokens = new address[](1);
        tokens[0] = token;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256[] memory fees = new uint256[](1);
        fees[0] = fee;

        _onFlashLoan(tokens, amounts, fees, data);

        // Approve repayment
        IERC20(token).approve(makerDssFlash, amount + fee);

        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    // ============ Abstract - Override in Attack Contract ============

    function _onFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory fees,
        bytes memory userData
    ) internal virtual;
}

