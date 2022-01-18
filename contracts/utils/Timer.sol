pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

/**
 * @title contract time for test environments
 */

contract Timer {
  uint256 private currentTime_;

  constructor() {
    currentTime_ = block.timestamp;
  }

  function setCurrentTime(uint256 time) external {
    currentTime_ = time;
  }

  function currentTime() public view returns (uint256) {
    return currentTime_;
  }
}

