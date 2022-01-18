pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeMath.sol";
import "../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/ERC20.sol";
import "../../lib/openzeppelin-contracts@4.3.2/contracts/access/AccessControlEnumerable.sol";
import "../utils/Mintable.sol";

contract RealitalMetaverse is Mintable {
  using SafeMath for uint256;

  //uint256 private constant maxSupply = 100000000 * 1e18;
  uint256 public constant maxSupply = 100000000 * 1e18;
  constructor() Mintable("Realital Metaverse", "RETA", maxSupply) {
    //_mint();
  }
}
