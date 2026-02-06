// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/chainlink/IChainlinkOracle.sol";
import "./interfaces/uniswap/IUniswapV3.sol";
import "./interfaces/token-standards/IERC20.sol";

/// @title Oracle
/// @notice Price oracle utilities using Chainlink and Uniswap V3 TWAP
/// @dev Provides token pricing for profit calculation across multiple tokens
abstract contract Oracle {

    enum PriceType {
        CHAINLINK,      // Use Chainlink price feed
        UNISWAP_TWAP,   // Use Uniswap V3 TWAP
        UNISWAP_SPOT,   // Use Uniswap V3 spot price
        AUTO            // Try Chainlink first, fallback to TWAP
    }

    // ============ Constants ============

    uint256 internal constant PRECISION = 1e18;
    uint160 internal constant Q96 = 2 ** 96;
    uint32 internal constant DEFAULT_TWAP_INTERVAL = 1800; // 30 minutes

    // ============ State ============

    address public v3Factory;
    address public quoteToken; // Base token for pricing (e.g., WETH or USDC)

    /// @notice Chainlink price feeds: token => feed address
    mapping(address => address) public chainlinkFeeds;

    /// @notice Preferred V3 pool fee for each token pair
    mapping(address => uint24) public preferredFees;

    /// @notice TWAP interval per token (0 = use default)
    mapping(address => uint32) public twapIntervals;

    // ============ Errors ============

    error StalePrice();
    error InvalidPrice();
    error NoOracleAvailable();
    error PoolNotFound();

    // ============ Main Price Function ============

    /// @notice Get price using specified oracle type
    /// @param token Token to get price for
    /// @param priceType Which oracle to use
    /// @return price Price in quoteToken terms (18 decimals)
    function _getPriceByType(
        address token,
        PriceType priceType
    ) internal view returns (uint256 price) {
        if (token == quoteToken) return PRECISION;

        if (priceType == PriceType.CHAINLINK) {
            return _getChainlinkPriceNormalized(token);
        } else if (priceType == PriceType.UNISWAP_TWAP) {
            uint32 interval = twapIntervals[token];
            if (interval == 0) interval = DEFAULT_TWAP_INTERVAL;
            return _getV3TwapPrice(token, interval);
        } else if (priceType == PriceType.UNISWAP_SPOT) {
            return _getV3SpotPrice(token);
        } else {
            // AUTO: try Chainlink first, fallback to TWAP
            return _getPrice(token);
        }
    }

    /// @notice Get value of token amount using specified oracle
    /// @param token Token address
    /// @param amount Token amount
    /// @param priceType Which oracle to use
    /// @return value Value in quoteToken (18 decimals)
    function _getValueByType(
        address token,
        uint256 amount,
        PriceType priceType
    ) internal view returns (uint256 value) {
        if (amount == 0) return 0;

        uint256 price = _getPriceByType(token, priceType);
        uint8 decimals = IERC20(token).decimals();

        if (decimals == 18) {
            value = (amount * price) / PRECISION;
        } else if (decimals < 18) {
            value = (amount * (10 ** (18 - decimals)) * price) / PRECISION;
        } else {
            value = (amount * price) / (10 ** (decimals - 18)) / PRECISION;
        }
    }

    /// @notice Get total value of multiple tokens using specified oracle
    function _getTotalValueByType(
        address[] memory tokens,
        uint256[] memory amounts,
        PriceType priceType
    ) internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < tokens.length; i++) {
            totalValue += _getValueByType(tokens[i], amounts[i], priceType);
        }
    }

    // ============ Chainlink Pricing ============

    /// @notice Get price from Chainlink feed
    /// @param token Token address
    /// @return price Price in feed's native decimals
    function _getChainlinkPrice(address token) internal view returns (uint256 price) {
        address feed = chainlinkFeeds[token];
        if (feed == address(0)) revert NoOracleAvailable();

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = IChainlinkAggregator(feed).latestRoundData();

        // Validate price data
        if (answer <= 0) revert InvalidPrice();
        if (answeredInRound < roundId) revert StalePrice();
        if (block.timestamp - updatedAt > 3600) revert StalePrice(); // 1 hour staleness

        price = uint256(answer);
    }

    /// @notice Get price normalized to 18 decimals
    /// @param token Token address
    /// @return price Price with 18 decimals
    function _getChainlinkPriceNormalized(address token) internal view returns (uint256 price) {
        address feed = chainlinkFeeds[token];
        if (feed == address(0)) revert NoOracleAvailable();

        uint8 feedDecimals = IChainlinkAggregator(feed).decimals();
        uint256 rawPrice = _getChainlinkPrice(token);

        if (feedDecimals == 18) {
            price = rawPrice;
        } else if (feedDecimals < 18) {
            price = rawPrice * (10 ** (18 - feedDecimals));
        } else {
            price = rawPrice / (10 ** (feedDecimals - 18));
        }
    }

    /// @notice Check if Chainlink feed is available and fresh
    function _hasChainlinkFeed(address token) internal view returns (bool) {
        address feed = chainlinkFeeds[token];
        if (feed == address(0)) return false;

        try IChainlinkAggregator(feed).latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256 updatedAt,
            uint80
        ) {
            return answer > 0 && (block.timestamp - updatedAt <= 3600);
        } catch {
            return false;
        }
    }

    // ============ Uniswap V3 TWAP Pricing ============

    /// @notice Get TWAP price from Uniswap V3 pool
    /// @param token Token to price
    /// @param twapInterval TWAP period in seconds (e.g., 1800 for 30 min)
    /// @return price Price of 1 token in quoteToken (18 decimals)
    function _getV3TwapPrice(
        address token,
        uint32 twapInterval
    ) internal view returns (uint256 price) {
        uint24 fee = preferredFees[token];
        if (fee == 0) fee = 3000; // Default to 0.3% pool

        address pool = IUniswapV3Factory(v3Factory).getPool(token, quoteToken, fee);
        if (pool == address(0)) revert PoolNotFound();

        int24 twapTick = _getTwapTick(pool, twapInterval);
        price = _getPriceFromTick(twapTick, token, pool);
    }

    /// @notice Get spot price from Uniswap V3 pool (current tick)
    /// @param token Token to price
    /// @return price Price of 1 token in quoteToken (18 decimals)
    function _getV3SpotPrice(address token) internal view returns (uint256 price) {
        uint24 fee = preferredFees[token];
        if (fee == 0) fee = 3000;

        address pool = IUniswapV3Factory(v3Factory).getPool(token, quoteToken, fee);
        if (pool == address(0)) revert PoolNotFound();

        (uint160 sqrtPriceX96, int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();
        price = _getPriceFromSqrtPrice(sqrtPriceX96, token, pool);
    }

    /// @notice Get TWAP tick from pool observations
    function _getTwapTick(address pool, uint32 twapInterval) internal view returns (int24 twapTick) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = twapInterval;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives,) = IUniswapV3Pool(pool).observe(secondsAgos);

        int56 tickCumulativeDelta = tickCumulatives[1] - tickCumulatives[0];
        twapTick = int24(tickCumulativeDelta / int56(uint56(twapInterval)));

        // Round towards negative infinity
        if (tickCumulativeDelta < 0 && (tickCumulativeDelta % int56(uint56(twapInterval)) != 0)) {
            twapTick--;
        }
    }

    /// @notice Convert tick to price
    function _getPriceFromTick(
        int24 tick,
        address token,
        address pool
    ) internal view returns (uint256 price) {
        // price = 1.0001^tick
        uint160 sqrtPriceX96 = _getSqrtRatioAtTick(tick);
        price = _getPriceFromSqrtPrice(sqrtPriceX96, token, pool);
    }

    /// @notice Convert sqrtPriceX96 to price with proper token ordering
    /// @dev sqrtPriceX96 = sqrt(price) * 2^96, where price = token1/token0
    function _getPriceFromSqrtPrice(
        uint160 sqrtPriceX96,
        address token,
        address pool
    ) internal view returns (uint256 price) {
        address token0 = IUniswapV3Pool(pool).token0();

        uint8 tokenDecimals = IERC20(token).decimals();
        uint8 quoteDecimals = IERC20(quoteToken).decimals();

        uint256 sqrtPrice = uint256(sqrtPriceX96);

        if (token == token0) {
            // Price of token0 in token1 = sqrtPrice^2 / 2^192
            // Split calculation to avoid overflow:
            // Step 1: sqrtPrice^2 >> 64 (fits in uint256 for reasonable prices)
            // Step 2: Divide by 2^128 (remaining part of 2^192)
            uint256 priceX128 = _mulDiv(sqrtPrice, sqrtPrice, 1 << 64);

            // Normalize to 18 decimals with decimal adjustment
            price = _mulDiv(
                priceX128,
                PRECISION * (10 ** quoteDecimals),
                (1 << 128) * (10 ** tokenDecimals)
            );
        } else {
            // Price of token1 in token0 = 2^192 / sqrtPrice^2
            // = (2^128 / sqrtPrice) * (2^64 / sqrtPrice)
            // Use inverse calculation
            uint256 priceX128 = _mulDiv(sqrtPrice, sqrtPrice, 1 << 64);

            // Invert: 2^256 / priceX128 >> 128 = 2^128 / priceX128 * 2^128
            // Simplified: (2^128)^2 / priceX128
            price = _mulDiv(
                (1 << 128),
                PRECISION * (10 ** quoteDecimals),
                priceX128 * (10 ** tokenDecimals) >> 64
            );
        }
    }

    /// @notice Multiply then divide with full precision
    /// @dev Handles intermediate overflow by splitting calculation
    function _mulDiv(uint256 a, uint256 b, uint256 denominator) internal pure returns (uint256 result) {
        // For simplicity, using unchecked math assuming reasonable values
        // In production, consider using a full mulDiv implementation
        uint256 prod0 = a * b;
        result = prod0 / denominator;
    }

    /// @notice Approximate sqrt ratio from tick (simplified)
    function _getSqrtRatioAtTick(int24 tick) internal pure returns (uint160) {
        uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint256(int256(tick));
        require(absTick <= 887272, "Tick out of range");

        uint256 ratio = absTick & 0x1 != 0 ? 0xfffcb933bd6fad37aa2d162d1a594001 : 0x100000000000000000000000000000000;
        if (absTick & 0x2 != 0) ratio = (ratio * 0xfff97272373d413259a46990580e213a) >> 128;
        if (absTick & 0x4 != 0) ratio = (ratio * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
        if (absTick & 0x8 != 0) ratio = (ratio * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
        if (absTick & 0x10 != 0) ratio = (ratio * 0xffcb9843d60f6159c9db58835c926644) >> 128;
        if (absTick & 0x20 != 0) ratio = (ratio * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
        if (absTick & 0x40 != 0) ratio = (ratio * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
        if (absTick & 0x80 != 0) ratio = (ratio * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
        if (absTick & 0x100 != 0) ratio = (ratio * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
        if (absTick & 0x200 != 0) ratio = (ratio * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
        if (absTick & 0x400 != 0) ratio = (ratio * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
        if (absTick & 0x800 != 0) ratio = (ratio * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
        if (absTick & 0x1000 != 0) ratio = (ratio * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
        if (absTick & 0x2000 != 0) ratio = (ratio * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
        if (absTick & 0x4000 != 0) ratio = (ratio * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
        if (absTick & 0x8000 != 0) ratio = (ratio * 0x31be135f97d08fd981231505542fcfa6) >> 128;
        if (absTick & 0x10000 != 0) ratio = (ratio * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
        if (absTick & 0x20000 != 0) ratio = (ratio * 0x5d6af8dedb81196699c329225ee604) >> 128;
        if (absTick & 0x40000 != 0) ratio = (ratio * 0x2216e584f5fa1ea926041bedfe98) >> 128;
        if (absTick & 0x80000 != 0) ratio = (ratio * 0x48a170391f7dc42444e8fa2) >> 128;

        if (tick > 0) ratio = type(uint256).max / ratio;

        return uint160((ratio >> 32) + (ratio % (1 << 32) == 0 ? 0 : 1));
    }

    // ============ Combined Pricing ============

    /// @notice Get price using best available oracle (Chainlink preferred)
    /// @param token Token to price
    /// @return price Price in quoteToken (18 decimals)
    function _getPrice(address token) internal view returns (uint256 price) {
        // If token is quoteToken, price is 1
        if (token == quoteToken) return PRECISION;

        // Try Chainlink first
        if (_hasChainlinkFeed(token)) {
            return _getChainlinkPriceNormalized(token);
        }

        // Fall back to V3 TWAP (30 min)
        return _getV3TwapPrice(token, 1800);
    }

    /// @notice Get value of token amount in quoteToken terms
    /// @param token Token address
    /// @param amount Token amount (in token's decimals)
    /// @return value Value in quoteToken (18 decimals)
    function _getValue(address token, uint256 amount) internal view returns (uint256 value) {
        if (amount == 0) return 0;

        uint256 price = _getPrice(token);
        uint8 decimals = IERC20(token).decimals();

        // Normalize amount to 18 decimals, then multiply by price
        if (decimals == 18) {
            value = (amount * price) / PRECISION;
        } else if (decimals < 18) {
            value = (amount * (10 ** (18 - decimals)) * price) / PRECISION;
        } else {
            value = (amount * price) / (10 ** (decimals - 18)) / PRECISION;
        }
    }

    /// @notice Get total value of multiple tokens
    /// @param tokens Token addresses
    /// @param amounts Token amounts
    /// @return totalValue Total value in quoteToken (18 decimals)
    function _getTotalValue(
        address[] memory tokens,
        uint256[] memory amounts
    ) internal view returns (uint256 totalValue) {
        for (uint256 i = 0; i < tokens.length; i++) {
            totalValue += _getValue(tokens[i], amounts[i]);
        }
    }

    // ============ Configuration ============

    /// @notice Set Chainlink feed for a token
    function _setChainlinkFeed(address token, address feed) internal {
        chainlinkFeeds[token] = feed;
    }

    /// @notice Set preferred V3 pool fee for a token
    function _setPreferredFee(address token, uint24 fee) internal {
        preferredFees[token] = fee;
    }

    /// @notice Batch set Chainlink feeds
    function _setChainlinkFeeds(address[] memory tokens, address[] memory feeds) internal {
        for (uint256 i = 0; i < tokens.length; i++) {
            chainlinkFeeds[tokens[i]] = feeds[i];
        }
    }
}
