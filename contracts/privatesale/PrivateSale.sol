pragma solidity ^0.8.0;
//pragma experimental ABIEncoderV2;

// SPDX-License-Identifier: MIT

import "../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeMath.sol";
import "../../lib/openzeppelin-contracts@4.3.2/contracts/utils/math/SafeCast.sol";
import "../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/ERC20.sol";
import "../../lib/openzeppelin-contracts@4.3.2/contracts/token/ERC20/utils/SafeERC20.sol";

import "../utils/Testable.sol";
import "../utils/Reservable.sol";
import "../utils/SafeMath16.sol";

contract PrivateSale is Reservable, Testable {
  using SafeMath for uint256;
  using SafeCast for uint256;
  using SafeMath16 for uint16;
  using SafeERC20 for IERC20Metadata;

  IERC20Metadata internal depositToken_;
  IERC20Metadata internal rewardToken_;

  struct Buyer {
    address id;
    uint256 depositedAmount; // deposited amount (maybe BUSD or BNB)
    uint256 assignedAmount; // assigned reward amount
    uint256 releasedAmount; // released amount
    uint16 releasedCount; // released count
    uint256 totalReleasedAmount;
  }

  uint256 public totalDeposited_;
  uint256 public totalReleased_;

  mapping(address => Buyer) internal buyers_;

  uint256 constant public PERIOD_UNIT = 86400;
  uint256 constant public PURCHASE_UNIT = 100;

  uint256 public depositTotalAmount_;
  uint256 public tokenPrice_;
  uint256 public rewardTotalAmount_;

  uint64 public startSellingTimestamp_;
  uint64 public endSellingTimestamp_;

  uint16 public releasePeriodDays_;
  uint16 public releaseTotalCount_;

  bool internal initialized_ = false;

  //-------------------------------------------------------------------------
  // EVENTS
  //-------------------------------------------------------------------------
  event Deposited(address indexed sender, uint256 value, uint256 total);
  event Released(address indexed sender, uint16 indexed count, uint256 value, uint256 total);

  //-------------------------------------------------------------------------
  // CONSTRUCTOR
  //-------------------------------------------------------------------------
  constructor(
    address timer,
    address depositToken,
    uint256 depositTotalAmount,
    address rewardToken,
    uint256 rewardTotalAmount,
    uint256 tokenPrice,
    uint64 startSellingTimestamp,
    uint64 endSellingTimestamp,
    uint16 releasePeriodDays,
    uint16 releaseTotalCount
  )
    Reservable(depositTotalAmount)
    Testable(timer)
  {
    require(
      depositToken != address(0),
      "DepositToken cannot be 0 address"
    );
    require(
      rewardToken != address(0),
      "RewardToken cannot be 0 address"
    );
    require(
      tokenPrice > 0,
      "tokenPrice must be more than zero"
    );
    require(
      currentTime() <= startSellingTimestamp,
      "startSellingTimestamp must be more than currentTime"
    );
    require(
      endSellingTimestamp > startSellingTimestamp,
      "endSellingTimestamp must be more than startSellingTimestamp"
    );
    require(
      depositTotalAmount > 0,
      "depositTotalAmount must be more than zero"
    );
    require(
      rewardTotalAmount > 0,
      "rewardTotalAmount must be more than zero"
    );
    require(
      releasePeriodDays > 0,
      "releasePeriodDays must be more than zero"
    );
    require(
      releaseTotalCount > 0,
      "releaseTotalCount must be more than zero"
    );
    require(
      rewardTotalAmount.mod(tokenPrice) == 0,
      "Invalid rewardTotalAmount and tokenPrice"
    );

    depositToken_ = IERC20Metadata(depositToken);
    rewardToken_ = IERC20Metadata(rewardToken);

    require(
      rewardTotalAmount == depositTotalAmount.div(tokenPrice).mul(10**rewardToken_.decimals()),
      "PrivateSale: totalAmounts is not matched"
    );
    require(
      rewardToken_.balanceOf(_msgSender()) >= rewardTotalAmount,
      "rewardToken balance is not enough to be reward"
    );

    depositTotalAmount_ = depositTotalAmount;
    tokenPrice_ = tokenPrice;
    rewardTotalAmount_ = rewardTotalAmount;

    startSellingTimestamp_ = startSellingTimestamp;
    endSellingTimestamp_ = endSellingTimestamp;

    releasePeriodDays_ = releasePeriodDays;
    releaseTotalCount_ = releaseTotalCount;
  }

  function initialize() external onlyOwner {
    require(
      initialized_ == false,
      "Duplicated calling to initialize"
    );
    require(
      rewardToken_.allowance(_msgSender(), address(this)) > 0,
      "To approve rewardToken is preceded"
    );

    rewardToken_.transferFrom(_msgSender(), address(this), rewardTotalAmount_);
    initialized_ = true;
  }

  //function cancelToSale

  function withdrawDeposited() external onlyOwner returns(uint256) {
    require(
      currentTime() >= endSellingTimestamp_,
      "Selling is not over yet"
    );

    depositToken_.approve(address(this), type(uint256).max);
    depositToken_.safeTransferFrom(address(this), _msgSender(), totalDeposited_);
    return totalDeposited_;
  }

  /**
   * @param depositAmount deposit token amount
   * @return total assigned reward token amount
   */
  function deposit(uint256 depositAmount) external payable onlyParticipant returns(uint256) {
    require(
      currentTime() >= startSellingTimestamp_,
      "Not in selling yet"
    );

    uint256 depositTokenDecimals = 10**depositToken_.decimals();
    uint256 purchaseUnit = PURCHASE_UNIT * depositTokenDecimals;

    require(
      0 < depositAmount,
      "depositAmount must be more than zero"
    );
    require(
      depositAmount.mod(purchaseUnit) == 0,
      "purchase unit is wrong"
    );
    address sender = _msgSender();
    require(
      sender != address(0) && sender != owner(),
      "Owner or zero address cannot deposit"
    );
    require(
      depositAmount <= availableDepositAmount(),
      "AvailableDepositAmount is not enough"
    );

    require(
      depositToken_.balanceOf(sender) >= depositAmount,
      "Not enough buyer's deposit amount"
    );

    uint256 amountToAssign = depositAmount.div(tokenPrice_).mul(10**rewardToken_.decimals());
    uint256 amountReserved = getReservedAmount(sender);

    uint256 remainingAmount = amountReserved - buyers_[sender].depositedAmount;

    require(
      depositAmount == remainingAmount,
      "PrivateSale: Not matched remainingAmount"
    );

    depositToken_.safeTransferFrom(sender, address(this), depositAmount);

    if(buyers_[sender].id == address(0)) {
      Buyer memory buyer = Buyer(
        sender,
        depositAmount,
        amountToAssign,
        0,
        0,
        0
      );

      buyers_[sender] = buyer;
    }
    else {
      Buyer storage buyer = buyers_[sender];
      buyer.depositedAmount = buyer.depositedAmount.add(depositAmount);
      buyer.assignedAmount = buyer.assignedAmount.add(amountToAssign);
    }

    totalDeposited_ += depositAmount;

    emit Deposited(sender, depositAmount, totalDeposited_);
    return buyers_[sender].assignedAmount;
  }

  /**
    @return (released amount, total assigned reward token amount)
   */
  function release() external onlyParticipant returns (uint256, uint256) {
    require(
      currentTime() >= endSellingTimestamp_,
      "Selling is not over yet"
    );

    address sender = _msgSender();
    uint256 amountToRelease = _availableReleaseAmount(sender);
    require(
      amountToRelease > 0,
      "Unable to release"
    );

    rewardToken_.approve(address(this), amountToRelease);
    rewardToken_.transferFrom(address(this), sender, amountToRelease);

    Buyer storage buyer = buyers_[sender];
    buyer.releasedAmount = buyer.releasedAmount.add(amountToRelease);
    buyer.releasedCount = _currentReleaseCount();
    buyer.totalReleasedAmount = buyer.totalReleasedAmount.add(amountToRelease);

    totalReleased_ = totalReleased_.add(amountToRelease);

    emit Released(sender, buyer.releasedCount, amountToRelease, buyer.totalReleasedAmount);

    return (amountToRelease, buyer.releasedAmount);
  }

  function assignedAmount() public view onlyParticipant returns (uint256) {
    return buyers_[_msgSender()].assignedAmount;
  }

  function availableDepositAmount() public view returns (uint256) {
    return depositTotalAmount_.sub(totalDeposited_);
  }

  function releasedAmount() public view onlyParticipant returns (uint256) {
    return buyers_[_msgSender()].releasedAmount;
  }

  /**
    @notice get the timestamp of next release
   */
  function nextRelease() public view returns (uint64) {
    uint256 _now = currentTime();
    if(_now < endSellingTimestamp_) {
      return endSellingTimestamp_;
    }

    uint64 releasePeriodSeconds = _releasePeriodSeconds();
    uint256 endOfReleaseTimestamp = endSellingTimestamp_ + releasePeriodSeconds * releaseTotalCount_;
    if(_now >= endOfReleaseTimestamp) {
      return 0;
    }

    return endSellingTimestamp_ + releasePeriodSeconds * _currentReleaseCount();
  }

  function sellingInformation() public view returns (uint256, uint256, uint64, uint64) {
    return (tokenPrice_, totalDeposited_, startSellingTimestamp_, endSellingTimestamp_);
  }

  function releaseInformation() public view returns (uint256, uint16, uint16) {
    return (totalReleased_, releasePeriodDays_, releaseTotalCount_);
  }

  function buyerInformation() public view onlyParticipant returns (uint256, uint256, uint256, uint16) {
    Buyer memory buyer = buyers_[_msgSender()];
    return (
      buyer.depositedAmount,
      buyer.assignedAmount,
      buyer.releasedAmount,
      buyer.releasedCount
    );
  }

  function buyerInformation(address buyerId) public view onlyOwner returns (uint256, uint256, uint256, uint16) {
    Buyer memory buyer = buyers_[buyerId];
    return (
      buyer.depositedAmount,
      buyer.assignedAmount,
      buyer.releasedAmount,
      buyer.releasedCount
    );
  }

  function getParticipantInformation(uint256 index) public view onlyOwner returns (
    address addr,
    uint256 rReserved,
    uint256 rDeposited,
    uint256 rAssigned,
    uint256 rReleased,
    uint16 rReleasedCount,
    uint256 rTotalReleased
  ) {
    addr = super.getParticipant(index);
    rReserved = reservedMap_[addr];

    Buyer memory buyer = buyers_[addr];

    rDeposited = buyer.depositedAmount;
    rAssigned = buyer.assignedAmount;
    rReleased = buyer.releasedAmount;
    rReleasedCount = buyer.releasedCount;
    rTotalReleased = buyer.totalReleasedAmount;
  }

  /**
    @notice get sender's available release amount
   */
  function availableReleaseAmount() public view onlyParticipant returns (uint256) {
    return _availableReleaseAmount(_msgSender());
  }

  //-------------------------------------------------------------------------
  // OVERRIDE FUNCTIONS
  //------------------------------------------------------------------------- 
  function updateReservedAmount(address addr, uint256 amount) public override onlyOwner returns (uint256) {
    require(buyers_[addr].depositedAmount < amount, "PrivateSale: updateReservedAmount cannot be less than exists deposited amount");

    return super.updateReservedAmount(addr, amount);
  }

  function removeParticipants(address[] memory addresses) public override onlyOwner {
    for(uint index = 0; index < addresses.length; ++index) {
      address addr = addresses[index];
      require(buyers_[addr].depositedAmount == 0, "PrivateSale: cannot include participant already deposited");
    }

    super.removeParticipants(addresses);
  }

  //-------------------------------------------------------------------------
  // INTERNAL FUNCTIONS
  //-------------------------------------------------------------------------

  /**
    @notice get sender's available release amount
   */
  function _availableReleaseAmount(address sender) internal view returns (uint256) {
    Buyer memory buyer = buyers_[sender];
    uint256 amount = 0;
    uint256 amountPerReleasing = _releaseAmount(buyer.assignedAmount);

    uint16 currentReleaseCount = _currentReleaseCount();
    if(buyer.releasedCount < currentReleaseCount) {
      amount = (currentReleaseCount - buyer.releasedCount) * amountPerReleasing;
    }

    uint256 expectedReleased = buyer.releasedCount * amountPerReleasing;
    if(buyer.totalReleasedAmount < expectedReleased) {
      amount += expectedReleased - buyer.totalReleasedAmount;
    }

    return amount;
  }

  function _currentReleaseCount() internal view returns (uint16) {
    uint256 _now = currentTime();
    if(_now < endSellingTimestamp_) {
      return 0;
    }

    uint16 releaseCount = _now.sub(endSellingTimestamp_).div(_releasePeriodSeconds()).toUint16() + 1;
    return releaseCount > releaseTotalCount_ ? releaseTotalCount_ : releaseCount;
  }

  function _releasePeriodSeconds() internal view returns (uint64) {
    return uint64(releasePeriodDays_) * 24 * 60 * 60;
  }

  /**
    @notice get amount of a release count
    @param assigned total balance of assigned
   */
  function _releaseAmount(uint256 assigned) internal view returns (uint256) {
    return assigned.div(releaseTotalCount_);
  }
}

