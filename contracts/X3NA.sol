// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/// @title IReferrals Interface
/// @notice Interface for the referral system contract
interface IReferrals {
    function registerUser(address user, address referrer) external;
    function incrementBetsAmount(address causer, uint256 amount) external;
    function doRewards(address user, uint256 amount) external;
    function getReferralStats(address user) external view returns (
        address referrer,
        uint256 totalRewards,
        uint256 claimedAmount,
        uint256 claimableAmount,
        uint256 turnover,
        uint64 currentRankBps,
        string memory rankName
    );
}

/// @title X3NA Prediction Market
/// @author X3NA Team
/// @notice A decentralized prediction market for price movements
/// @dev Upgradeable contract using OpenZeppelin's proxy pattern
contract X3NA is Initializable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    /// @notice Role identifier for operators who can manage rounds
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Reference to the referral system contract
    IReferrals public referrals;

    /// @notice Grace period in seconds for operator actions after timestamps
    uint64 public bufferSeconds;

    /// @notice Minimum allowed bet amount in wei
    uint256 public minBetAmount;

    /// @notice Maximum allowed bet amount in wei
    uint256 public maxBetAmount;

    /// @notice Fixed fee deducted for automatic reward distribution in wei
    uint256 public feeForAutoClaim;

    /// @notice Treasury fee in basis points (e.g., 500 = 5%)
    uint256 public treasuryFeeBps;

    /// @notice Address that receives treasury fees
    address public treasuryAddress;

    /// @notice Mapping of round index to round data
    mapping(uint256 => Round) public rounds;

    /// @notice Mapping of round index to user address to bet info
    mapping(uint256 => mapping(address => BetInfo)) public bets;

    /// @notice Mapping of round index to array of participating users
    mapping(uint256 => address[]) public roundUsers;
    
    /// @notice Auto claim fee in basis points (currently unused)
    uint256 public autoClaimFeeBps;

    /// @notice Bet position type
    enum Position {Bull, Bear}

    /// @notice Round data structure
    /// @param startTimestamp When the betting period starts
    /// @param lockTimestamp When the betting period ends
    /// @param closeTimestamp When the round results are finalized
    /// @param lockPrice Asset price at lock time
    /// @param closePrice Asset price at close time
    /// @param bullAmount Total amount bet on Bull position
    /// @param bearAmount Total amount bet on Bear position
    /// @param rewardAmount Total reward pool after treasury fee
    struct Round {
        uint64 startTimestamp;
        uint64 lockTimestamp;
        uint64 closeTimestamp;
        int256 lockPrice;
        int256 closePrice;
        uint256 bullAmount;
        uint256 bearAmount;
        uint256 rewardAmount;
    }

    /// @notice User bet information
    /// @param position User's chosen position (Bull or Bear)
    /// @param amount Bet amount in wei
    /// @param claimed Whether the reward has been claimed
    struct BetInfo {
        Position position;
        uint256 amount;
        bool claimed;
    }

    /// @notice Emitted when a user places a bet
    /// @param sender Address of the bettor
    /// @param roundIndex Index of the round
    /// @param amount Bet amount in wei
    /// @param position Chosen position (Bull or Bear)
    event Bet(address indexed sender, uint256 indexed roundIndex, uint256 amount, Position position);

    /// @notice Emitted when a user claims rewards
    /// @param sender Address of the claimer
    /// @param roundIndex Index of the round
    /// @param amount Claimed amount in wei
    /// @param result Outcome: 1=win, 0=draw/refund, -1=lose
    event Claim(address indexed sender, uint256 indexed roundIndex, uint256 amount, int8 result);

    /// @notice Emitted when a new round starts
    /// @param roundIndex Index of the round
    /// @param betsTimeSeconds Duration of betting period
    /// @param waitingTimeSeconds Duration of waiting period after lock
    /// @param data Additional round metadata
    event RoundStarted(uint256 indexed roundIndex, uint64 betsTimeSeconds, uint64 waitingTimeSeconds, bytes data);

    /// @notice Emitted when a round is locked
    /// @param roundIndex Index of the round
    /// @param lockPrice Price at lock time
    event RoundLocked(uint256 indexed roundIndex, int256 lockPrice);

    /// @notice Emitted when a round ends
    /// @param roundIndex Index of the round
    /// @param round Final round data
    event RoundEnded(uint256 indexed roundIndex, Round round);

    /// @notice Initializes the contract with configuration parameters
    /// @param _referrals Address of the referral contract
    /// @param _bufferSeconds Grace period for operator actions
    /// @param _minBetAmount Minimum bet amount
    /// @param _maxBetAmount Maximum bet amount
    /// @param _feeForAutoClaim Fee for automatic claims
    /// @param _treasuryFee Treasury fee in basis points
    /// @param _treasuryAddress Address to receive treasury fees
    /// @param _operatorAddress Address to grant operator role
    function initialize(
        IReferrals _referrals,
        uint64 _bufferSeconds,
        uint256 _minBetAmount,
        uint256 _maxBetAmount,
        uint256 _feeForAutoClaim,
        uint256 _treasuryFee,
        address _treasuryAddress,
        address _operatorAddress
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        referrals = _referrals;
        bufferSeconds = _bufferSeconds;
        minBetAmount = _minBetAmount;
        maxBetAmount = _maxBetAmount;
        feeForAutoClaim = _feeForAutoClaim;
        treasuryFeeBps = _treasuryFee;
        treasuryAddress = _treasuryAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, _operatorAddress);
    }

    /// @notice Place a bet on price direction
    /// @param roundIndex Index of the round to bet on
    /// @param position Bull (price up) or Bear (price down)
    /// @dev Bet amount is msg.value. One bet per user per round.
    function bet(uint256 roundIndex, Position position) external payable whenNotPaused nonReentrant {
        Round storage round = rounds[roundIndex];

        require(round.startTimestamp != 0 && round.startTimestamp <= _timeNow() && _timeNow() < round.lockTimestamp, "Round not bettable");
        require(msg.value >= minBetAmount, "Bet amount < minBetAmount");
        require(msg.value <= maxBetAmount, "Bet amount > maxBetAmount");
        require(bets[roundIndex][msg.sender].amount == 0, "Can only bet once per round");

        uint256 amount = msg.value;
        referrals.incrementBetsAmount(msg.sender, amount);

        if (position == Position.Bull)
            round.bullAmount += amount;
        else
            round.bearAmount += amount;

        bets[roundIndex][msg.sender] = BetInfo({
            position: position,
            amount: amount,
            claimed: false
        });
        roundUsers[roundIndex].push(msg.sender);

        emit Bet(msg.sender, roundIndex, amount, position);
    }

    /// @notice Register a referrer for the caller
    /// @param referrer Address of the referrer
    function registerReferrer(address referrer) external {
        referrals.registerUser(msg.sender, referrer);
    }

    /// @notice Claim rewards for multiple completed rounds
    /// @param roundsToClaim Array of round indices to claim
    /// @dev Winners receive proportional share of reward pool. Draw results in refund.
    function claim(uint256[] calldata roundsToClaim) external nonReentrant {
        address userAddress = msg.sender;
        uint256 rewards;

        for (uint256 i = 0; i < roundsToClaim.length; i++) {
            uint256 roundIndex = roundsToClaim[i];
            BetInfo memory betInfo = bets[roundIndex][userAddress];

            if (betInfo.amount == 0 || betInfo.claimed)
                return revert("no bet or already claimed");

            Round memory round = rounds[roundIndex];
            (bool refundable, Position winPosition) = _getRoundResult(round);

            int8 status;
            if (!refundable)
                status = (betInfo.position == winPosition) ? int8(1) : -1;
            uint256 reward_;

            if (status == 0) {
                reward_ = betInfo.amount;
            } else if (status == 1) {
                uint256 rewardBaseCalAmount = (winPosition == Position.Bull) ? round.bullAmount : round.bearAmount;
                reward_ = (betInfo.amount * round.rewardAmount) / rewardBaseCalAmount;
            }

            bets[roundIndex][userAddress].claimed = true;
            emit Claim(userAddress, roundIndex, reward_, status);

            rewards += reward_;
        }

        _payOut(userAddress, rewards);
    }

    /// @notice Automatically distribute rewards to users (operator only)
    /// @param roundIndex Index of the round
    /// @param from Starting index in user array
    /// @param to Ending index in user array (exclusive)
    /// @dev Deducts feeForAutoClaim from each reward
    function sendRewards(uint256 roundIndex, uint256 from, uint256 to) public whenNotPaused onlyRole(OPERATOR_ROLE) {
        Round memory round = rounds[roundIndex];
        (bool refundable, Position winPosition) = _getRoundResult(round);
        uint256 rewardBaseCalAmount = (winPosition == Position.Bull) ? round.bullAmount : round.bearAmount;

        if (to > roundUsers[roundIndex].length) to = roundUsers[roundIndex].length;
        for (uint256 i = from; i < to; i++) {

            address userAddress = roundUsers[roundIndex][i];
            BetInfo memory betInfo = bets[roundIndex][userAddress];
            if (betInfo.amount == 0 || betInfo.claimed) continue;

            int8 status;
            if (!refundable)
                status = (betInfo.position == winPosition) ? int8(1) : -1;
            uint256 reward_;

            if (status == 0) {
                reward_ = betInfo.amount;
            } else if (status == 1) {
                reward_ = (betInfo.amount * round.rewardAmount) / rewardBaseCalAmount;
            }

            if (reward_ > feeForAutoClaim) {
                reward_ -= feeForAutoClaim;
            }

            bets[roundIndex][userAddress].claimed = true;
            emit Claim(userAddress, roundIndex, reward_, status);

            if (reward_ > 0) {
                _payOut(userAddress, reward_);
            }
        }
    }

    /// @notice Start a new betting round (operator only)
    /// @param roundIndex Unique index for the round
    /// @param betsTimeSeconds Duration users can place bets
    /// @param waitingTimeSeconds Duration after lock before close
    /// @param data Additional metadata (e.g., asset symbol)
    function startRound(uint256 roundIndex, uint64 betsTimeSeconds, uint64 waitingTimeSeconds, bytes calldata data) public whenNotPaused onlyRole(OPERATOR_ROLE) {
        require(rounds[roundIndex].startTimestamp == 0, "Round already exists");

        rounds[roundIndex] = Round({
            startTimestamp: _timeNow(),
            lockTimestamp: _timeNow() + betsTimeSeconds,
            closeTimestamp: _timeNow() + betsTimeSeconds + waitingTimeSeconds,
            bullAmount: 0,
            bearAmount: 0,
            lockPrice: 0,
            closePrice: 0,
            rewardAmount: 0
        });

        emit RoundStarted(roundIndex, betsTimeSeconds, waitingTimeSeconds, data);
    }

    /// @notice Lock a round and record the lock price (operator only)
    /// @param roundIndex Index of the round to lock
    /// @param lockPrice Asset price at lock time
    /// @dev Must be called within bufferSeconds after lockTimestamp
    function lockRound(uint256 roundIndex, int256 lockPrice) public whenNotPaused onlyRole(OPERATOR_ROLE) {
        Round storage round = rounds[roundIndex];

        require(round.startTimestamp != 0, "Round not started");
        require(round.lockPrice == 0, "Round already locked");
        require(_timeNow() >= round.lockTimestamp, "Too early to lock");
        require(_timeNow() <= round.lockTimestamp + bufferSeconds, "Too late to lock");

        round.lockPrice = lockPrice;

        emit RoundLocked(roundIndex, lockPrice);
    }

    /// @notice End a round and calculate rewards (operator only)
    /// @param roundIndex Index of the round to end
    /// @param closePrice Asset price at close time
    /// @dev Treasury fee is deducted and sent. If prices equal, round is refundable.
    function endRound(uint256 roundIndex, int256 closePrice) public whenNotPaused onlyRole(OPERATOR_ROLE) {
        Round storage round = rounds[roundIndex];

        require(round.lockTimestamp != 0, "Round not locked");
        require(round.closePrice == 0, "Round already ended");
        require(_timeNow() >= round.closeTimestamp, "Too early to end");
        require(_timeNow() <= round.closeTimestamp + bufferSeconds, "Too late to end");

        round.closePrice = closePrice;

        if (closePrice == round.lockPrice) {
            // Draw: all bets refundable, no treasury fee
        } else {
            uint256 totalAmount = round.bullAmount + round.bearAmount;
            uint256 treasuryAmt = totalAmount * treasuryFeeBps / 10_000;
            uint256 rewardAmount = totalAmount - treasuryAmt;

            round.rewardAmount = rewardAmount;

            if (treasuryAmt != 0)
                _safeTransferNative(treasuryAddress, treasuryAmt);
        }

        emit RoundEnded(roundIndex, round);
    }

    /// @notice End round and distribute rewards in one transaction (operator only)
    /// @param roundIndex Index of the round
    /// @param closePrice Asset price at close time
    /// @param from Starting index for reward distribution
    /// @param to Ending index (0 = all users)
    function endRoundAndSendRewards(uint256 roundIndex, int256 closePrice, uint256 from, uint256 to) public whenNotPaused onlyRole(OPERATOR_ROLE) {
        if (to == 0) to = roundUsers[roundIndex].length;

        endRound(roundIndex, closePrice);
        sendRewards(roundIndex, from, to);
    }

    /// @notice Set contract pause state (admin only)
    /// @param isPause True to pause, false to unpause
    function setPause(bool isPause) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (isPause) _pause();
        else _unpause();
    }

    /// @notice Update buffer seconds parameter (admin only, when paused)
    /// @param _bufferSeconds New buffer duration in seconds
    function setBufferSeconds(uint64 _bufferSeconds) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        bufferSeconds = _bufferSeconds;
    }

    /// @notice Update min and max bet amounts (admin only, when paused)
    /// @param _minBetAmount New minimum bet amount in wei
    /// @param _maxBetAmount New maximum bet amount in wei
    function setMinMaxBetAmounts(uint256 _minBetAmount, uint256 _maxBetAmount) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        minBetAmount = _minBetAmount;
        maxBetAmount = _maxBetAmount;
    }

    /// @notice Update auto-claim fee (admin only, when paused)
    /// @param _feeForAutoClaim New fee amount in wei
    function setFeeForAutoClaim(uint256 _feeForAutoClaim) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        feeForAutoClaim = _feeForAutoClaim;
    }

    /// @notice Update auto-claim fee in basis points (admin only, when paused)
    /// @param _autoClaimFeeBps New fee in basis points (max 1000 = 10%)
    function setAutoClaimFeeBps(uint256 _autoClaimFeeBps) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_autoClaimFeeBps <= 1000, "Auto claim fee too high");
        autoClaimFeeBps = _autoClaimFeeBps;
    }

    /// @notice Update treasury fee (admin only, when paused)
    /// @param _treasuryFee New fee in basis points (max 10000 = 100%)
    function setTreasuryFee(uint256 _treasuryFee) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasuryFee <= 10000, "Treasury fee too high");
        treasuryFeeBps = _treasuryFee;
    }

    /// @notice Update treasury address (admin only, when paused)
    /// @param _treasuryAddress New treasury address
    function setTreasuryAddress(address _treasuryAddress) external whenPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasuryAddress != address(0), "Invalid treasury address");
        treasuryAddress = _treasuryAddress;
    }

    /// @notice Pause the contract (admin only)
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpause the contract (admin only)
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Withdraw funds from contract (admin only)
    /// @param to Recipient address
    /// @param amount Amount to withdraw in wei
    function adminWithdraw(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Invalid address");
        _safeTransferNative(to, amount);
    }

    /// @dev Internal function to send rewards to user
    function _payOut(address to, uint256 amount) internal {
        if (amount > 0) {
            _safeTransferNative(to, amount);
        }
    }

    /// @dev Determine round result and winning position
    /// @return isRefundable True if round should be refunded (draw or invalid)
    /// @return winPosition Winning position (Bull or Bear)
    function _getRoundResult(Round memory round) internal view returns (bool isRefundable, Position winPosition) {
        require(round.startTimestamp != 0, "Round has not started");
        require(_timeNow() > round.closeTimestamp, "Round has not ended");

        if (_timeNow() > round.closeTimestamp + bufferSeconds && round.closePrice == 0)
            return (true, Position.Bull);

        if (round.closePrice > round.lockPrice) return (false, Position.Bull);
        if (round.closePrice < round.lockPrice) return (false, Position.Bear);
        if (round.closePrice == round.lockPrice) return (true, Position.Bull);
        revert();
    }

    /// @dev Safely transfer native token (ETH)
    function _safeTransferNative(address to, uint256 value) internal {
        (bool success,) = to.call{value: value}("");
        require(success, "NATIVE_TRANSFER_FAILED");
    }

    /// @dev Get current block timestamp
    function _timeNow() internal view virtual returns (uint64) {
        return uint64(block.timestamp);
    }
}
