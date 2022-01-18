// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeMath.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/proxy/transparent/ProxyAdmin.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "./IRetawarsHero.sol";
import "../RetaNft.sol";
import "../../utils/RetawarsMaterial.sol";
import "./IRWHeroGenerator.sol";


contract RetawarsHero is IRetawarsHero, IRWHeroSpawner, IRWHeroPresaleSpawner, RetaNft {
  using SafeMath for uint256;
  
  mapping(uint256 => Hero) public heros_;

  address private generator_;

  event Spawned(address indexed minter, address indexed tokenOwner, uint256 indexed tokenId, IRetawarsHero.Hero hero, uint64 ms);
  event LevelUpSuccess(address indexed editor, address indexed tokenOwner, uint256 indexed tokenId, uint8 levelBefore, uint8 levelAfter, uint32 chance, uint32 randOut, uint64 ms);
  event LevelUpFailure(address indexed editor, address indexed tokenOwner, uint256 indexed tokenId, uint8 level, uint32 chance, uint32 randOut, uint64 ms);
  event LevelChanged(address indexed editor, address indexed tokenOwner, uint256 indexed tokenId, uint8 levelBefore, uint8 levelAfter);

  constructor() 
    RetaNft("Retawars Hero", "RWHero", "https://api.retawars.com/hero/", 101)
  {
  }

  function setGenerator(address generatorAddr) public onlyOwner {
    require(IRWHeroGenerator(generatorAddr).getCaller() == address(this), "RetawarsHero: The generator's caller is wrong");
    generator_ = generatorAddr;
  }

  modifier usingGenerator {
    require(generator_ != address(0), "RetawarsHero: The generator is empty");
    _;
  }

  /**
    @dev `spawn` only called by RWHeroManager contract
   */
  function spawn(address to, uint64 ms)
    external
    onlyMinter usingGenerator whenNotPaused
    returns (uint256)
  {
    IRWHeroGenerator generator = IRWHeroGenerator(generator_);

    Hero memory hero = generator.generate(to, ms);
    uint256 tokenId = super.mint(to);

    heros_[tokenId] = hero;

    emit Spawned(_msgSender(), to, tokenId, hero, ms);

    return tokenId;
  }

  /**
    @dev `spawnPresale` only called by RWHeroPresale contract
   */
  function spawnPresale(address to, uint64 ms, uint16 refRank)
    external
    onlyMinter usingGenerator whenNotPaused
    returns (uint256)
  {
    IRWHeroGenerator generator = IRWHeroGenerator(generator_);

    Hero memory hero = generator.generatePresale(to, ms, refRank);
    uint256 tokenId = super.mint(to);

    heros_[tokenId] = hero;

    emit Spawned(_msgSender(), to, tokenId, hero, ms);

    return tokenId;
  }

  function getHeroOwner(uint256 tokenId) external view validToken(tokenId) returns (address) {
    return ownerOf(tokenId);
  }

  function levelUpFallible(uint256 tokenId, uint8 level, uint32 chance, uint64 ms)
    external validToken(tokenId) onlyEditor usingGenerator whenNotPaused
    returns (uint8)
  {
    address to = ownerOf(tokenId);
    uint32 randOut = 0;

    Hero storage hero = heros_[tokenId];
    uint8 levelBefore = hero.level_;

    if(chance < 10000) {
      IRWHeroGenerator generator = IRWHeroGenerator(generator_);
      randOut = uint32(generator.getRandom(to, ms) % 10000);
      if(randOut >= chance) {
        emit LevelUpFailure(_msgSender(), to, tokenId, levelBefore, chance, randOut, ms);

        return levelBefore;
      }
    }

    hero.level_ = level;

    emit LevelUpSuccess(_msgSender(), to, tokenId, levelBefore, level, chance, randOut, ms);

    return level;
  }

  function setLevel(uint256 tokenId, uint8 level)
    external
    validToken(tokenId) onlyEditor whenNotPaused
  {
    return _setLevel(tokenId, level);
  }

  function _setLevel(uint256 tokenId, uint8 level) internal {
    address to = ownerOf(tokenId);

    Hero storage hero = heros_[tokenId];
    uint8 levelBefore = hero.level_;
    hero.level_ = level;

    emit LevelChanged(_msgSender(), to, tokenId, levelBefore, hero.level_);
  }

  function getLevel(uint256 tokenId) external view returns (uint8) {
    return heros_[tokenId].level_;
  }

  function getGrade(uint256 tokenId) external validToken(tokenId) view returns (Grade) {
    return heros_[tokenId].grade_;
  }

  function getHero(uint256 tokenId) external validToken(tokenId) view returns (Hero memory) {
    return heros_[tokenId];
  }

  function burnHeros(uint256[] memory tokenIds) public override onlyEditor whenNotPaused {
    for(uint index = 0; index < tokenIds.length; ++index) {
      uint256 tokenId = tokenIds[index];

      super.burn(tokenId);
      delete heros_[tokenId];
    }
  }
}
