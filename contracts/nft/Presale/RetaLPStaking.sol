// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../lib/openzeppelin-contracts@4.3.2/contracts/access/Ownable.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/security/Pausable.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/Address.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeMath.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeCast.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "../../utils/BlockTestable.sol";


contract RetaLPStaking is BlockTestable, Ownable, Pausable {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using Address for address;
  using SafeERC20 for IERC20Metadata;

  struct UserInfo {
    uint256 rewardDebt;
    uint256 lpAmount;
  }

  // about a day
  uint256 public constant BLOCK_PER_PHASE = 28800;

  bool initialized_ = false;

  mapping(address => UserInfo) public users_;

  IERC20Metadata private lpToken_;
  IERC20Metadata private reta_;

  uint256 public startBlock_;
  uint256 public endBlock_;
  uint16 public phase_;

  // 전체 보상
  uint256 public totalReward_;

  // 현재까지 지급된 보상
  uint256 public totalPaiedReward_;

  // 마지막 업데이트 된 블록
  uint256 public lastRewardBlock_;

  // LP당 보상 (누적)
  uint256 public accRewardPerShare_;

  // 블록당 보상
  uint256 public rewardPerBlock_;

  // 페이즈당 보상
  uint256 public rewardPerPhase_;

  event Deposited(address indexed sender, uint256 totalAmount, uint256 depositedAmount, uint256 income);
  event Withdrawed(address indexed sender, uint256 totalAmount, uint256 withdrawedAmount, uint256 income);
  event Harvested(address indexed sender, uint256 totalAmount, uint256 income);
  event EmergencyWithdrawed(address indexed sender, uint256 withdrawedAmount);

  constructor(address blockNumberer, address reta, address lpToken, uint256 startBlock, uint16 phase, uint256 totalReward)
    BlockTestable(blockNumberer)
  {
    require(reta.isContract(), "RetaLPStaking: reta is not a contract");
    require(lpToken.isContract(), "RetaLPStaking: lpToken is not a contract");
    require(startBlock > currentBlock() && 0 < phase, "RetaLPStaking: invalid block range");

    lpToken_ = IERC20Metadata(lpToken);
    reta_ = IERC20Metadata(reta);

    require(totalReward <= reta_.balanceOf(_msgSender()), "RetaLPStaking: Not enough RETA for reward");

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
      "RetaLPStaking: Duplicated calling to initialize"
    );
    require(
      reta_.allowance(_msgSender(), address(this)) > 0,
      "RetaLPStaking: To approve rewardToken is preceded"
    );

    reta_.transferFrom(_msgSender(), address(this), totalReward_);
    initialized_ = true;
  }

  function getMyStakingAmount() public view returns (uint256) {
    return users_[_msgSender()].lpAmount;
  }

  function getMyRewardPerBlock() public view returns (uint256) {
    uint256 lpSupply = lpToken_.balanceOf(address(this));
    if(0 == lpSupply) {
      return 0;
    }

    UserInfo storage user = users_[_msgSender()];
    if(0 == user.lpAmount) {
      return 0;
    }

    return rewardPerBlock_.mul(user.lpAmount.mul(1e12).div(lpSupply)).div(1e12);
  }

  function updateReward() public {
    if(lastRewardBlock_ >= endBlock_) {
      return;
    }

    uint256 currentBlockNumber = currentBlock();
    if(currentBlockNumber <= lastRewardBlock_) {
      return;
    }

    uint256 lpSupply = lpToken_.balanceOf(address(this));
    if(0 == lpSupply) {
      lastRewardBlock_ = currentBlockNumber;
      return;
    }

    uint256 targetBlockNumber = currentBlockNumber;
    if(targetBlockNumber > endBlock_) {
      targetBlockNumber = endBlock_;
    }
    uint256 reward = (targetBlockNumber - lastRewardBlock_).mul(rewardPerBlock_);
  
    accRewardPerShare_ = accRewardPerShare_.add(reward.mul(1e12).div(lpSupply));
    lastRewardBlock_ = currentBlockNumber;
  }

  /**
   *    LP Token 예치
   */
  function deposit(uint256 depositAmount) public whenNotPaused returns (uint256 reward) {
    address sender = _msgSender();
    UserInfo storage user = users_[sender];
    uint256 currentBlockNumber = currentBlock();

    require(currentBlockNumber < endBlock_, "RetaLPStaking: staking ended");

    updateReward();

    // 기존 보상 수령
    if(0 < user.lpAmount) {
      reward = accRewardPerShare_.mul(user.lpAmount).div(1e12).sub(user.rewardDebt);
      if(0 < reward) {
        _transferReta(sender, reward);
      }
    }

    if(0 < depositAmount) {
      lpToken_.safeTransferFrom(sender, address(this), depositAmount);
      user.lpAmount = user.lpAmount.add(depositAmount);
    }

    user.rewardDebt = accRewardPerShare_.mul(user.lpAmount).div(1e12);

    emit Deposited(sender, user.lpAmount, depositAmount, reward);
  }

  /**
   *    LP Token 출금
   */
  function withdraw(uint256 withdrawAmount) public whenNotPaused returns (uint256 reward) {
    address sender = _msgSender();
    UserInfo storage user = users_[sender];
    require(user.lpAmount >= withdrawAmount, "RetaLPStaking: invalid amount");

    updateReward();

    reward = accRewardPerShare_.mul(user.lpAmount).div(1e12).sub(user.rewardDebt);
    if(0 < reward) {
      _transferReta(sender, reward);
    }

    if(withdrawAmount > 0) {
      user.lpAmount = user.lpAmount.sub(withdrawAmount);
      lpToken_.safeTransfer(sender, withdrawAmount);
    }

    user.rewardDebt = accRewardPerShare_.mul(user.lpAmount).div(1e12);

    emit Withdrawed(sender, user.lpAmount, withdrawAmount, reward);
  }

  function harvest() public whenNotPaused returns (uint256 reward) {
    address sender = _msgSender();
    UserInfo storage user = users_[sender];

    updateReward();

    if(0 < user.lpAmount) {
      reward = accRewardPerShare_.mul(user.lpAmount).div(1e12).sub(user.rewardDebt);
      if(0 < reward) {
        _transferReta(sender, reward);
      }

      user.rewardDebt = accRewardPerShare_.mul(user.lpAmount).div(1e12);
    }

    emit Harvested(sender, user.lpAmount, reward);
  }

  function pendingReward() public view returns (uint256) {
    UserInfo storage user = users_[_msgSender()];
    if(0 == user.lpAmount) {
      return 0;
    }

    uint256 accRewardPerShare = accRewardPerShare_;
    uint256 targetBlock = currentBlock();

    if(targetBlock > endBlock_) {
      targetBlock = endBlock_;
    }

    if(targetBlock > lastRewardBlock_) {
      uint256 reward = (targetBlock - lastRewardBlock_).mul(rewardPerBlock_);
      uint256 lpSupply = lpToken_.balanceOf(address(this));
      accRewardPerShare = accRewardPerShare_.add(reward.mul(1e12).div(lpSupply));
    }

    return accRewardPerShare.mul(user.lpAmount).div(1e12).sub(user.rewardDebt);
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
    require(0 < balance, "RetaLPStaking: No balance");

    if(reta_.allowance(address(this), owner()) < balance) {
      reta_.approve(address(this), type(uint256).max);
    }

    reta_.safeTransferFrom(address(this), _msgSender(), balance);
    return balance;
  }

  // emergency withdraw lp token
  function emergencyWithdraw() public {
    address sender = _msgSender();
    UserInfo storage user = users_[sender];
    require(0 < user.lpAmount, "RetaLPStaking: No balance");

    lpToken_.safeTransfer(sender, user.lpAmount);
    emit EmergencyWithdrawed(sender, user.lpAmount);

    user.lpAmount = 0;
    user.rewardDebt = 0;
  }

  function _transferReta(address recipient, uint256 rewardAmount) internal {
    if(reta_.allowance(address(this), recipient) < rewardAmount) {
      reta_.approve(address(this), type(uint256).max);
    }

    totalPaiedReward_ += rewardAmount;

    reta_.transfer(recipient, rewardAmount);
  }
}
