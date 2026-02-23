# X3NA Smart Contract Documentation

## Overview

X3NA is an upgradeable prediction market smart contract that allows users to bet on price movements (Bull/Bear positions). The contract implements a round-based betting system where users can place bets during an active betting period and claim rewards after round resolution.

## Contract Architecture

### Inheritance

```
X3NA
├── Initializable (upgradeable pattern)
├── AccessControlUpgradeable (role-based access)
├── PausableUpgradeable (emergency stops)
└── ReentrancyGuardUpgradeable (security)
```

### Roles

| Role                 | Description                                                |
| -------------------- | ---------------------------------------------------------- |
| `DEFAULT_ADMIN_ROLE` | Full administrative access, can modify contract parameters |
| `OPERATOR_ROLE`      | Can manage rounds (start, lock, end) and send rewards      |

---

## Data Structures

### Enums

```solidity
enum Position { Bull, Bear }
```

### Structs

#### Round

```solidity
struct Round {
    uint64 startTimestamp;    // When betting period starts
    uint64 lockTimestamp;     // When betting period ends
    uint64 closeTimestamp;    // When round results are finalized
    int256 lockPrice;         // Price at lock time
    int256 closePrice;        // Price at close time
    uint256 bullAmount;       // Total amount bet on Bull
    uint256 bearAmount;       // Total amount bet on Bear
    uint256 rewardAmount;     // Total reward pool after fees
}
```

#### BetInfo

```solidity
struct BetInfo {
    Position position;  // Bull or Bear
    uint256 amount;     // Bet amount in wei
    bool claimed;       // Whether reward has been claimed
}
```

---

## State Variables

| Variable          | Type         | Description                                            |
| ----------------- | ------------ | ------------------------------------------------------ |
| `referrals`       | `IReferrals` | Reference to referral system contract                  |
| `bufferSeconds`   | `uint64`     | Grace period for operator actions                      |
| `minBetAmount`    | `uint256`    | Minimum bet amount (wei)                               |
| `maxBetAmount`    | `uint256`    | Maximum bet amount (wei)                               |
| `feeForAutoClaim` | `uint256`    | Fixed fee deducted for auto-claim (wei)                |
| `autoClaimFeeBps` | `uint256`    | ⚠️ Declared but not used in current implementation     |
| `treasuryFeeBps`  | `uint256`    | Treasury fee percentage (basis points, e.g., 200 = 2%) |
| `treasuryAddress` | `address`    | Address receiving treasury fees                        |

### Mappings

| Mapping                  | Description                       |
| ------------------------ | --------------------------------- |
| `rounds[roundIndex]`     | Round data by index               |
| `bets[roundIndex][user]` | User's bet info for a round       |
| `roundUsers[roundIndex]` | Array of users who bet in a round |

---

## Events

| Event          | Parameters                                                    | Description                                                     |
| -------------- | ------------------------------------------------------------- | --------------------------------------------------------------- |
| `Bet`          | `sender`, `roundIndex`, `amount`, `position`                  | Emitted when a bet is placed                                    |
| `Claim`        | `sender`, `roundIndex`, `amount`, `result`                    | Emitted when reward is claimed (result: 1=win, 0=draw, -1=lose) |
| `RoundStarted` | `roundIndex`, `betsTimeSeconds`, `waitingTimeSeconds`, `data` | Emitted when a new round starts                                 |
| `RoundLocked`  | `roundIndex`, `lockPrice`                                     | Emitted when betting period ends                                |
| `RoundEnded`   | `roundIndex`, `round`                                         | Emitted when round is finalized                                 |

---

## Functions

### Public Functions (Users)

#### `bet(uint256 roundIndex, Position position)`

Place a bet on a round.

**Requirements:**

- Contract not paused
- Round is in betting period (`startTimestamp <= now < lockTimestamp`)
- Bet amount between `minBetAmount` and `maxBetAmount`
- User hasn't bet on this round yet
- Caller is not a contract (EOA only)

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `roundIndex` | `uint256` | The round to bet on |
| `position` | `Position` | Bull (0) or Bear (1) |

**Payable:** Yes (bet amount sent as `msg.value`)

---

#### `claim(uint256[] calldata roundsToClaim)`

Claim rewards for multiple completed rounds.

**Requirements:**

- Caller is not a contract
- User has unclaimed bets on the specified rounds

**Payout Logic:**

- **Win:** `(betAmount * rewardAmount) / winningPoolAmount`
- **Draw/Refund:** Full bet amount returned

---

#### `registerReferrer(address referrer)`

Register a referrer address for the caller.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `referrer` | `address` | Referrer's wallet address |

---

### Operator Functions

#### `startRound(uint256 roundIndex, uint64 betsTimeSeconds, uint64 waitingTimeSeconds, bytes calldata data)`

Start a new betting round.

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `roundIndex` | `uint256` | Unique round identifier |
| `betsTimeSeconds` | `uint64` | Duration of betting period |
| `waitingTimeSeconds` | `uint64` | Duration between lock and close |
| `data` | `bytes` | Additional round metadata |

**Timeline:**

```
startTimestamp ──────────────────► lockTimestamp ──────────────────► closeTimestamp
                  [Betting Period]                  [Waiting Period]
```

---

#### `lockRound(uint256 roundIndex, int256 lockPrice)`

Lock the round and record the lock price.

**Requirements:**

- Round has started
- Not already locked
- Within valid time window (`lockTimestamp` to `lockTimestamp + bufferSeconds`)

---

#### `endRound(uint256 roundIndex, int256 closePrice)`

End the round and calculate rewards.

**Requirements:**

- Round is locked
- Not already ended
- Within valid time window (`closeTimestamp` to `closeTimestamp + bufferSeconds`)

**Reward Calculation:**

```
totalAmount = bullAmount + bearAmount
treasuryAmount = totalAmount * treasuryFeeBps / 10000
rewardAmount = totalAmount - treasuryAmount
```

---

#### `sendRewards(uint256 roundIndex, uint256 from, uint256 to)`

Automatically send rewards to users (paginated).

**Parameters:**
| Name | Type | Description |
|------|------|-------------|
| `roundIndex` | `uint256` | Round to process |
| `from` | `uint256` | Start index in users array |
| `to` | `uint256` | End index in users array |

**Auto-Claim Fee:**
A fixed `feeForAutoClaim` is deducted from each reward before sending.

---

#### `endRoundAndSendRewards(uint256 roundIndex, int256 closePrice, uint256 from, uint256 to)`

Combines `endRound` and `sendRewards` in a single transaction.

---

### Admin Functions

| Function | Description |
| -------- | ----------- |

| `setPause(bool isPause)` | Pause/unpause the contract |
| `setBufferSeconds(uint64)` | Set the buffer time for operator actions |
| `setMinMaxBetAmounts(uint256, uint256)` | Set min/max bet limits |
| `setFeeForAutoClaim(uint256)` | Set fixed auto-claim fee |
| `setAutoClaimFeeBps(uint256)` | Set percentage auto-claim fee (max 10%) |
| `setTreasuryFee(uint256)` | Set treasury fee percentage |
| `setTreasuryAddress(address)` | Set treasury wallet address |
| `adminWithdraw(address, uint256)` | Emergency withdrawal |

> ⚠️ **Note:** Most admin functions require the contract to be paused.

---

## Round Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              ROUND LIFECYCLE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. START ROUND                                                             │
│     └─► Operator calls startRound()                                         │
│         └─► Users can place bets                                            │
│                                                                             │
│  2. LOCK ROUND                                                              │
│     └─► Operator calls lockRound() with lockPrice                           │
│         └─► No more bets accepted                                           │
│                                                                             │
│  3. END ROUND                                                               │
│     └─► Operator calls endRound() with closePrice                           │
│         └─► Rewards calculated, treasury fee sent                           │
│                                                                             │
│  4. CLAIM/DISTRIBUTE                                                        │
│     └─► Users call claim() OR                                               │
│     └─► Operator calls sendRewards()                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Winning Logic

| Condition                 | Result                          |
| ------------------------- | ------------------------------- |
| `closePrice > lockPrice`  | **Bull wins**                   |
| `closePrice < lockPrice`  | **Bear wins**                   |
| `closePrice == lockPrice` | **Draw** (all bets refunded)    |
| Round not ended in time   | **Invalid** (all bets refunded) |

---

## Security Features

1. **ReentrancyGuard** - Prevents reentrancy attacks on claim functions
2. **Pausable** - Emergency stop mechanism
3. **Access Control** - Role-based permissions
4. **notContract Modifier** - Blocks smart contract interactions (EOA only)
5. **Buffer Time** - Grace period prevents timing exploits
6. **Safe Native Transfer** - Proper error handling for ETH transfers

---

## Fee Structure

### Treasury Fee

- Applied to total pool on round end
- Configurable via `treasuryFeeBps` (basis points)
- Example: 500 = 5%

### Auto-Claim Fee

- **Fixed fee** (`feeForAutoClaim`) deducted when operator sends rewards automatically via `sendRewards()`
- Only charged if `reward > feeForAutoClaim`
- Users claiming manually via `claim()` do NOT pay this fee

> 💡 **Note:** The contract also declares `autoClaimFeeBps` (percentage-based fee), but it's not currently used in the implementation. Only the fixed `feeForAutoClaim` is active.

---

## Integration with Referrals

The contract integrates with an external `IReferrals` contract:

- `registerUser()` - Called when user registers referrer
- `incrementBetsAmount()` - Called on each bet to track turnover

---

## Initialization Parameters

```solidity
function initialize(
    IReferrals _referrals,      // Referral contract address
    uint64 _bufferSeconds,       // Buffer time (e.g., 30)
    uint256 _minBetAmount,       // Min bet (e.g., 0.001 ETH)
    uint256 _maxBetAmount,       // Max bet (e.g., 10 ETH)
    uint256 _feeForAutoClaim,    // Auto-claim fee (e.g., 0.0000143 ETH)
    uint256 _treasuryFee,        // Treasury fee bps (e.g., 500)
    address _treasuryAddress,    // Treasury wallet
    address _operatorAddress     // Operator address
)
```

---

## Gas Optimization Notes

- `sendRewards` is paginated to avoid gas limits
- Use `endRoundAndSendRewards` for fewer transactions
- Batch claiming multiple rounds in single `claim()` call
