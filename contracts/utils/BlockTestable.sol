pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "./BlockNumberer.sol";

/**
 * @title Base class that provides block overrides, but only if being run in test mode.
 */
abstract contract BlockTestable {
  // If the contract is being run on the test network, then `numbererAddress` will be the 0x0 address.
  // Note: this variable should be set on construction and never modified.
  address public numbererAddress_;

  /**
    * @notice Constructs the Testable contract. Called by child contracts.
    * @param numbererAddress Contract that stores the current block in a testing environment.
    * Must be set to 0x0 for production environments that use live time.
    */
  constructor(address numbererAddress) {
    numbererAddress_ = numbererAddress;
  }

  /**
    * @notice Reverts if not running in test mode.
    */
  modifier onlyIfTest {
    require(numbererAddress_ != address(0x0));
    _;
  }

  /**
    * @notice Sets the current time.
    * @dev Will revert if not running in test mode.
    * @param blockNumber number to set current Testable block number to.
    */
  function setCurrentBlock(uint256 blockNumber) external onlyIfTest {
    BlockNumberer(numbererAddress_).setCurrentBlock(blockNumber);
  }

  /**
    * @notice Gets the current time. Will return the last time set in `setCurrentBlock` if running in test mode.
    * Otherwise, it will return the block number.
    * @return uint for the current Testable block number.
    */
  function currentBlock() public view returns (uint256) {
    if (numbererAddress_ != address(0x0)) {
      return BlockNumberer(numbererAddress_).currentBlock();
    }
    else {
      return block.number;
    }
  }
}
