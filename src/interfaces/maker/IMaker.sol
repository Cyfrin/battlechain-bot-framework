// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
interface IDSS {
      function hope(address usr) external;
      function nope(address usr) external;
  }

  interface IDaiJoin {
      function join(address usr, uint256 wad) external;
      function exit(address usr, uint256 wad) external;
  }

  interface IGemJoin {
      function join(address usr, uint256 amt) external;
      function exit(address usr, uint256 amt) external;
      function gem() external view returns (address);
      function ilk() external view returns (bytes32);
  }

  interface IVat {
      function hope(address usr) external;
      function nope(address usr) external;
      function live() external view returns (uint256);
      function ilks(bytes32) external view returns (uint256 Art, uint256 rate, uint256 spot, uint256 line, uint256 dust);
      function urns(bytes32, address) external view returns (uint256 ink, uint256 art);
      function gem(bytes32, address) external view returns (uint256);
      function dai(address) external view returns (uint256);
      function sin(address) external view returns (uint256);
      function debt() external view returns (uint256);
      function vice() external view returns (uint256);
      function Line() external view returns (uint256);
      function frob(bytes32 i, address u, address v, address w, int256 dink, int256 dart) external;
      function fork(bytes32 ilk, address src, address dst, int256 dink, int256 dart) external;
      function move(address src, address dst, uint256 rad) external;
      function flux(bytes32 ilk, address src, address dst, uint256 wad) external;
  }

  interface IDssFlash {
      function flashLoan(address receiver, address token, uint256 amount, bytes calldata data) external returns (bool);
      function vatDaiFlashLoan(address receiver, uint256 amount, bytes calldata data) external returns (bool);
      function max() external view returns (uint256);
      function toll() external view returns (uint256);
  }

  interface IERC3156FlashBorrower {
      function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data) external returns (bytes32);
  }

  interface IERC3156FlashLender {
      function maxFlashLoan(address token) external view returns (uint256);
      function flashFee(address token, uint256 amount) external view returns (uint256);
      function flashLoan(address receiver, address token, uint256 amount, bytes calldata data) external returns (bool);
  }
