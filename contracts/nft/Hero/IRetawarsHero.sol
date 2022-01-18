// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;


interface IRetawarsHero {
  enum Grade {
    COMMON,
    UNCOMMON,
    RARE,
    EPIC,
    LEGENDARY
  }

  enum Gender {
    MALE,
    FEMALE
  }

  enum Major {
    COMBAT,
    MINING,
    LOGGING,
    FARMING,
    CRAFTING,
    MAX
  }

  struct Hero {
    Grade grade_;
    Gender gender_;
    Major major_;

    uint8 level_;

    // uint8 vit_;
    // uint8 str_;
    // uint8 agi_;
    // uint8 int_;
    // uint8 luk_;
    uint8[5] stats_;

    // uint8 combat_;
    // uint8 mining_;
    // uint8 logging_;
    // uint8 farming_;
    // uint8 crafting_;
    uint8[5] skills_;
  }

  function getHeroOwner(uint256 tokenId) external view returns (address);

  function levelUpFallible(uint256 tokenId, uint8 level, uint32 chance, uint64 ms) external returns (uint8);
  function setLevel(uint256 tokenId, uint8 level) external;

  function getLevel(uint256 tokenId) external view returns (uint8);
  function getGrade(uint256 tokenId) external view returns (Grade);
  function getHero(uint256 tokenId) external view returns (Hero memory);

  function burnHeros(uint256[] memory tokenIds) external;
}

interface IRWHeroSpawner {
  function spawn(address to, uint64 ms) external returns (uint256);
}

interface IRWHeroPresaleSpawner {
  function spawnPresale(address to, uint64 ms, uint16 refRank) external returns (uint256);
}

