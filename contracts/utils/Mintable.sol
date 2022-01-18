pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeMath.sol";
import "../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/ERC20.sol";

import "./Ownable.sol";

abstract contract Mintable is ERC20, Ownable {
  using SafeMath for uint256;

  bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

  uint256 public maxSupply_;
  constructor(string memory name, string memory symbol, uint256 maxSupply) ERC20(name, symbol) {
    _setupRole(MINTER_ROLE, _msgSender());
    maxSupply_ = maxSupply;
  }

  function mint(address to, uint256 amount) public virtual {
    require(hasRole(MINTER_ROLE, _msgSender()), "Mintable: must have minter role to mint");
    require(amount.add(totalSupply()) <= maxSupply_, "Mintable: exceed to mint amount");
    super._mint(to, amount);
  }

  function addMinter(address minter) public onlyOwner {
    super.grantRole(MINTER_ROLE, minter);
  }

  function removeMinter(address minter) public onlyOwner {
    super.revokeRole(MINTER_ROLE, minter);
  }

  function renounceMinter() public onlyMinter {
    super.renounceRole(MINTER_ROLE, _msgSender());
  }

  modifier onlyMinter() {
    require(hasRole(MINTER_ROLE, _msgSender()), "Mintable: must have minter role");
    _;
  }
}
