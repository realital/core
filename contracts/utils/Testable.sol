pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "./Timer.sol";

/**
 * @title Base class that provides time overrides, but only if being run in test mode.
 */
abstract contract Testable {
  // If the contract is being run on the test network, then `timerAddress` will be the 0x0 address.
  // Note: this variable should be set on construction and never modified.
  address public timerAddress_;

  /**
    * @notice Constructs the Testable contract. Called by child contracts.
    * @param timerAddress Contract that stores the current time in a testing environment.
    * Must be set to 0x0 for production environments that use live time.
    */
  constructor(address timerAddress) {
    timerAddress_ = timerAddress;
  }

  /**
    * @notice Reverts if not running in test mode.
    */
  modifier onlyIfTest {
    require(timerAddress_ != address(0x0));
    _;
  }

  /**
    * @notice Sets the current time.
    * @dev Will revert if not running in test mode.
    * @param time timestamp to set current Testable time to.
    */
  function setCurrentTime(uint256 time) external onlyIfTest {
    Timer(timerAddress_).setCurrentTime(time);
  }

  /**
    * @notice Gets the current time. Will return the last time set in `setCurrentTime` if running in test mode.
    * Otherwise, it will return the block timestamp.
    * @return uint for the current Testable timestamp.
    */
  function currentTime() public view returns (uint256) {
    if (timerAddress_ != address(0x0)) {
      return Timer(timerAddress_).currentTime();
    }
    else {
      return block.timestamp;
    }
  }
}
