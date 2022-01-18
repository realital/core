pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeMath.sol";

import "./Whitelistable.sol";

abstract contract Reservable is Whitelistable {
  using SafeMath for uint256;

  mapping(address => uint256) internal reservedMap_;
  uint256 public totalAmountToReserve_;
  uint256 public reserved_;

  constructor(uint256 totalAmountToReserve) {
    totalAmountToReserve_ = totalAmountToReserve;
  }

  function addParticipants(address[] memory /*addresses*/) public override view onlyOwner {
    require(false, "Reservable: use addParticipants(addresses, amounts)");
  }

  function addParticipants(address[] memory addresses, uint256[] memory amounts) public onlyOwner returns (uint256) {
    require(addresses.length == amounts.length, "Reservable: the length of addresses and amounts is not matched");
    uint256 amount = 0;
    for(uint index = 0; index < addresses.length; ++index) {
      require(reservedMap_[addresses[index]] == 0, "Reservable: An address is already a participant");

      amount += amounts[index];
    }

    require(amount + reserved_ <= totalAmountToReserve_, "Reservable: Exceeded amount to assign");
    super.addParticipants(addresses);

    for(uint index = 0; index < addresses.length; ++index) {
      reservedMap_[addresses[index]] = amounts[index];
    }
    reserved_ += amount;

    return reserved_;
  }

  function removeParticipants(address[] memory addresses) public virtual override onlyOwner {
    super.removeParticipants(addresses);

    for(uint index = 0; index < addresses.length; ++index)  {
      uint256 amount = reservedMap_[addresses[index]];
      reserved_ = reserved_.sub(amount);

      delete reservedMap_[addresses[index]];
    }
  }

  function updateReservedAmount(address addr, uint256 amount) public virtual onlyOwner returns (uint256) {
    require(isParticipants(addr), "Reservable: The address is not participants");
    uint256 existAmount = reservedMap_[addr];
    reserved_ = reserved_.sub(existAmount);

    reservedMap_[addr] = amount;
    reserved_ = reserved_.add(amount);

    return reserved_;
  }

  function getReservedAmount(address addr) public view onlyParticipant returns (uint256) {
    return reservedMap_[addr];
  }
}
