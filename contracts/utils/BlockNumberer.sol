pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

/**
 * @title contract block number for test environments
 */

contract BlockNumberer {
  uint256 private currentBlock_;

  constructor() {
    currentBlock_ = block.number;
  }

  function setCurrentBlock(uint256 number) external {
    currentBlock_ = number;
  }

  function increaseBlock(uint256 number) external {
    currentBlock_ += number;
  }

  function currentBlock() public view returns (uint256) {
    return currentBlock_;
  }
}

