// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../../../lib/openzeppelin-contracts@4.3.2/contracts/access/Ownable.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/Address.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/structs/EnumerableSet.sol";

import "./IRWHeroGenerator.sol";
import "./IRetawarsHero.sol";


contract RWHeroGenerator is IRWHeroGenerator, Ownable {
  using Address for address;
  using EnumerableSet for EnumerableSet.UintSet;

  address public caller_;
  uint256 private seed_;

  EnumerableSet.UintSet private implemented_;
  uint256 private last_;

  uint8 constant private MAX_STAT = 24; // COMMON
  uint8 constant private STAT_GRADE_GAP = 3;
  uint8 constant private STAT_RANGE = 7;
  uint8[5] private TOTAL_STATS = [92, 104, 116, 128, 140];

  constructor(address caller, uint256 seed) {
    require(caller.isContract(), "RWHeroGenerator: the caller must be a contract");

    seed_ = seed;
    caller_ = caller;

    _setDefaultImplemented();
  }

  function updateHeros() public onlyOwner {
    require(implemented_.length() < 8, "IRWHeroGenerator: already updated fully");
    _addOtherImplemented();
  }

  function updateCraftsman() public onlyOwner {
    _addCraftsman();
  }

  function addHeroType(IRetawarsHero.Gender gender, IRetawarsHero.Major major) public onlyOwner {
    uint16 heroType = _mergeHeroType(gender, major);
    require(false == implemented_.contains(heroType), "IRWHeroGenerator: existing hero type");

    implemented_.add(heroType);
  }

  function setCaller(address caller) public onlyOwner {
    require(caller.isContract(), "RWHeroGenerator: the caller must be a contract");
    caller_ = caller;
  }

  modifier onlyCaller {
    require(_msgSender() == caller_, "RWHeroGenerator: only callable by registered contract");
    _;
  }

  function getCaller() external view returns (address) {
    return caller_;
  }

  function getRandom(address sender, uint64 ms) external onlyCaller returns (uint256 retval) {
    retval = _getRandom(sender, ms, 201607031050);
  }

  function generate(address sender, uint64 ms) external onlyCaller returns (IRetawarsHero.Hero memory retval) {
    uint256 rand = _getRandom(sender, ms, 0);
    uint16 gradeRate = uint16(rand % 10000);
    IRetawarsHero.Grade grade = _getGrade(gradeRate);
    (IRetawarsHero.Gender gender, IRetawarsHero.Major major) = _getRandomHeroType(uint8((rand >> 16) % type(uint8).max));

    uint8[4] memory mainStat = _getMainStat(grade, sender, ms);
    uint8[5] memory skills = _getSkill(grade, major, sender, ms);

    retval = IRetawarsHero.Hero(
      grade,
      gender,
      major,
      1,
      [
        mainStat[0],
        mainStat[1],
        mainStat[2],
        mainStat[3],
        uint8((rand >> 24) % 4) + 1
      ],
      skills
    );
  }

  function generatePresale(address sender, uint64 ms, uint16 refRank) external onlyCaller returns (IRetawarsHero.Hero memory retval) {
    uint256 rand = _getRandom(sender, ms, 0);
    IRetawarsHero.Grade grade = IRetawarsHero.Grade.COMMON;
    if(0 < refRank) {
      if(refRank == 1) {
        grade = IRetawarsHero.Grade.EPIC;
      }
      else if(refRank < 16) {
        grade = IRetawarsHero.Grade.RARE;
      }
      else if(refRank < 46) {
        grade = IRetawarsHero.Grade.UNCOMMON;
      }
    }
    else {
      uint16 gradeRate = uint16(rand % 10000);
      grade = _getGrade(gradeRate);
    }

    (IRetawarsHero.Gender gender, IRetawarsHero.Major major) = _getRandomHeroType(uint8((rand >> 16) % type(uint8).max));
    uint8[4] memory mainStat = _getMainStat(grade, sender, ms);
    uint8[5] memory skills = _getSkill(grade, major, sender, ms);

    retval = IRetawarsHero.Hero(
      grade,
      gender,
      major,
      1,
      [
        mainStat[0],
        mainStat[1],
        mainStat[2],
        mainStat[3],
        5
      ],
      skills
    );
  }

  function _getGrade(uint16 gradeRate) internal pure returns (IRetawarsHero.Grade grade) {
    if(gradeRate == 0) {
      grade = IRetawarsHero.Grade.LEGENDARY;
    }
    else if(gradeRate < 100) {
      grade = IRetawarsHero.Grade.EPIC;
    }
    else if(gradeRate < 1600) {
      grade = IRetawarsHero.Grade.RARE;
    }
    else if(gradeRate < 4600) {
      grade = IRetawarsHero.Grade.UNCOMMON;
    }
  }

  function _getRandom(address sender, uint64 ms, uint256 nonce) internal returns (uint256) {
    last_ = uint(keccak256(abi.encodePacked((block.difficulty << 16) | block.number, ms, sender, last_^seed_, nonce)));
    return last_;
  }

  function _getMainStat(IRetawarsHero.Grade grade, address sender, uint64 ms)
    internal 
    returns (uint8[4] memory stat)
  {
    uint8 endStat = MAX_STAT + STAT_GRADE_GAP * uint8(grade);
    uint8 beginStat = endStat - (STAT_RANGE - uint8(grade));
    require(endStat > beginStat, "RWHeroGenerator: stat error");

    uint256 rand = _getRandom(sender, ms, 37606581976);
    uint8 statLeft = TOTAL_STATS[uint8(grade)] - (beginStat * 4);

    for(uint index = 0; index < 4; ++index) {
      uint8 next = uint8((rand >> (8 * index)) % (endStat - beginStat + 1));
      if(next < statLeft) {
        stat[index] = next;
      }
      else {
        stat[index] = statLeft;
      }

      statLeft -= stat[index];
      stat[index] += beginStat;
      require(stat[index] >= beginStat && stat[index] <= endStat, "RWHeroGenerator: invalid generated stat");
    }

    //require(statLeft == 0, "RWHeroGenerator: statLeft is not zero");
  }

  uint8[2] private SKILL_MAJOR_RANGE = [10, 12];
  uint8[2] private SKILL_MINOR_RANGE = [4, 8];
  uint8 constant private TOTAL_SKILL = 32;

  function _getSkill(IRetawarsHero.Grade grade, IRetawarsHero.Major major, address sender, uint64 ms)
    internal
    returns (uint8[5] memory skill)
  {
    uint256 rand = _getRandom(sender, ms, 47606581976);
    uint8 majorRange = SKILL_MAJOR_RANGE[1] - SKILL_MAJOR_RANGE[0];
    uint8 minorRange = SKILL_MINOR_RANGE[1] - SKILL_MINOR_RANGE[0];

    uint8 skillLeft = TOTAL_SKILL - (SKILL_MAJOR_RANGE[0] + SKILL_MINOR_RANGE[0] * 4);
    for(uint8 index = 0; index < 5; ++index) {
      uint8 base = 0;
      uint8 gen = 0;
      if(0 == index) {
        gen = uint8((rand >> (16 * index)) % (majorRange + 1));
        base = SKILL_MAJOR_RANGE[0];
      }
      else {
        gen = uint8((rand >> (16 * index + 8)) % (minorRange + 1));
        base = SKILL_MINOR_RANGE[0];
      }

      if(gen > skillLeft) {
        gen = skillLeft;
      }

      skillLeft -= gen;
      skill[index] = base + gen + uint8(grade);

      if(grade == IRetawarsHero.Grade.LEGENDARY) {
        ++skill[index];
      }
    }

    uint8 nMajor = uint8(major);
    if(0 != nMajor) {
      skill[0] ^= skill[nMajor] ^= skill[0] ^= skill[nMajor];
    }

    //require(skillLeft == 0, "RWHeroGenerator: skillLeft is not zero");
  }

  // 2021. 12 - First deployed for presale
  function _setDefaultImplemented() internal {
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.MALE, IRetawarsHero.Major.COMBAT));
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.MALE, IRetawarsHero.Major.MINING));
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.FEMALE, IRetawarsHero.Major.LOGGING));
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.FEMALE, IRetawarsHero.Major.FARMING));
  }

  // Next schedule to deploy
  function _addOtherImplemented() internal {
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.MALE, IRetawarsHero.Major.LOGGING));
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.MALE, IRetawarsHero.Major.FARMING));
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.FEMALE, IRetawarsHero.Major.COMBAT));
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.FEMALE, IRetawarsHero.Major.MINING));
  }

  // For adding crafting major
  function _addCraftsman() internal {
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.MALE, IRetawarsHero.Major.CRAFTING));
    implemented_.add(_mergeHeroType(IRetawarsHero.Gender.FEMALE, IRetawarsHero.Major.CRAFTING));
  }

  function _getRandomHeroType(uint8 seed) internal view returns (IRetawarsHero.Gender gender, IRetawarsHero.Major major) {
    require(implemented_.length() < type(uint8).max, "RWHeroGenerator: critical error #1");
    uint8 index = uint8(seed % implemented_.length());
    return _splitHeroType(uint16(implemented_.at(index)));
  }

  function _mergeHeroType(IRetawarsHero.Gender gender, IRetawarsHero.Major major) internal pure returns (uint16) {
    return uint16((uint16(gender) << 8) | uint16(major));
  }

  function _splitHeroType(uint16 merged) internal pure returns (IRetawarsHero.Gender gender, IRetawarsHero.Major major) {
    gender = IRetawarsHero.Gender(merged >> 8);
    major = IRetawarsHero.Major(uint8(merged));
  }
}


