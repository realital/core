pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

import "./Ownable.sol";

abstract contract Whitelistable is Ownable {
  bytes32 public constant PARTICIPANT_ROLE = keccak256("PARTICIPANT_ROLE");

  constructor() {
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function addParticipants(address[] memory addresses) public virtual onlyOwner {
    for(uint index = 0; index < addresses.length; ++index)  {
      _setupRole(PARTICIPANT_ROLE, addresses[index]);
    }
  }

  function removeParticipants(address[] memory addresses) public virtual onlyOwner {
    for(uint index = 0; index < addresses.length; ++index)  {
      revokeRole(PARTICIPANT_ROLE, addresses[index]);
    }
  }

  function isParticipants(address addr) public virtual view returns(bool) {
    return hasRole(PARTICIPANT_ROLE, addr);
  }

  modifier onlyParticipant() {
    require(hasRole(PARTICIPANT_ROLE, _msgSender()), "Whitelistable: must have participant role");
    _;
  }

  function getParticipantCount() public view onlyOwner returns (uint256) {
    return getRoleMemberCount(PARTICIPANT_ROLE);
  }

  function getParticipant(uint256 index) internal view onlyOwner returns(address) {
    return getRoleMember(PARTICIPANT_ROLE, index);
  }
}
