// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title X3NA Referral System
/// @author X3NA Team
/// @notice Multi-tier referral program with volume-based commission rates
/// @dev Upgradeable contract using OpenZeppelin's proxy pattern
contract Referrals is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    /// @notice Role identifier for operators (X3NA contract)
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Mapping of user address to registration timestamp
    mapping(address => uint64) public registrationTimestamps;

    /// @notice Mapping of user address to their referrer
    mapping(address => address) public referrers;

    /// @notice Mapping of referrer address to total rewards earned
    mapping(address => uint256) public rewards;

    /// @notice Mapping of referrer address to claimed rewards amount
    mapping(address => uint256) public claimedRewards;

    /// @notice Mapping of referrer address to total bet volume from referrals
    mapping(address => uint256) public referralsBetsAmount;

    /// @notice Mapping of user address to custom commission rate in basis points
    mapping(address => uint64) public customCommissions;

    /// @notice Emitted when a user registers with a referrer
    event RegisterUser(address indexed user, address indexed referrer);

    /// @notice Emitted when referral rewards are updated
    event UpdateRewards(address indexed user, uint256 amount, address from);

    /// @notice Emitted when a user claims their rewards
    event ClaimRewards(address indexed user, uint256 amount);

    /// @notice Emitted when admin sets custom commission for a user
    event SetCustomCommission(address indexed user, uint64 bps);

    /// @notice Emitted when admin removes custom commission from a user
    event RemoveCustomCommission(address indexed user);

    /// @notice Initialize the contract
    /// @dev Sets up access control and grants admin role to deployer
    function initialize() public initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Register caller with a referrer
    /// @param referrer Address of the referrer
    function register(address referrer) external {
        _registerUser(msg.sender, referrer);
    }

    /// @notice Claim all available referral rewards
    /// @dev Transfers claimable amount to caller
    function claimRewards() public {
        uint256 claimable = rewards[msg.sender] - claimedRewards[msg.sender];
        require(claimable > 0, "No rewards to claim");

        claimedRewards[msg.sender] += claimable;

        _safeTransferNative(msg.sender, claimable);
        emit ClaimRewards(msg.sender, claimable);
    }

    /// @notice Get unclaimed reward amount for a user
    /// @param user Address to check
    /// @return Claimable amount in wei
    function getClaimableRewards(address user) external view returns (uint256) {
        return rewards[user] - claimedRewards[user];
    }

    /// @notice Get user's current rank and commission rate
    /// @param user Address to check
    /// @return bps Commission rate in basis points
    /// @return rankName Name of the rank tier
    /// @dev Ranks: Starter (20%), Bronze (25%), Silver (30%), Gold (35%), Platinum (40%), Ambassador (50%)
    function getUserRank(address user) external view returns (uint64 bps, string memory rankName) {
        bps = _getUserRewardsBps(user);
        
        if (customCommissions[user] > 0) {
            return (bps, "Custom");
        }
        
        if (bps == 2000) return (bps, "Starter");    
        if (bps == 2500) return (bps, "Bronze");     
        if (bps == 3000) return (bps, "Silver");     
        if (bps == 3500) return (bps, "Gold");       
        if (bps == 4000) return (bps, "Platinum");   
        return (bps, "Ambassador");                         
    }

    /// @notice Get comprehensive referral statistics for a user
    /// @param user Address to check
    /// @return referrer User's referrer address
    /// @return totalRewards Total rewards earned
    /// @return claimedAmount Amount already claimed
    /// @return claimableAmount Amount available to claim
    /// @return turnover Total bet volume from referrals
    /// @return currentRankBps Current commission rate in basis points
    /// @return rankName Current rank name
    function getReferralStats(address user) external view returns (
        address referrer,
        uint256 totalRewards,
        uint256 claimedAmount,
        uint256 claimableAmount,
        uint256 turnover,
        uint64 currentRankBps,
        string memory rankName
    ) {
        referrer = referrers[user];
        totalRewards = rewards[user];
        claimedAmount = claimedRewards[user];
        claimableAmount = totalRewards - claimedAmount;
        turnover = referralsBetsAmount[user];
        (currentRankBps, rankName) = this.getUserRank(user);
    }

    /// @notice Set custom commission rate for a user (admin only)
    /// @param user Address to set commission for
    /// @param bps Commission rate in basis points (1-10000)
    function addCustomCommission(address user, uint64 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(user != address(0), "Invalid user address");
        require(bps > 0 && bps <= 10000, "BPS must be between 1 and 10000");
        
        customCommissions[user] = bps;
        emit SetCustomCommission(user, bps);
    }

    /// @notice Remove custom commission from a user (admin only)
    /// @param user Address to remove commission from
    function removeCustomCommission(address user) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(user != address(0), "Invalid user address");
        require(customCommissions[user] > 0, "No custom commission set");
        
        delete customCommissions[user];
        emit RemoveCustomCommission(user);
    }

    /// @notice Reset turnover counter for a user (admin only)
    /// @param user Address to reset
    function resetTurnover(address user) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(user != address(0), "Invalid user address");
        referralsBetsAmount[user] = 0;
    }

    /// @notice Remove referrer link for a user (admin only)
    /// @param user Address to unlink
    function removeReferrer(address user) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(user != address(0), "Invalid user address");
        require(referrers[user] != address(0), "User has no referrer");
        
        delete referrers[user];
        delete registrationTimestamps[user];
    }

    /// @notice Check if user has custom commission
    /// @param user Address to check
    /// @return True if custom commission is set
    function hasCustomCommission(address user) external view returns (bool) {
        return customCommissions[user] > 0;
    }

    /// @notice Register a user with referrer (operator only)
    /// @param user Address of the user to register
    /// @param referrer Address of the referrer
    function registerUser(address user, address referrer) external onlyRole(OPERATOR_ROLE) {
        _registerUser(user, referrer);
    }

    /// @notice Increment bet amount for referrer tracking (operator only)
    /// @param causer Address of the user who placed the bet
    /// @param amount Bet amount in wei
    function incrementBetsAmount(address causer, uint256 amount) external nonReentrant onlyRole(OPERATOR_ROLE) {
        require(causer != address(0), "Invalid user address");
        require(amount > 0, "Amount must be greater than zero");

        address referrer = referrers[causer];
        if (referrer == address(0)) return;

        referralsBetsAmount[referrer] += amount;
    }

    /// @notice Distribute referral rewards (operator only)
    /// @param causer Address of the user whose action triggered rewards
    /// @param amount Base amount to calculate rewards from
    /// @dev Requires msg.value to cover the reward amount
    function doRewards(address causer, uint256 amount) external payable nonReentrant onlyRole(OPERATOR_ROLE) {
        require(causer != address(0), "Invalid user address");
        require(amount > 0, "Amount must be greater than zero");

        address referrer = referrers[causer];
        if (referrer == address(0)) return;

        uint rewardsBps = _getUserRewardsBps(referrer);
        uint256 reward = amount * rewardsBps / 10_000;
        
        require(msg.value >= reward, "Insufficient ETH sent for reward");
        
        rewards[referrer] += reward;

        emit UpdateRewards(referrer, reward, causer);
        
        if (msg.value > reward) {
            _safeTransferNative(msg.sender, msg.value - reward);
        }
    }

    /// @dev Calculate commission rate based on turnover volume
    /// @param referrer Address to calculate rate for
    /// @return Commission rate in basis points
    /// @dev Tier thresholds (ETH): 0.303, 1.515, 6.06, 15.15, 30.30, 151.52
    function _getUserRewardsBps(address referrer) internal view returns (uint64) {
        uint64 customBps = customCommissions[referrer];
        if (customBps > 0) {
            return customBps;
        }
        
        uint256 amount = referralsBetsAmount[referrer];
        
        if (amount < 0.303 ether) return 2000;      // Starter: 20%
        if (amount < 1.515 ether) return 2500;      // Bronze: 25%
        if (amount < 6.06 ether) return 3000;       // Silver: 30%
        if (amount < 15.15 ether) return 3500;      // Gold: 35%
        if (amount < 30.30 ether) return 4000;      // Platinum: 40%
        if (amount < 151.52 ether) return 5000;     // Ambassador: 50%
        return 5000;
    }

    /// @dev Internal function to register user with referrer
    function _registerUser(address user, address referrer) internal {
        require(user != address(0), "Invalid user address");
        require(referrer != address(0), "Invalid referrer address");

        require(registrationTimestamps[user] == 0, "User already registered");
        require(user != referrer, "User cannot refer themselves");

        registrationTimestamps[user] = uint64(block.timestamp);
        referrers[user] = referrer;
        emit RegisterUser(user, referrer);
    }

    /// @dev Safely transfer native token (ETH)
    function _safeTransferNative(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}("");
        require(success, "NATIVE_TRANSFER_FAILED");
    }

    /// @notice Fund the contract with ETH (admin only)
    /// @dev Used to provide liquidity for reward payouts
    function fundContract() external payable onlyRole(DEFAULT_ADMIN_ROLE) {
    }

    /// @notice Accept ETH transfers
    receive() external payable {
    }

    /// @notice Withdraw funds from contract (admin only)
    /// @param to Recipient address
    /// @param amount Amount to withdraw in wei
    function adminWithdraw(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid user address");
        _safeTransferNative(to, amount);
    }
}
