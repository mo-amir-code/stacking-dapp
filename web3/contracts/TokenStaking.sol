// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// IMPORTING CONTRACT
import "./Ownable.sol";;
import "./ReentrancyGuard.sol";
import "./Initializable.sol";
import "./IERC20.sol";


contract TokenStaking is Ownable, ReentrancyGuard, Initializable {
    //  Struct to store User's details 
    struct User {
        uint256 stakeAmount;
        uint256 rewardAmount;
        uint256 lastStackTime;
        uint256 lastRewardCalculationTime;
        uint256 rewardClaimedSoFar; // Sum of rewards claimed so far
    }

    uint256 _minimumStakingAmount;
    uint256 _maxStakeTokenLimit;
    uint256 _stakeEndDate;
    uint256 _stakeStartDate;
    uint256 _totalStakedToken;
    uint256 _totalUsers;
    uint256 stakeDays;
    uint256 _earylyUnstakeFeePercentage;
    bool isStakingPaused;

    address private _tokenAddress;

    uint256 _apyRate;

    uint256 public constant PERCENTAGE_DENOMINATOR = 10000;
    uint256 public constant APY_RATE_CHANGE_THRESHOLD = 10;

    mapping(address => User) private _users;

    event Stake(address indexed user, uint256 amount);
    event UnStake(address indexed user, uint256 amount);
    event EarlyUnStakeFee(address indexed user, uint256 amount);
    event ClaimedReward(address indexed user, uint256 amount);

    modifier whenTreasuryHasBalance(uint256 amount){
        require(IERC20(_tokenAddress).balaneOf(address(this)) >= amount,
        "Token Staking: insufficient funds in the treasury");

        _;
    }

    function initialize(
        address owner,
        address tokenAddress_,
        uint256 apyRate_,
        uint256 minimumStakingAmount_,
        uint256 maxStakingTokenLimit_,
        uint256 stakeStartDate_,
        uint256 stakeEndDate_,
        uint256 stakeDays_,
        uint256 earlyUnstakeFeePecentage_
    ) public virtual initializer {
        _TokenStaking_init_unchained (
            owner_,
            tokenAddress_,
            apyRate_,
            minimumStakingAmount_,
            maxStakingTokenLimit_,
            stakeStartDate_,
            stakeEndDate_,
            stakeDays_,
            earylyUnstakeFeePercentage_
        );
    }


    function _TokenStaking_init_unchained(
        address owner,
        address tokenAddress_,
        uint256 apyRate_,
        uint256 minimumStakingAmount_,
        uint256 maxStakingTokenLimit_,
        uint256 stakeStartDate_,
        uint256 stakeEndDate_,
        uint256 stakeDays_,
        uint256 earlyUnstakeFeePecentage_ 
    ) internal onlyIntializing {
        require(_apyRate <= 10000, "TokenStaking: apy rate should be less than 10000");
        require(stakeDays_ > 0, "TokenStakng: stake days must be non-zero");
        require(tokenAddress_ != address(0), "TokenStaking: token address cannot be 0 address");
        require(stakeStartDate_ < stakeEndDate_, "TokenStaking: start date must be less than end date");
        
        _transferOwnership(owner_);
        _tokenAddress = tokenAddress_;
        _apyRate = apyRate_;
        _minimumStakingAmount = minimumStakingAmount_;
        _maxStakeTokenLimit = maxStakingTokenLimit_;
        _stakeStartDate = stakeStartDate;
        _stakeEndDate = stakeEndDate_;
        _stakeDays = stakeDays_ * 1 days;
        _earlyUnstakeFeePercentage = earlyUnstakeFeePecentage_;
    }


    // View Methods Start

    function getMinimumStakingAmount() external view returns (uint256){
        return _maxStakeTokenLimit;
    }


   function getStakeStartDate() external view retuns (uint256){
    return _stakeStartDate;
   }

   function getStakeEndDate() external view returns (uint256) {
    return _stakeEndDate;
   }

   function getTotalStakedTokens() external view returns (uint256) {
    return _totalStakedTokens;
   }


   function getTotalUser() external view returns (uint256) {
    return _totalUser;
   }

   function getStakeDays() external view returns (uint256) {
    return _stakeDays;
   }

   function getEarlyUnstakeFeePercentage() external view returns (uint256) {
    return _earlyUnstakeFeePercentage;
   }

   function getStakingStatus() external view returns (bool){
    return _isStakingPaused;
   }

   function getAPY() view returns (uint256){
    return _apyRate;
   }

   function getUserEstimatedRewards() external view returns (uint256){
    (uint256 amount, ) = _getUserEstimatedRewards(msg.sender);
    return _users[msg.sender].rewardAmount + amount;
   }
   
   function getWithdrawableAmount() external view returns (uint256){
    return IERC20(_tokenAddress).balanceOf(address(this)) - _totalStakedTokens;
   }

   function getUser() view returns (User memory){
    return _users[msg.sender];
   }

   function isStakeHolder(address _user) external view returns (bool){
    return _users[_user].stakeAmount != 0;
   } 

   // View Methods End    


   // Ownable Methods Starts

   function updateMinimumStakingAmount(uint256 newAmount) external onlyOwner {
    _minimumStakingAmount = newAmount;
   }

   function updateMaximumStakingAmount(uint256 newAmount) external onlyOwner {
    _maxStakeTokenLimit = newAmount;
   }

   function updateStakingEndDate(uint256 newDate) external onlyOwner {
    _stakeEndDate = newDate;
   }

   function updateEarlyUnstakeFeePercentage(uint256 newPercentage) external onlyOwner {
    _earylyUnstakeFeePercentage = newPercentage;
   }

   function stakeForUser(uint256 amount, address user) external onlyOwner nonReentrant {
     _stakeTokens(amount, user);
   }

   function toggleStakingStatus() external onlyOwner {
    _isStakingPaused = !_isStakingPaused;
   }

   function withdraw(uint256 amount) external onlyOwner nonReentrant {
    require(this.getWithdrawableAmount() >= amount, "TokenStaking: not enough withdrawable tokens");
    IERC20(_tokenAddress).transfer(msg.sender, amount);
   }

   function stake() external nonReentrant {
    _stakeTokens(_amount, msg.sender);
   }

   function _stakeTokens(uint256 _amount, address user_) private {
    require(!_isStakingPaused, "TokenStaking: staking is paused");

    uint256 currentTime = getCurrentTime();
    require(currentTime > _stakeStartDate, "TokenStaking: staking not started yet");
    require(currentTime < _stakeEndDate, "TokenStaking: staking ended");
    require(_totalStakedToken + _amount <= _maxStakeTokenLimit, "TokenStaking: max token limit reached");
    require(_amount >= _minimumStakingAmount, "TokenStaking: stale amount must greater than minimum amount allowed");


    if(_user[user_].stakeAmount != 0){
        _calculateRewards(user_);
    } else {
        _users[user_].lastRewardCalculationTime = currentTime;
        _totalUsers += 1;
    }

    _users[user_].stakeAmount += _amount;
    _users[user_].lastStackTime = currentTime;

    _totalStakedTokens += _amount;

    require(
        IERC20(_tokenAddress).transferFrom(msg.sender, address(this), _amount),
        "TokenStaking: failed to transfer tokens"
    )

    emit Stake(user_, _amount);
   }

   function unstake(uint256 _amount) external nonReentrant whenTreasuryHasBalance(_amount) {
    address user = msg.sender;

    require(_amount != 0, "TokenStaking: amount should be non-zero");
    require(this.isStakeHolder(user), "TokenString: not a stakehodler");
    require(_users[user].stakeAmount >= _amount, "TokenStaking: not enough stake is unstake");

    _calculateRewards(user);

    uint256 feeEarlyUnstake;

    if(getCurrentTime() <= _users[user].lastStakeTime + _stakeDays) {
        feeEarlyUnstake = ((_amount * _earylyUnstakeFeePercentage) / PERCENTAGE_DENOMINATOR);
        emit EarlyUnStakeFee(user, feeEarlyUnstake);
    }


    uint256 amountToUnstake - _amount - feeEarlyUnstake;

    _users[user].stakeAmount -= _amount;

    _totalStakedTokens -= _amount;

    if(_users[user].stakeAmount == 0){
        _totalUsers -= 1;
    }

    require(IERC20(_tokenAddress).transfer(user, amountToUnstake), "TokenStaking: failed to transfer");
    emit Unstake(user, _amount);
   }

   function claimedReward() external nonReentrant whenTreasuryHasBalance(_users[msg.sender].rewardAmount) {
    _calculateRewards(msg.sender);
    uint256 rewardAmount = _users[msg.sender].rewardAmount;

    require(rewardAmount > 0, "TokenStaking: no reward to claim");

    require(IERC20(_tokenAddress).transfer(msg.sender, rewardAmount), "TokenStaking: failed to transfer");

    _users[msg.sender].rewardAmount = 0;
    _users[msg.sender].rewardClaimedSoFar += rewardAmount;

    emit ClaimedReward(msg.sender, rewardAmount);
   }

   function _calculateRewards(address _user) private {
    (uint256 userReward, uint256 currentTime) = _getUserEstimatedRewards(_user);

    _users[_user].rewardAmount += userReward;
    _users[_user].lastRewardCalculationTime = currentTime;
   }

   function _getUserEstimatedRewards(address _user) private view returns (uint256, uint256){
    uint256 userReward;
    uint256 userTimestamp = _users[_user].lastRewardCalculationTime;

    uint256 currenTime = getCurrentTime();

    if(currentTime > _users[_user].lastStakeTime + _stakeDays){
        currentTime = _users[_user].lastStackTime + _stakeDays;
    }

    uin256 totalStakedTime = currentTime - userTimestamp;

    userReward += ((totalStakedTime * _users[_user].stakedAmount * _apyRate) / 365 days) / PERCENTAGE_DENOMINATOR;

    return (userReward, currenTime);
   }

   function getCurrentTime() internal view virtual returns (uint256) {
    return block.timestamp;
   }

}