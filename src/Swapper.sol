// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/uniswap/IUniswapV2.sol";
import "./interfaces/uniswap/IUniswapV3.sol";
import "./interfaces/token-standards/IERC20.sol";
import "./interfaces/token-standards/IWETH.sol";

/// @title Swapper
/// @notice DEX swap utilities for whitehat attack contracts
/// @dev Supports Uniswap V2 and V3 style swaps
abstract contract Swapper {

    // ============ State ============

    address public v2Router;
    address public v2Factory;
    address public v3Router;
    address public v3Factory;
    address public weth;

    // ============ Errors ============

    error InsufficientOutput();
    error SwapFailed();
    error InvalidPath();
    error PoolNotFound();

    // ============ V2 Swaps ============

    /// @notice Swap exact tokens for tokens via V2 router
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param amountIn Amount of input tokens
    /// @param amountOutMin Minimum output (set to 0 for no slippage protection in attacks)
    /// @return amountOut Actual output amount
    function _swapV2ExactIn(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IERC20(tokenIn).approve(v2Router, amountIn);

        uint256[] memory amounts = IUniswapV2Router02(v2Router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        amountOut = amounts[amounts.length - 1];
    }

    /// @notice Swap exact tokens via V2 with multi-hop path
    /// @param path Token path [tokenIn, ..., tokenOut]
    /// @param amountIn Amount of input tokens
    /// @param amountOutMin Minimum output
    /// @return amountOut Actual output amount
    function _swapV2ExactInMulti(
        address[] memory path,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        if (path.length < 2) revert InvalidPath();

        IERC20(path[0]).approve(v2Router, amountIn);

        uint256[] memory amounts = IUniswapV2Router02(v2Router).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            address(this),
            block.timestamp
        );

        amountOut = amounts[amounts.length - 1];
    }

    /// @notice Swap tokens for exact tokens via V2 router
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param amountOut Exact output amount desired
    /// @param amountInMax Maximum input allowed
    /// @return amountIn Actual input amount used
    function _swapV2ExactOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMax
    ) internal returns (uint256 amountIn) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        IERC20(tokenIn).approve(v2Router, amountInMax);

        uint256[] memory amounts = IUniswapV2Router02(v2Router).swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,
            address(this),
            block.timestamp
        );

        amountIn = amounts[0];
    }

    /// @notice Direct V2 pair swap (more gas efficient, no router)
    /// @param pair The V2 pair address
    /// @param tokenIn Input token address
    /// @param amountIn Amount of input tokens
    /// @param feeBps Fee in basis points (e.g., 30 for 0.3%, 25 for 0.25%)
    /// @return amountOut Output amount received
    function _swapV2Direct(
        address pair,
        address tokenIn,
        uint256 amountIn,
        uint256 feeBps
    ) internal returns (uint256 amountOut) {
        IUniswapV2Pair pairContract = IUniswapV2Pair(pair);

        address token0 = pairContract.token0();

        bool isToken0 = tokenIn == token0;

        (uint112 reserve0, uint112 reserve1,) = pairContract.getReserves();
        (uint256 reserveIn, uint256 reserveOut) = isToken0
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));

        // Calculate output: fee multiplier = (10000 - feeBps) / 10000
        uint256 amountInWithFee = amountIn * (10000 - feeBps);
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 10000 + amountInWithFee);

        // Transfer tokens to pair
        IERC20(tokenIn).transfer(pair, amountIn);

        // Execute swap
        (uint256 amount0Out, uint256 amount1Out) = isToken0
            ? (uint256(0), amountOut)
            : (amountOut, uint256(0));

        pairContract.swap(amount0Out, amount1Out, address(this), "");
    }

    /// @notice Get V2 pair address for token pair
    function _getV2Pair(address tokenA, address tokenB) internal view returns (address pair) {
        pair = IUniswapV2Factory(v2Factory).getPair(tokenA, tokenB);
        if (pair == address(0)) revert PoolNotFound();
    }

    /// @notice Get expected output for V2 swap
    function _getV2AmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) internal view returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = IUniswapV2Router02(v2Router).getAmountsOut(amountIn, path);
        amountOut = amounts[amounts.length - 1];
    }

    // ============ V3 Swaps ============

    /// @notice Swap exact tokens via V3 router (single hop)
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param fee Pool fee tier (500, 3000, 10000)
    /// @param amountIn Exact input amount
    /// @param amountOutMin Minimum output
    /// @return amountOut Actual output
    function _swapV3ExactInSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        IERC20(tokenIn).approve(v3Router, amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: 0
        });

        amountOut = ISwapRouter(v3Router).exactInputSingle(params);
    }

    /// @notice Swap exact tokens via V3 router (multi-hop)
    /// @param path Encoded path (tokenIn, fee, tokenMid, fee, tokenOut)
    /// @param amountIn Exact input amount
    /// @param amountOutMin Minimum output
    /// @return amountOut Actual output
    function _swapV3ExactInMulti(
        bytes memory path,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        // Decode first token from path for approval
        address tokenIn;
        assembly {
            tokenIn := mload(add(path, 20))
        }

        IERC20(tokenIn).approve(v3Router, amountIn);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: path,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin
        });

        amountOut = ISwapRouter(v3Router).exactInput(params);
    }

    /// @notice Swap for exact output via V3 router (single hop)
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param fee Pool fee tier
    /// @param amountOut Exact output desired
    /// @param amountInMax Maximum input allowed
    /// @return amountIn Actual input used
    function _swapV3ExactOutSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint256 amountInMax
    ) internal returns (uint256 amountIn) {
        IERC20(tokenIn).approve(v3Router, amountInMax);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: amountInMax,
            sqrtPriceLimitX96: 0
        });

        amountIn = ISwapRouter(v3Router).exactOutputSingle(params);
    }

    /// @notice Direct V3 pool swap (no router, more control)
    /// @param pool The V3 pool address
    /// @param zeroForOne True if swapping token0 for token1
    /// @param amountSpecified Positive for exact input, negative for exact output
    /// @return amount0 Token0 delta (negative = sent, positive = received)
    /// @return amount1 Token1 delta (negative = sent, positive = received)
    function _swapV3Direct(
        address pool,
        bool zeroForOne,
        int256 amountSpecified
    ) internal returns (int256 amount0, int256 amount1) {
        // sqrtPriceLimitX96: max/min price to prevent extreme slippage
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? 4295128739 + 1  // MIN_SQRT_RATIO + 1
            : 1461446703485210103287273052203988822378723970342 - 1; // MAX_SQRT_RATIO - 1

        (amount0, amount1) = IUniswapV3Pool(pool).swap(
            address(this),
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            ""
        );
    }

    /// @notice Get V3 pool address for token pair and fee
    function _getV3Pool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) internal view returns (address pool) {
        pool = IUniswapV3Factory(v3Factory).getPool(tokenA, tokenB, fee);
        if (pool == address(0)) revert PoolNotFound();
    }

    /// @notice Encode V3 multi-hop path
    /// @dev Path format: tokenIn (20 bytes) | fee (3 bytes) | tokenOut (20 bytes) | ...
    function _encodeV3Path(
        address[] memory tokens,
        uint24[] memory fees
    ) internal pure returns (bytes memory path) {
        if (tokens.length != fees.length + 1) revert InvalidPath();

        path = abi.encodePacked(tokens[0]);
        for (uint256 i = 0; i < fees.length; i++) {
            path = abi.encodePacked(path, fees[i], tokens[i + 1]);
        }
    }

    // ============ V3 Swap Callback ============

    /// @notice Callback for V3 direct swaps - must be implemented if using _swapV3Direct
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external virtual {
        // Default implementation: pay the required tokens
        // Override if you need custom logic
        if (amount0Delta > 0) {
            address token0 = IUniswapV3Pool(msg.sender).token0();
            IERC20(token0).transfer(msg.sender, uint256(amount0Delta));
        }
        if (amount1Delta > 0) {
            address token1 = IUniswapV3Pool(msg.sender).token1();
            IERC20(token1).transfer(msg.sender, uint256(amount1Delta));
        }
    }

    // ============ Convenience Functions ============

    /// @notice Swap all balance of a token via V2 (no slippage protection)
    function _swapAllV2(
        address tokenIn,
        address tokenOut
    ) internal returns (uint256 amountOut) {
        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        if (balance > 0) {
            amountOut = _swapV2ExactIn(tokenIn, tokenOut, balance, 0);
        }
    }

    /// @notice Swap all balance of a token via V3 (0.3% fee, no slippage protection)
    function _swapAllV3(
        address tokenIn,
        address tokenOut
    ) internal returns (uint256 amountOut) {
        uint256 balance = IERC20(tokenIn).balanceOf(address(this));
        if (balance > 0) {
            amountOut = _swapV3ExactInSingle(tokenIn, tokenOut, 3000, balance, 0);
        }
    }
}
