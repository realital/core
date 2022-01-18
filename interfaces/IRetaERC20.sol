pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IRetaERC20 is IERC20, IERC20Metadata {
  function mint(address account, uint256 amount) external;
  function burn(uint256 amount) external;
  function burnFrom(address account, uint256 amount) external;
}
