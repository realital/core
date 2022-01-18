pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "./ERC20/RetaERC20MinterPauser.sol";

abstract contract RetawarsMaterial is RetaERC20MinterPauser {
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  
  constructor(string memory name, string memory symbol)
    RetaERC20MinterPauser(name, symbol) {
  }

  function owner() public view virtual returns (address) {
    return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
  }

  modifier onlyOwner() {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "RetawarsMaterial: caller is not owner");
    _;
  }

  function renounceOwnership() public virtual onlyOwner {
    super.revokeRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function transferOwnership(address newOwner) public virtual onlyOwner {
    require(newOwner != address(0), "RetawarsMaterial: new owner is the zero address");
    _setOwner(newOwner);
  }

  function _setOwner(address newOwner) private {
    address oldOwner = owner();
    super.grantRole(DEFAULT_ADMIN_ROLE, newOwner);
    super.revokeRole(DEFAULT_ADMIN_ROLE, oldOwner);
    emit OwnershipTransferred(oldOwner, newOwner);
  }
}
