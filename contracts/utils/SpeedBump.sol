// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../lib/openzeppelin-contracts@4.3.2/contracts/utils/Context.sol";

abstract contract SpeedBump is Context {
  mapping (address => uint) private userLastAction_;
  uint throttleTime = 1; 

  // Attach this to critical functions, such as balance withdrawals
  modifier speedBump() {
    address sender = _msgSender();
    require(block.number - throttleTime >= userLastAction_[sender]);
    userLastAction_[sender] = block.number;
    _;
  }
}
