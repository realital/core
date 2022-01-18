// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../../lib/openzeppelin-contracts@4.3.2/contracts/access/Ownable.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/security/Pausable.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/security/ReentrancyGuard.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/Address.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeMath.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/structs/EnumerableSet.sol";

import "../Hero/IRetawarsHero.sol";
import "../../utils/SpeedBump.sol";
import "../../utils/SafeMath16.sol";

contract RWHeroPresale is Ownable, Pausable, ReentrancyGuard, SpeedBump {
  using SafeMath for uint256;
  using SafeMath16 for uint16;
  using SafeERC20 for IERC20Metadata;
  using Address for address;
  using EnumerableSet for EnumerableSet.AddressSet;

  struct Participant {
    // 1-[referralMax_], 0 == unrank
    uint16 currentRank_;

    // referral claimed token id
    uint256 referralRewarded_;

    // purchased token id
    uint256[] heroSpawned_;

    // who recommends this participant
    address recommender_;
  }

  uint16 constant public REFERRAL_MAX = 100;
  uint8 constant public SPAWN_MAX = 100;

  uint16 public presaleMax_;
  uint16 public referralMax_;

  // ranking
  address[REFERRAL_MAX] public referralRank_;

  mapping (address => Participant) participants_;
  mapping (address => EnumerableSet.AddressSet) private referralScores_;

  uint16 public lastComputed_;
  uint16 public soldCount_;
  uint16 public claimedCount_;

  IRWHeroPresaleSpawner private spawner_;
  IERC20Metadata public busd_;


  uint16 constant private BEGIN_PRICE = 200;
  uint16 constant private END_PRICE = 500;
  uint16 constant private PRICE_INCREMENT_UNIT = 20;
  uint16 constant private BEGIN_AMOUNT = 100;
  uint16 constant private BEGIN_AMOUNT_INCREMENT = 14;
  uint16 constant private AMOUNT_INCREMENT_UNIT = 12;

  uint16 public currentPrice_;
  uint16 public currentAmount_;
  uint16 public currentAmountIncrement_;

  uint16 public accumulatedAmount_;

  event Purchased(address indexed buyer, uint256 indexed tokenId, uint256 price, uint16 soldCount);
  event Claimed(address indexed claimer, uint256 indexed tokenId, uint16 ranking, uint16 score, uint16 claimedCount);

  constructor(address spawner, address busd, uint16 presaleMax, uint16 referralMax) {
    require(referralMax <= REFERRAL_MAX, "RWHeroPresale: referralMax overflows");
    require(spawner.isContract(), "RWHeroPresale: spawner is not a contract");
    require(busd.isContract(), "RWHeroPresale: busd is not a contract");

    spawner_ = IRWHeroPresaleSpawner(spawner);
    busd_ = IERC20Metadata(busd);

    presaleMax_ = presaleMax;
    referralMax_ = referralMax;

    currentPrice_ = BEGIN_PRICE;
    currentAmount_ = presaleMax_ < BEGIN_AMOUNT ? presaleMax_ : BEGIN_AMOUNT;
    currentAmountIncrement_ = BEGIN_AMOUNT_INCREMENT;

    accumulatedAmount_ = currentAmount_;
  }

  /**
    @dev `ms` for random generating
   */
  function purchase(uint256 fixedPrice, address referral, uint64 ms) public whenNotPaused speedBump returns (uint256) {
    require(soldCount_ < presaleMax_, "RWHeroPresale: presale is done");

    address sender = _msgSender();
    require(
      sender != address(0) && sender != owner(),
      "RWHeroPresale: Owner or zero address cannot purchase"
    );
    require(referral != sender, "RWHeroPresale: referral cannot be self");

    Participant storage participant = participants_[sender];

    // if the participant is not first to purchase
    if(participant.heroSpawned_.length > 0) {
      require(participant.recommender_ == referral || referral == address(0), "RWHeroPresale: cannot change referral");
      if(address(0) != participant.recommender_) {
        referral = participant.recommender_;
      }
    }
    else {
      if(address(0) != referral) {
        require(isValidReferral(referral), "RWHeroPresale: cannot call the referral who is not registered");
        participant.recommender_ = referral;
      }
    }

    require(participant.heroSpawned_.length < SPAWN_MAX, "RWHeroPresale: presale purchase limitation is 100");

    // Payment
    uint256 price = getPrice();
    if(0 != fixedPrice) {
      require(price == fixedPrice, "RWHeroPresale: the price is changed");
    }
    require(price >= BEGIN_PRICE * 10**busd_.decimals(), "RWHeroPresale: the price is invalid");
    require(busd_.allowance(sender, address(this)) >= price, "RWHeroPresale: buyer should be approved for BUSD");
    require(busd_.balanceOf(sender) >= price, "RWHeroPresale: not enough BUSD");

    busd_.safeTransferFrom(sender, address(this), price);

    // Transfer to owner
    if(busd_.allowance(address(this), owner()) < price) {
      busd_.approve(address(this), type(uint256).max);
    }
    busd_.safeTransferFrom(address(this), owner(), price);

    // Spawn
    uint256 tokenId = spawner_.spawnPresale(sender, ms, 0);
    participant.heroSpawned_.push(tokenId);

    ++soldCount_;
    _computePrice();

    if(address(0) != referral && !referralScores_[referral].contains(sender)) {
      referralScores_[referral].add(sender);
      _computeRanking(referral);
    }

    emit Purchased(sender, tokenId, price, soldCount_);

    return tokenId;
  }

  function withdrawProfit() public onlyOwner nonReentrant returns (uint256) {
    uint256 balance = busd_.balanceOf(address(this));
    require(0 < balance, "RWHeroPresale: No balance");

    if(busd_.allowance(address(this), _msgSender()) < balance) {
      busd_.approve(address(this), type(uint256).max);
    }

    busd_.safeTransferFrom(address(this), _msgSender(), balance);
    return balance;
  }

  function claimReward(uint64 ms) public whenNotPaused returns (uint256) {
    address sender = _msgSender();
    require(claimedCount_ < referralMax_, "RWHeroPresale: no more claimed");
    require(soldCount_ >= presaleMax_, "RWHeroPresale: now is on presale yet");
    require(participants_[sender].heroSpawned_.length > 0, "RWHeroPresale: no reward");
    require(referralScores_[sender].length() > 0, "RWHeroPresale: no reward #2");
    require(participants_[sender].referralRewarded_ == 0, "RWHeroPresale: already claimed");

    (uint16 ranking, uint16 score) = getRank(sender);
    require(0 < ranking && ranking - 1 < referralMax_, "RWHeroPresale: Unranked");

    uint256 tokenId = spawner_.spawnPresale(sender, ms, ranking);
    participants_[sender].referralRewarded_ = tokenId;

    ++claimedCount_;

    emit Claimed(sender, tokenId, ranking, score, claimedCount_);

    return tokenId;
  }

  function isValidReferral(address referral) public view returns (bool) {
    return participants_[referral].heroSpawned_.length > 0;
  }

  function getReferralReward(address receiver) public view returns (uint256) {
    return participants_[receiver].referralRewarded_;
  }

  function getPrice() public view returns (uint256) {
    return currentPrice_ * 10**busd_.decimals();
  }

  function getNextPrice() public view returns (uint256) {
    uint256 price = currentPrice_.add(PRICE_INCREMENT_UNIT);
    return (price > END_PRICE ? END_PRICE : price) * 10**busd_.decimals();
  }

  function remainingCurrentAmount() public view returns (uint16) {
    return accumulatedAmount_ - soldCount_;
  }

  function remainingTotalAmount() public view returns (uint16) {
    return presaleMax_ - soldCount_;
  }

  function getReferralList() public view returns (address[] memory) {
    return referralScores_[_msgSender()].values();
  }
  
  // one-based
  function getRankRange(uint16 from, uint16 to)
    public view
    returns (uint16[] memory ranks, address[] memory addrs, uint16[] memory scores)
  {
    require(0 < from && from <= to && to <= referralMax_, "RWHeroPresale: invalid range");
    uint16 length = to - from + 1;

    ranks = new uint16[](length);
    addrs = new address[](length);
    scores = new uint16[](length);

    for(uint16 index = from - 1; index < to; ++index) {
      address addr = referralRank_[index];
      if(address(0) == addr) {
        break;
      }

      ranks[index] = index + 1;
      addrs[index] = addr;
      scores[index] = uint16(referralScores_[addr].length());
    }
  }

  function getRank(address ranker) public view returns (uint16 rank, uint16 score) {
    rank = participants_[ranker].currentRank_;
    score = uint16(referralScores_[ranker].length());
  }

  uint16 private rankedCount_;

  function _computeRanking(address updatedAddr) internal {
    require(lastComputed_ < soldCount_, "RWHeroPresale: cannot call computeRanking at same sold count");
    lastComputed_ = soldCount_;

    Participant storage participant = participants_[updatedAddr];
    require(participant.heroSpawned_.length > 0, "RWHeroPresale: Invalid referral target");

    uint16 currentScore = uint16(referralScores_[updatedAddr].length());
    require(0 < currentScore, "RWHeroPresale: Unexpected score");

    if(referralMax_ == rankedCount_) {
      address tailAddr = referralRank_[rankedCount_ - 1];
      if(tailAddr == updatedAddr) {
        tailAddr = referralRank_[rankedCount_ - 2];
      }

      uint16 tailScore = uint16(referralScores_[tailAddr].length());
      if(currentScore <= tailScore) {
        return;
      }
    }

    if(participant.currentRank_ == 0) {
      _insertRanking(updatedAddr);
      return;
    }

    for(uint16 current = participant.currentRank_ - 1; current >= 1; --current) {
      uint16 above = current - 1;
      if(referralScores_[referralRank_[above]].length() >= currentScore) {
        break;
      }

      _swapRanking(current, above);
    }
  }

  function _swapRanking(uint16 from, uint16 to) internal {
    address fromAddr = referralRank_[from];
    address toAddr = referralRank_[to];

    referralRank_[from] = toAddr;
    referralRank_[to] = fromAddr;

    participants_[fromAddr].currentRank_ ^= participants_[toAddr].currentRank_
      ^= participants_[fromAddr].currentRank_ ^= participants_[toAddr].currentRank_;
  }

  function _insertRanking(address addr) internal {
    Participant storage participant = participants_[addr];
    require(participant.currentRank_ == 0, "RWHeroPresale: already on the ranking");

    uint16 score = uint16(referralScores_[addr].length());
    if(rankedCount_ < referralMax_) {
      referralRank_[rankedCount_] = addr;
      participant.currentRank_ = ++rankedCount_;
      return;
    }

    require(rankedCount_ == referralMax_, "RWHeroPresale: ranked count is not maximum yet");

    for(int16 index = int16(referralMax_) - 1; index >= 0; --index) {
      uint16 curr = uint16(index);
      address target = referralRank_[curr];
      uint16 targetScore = uint16(referralScores_[target].length());

      if(curr == referralMax_ - 1) {
        require(score > targetScore, "RWHeroPresale: cannot insert the addr.");
        require(participants_[target].currentRank_ == referralMax_, "RWHeroPresale: wrong ranking");

        participant.currentRank_ = participants_[target].currentRank_;
        participants_[target].currentRank_ = 0;
        referralRank_[curr] = addr;

        continue;
      }

      if(score > targetScore) {
        require(participant.currentRank_ == curr + 2);
        _swapRanking(curr, curr + 1);
      }
      else {
        break;
      }
    }
  }

  function _computePrice() internal {
    if(soldCount_ >= presaleMax_) {
      return;
    }

    if(soldCount_ >= accumulatedAmount_) {
      currentPrice_ = currentPrice_.add(PRICE_INCREMENT_UNIT);
      currentAmount_ = currentAmount_.add(currentAmountIncrement_);
      currentAmountIncrement_ = currentAmountIncrement_.add(AMOUNT_INCREMENT_UNIT);

      if(END_PRICE < currentPrice_) {
        currentPrice_ = END_PRICE;
      }
      accumulatedAmount_ = accumulatedAmount_.add(currentAmount_);
    }
  }

/*
  function computePriceForTest(uint16 increaseCount) external onlyOwner {
    soldCount_ += increaseCount;
    _computePrice();
  }

  function computeRankingForTest(address updatedAddr, address randomAddr) external onlyOwner {
    //require(lastComputed_ < soldCount_, "RWHeroPresale: cannot call computeRanking at same sold count");
    //lastComputed_ = soldCount_;

    require(!referralScores_[updatedAddr].contains(randomAddr), "RWHeroPresale: duplicated random addr");
    referralScores_[updatedAddr].add(randomAddr);

    Participant storage participant = participants_[updatedAddr];
    //require(participant.heroSpawned_.length > 0, "RWHeroPresale: Invalid referral target");

    uint16 currentScore = uint16(referralScores_[updatedAddr].length());
    require(0 < currentScore, "RWHeroPresale: Unexpected score");

    if(referralMax_ == rankedCount_) {
      address tailAddr = referralRank_[rankedCount_ - 1];
      if(tailAddr == updatedAddr) {
        tailAddr = referralRank_[rankedCount_ - 2];
      }

      uint16 tailScore = uint16(referralScores_[tailAddr].length());
      if(currentScore <= tailScore) {
        return;
      }
    }

    if(participant.currentRank_ == 0) {
      _insertRanking(updatedAddr);
      return;
    }

    for(uint16 current = participant.currentRank_ - 1; current >= 1; --current) {
      uint16 above = current - 1;
      if(referralScores_[referralRank_[above]].length() >= currentScore) {
        break;
      }

      _swapRanking(current, above);
    }
  }
*/
}
