// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./IRetawarsHero.sol";

interface IRWHeroGenerator {
  function getCaller() external view returns (address);
  function getRandom(address sender, uint64 ms) external returns (uint256);
  function generate(address sender, uint64 ms) external returns (IRetawarsHero.Hero memory);
  function generatePresale(address sender, uint64 ms, uint16 refRank) external returns (IRetawarsHero.Hero memory);
}
