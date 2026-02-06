// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
interface ICurvePool {
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function fee() external view returns (uint256);
    function A() external view returns (uint256);

    function get_dy(int128 i, int128 j, uint256 dx) external view returns (uint256);
    function get_dy_underlying(int128 i, int128 j, uint256 dx) external view returns (uint256);

    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external payable returns (uint256);
    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount) external payable returns (uint256);
    function add_liquidity(uint256[4] calldata amounts, uint256 min_mint_amount) external payable returns (uint256);

    function remove_liquidity(uint256 _amount, uint256[2] calldata min_amounts) external returns (uint256[2] memory);
    function remove_liquidity(uint256 _amount, uint256[3] calldata min_amounts) external returns (uint256[3] memory);
    function remove_liquidity(uint256 _amount, uint256[4] calldata min_amounts) external returns (uint256[4] memory);

    function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 min_amount) external returns (uint256);
    function remove_liquidity_imbalance(uint256[2] calldata amounts, uint256 max_burn_amount) external returns (uint256);

    function calc_token_amount(uint256[2] calldata amounts, bool deposit) external view returns (uint256);
    function calc_token_amount(uint256[3] calldata amounts, bool deposit) external view returns (uint256);
    function calc_withdraw_one_coin(uint256 _token_amount, int128 i) external view returns (uint256);
}

interface ICurvePoolV2 {
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
    function price_oracle(uint256 k) external view returns (uint256);
    function price_scale(uint256 k) external view returns (uint256);
    function last_prices(uint256 k) external view returns (uint256);
    function get_virtual_price() external view returns (uint256);
    function fee() external view returns (uint256);
    function A() external view returns (uint256);
    function gamma() external view returns (uint256);

    function get_dy(uint256 i, uint256 j, uint256 dx) external view returns (uint256);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external payable returns (uint256);
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy, bool use_eth) external payable returns (uint256);
    function exchange_underlying(uint256 i, uint256 j, uint256 dx, uint256 min_dy) external returns (uint256);

    function add_liquidity(uint256[2] calldata amounts, uint256 min_mint_amount) external payable returns (uint256);
    function add_liquidity(uint256[3] calldata amounts, uint256 min_mint_amount) external payable returns (uint256);

    function remove_liquidity(uint256 _amount, uint256[2] calldata min_amounts) external returns (uint256[2] memory);
    function remove_liquidity_one_coin(uint256 token_amount, uint256 i, uint256 min_amount) external returns (uint256);

    function calc_token_amount(uint256[2] calldata amounts) external view returns (uint256);
    function calc_withdraw_one_coin(uint256 token_amount, uint256 i) external view returns (uint256);
}

interface ICurveRegistry {
    function get_pool_from_lp_token(address lp_token) external view returns (address);
    function get_lp_token(address pool) external view returns (address);
    function get_n_coins(address pool) external view returns (uint256[2] memory);
    function get_coins(address pool) external view returns (address[8] memory);
    function get_underlying_coins(address pool) external view returns (address[8] memory);
    function get_decimals(address pool) external view returns (uint256[8] memory);
    function get_balances(address pool) external view returns (uint256[8] memory);
    function get_virtual_price_from_lp_token(address lp_token) external view returns (uint256);
    function find_pool_for_coins(address from, address to) external view returns (address);
    function find_pool_for_coins(address from, address to, uint256 i) external view returns (address);
}