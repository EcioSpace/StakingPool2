// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

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

contract ECIOWhiteListSilver is Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _userStakeCount;
    Counters.Counter private _userUnstakeCount;

    /** 10,000,000 ECIO **/
    uint256 public constant TOTAL_ECIO_PER_POOL = 10000000000000000000000000;

    /** 10,000,000 ECIO **/
    uint256 public constant MAXIMUM_STAKING = 10000000000000000000000000;

    /**  150,000 ECIO **/
    uint256 public constant MINIMUM_STAKING = 150000000000000000000000;

    /** Token lock time after unstaked*/
    uint256 public constant WITHDRAW_LOCK_DAY = 45;

    //**************** LIMIT USER FOR THIS POOL *******************/
    uint256 public constant LIMIT_USER = 300 - 1;

    /** Reward Rate 40% */
    uint256 public constant REWARD_RATE = 40;

    uint256 public endPool;

    constructor() {}

    struct Stake {
        uint256 amount;
        uint256 timestamp;
        bool isClaimed;
    }

    mapping(address => Stake) public stakers;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public stakeCounts;
    mapping(address => uint256) private _releaseTime;
    mapping(uint256 => address) private _stakerAddresses;

    /** Total reward are claimed */
    uint256 public claimedReward = 0;

    /** Total supply of the pool */
    uint256 public totalSupply;

    // uint256 private mockupTimestamp;

    IERC20 ecioToken;

    /************************* EVENTS *****************************/
    event StakeEvent(
        address indexed account,
        uint256 indexed timestamp,
        uint256 amount,
        uint256 indexed _userStakeCount
    );
    event UnStakeEvent(
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
        // if (_lockedBalances[_account] != 0) {
        //     return "WAITING";
        // }

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
        return balances[_account];
    }

    function earned(address account) public view returns (uint256) {
        uint256 timestamp = getTimestamp();

        //Reward = Staked Amount * Reward Rate * TimeDiff(in Seconds) / RewardInterval
        uint256 reward = ((stakers[account].amount *
            REWARD_RATE *
            (timestamp - stakers[account].timestamp)) / 100) / (86400 * 365);
        return reward;
    }

    function getUserCount() public view returns (uint256) {
        uint256 userCount = _userStakeCount.current() -
            _userUnstakeCount.current();
        return userCount;
    }

    function checkDuplicateUser(address account) public view returns (bool) {
        uint256 userCount = _userStakeCount.current();
        for (uint256 i = 0; i < userCount; i++) {
            if (account != _stakerAddresses[i]) {
                return true;
            }
        }
        return false;
    }

    /************************* SEND FUNC *****************************/
    function unStake() external {
        require(balances[msg.sender] != 0);
        require(_releaseTime[msg.sender] != 0);
        require(getTimestamp() >= _releaseTime[msg.sender]);
        require(stakers[msg.sender].isClaimed == false);

        uint256 balance = balances[msg.sender];
        uint256 reward = earned(msg.sender);

        totalSupply = totalSupply - balance;
        claimedReward = claimedReward + reward;

        //decrease
        _userUnstakeCount.increment();

        //Transfer ECIO
        ecioToken.transfer(msg.sender, balance);
        ecioToken.transfer(msg.sender, reward);

        //Clear balance
        delete stakers[msg.sender];


        _releaseTime[msg.sender] = 0;
        balances[msg.sender] = 0;

        emit UnStakeEvent(msg.sender, getTimestamp(), balance, reward);
    }

    function stake(uint256 amount) external {
        //validate
        uint256 ecioBalance = ecioToken.balanceOf(msg.sender);
        uint256 timestamp = getTimestamp();
        uint256 userStakeCount = getUserCount();
        bool checkDup = checkDuplicateUser(msg.sender);
        
        require(amount <= ecioBalance, "Staking: your amount is not enough");
        require(totalSupply + amount <= MAXIMUM_STAKING, "Staking: Staking amount has reached its limit.");
        require(balances[msg.sender] + amount >= MINIMUM_STAKING, "Staking: Your amount has not reached minimum.");
        require(userStakeCount <= LIMIT_USER, "Staking: Your amount has not reached minimum.");
        require(checkDup = true, "Staking: You can't stake more than once");

        // add address to mapping
        uint256 currentUserId = _userStakeCount.current();
        _stakerAddresses[currentUserId] = msg.sender;

        totalSupply = totalSupply + amount;
        balances[msg.sender] = balances[msg.sender] + amount;
        stakers[msg.sender] = (Stake(amount, timestamp, false));
        ecioToken.transferFrom(msg.sender, address(this), amount);
        lock(msg.sender);
        _userStakeCount.increment();

        emit StakeEvent(msg.sender, timestamp, amount, getUserCount());
    }

    function lock(address account) internal {
        _releaseTime[account] = getTimestamp() + 5 minutes;
    }
}
