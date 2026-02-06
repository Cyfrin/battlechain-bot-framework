// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// wrapped tokens
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

  interface IWBNB is IWETH {}
  interface IWFTM is IWETH {}
  interface IWAVAX is IWETH {}
  interface IWMATIC is IWETH {}