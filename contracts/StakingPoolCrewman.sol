// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//
//     #######    #####     ##     #####
//    ##         ##    ##   ##   ##     ##
//    ##        ##          ##  ##       ##
//    ########  ##          ##  ##       ##
//    ##        ##          ##  ##       ##
//    ##         ##    ##   ##   ##     ##
//     #######    #####     ##     #####
//
/// @author ECIO Engineering Team
/// @title ECIO Staking Pool 1st Smart Contract

contract ECIOStakingPoolCrewman is Ownable {
    
    /** 70,000,000 ECIO **/
    uint256 public constant TOTAL_ECIO_PER_POOL = 70000000000000000000000000;

    /** 70,000,000 ECIO **/
    uint256 public constant MAXIMUM_STAKING = 70000000000000000000000000;

    /**  5,000 ECIO **/
    uint256 public constant MINIMUM_STAKING = 5000000000000000000000;

    /** Ugent unstake fee (10%) **/
    uint256 public constant FEE = 1000;

    /** Token lock time after unstaked*/
    uint256 public constant WITHDRAW_LOCK_DAY = 3;
    
    /** Reward Rate 150% */
    uint256 public constant REWARD_RATE = 100;

    uint256 public endPool;

    constructor() {
        endPool = getTimestamp() + 365 days;
    }

    struct Stake {
        uint256 amount;
        uint256 timestamp;
    }
    
    mapping(address => Stake[]) public stakers;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public stakeCounts;
    mapping(address => uint256) private _lockedBalances;
    mapping(address => uint256) private _lockedRewards;
    mapping(address => uint256) private _releaseTime;

    /** Total reward are claimed */
    uint256 public claimedReward = 0;

    /** Total supply of the pool */
    uint256 public totalSupply;

    /** Total ECIO fee that charge from ugent unstaking */
    uint256 public totalFee;

    // uint256 private mockupTimestamp;

    IERC20 ecioToken;

    /************************* EVENTS *****************************/
    event StakeEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 amount
    );
    event UnStakeEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 amount,
        uint256 reward
    );
    event UnStakeNowEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 amount,
        uint256 reward,
        uint256 fee
    );
    event ClaimEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 amount,
        uint256 reward
    );

    /************************* MANAGEMENT FUNC *****************************/
    function setupECIOToken(address _ecioToken) public onlyOwner {
        ecioToken = IERC20(_ecioToken);
    }

    // function setMockupTimestamp(uint256 timestamp) public onlyOwner {
    //     mockupTimestamp = timestamp;
    // }

    function transfer(
        address _contractAddress,
        address _to,
        uint256 _amount
    ) public onlyOwner {
        IERC20 _token = IERC20(_contractAddress);
        _token.transfer(_to, _amount);
    }

    /************************* VIEW FUNC *****************************/

    function getTimestamp() public view returns (uint256) {
        // if (mockupTimestamp != 0) {
        //     return mockupTimestamp;
        // }

        return block.timestamp;
    }

    function isPoolClose() public view returns (bool) {
        return (block.timestamp >= endPool);
    }

    function status(address _account) public view returns (string memory) {
        if (balances[_account] != 0) {
            return "STAKED";
        }

        if (_lockedBalances[_account] != 0) {
            return "WAITING";
        }

        return "NO STAKE";
    }

    function isUnlock(address account) public view returns (bool) {
        return _releaseTime[account] <= getTimestamp();
    }

    function releaseTime(address _account) public view returns (uint256) {
        return _releaseTime[_account];
    }

    function remainingPool() public view returns (uint256) {
        return MAXIMUM_STAKING - totalSupply;
    }

    function remainingReward() public view returns (uint256) {
        return TOTAL_ECIO_PER_POOL - claimedReward;
    }

    function staked(address _account) public view returns (uint256) {
        if (_lockedBalances[_account] != 0) {
            return _lockedBalances[_account];
        }

        return balances[_account];
    }

    function earned(address account) public view returns (uint256) {
        
        if (_lockedRewards[account] != 0) {
            return _lockedRewards[account];
        }

        uint256 timestamp;
        if (isPoolClose()) {
            timestamp = endPool;
        } else {
            timestamp = getTimestamp();
        }

        //Reward = Staked Amount * Reward Rate * TimeDiff(in Seconds) / RewardInterval
        uint256 totalReward = 0;
        uint256 count = stakeCounts[account];
        for (uint256 index = 0; index < count; index++) {
            uint256 reward = ((stakers[account][index].amount *
                REWARD_RATE *
                (timestamp - stakers[account][index].timestamp)) / 100 ) / 
                (86400 * 365); 
            totalReward = totalReward + reward;
        }

        return totalReward;
    }

    /************************* SEND FUNC *****************************/
    function unStake() external {

        require(balances[msg.sender] != 0);

        uint256 balance = balances[msg.sender];

        uint256 reward = earned(msg.sender);

        lock(balance, reward); // Lock 3 Days

        claimedReward = claimedReward + reward;

        totalSupply = totalSupply - balance;

        //Clear balance
        delete stakers[msg.sender];

        stakeCounts[msg.sender] = 0;

        balances[msg.sender] = 0;

        emit UnStakeEvent(msg.sender, getTimestamp(), balance, reward);
    }

    function unStakeNow() external {
        require(_lockedBalances[msg.sender] != 0);

        uint256 amount = _lockedBalances[msg.sender];
        uint256 reward = _lockedRewards[msg.sender];

        uint256 fee = (amount * FEE) / 10000;

        //Transfer ECIO
        ecioToken.transfer(msg.sender, amount - fee);
        ecioToken.transfer(msg.sender, reward);

        totalFee = totalFee + fee;

        _lockedBalances[msg.sender] = 0;
        _lockedRewards[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;

        emit UnStakeNowEvent(msg.sender, getTimestamp(), amount, reward, fee);
    }

    function claim() external {
        require(_releaseTime[msg.sender] != 0);
        require(_releaseTime[msg.sender] <= getTimestamp());
        require(_lockedBalances[msg.sender] != 0);

        uint256 amount = _lockedBalances[msg.sender];
        uint256 reward = _lockedRewards[msg.sender];

        //Transfer ECIO
        ecioToken.transfer(msg.sender, amount);
        ecioToken.transfer(msg.sender, reward);

        _lockedBalances[msg.sender] = 0;
        _lockedRewards[msg.sender] = 0;
        _releaseTime[msg.sender] = 0;

        emit ClaimEvent(msg.sender, getTimestamp(), amount, reward);
    }

    function stake(uint256 amount) external {

        //validate
        uint256 ecioBalance = ecioToken.balanceOf(msg.sender);
        uint256 timestamp = getTimestamp();
        require(!isPoolClose(), "Pool is closed");
        require(amount <= ecioBalance);
        require(totalSupply + amount <= MAXIMUM_STAKING);
        require(balances[msg.sender] + amount >= MINIMUM_STAKING);

        totalSupply = totalSupply + amount;
        balances[msg.sender] = balances[msg.sender] + amount;
        stakers[msg.sender].push(Stake(amount, timestamp));
        stakeCounts[msg.sender] = stakeCounts[msg.sender] + 1;
        ecioToken.transferFrom(msg.sender, address(this), amount);

        emit StakeEvent(msg.sender, timestamp, amount);
    }

    function lock(uint256 amount, uint256 reward) internal {
        _lockedBalances[msg.sender] = amount;
        _lockedRewards[msg.sender] = reward;
        _releaseTime[msg.sender] = getTimestamp() + 3 days;
    }
}