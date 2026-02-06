// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
interface IComet {
      function supply(address asset, uint256 amount) external;
      function supplyTo(address dst, address asset, uint256 amount) external;
      function supplyFrom(address from, address dst, address asset, uint256 amount) external;
      function withdraw(address asset, uint256 amount) external;
      function withdrawTo(address to, address asset, uint256 amount) external;
      function withdrawFrom(address src, address to, address asset, uint256 amount) external;

      function absorb(address absorber, address[] calldata accounts) external;
      function buyCollateral(address asset, uint256 minAmount, uint256 baseAmount, address recipient) external;

      function balanceOf(address account) external view returns (uint256);
      function borrowBalanceOf(address account) external view returns (uint256);
      function collateralBalanceOf(address account, address asset) external view returns (uint128);
      function getAssetInfo(uint8 i) external view returns (
          uint8 offset,
          address asset,
          address priceFeed,
          uint64 scale,
          uint64 borrowCollateralFactor,
          uint64 liquidateCollateralFactor,
          uint64 liquidationFactor,
          uint128 supplyCap
      );
      function getAssetInfoByAddress(address asset) external view returns (
          uint8 offset,
          address assetAddress,
          address priceFeed,
          uint64 scale,
          uint64 borrowCollateralFactor,
          uint64 liquidateCollateralFactor,
          uint64 liquidationFactor,
          uint128 supplyCap
      );
      function isLiquidatable(address account) external view returns (bool);
      function getPrice(address priceFeed) external view returns (uint256);
      function baseToken() external view returns (address);
      function baseTokenPriceFeed() external view returns (address);
      function numAssets() external view returns (uint8);
  }
