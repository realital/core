// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../lib/openzeppelin-contracts@4.3.2/contracts/access/Ownable.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/security/Pausable.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/Address.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeMath.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeCast.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/structs/EnumerableSet.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC721/IERC721.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC721/IERC721Receiver.sol";

import "../../utils/BlockTestable.sol";
import "../../utils/SafeMath32.sol";

import "../Hero/IRetawarsHero.sol";

contract RWHeroStaking is BlockTestable, Ownable, Pausable, IERC721Receiver {
  using SafeMath for uint256;
  using SafeMath32 for uint32;
  using SafeCast for uint256;
  using Address for address;
  using SafeERC20 for IERC20Metadata;
  using EnumerableSet for EnumerableSet.UintSet;

  struct UserInfo {
    uint256 rewardDebt;
    uint32 power;
    EnumerableSet.UintSet tokenIds;
  }

  // about a day
  uint256 public constant BLOCK_PER_PHASE = 28800;

  bool initialized_ = false;

  mapping(address => UserInfo) users_;

  address private heroAddress_;
  IERC20Metadata private reta_;

  uint256 public startBlock_;
  uint256 public endBlock_;
  uint16 public phase_;

  // 전체 보상
  uint256 public totalReward_;

  // 스테이킹 등록된 NFT 수
  uint32 public totalStakingTokenAmount_;
  // 스테이킹 등록된 NFT Power 총합
  uint256 public totalStakingPower_;

  // 현재까지 지급된 보상
  uint256 public totalPaiedReward_;

  // 마지막 업데이트 된 블록
  uint256 public lastRewardBlock_;

  // 파워당 보상 (누적)
  uint256 public accRewardPerPower_;

  // 블록당 보상
  uint256 public rewardPerBlock_;

  // 페이즈당 보상
  uint256 public rewardPerPhase_;


  event Deposited(address indexed sender, uint32 totalPower, uint32 depositedPower, uint256 income, uint256[] tokenIds);
  event Withdrawed(address indexed sender, uint32 totalPower, uint32 withdrawedPower, uint256 income, uint256[] tokenIds);
  event Harvested(address indexed sender, uint32 totalPower, uint256 income);
  event EmergencyWithdrawed(address indexed sender, uint32 totalPower, uint32 withdrawedPower, uint256[] tokenIds);

  event HeroReceived(address indexed operator, address indexed from, uint256 tokenId, bytes data);

  constructor(address blockNumberer, address hero, address reta, uint256 startBlock, uint16 phase, uint256 totalReward)
    BlockTestable(blockNumberer)
  {
    require(hero.isContract(), "RWHeroStaking: hero is not a contract");
    require(reta.isContract(), "RWHeroStaking: reta is not a contract");
    require(startBlock > currentBlock() && 0 < phase, "RWHeroStaking: invalid block range");

    heroAddress_ = hero;
    reta_ = IERC20Metadata(reta);

    require(totalReward <= reta_.balanceOf(_msgSender()), "RWHeroStaking: Not enough RETA for reward");

    startBlock_ = startBlock;
    phase_ = phase;

    endBlock_ = startBlock_.add(BLOCK_PER_PHASE.mul(phase_));

    totalReward_ = totalReward;
    lastRewardBlock_ = startBlock_;

    rewardPerBlock_ = totalReward_.div(BLOCK_PER_PHASE.mul(phase_));
    rewardPerPhase_ = totalReward_.div(phase_);
  }

  function initialize() external onlyOwner {
    require(
      initialized_ == false,
      "RWHeroStaking: Duplicated calling to initialize"
    );
    require(
      reta_.allowance(_msgSender(), address(this)) > 0,
      "RWHeroStaking: To approve rewardToken is preceded"
    );

    reta_.transferFrom(_msgSender(), address(this), totalReward_);
    initialized_ = true;
  }

  function getMyHeroes() public view returns (uint256[] memory) {
    return users_[_msgSender()].tokenIds.values();
  }

  function getMyPower() public view returns (uint32) {
    return users_[_msgSender()].power;
  }

  function getMyRewardPerBlock() public view returns (uint256) {
    UserInfo storage user = users_[_msgSender()];
    if(0 == user.power) {
      return 0;
    }

    return rewardPerBlock_.mul(uint256(user.power).mul(1e12).div(totalStakingPower_)).div(1e12);
  }

  function getHeroes(address owner) public view onlyOwner returns (uint256[] memory) {
    return users_[owner].tokenIds.values();
  }

  function getHeroPower(uint256 tokenId) public view returns (uint32) {
    IRetawarsHero heroContract = IRetawarsHero(heroAddress_);
    IRetawarsHero.Hero memory hero = heroContract.getHero(tokenId);
    return _getPower(hero);
  }

  function updateReward() public {
    if(lastRewardBlock_ >= endBlock_) {
      return;
    }

    uint256 currentBlockNumber = currentBlock();
    if(currentBlockNumber <= lastRewardBlock_) {
      return;
    }

    if(0 == totalStakingPower_) {
      lastRewardBlock_ = currentBlockNumber;
      return;
    }

    uint256 targetBlockNumber = currentBlockNumber;
    if(targetBlockNumber > endBlock_) {
      targetBlockNumber = endBlock_;
    }
    uint256 reward = (targetBlockNumber - lastRewardBlock_).mul(rewardPerBlock_);
  
    accRewardPerPower_ = accRewardPerPower_.add(reward.mul(1e12).div(totalStakingPower_));
    lastRewardBlock_ = currentBlockNumber;
  }

  /**
   *    ERC721 예치
   */
  function deposit(uint256[] memory tokenIds) public whenNotPaused returns (uint256 reward) {
    IERC721 erc721 = IERC721(heroAddress_);

    address sender = _msgSender();
    UserInfo storage user = users_[sender];
    uint256 currentBlockNumber = currentBlock();

    require(currentBlockNumber < endBlock_, "RWHeroStaking: staking ended");

    updateReward();

    // 기존 보상 수령
    if(0 < user.power) {
      reward = accRewardPerPower_.mul(user.power).div(1e12).sub(user.rewardDebt);
      if(0 < reward) {
        _transferReta(sender, reward);
      }
    }

    uint32 totalPower = 0;
    for(uint16 index = 0; index < tokenIds.length; ++index) {
      uint256 tokenId = tokenIds[index];
      uint32 heroPower = getHeroPower(tokenId);
      require(0 < heroPower, "RWHeroStaking: only support presale hero");

      totalPower = totalPower.add(heroPower);
      erc721.safeTransferFrom(sender, address(this), tokenId);

      user.tokenIds.add(tokenId);
    }

    user.power = user.power.add(totalPower);
    user.rewardDebt = accRewardPerPower_.mul(user.power).div(1e12);

    totalStakingPower_ = totalStakingPower_.add(totalPower);
    totalStakingTokenAmount_ = totalStakingTokenAmount_.add(tokenIds.length.toUint16());

    emit Deposited(sender, user.power, totalPower, reward, tokenIds);
  }

  /**
   *    ERC721 출금
   */
  function withdraw(uint256[] memory tokenIds) public whenNotPaused returns (uint256 reward) {
    address sender = _msgSender();
    UserInfo storage user = users_[sender];

    require(0 < user.tokenIds.length(), "RWHeroStaking: no hero");

    IERC721 erc721 = IERC721(heroAddress_);

    updateReward();

    // 기존 보상 수령
    reward = accRewardPerPower_.mul(user.power).div(1e12).sub(user.rewardDebt);
    if(0 < reward) {
      _transferReta(sender, reward);
    }

    uint32 totalPower = 0;
    for(uint16 index = 0; index < tokenIds.length; ++index) {
      uint256 tokenId = tokenIds[index];
      require(user.tokenIds.contains(tokenId), "RWHeroStaking: caller is not owner");
      totalPower = totalPower.add(getHeroPower(tokenId));
      erc721.safeTransferFrom(address(this), sender, tokenId);

      user.tokenIds.remove(tokenId);
    }

    user.power = user.power.sub(totalPower);
    user.rewardDebt = accRewardPerPower_.mul(user.power).div(1e12);

    totalStakingPower_ = totalStakingPower_.sub(totalPower);
    totalStakingTokenAmount_ = totalStakingTokenAmount_.sub(tokenIds.length.toUint16());

    emit Withdrawed(sender, user.power, totalPower, reward, tokenIds);
  }

  function harvest() public whenNotPaused returns (uint256 reward) {
    address sender = _msgSender();
    UserInfo storage user = users_[sender];

    require(0 < user.tokenIds.length(), "RWHeroStaking: no hero");

    updateReward();

    if(0 < user.power) {
      reward = accRewardPerPower_.mul(user.power).div(1e12).sub(user.rewardDebt);
      if(0 < reward) {
        _transferReta(sender, reward);
      }

      user.rewardDebt = accRewardPerPower_.mul(user.power).div(1e12);
    }

    emit Harvested(sender, user.power, reward);
  }

  function pendingReward() public view returns (uint256) {
    UserInfo storage user = users_[_msgSender()];
    if(0 == user.tokenIds.length()) {
      return 0;
    }

    uint256 accRewardPerPower = accRewardPerPower_;
    uint256 targetBlock = currentBlock();
    if(targetBlock > endBlock_) {
      targetBlock = endBlock_;
    }

    if(targetBlock > lastRewardBlock_) {
      uint256 reward = (targetBlock - lastRewardBlock_).mul(rewardPerBlock_);
      accRewardPerPower = accRewardPerPower_.add(reward.mul(1e12).div(totalStakingPower_));
    }

    return accRewardPerPower.mul(user.power).div(1e12).sub(user.rewardDebt);
  }

  // 남은 보상 총 수량 (스테이킹이 아직 안된)
  function getRemainingRewardBalance() public view returns (uint256) {
    uint256 currentBlockNumber = currentBlock();
    // 스테이킹이 완료 된 경우
    if(endBlock_ <= currentBlockNumber) {
      return 0;
    }

    // 스테이킹 시작전
    if(currentBlockNumber <= startBlock_) {
      return totalReward_;
    }

    return totalReward_.sub(rewardPerBlock_.mul(currentBlockNumber - startBlock_));
  }


  // Emergency function - withdraw all reta balance.
  // DO NOT call once normal working
  function withdrawRewardBalance() public onlyOwner returns (uint256) {
    uint256 balance = reta_.balanceOf(address(this));
    require(0 < balance, "RWHeroStaking: No balance");

    if(reta_.allowance(address(this), owner()) < balance) {
      reta_.approve(address(this), type(uint256).max);
    }

    reta_.safeTransferFrom(address(this), _msgSender(), balance);
    return balance;
  }

  // emergency withdraw (erc721)
  function emergencyWithdraw() public {
    address sender = _msgSender();
    UserInfo storage user = users_[sender];
    require(0 < user.tokenIds.length(), "RWHeroStaking: no hero");

    IERC721 erc721 = IERC721(heroAddress_);

    uint32 totalPower = 0;
    for(uint16 index = 0; index < user.tokenIds.length(); ++index) {
      uint256 tokenId = user.tokenIds.at(index);
      require(user.tokenIds.contains(tokenId), "RWHeroStaking: caller is not owner");
      totalPower = totalPower.add(getHeroPower(tokenId));
      erc721.safeTransferFrom(address(this), sender, tokenId);
    }

    totalStakingPower_ = totalStakingPower_.sub(totalPower);
    totalStakingTokenAmount_ = totalStakingTokenAmount_.sub(user.tokenIds.length().toUint16());

    user.power = 0;
    user.rewardDebt = 0;

    emit EmergencyWithdrawed(sender, user.power, totalPower, user.tokenIds.values());

    for(int index = user.tokenIds.length().toInt256() - 1; index >= 0; --index) {
      user.tokenIds.remove(user.tokenIds.at(uint256(index)));
    }
  }

  function _transferReta(address recipient, uint256 rewardAmount) internal {
    if(reta_.allowance(address(this), recipient) < rewardAmount) {
      reta_.approve(address(this), type(uint256).max);
    }

    totalPaiedReward_ += rewardAmount;

    reta_.transfer(recipient, rewardAmount);
  }

  function _getPower(IRetawarsHero.Hero memory hero) internal pure returns (uint32) {
    // Only support presale token
    if(5 > hero.stats_[4]) {
      return 0;
    }

    return hero.stats_[0] + hero.stats_[1] + hero.stats_[2] + hero.stats_[3]
      + hero.skills_[0] + hero.skills_[1] + hero.skills_[2] + hero.skills_[3] + hero.skills_[4]
      - 65;
  }

  function onERC721Received(
    address operator,
    address from,
    uint256 tokenId,
    bytes calldata data
  ) external returns (bytes4) {
    emit HeroReceived(operator, from, tokenId, data);
    return this.onERC721Received.selector;
  }
}
