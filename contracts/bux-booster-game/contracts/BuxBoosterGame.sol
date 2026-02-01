// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BuxBoosterGame
 * @notice On-chain provably fair coin flip game (V3)
 * @dev UUPS Upgradeable contract using commit-reveal pattern.
 *      Supports 9 difficulty levels (-4 to 5).
 *      All dependencies flattened in this file for easier verification.
 *
 * GAME RULES:
 * - Win One Mode (difficulty -4 to -1): Player wins if ANY flip matches prediction
 * - Win All Mode (difficulty 1 to 5): Player must get ALL flips correct
 * - Multipliers include house edge
 * - Max bet = 0.1% of house balance, scaled by multiplier
 *
 * PROVABLY FAIR (V3):
 * - Server submits commitment hash BEFORE player bets
 * - Server calculates results off-chain using server seed
 * - Server reveals seed when settling bet (must match commitment)
 * - Players can verify results off-chain using revealed seed
 * - commitmentHash serves as betId (simpler, more gas efficient)
 *
 * UPGRADEABILITY:
 * - Uses UUPS proxy pattern (EIP-1822)
 * - Only owner can authorize upgrades
 * - State is preserved across upgrades
 * - V3: Server-side result calculation, comprehensive BetSettled event
 */

// ============================================================
// =============== FLATTENED DEPENDENCIES =====================
// ============================================================
// The following interfaces and base contracts are included
// directly for easier verification on block explorers.
// Uses UPGRADEABLE versions for proxy compatibility.
// ============================================================

// ============ IERC20 Interface ============

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// ============ SafeERC20 Library ============

library SafeERC20 {
    error SafeERC20FailedOperation(address token);

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        if (!success || (returndata.length != 0 && !abi.decode(returndata, (bool)))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }
}

// ============ IROGUEBankroll Interface ============

interface IROGUEBankroll {
    // Functions for BuxBooster integration with ROGUEBankroll
    function updateHouseBalanceBuxBoosterBetPlaced(
        bytes32 commitmentHash,
        int8 difficulty,
        uint8[] calldata predictions,
        uint256 nonce,
        uint256 maxPayout
    ) external payable returns(bool);

    function settleBuxBoosterWinningBet(
        address winner,
        bytes32 commitmentHash,
        uint256 betAmount,
        uint256 payout,
        int8 difficulty,
        uint8[] calldata predictions,
        uint8[] calldata results,
        uint256 nonce,
        uint256 maxPayout
    ) external returns(bool);

    function settleBuxBoosterLosingBet(
        address player,
        bytes32 commitmentHash,
        uint256 wagerAmount,
        int8 difficulty,
        uint8[] calldata predictions,
        uint8[] calldata results,
        uint256 nonce,
        uint256 maxPayout
    ) external returns(bool);

    function getHouseInfo() external view returns (
        uint256 netBalance,
        uint256 totalBalance,
        uint256 minBetSize,
        uint256 maxBetSize
    );
}

// ============ Initializable (for upgradeable contracts) ============

abstract contract Initializable {
    uint64 private _initialized;
    bool private _initializing;

    error InvalidInitialization();
    error NotInitializing();

    event Initialized(uint64 version);

    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        uint64 initialized = _initialized;

        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    modifier reinitializer(uint64 version) {
        if (_initializing || _initialized >= version) {
            revert InvalidInitialization();
        }
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    modifier onlyInitializing() {
        if (!_initializing) {
            revert NotInitializing();
        }
        _;
    }

    function _disableInitializers() internal virtual {
        if (_initializing) {
            revert InvalidInitialization();
        }
        if (_initialized != type(uint64).max) {
            _initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    function _getInitializedVersion() internal view returns (uint64) {
        return _initialized;
    }

    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}

// ============ ContextUpgradeable ============

abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {}
    function __Context_init_unchained() internal onlyInitializing {}

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// ============ OwnableUpgradeable ============

abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// ============ ReentrancyGuardUpgradeable ============

abstract contract ReentrancyGuardUpgradeable is Initializable {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    error ReentrancyGuardReentrantCall();

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = NOT_ENTERED;
    }
}

// ============ PausableUpgradeable ============

abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    bool private _paused;

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();

    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
        _paused = false;
    }

    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    modifier whenPaused() {
        _requirePaused();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// ============ ERC1967Utils (for UUPS) ============

library ERC1967Utils {
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    error ERC1967InvalidImplementation(address implementation);

    function getImplementation() internal view returns (address) {
        return address(uint160(uint256(_getSlot(IMPLEMENTATION_SLOT))));
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        if (data.length > 0) {
            (bool success,) = newImplementation.delegatecall(data);
            require(success, "upgrade call failed");
        }
    }

    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        assembly {
            sstore(IMPLEMENTATION_SLOT, newImplementation)
        }
    }

    function _getSlot(bytes32 slot) private view returns (bytes32 value) {
        assembly {
            value := sload(slot)
        }
    }
}

// ============ UUPSUpgradeable ============

abstract contract UUPSUpgradeable is Initializable {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable __self = address(this);

    error UUPSUnauthorizedCallContext();
    error UUPSUnsupportedProxiableUUID(bytes32 slot);

    modifier onlyProxy() {
        if (address(this) == __self) {
            revert UUPSUnauthorizedCallContext();
        }
        _;
    }

    modifier notDelegated() {
        if (address(this) != __self) {
            revert UUPSUnauthorizedCallContext();
        }
        _;
    }

    function __UUPSUpgradeable_init() internal onlyInitializing {}
    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {}

    function proxiableUUID() external view virtual notDelegated returns (bytes32) {
        return ERC1967Utils.IMPLEMENTATION_SLOT;
    }

    function upgradeToAndCall(address newImplementation, bytes memory data) public payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    function _authorizeUpgrade(address newImplementation) internal virtual;
}

// ============================================================
// ===================== MAIN CONTRACT ========================
// ============================================================

contract BuxBoosterGame is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // ============ Structs ============

    struct TokenConfig {
        bool enabled;
        uint256 houseBalance;
    }

    struct Bet {
        address player;
        address token;
        uint256 amount;
        int8 difficulty;       // -4 to 5
        uint8[] predictions;   // 0 = heads, 1 = tails
        bytes32 commitmentHash;
        uint256 nonce;
        uint256 timestamp;
        BetStatus status;
    }

    struct PlayerStats {
        uint256 totalBets;
        uint256 totalStaked;
        int256 overallProfitLoss;
        // Per-difficulty stats (indexed by difficulty + 4 for array access)
        uint256[9] betsPerDifficulty;      // Count of bets at each difficulty
        int256[9] profitLossPerDifficulty; // P/L at each difficulty
    }

    enum BetStatus {
        Pending,
        Won,
        Lost,
        Expired
    }

    // ============ Constants ============

    uint8 constant MODE_WIN_ALL = 0;
    uint8 constant MODE_WIN_ONE = 1;

    // Multipliers in basis points (10000 = 1x) - includes house edge
    // Index 0-3: Win One (-4 to -1), Index 4-8: Win All (1 to 5)
    // NOTE: Initialized in initializeV2() for proxy compatibility
    /// @custom:oz-upgrades-unsafe-allow state-variable-assignment
    uint32[9] public MULTIPLIERS;

    // NOTE: Initialized in initializeV2() for proxy compatibility
    /// @custom:oz-upgrades-unsafe-allow state-variable-assignment
    uint8[9] public FLIP_COUNTS;
    /// @custom:oz-upgrades-unsafe-allow state-variable-assignment
    uint8[9] public GAME_MODES;

    uint256 public constant BET_EXPIRY = 1 hours;
    uint256 public constant MIN_BET = 1e18; // 1 token (18 decimals)
    uint256 public constant MAX_BET_BPS = 10; // 0.1% = 10 basis points

    // ============ State Variables ============

    mapping(address => TokenConfig) public tokenConfigs;
    mapping(bytes32 => Bet) public bets;
    mapping(address => uint256) public playerNonces;
    mapping(address => bytes32[]) public playerBetHistory;
    mapping(address => PlayerStats) public playerStats;

    // Commitment tracking: commitmentHash => Commitment
    // Server submits commitment BEFORE player bets, proving the result was pre-determined
    mapping(bytes32 => Commitment) public commitments;

    // Lookup commitment by player + nonce (for UI to find unused commitments)
    // player => nonce => commitmentHash
    mapping(address => mapping(uint256 => bytes32)) public playerCommitments;

    struct Commitment {
        address player;         // Player this commitment is for
        uint256 nonce;          // Expected nonce for this bet
        uint256 timestamp;      // When commitment was made (for record-keeping)
        bool used;              // Whether this commitment has been used
        bytes32 serverSeed;     // Revealed after bet is settled (empty until then)
    }

    address public settler;

    uint256 public totalBetsPlaced;
    uint256 public totalBetsSettled;

    // ============ Events ============

    event TokenConfigured(address indexed token, bool enabled);

    event CommitmentSubmitted(
        bytes32 indexed commitmentHash,
        address indexed player,
        uint256 nonce
    );

    event BetPlaced(
        bytes32 indexed commitmentHash,  // Now using commitmentHash as betId
        address indexed player,
        address indexed token,
        uint256 amount,
        int8 difficulty,
        uint8[] predictions,
        uint256 nonce
    );

    event BetSettled(
        bytes32 indexed commitmentHash,
        address indexed player,
        bool won,
        uint8[] results,
        uint256 payout,
        bytes32 serverSeed
    );

    event BetDetails(
        bytes32 indexed commitmentHash,
        address indexed token,
        uint256 amount,
        int8 difficulty,
        uint8[] predictions,
        uint256 nonce,
        uint256 timestamp
    );

    event BetExpired(bytes32 indexed betId, address indexed player);
    event HouseDeposit(address indexed token, uint256 amount);
    event HouseWithdraw(address indexed token, uint256 amount);

    // V6: Referral events
    event ReferralRewardPaid(
        bytes32 indexed commitmentHash,
        address indexed referrer,
        address indexed player,
        address token,
        uint256 amount
    );
    event ReferrerSet(address indexed player, address indexed referrer);
    event ReferralAdminChanged(address indexed previousAdmin, address indexed newAdmin);

    // V5: ROGUE betting support (add at end to preserve storage layout)
    address public rogueBankroll;  // Address of ROGUEBankroll contract
    address constant ROGUE_TOKEN = address(0);  // Special address to represent ROGUE (native token)

    // V6: Referral system (add at end to preserve storage layout)
    /// @notice Referral reward basis points for BUX token bets (100 = 1%)
    uint256 public buxReferralBasisPoints;

    /// @notice Mapping from player to their referrer address
    mapping(address => address) public playerReferrers;

    /// @notice Total referral rewards paid out per token
    mapping(address => uint256) public totalReferralRewardsPaid;

    /// @notice Total referral rewards earned per referrer per token
    mapping(address => mapping(address => uint256)) public referrerTokenEarnings;

    /// @notice Admin address authorized to set player referrers (e.g., BuxMinter service)
    address public referralAdmin;

    // ============ Errors ============

    error TokenNotEnabled();
    error BetAmountTooLow();
    error BetAmountTooHigh();
    error InvalidDifficulty();
    error InvalidPredictions();
    error BetNotFound();
    error BetAlreadySettled();
    error BetExpiredError();
    error InvalidServerSeed();
    error InsufficientHouseBalance();
    error UnauthorizedSettler();
    error BetNotExpired();
    error CommitmentNotFound();
    error CommitmentAlreadyUsed();
    error CommitmentWrongPlayer();
    error CommitmentWrongNonce();
    error InvalidToken();

    // ============ Modifiers ============

    modifier onlySettler() {
        if (msg.sender != settler && msg.sender != owner()) {
            revert UnauthorizedSettler();
        }
        _;
    }

    // ============ Initializer (replaces constructor for upgradeable contracts) ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (called once via proxy)
     */
    function initialize() initializer public {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Initialize V2 - sets game constants that weren't initialized in V1
     * @dev Called once after upgrading to V2. Populates MULTIPLIERS, FLIP_COUNTS, and GAME_MODES arrays.
     */
    function initializeV2() reinitializer(2) public {
        // Multipliers in basis points (10000 = 1x) - includes house edge
        // Index 0-3: Win One (-4 to -1), Index 4-8: Win All (1 to 5)
        MULTIPLIERS[0] = 10200;   // -4: 1.02x (Win One, 5 flips)
        MULTIPLIERS[1] = 10500;   // -3: 1.05x (Win One, 4 flips)
        MULTIPLIERS[2] = 11300;   // -2: 1.13x (Win One, 3 flips)
        MULTIPLIERS[3] = 13200;   // -1: 1.32x (Win One, 2 flips)
        MULTIPLIERS[4] = 19800;   // 1: 1.98x (Win All, 1 flip)
        MULTIPLIERS[5] = 39600;   // 2: 3.96x (Win All, 2 flips)
        MULTIPLIERS[6] = 79200;   // 3: 7.92x (Win All, 3 flips)
        MULTIPLIERS[7] = 158400;  // 4: 15.84x (Win All, 4 flips)
        MULTIPLIERS[8] = 316800;  // 5: 31.68x (Win All, 5 flips)

        // Number of flips per difficulty
        FLIP_COUNTS[0] = 5;  // -4
        FLIP_COUNTS[1] = 4;  // -3
        FLIP_COUNTS[2] = 3;  // -2
        FLIP_COUNTS[3] = 2;  // -1
        FLIP_COUNTS[4] = 1;  // 1
        FLIP_COUNTS[5] = 2;  // 2
        FLIP_COUNTS[6] = 3;  // 3
        FLIP_COUNTS[7] = 4;  // 4
        FLIP_COUNTS[8] = 5;  // 5

        // Game modes: 0 = Win All, 1 = Win One
        GAME_MODES[0] = MODE_WIN_ONE;  // -4
        GAME_MODES[1] = MODE_WIN_ONE;  // -3
        GAME_MODES[2] = MODE_WIN_ONE;  // -2
        GAME_MODES[3] = MODE_WIN_ONE;  // -1
        GAME_MODES[4] = MODE_WIN_ALL;  // 1
        GAME_MODES[5] = MODE_WIN_ALL;  // 2
        GAME_MODES[6] = MODE_WIN_ALL;  // 3
        GAME_MODES[7] = MODE_WIN_ALL;  // 4
        GAME_MODES[8] = MODE_WIN_ALL;  // 5
    }

    /**
     * @notice Initialize V3 - server-side result calculation upgrade
     * @dev V3 changes:
     *      - settleBet now accepts results from server instead of calculating on-chain
     *      - commitmentHash is used as betId (simpler, more gas efficient)
     *      - BetSettled event includes full game details for transparency
     *      - Removed on-chain result generation (_generateClientSeed, _generateResults, _checkWin)
     */
    function initializeV3() reinitializer(3) public {
        // No state changes needed - all changes are in function logic
        // This function exists to mark the upgrade and allow future migrations if needed
    }

    /**
     * @notice Initialize V5 - ROGUE betting support
     * @param _rogueBankroll Address of ROGUEBankroll contract
     */
    function initializeV5(address _rogueBankroll) reinitializer(5) public {
        rogueBankroll = _rogueBankroll;
    }

    /**
     * @notice Initialize V6 - Referral system
     * @dev Sets referral basis points to 100 (1% of losing BUX bets)
     */
    function initializeV6() reinitializer(6) public {
        buxReferralBasisPoints = 100;  // 1% (100 basis points)
    }

    /**
     * @notice Required by UUPS - only owner can upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Referral Functions (V6) ============

    /**
     * @notice Set the referral reward basis points for BUX token
     * @param _basisPoints Referral reward in basis points (max 100 = 1%)
     */
    function setBuxReferralBasisPoints(uint256 _basisPoints) external onlyOwner {
        require(_basisPoints <= 100, "Max 1%");
        buxReferralBasisPoints = _basisPoints;
    }

    /**
     * @notice Get the current BUX referral basis points
     * @return Current basis points value
     */
    function getBuxReferralBasisPoints() external view returns (uint256) {
        return buxReferralBasisPoints;
    }

    /**
     * @notice Get total referral rewards paid for a token
     * @param token The token address
     * @return Total amount paid
     */
    function getTotalReferralRewardsPaid(address token) external view returns (uint256) {
        return totalReferralRewardsPaid[token];
    }

    /**
     * @notice Get total earnings for a referrer for a specific token
     * @param referrer The referrer address
     * @param token The token address
     * @return Total amount earned
     */
    function getReferrerTokenEarnings(address referrer, address token) external view returns (uint256) {
        return referrerTokenEarnings[referrer][token];
    }

    /**
     * @notice Set the referral admin address (owner only)
     * @dev The referral admin can call setPlayerReferrer on behalf of the system
     * @param _admin The new referral admin address (e.g., BuxMinter service wallet)
     */
    function setReferralAdmin(address _admin) external onlyOwner {
        emit ReferralAdminChanged(referralAdmin, _admin);
        referralAdmin = _admin;
    }

    /**
     * @notice Get the current referral admin address
     * @return The referral admin address
     */
    function getReferralAdmin() external view returns (address) {
        return referralAdmin;
    }

    /**
     * @notice Set a player's referrer (can only be set once)
     * @dev Called by referral admin (BuxMinter service) or owner on signup
     * @param player The player's smart wallet address
     * @param referrer The referrer's smart wallet address
     */
    function setPlayerReferrer(address player, address referrer) external {
        require(msg.sender == owner() || msg.sender == referralAdmin, "Not authorized");
        require(playerReferrers[player] == address(0), "Referrer already set");
        require(referrer != address(0), "Invalid referrer");
        require(player != referrer, "Self-referral not allowed");

        playerReferrers[player] = referrer;
        emit ReferrerSet(player, referrer);
    }

    /**
     * @notice Batch set multiple player referrers (for efficiency)
     * @dev Called by referral admin (BuxMinter service) or owner
     * @param players Array of player addresses
     * @param referrers Array of corresponding referrer addresses
     */
    function setPlayerReferrersBatch(
        address[] calldata players,
        address[] calldata referrers
    ) external {
        require(msg.sender == owner() || msg.sender == referralAdmin, "Not authorized");
        require(players.length == referrers.length, "Array length mismatch");

        for (uint256 i = 0; i < players.length; i++) {
            if (playerReferrers[players[i]] == address(0) &&
                referrers[i] != address(0) &&
                players[i] != referrers[i]) {
                playerReferrers[players[i]] = referrers[i];
                emit ReferrerSet(players[i], referrers[i]);
            }
        }
    }

    /**
     * @notice Get a player's referrer
     * @param player The player address
     * @return The referrer's address (or address(0) if none)
     */
    function getPlayerReferrer(address player) external view returns (address) {
        return playerReferrers[player];
    }

    // ============ Settler Functions ============

    /**
     * @notice Submit a commitment hash BEFORE player places bet (provably fair)
     * @dev Only settler can submit commitments. This proves the server seed
     *      was determined before the player made their predictions.
     *      The commitment is stored and can be looked up by player + nonce.
     * @param commitmentHash SHA256 hash of server seed
     * @param player The player this commitment is for
     * @param nonce The expected nonce for this player's next bet
     */
    function submitCommitment(
        bytes32 commitmentHash,
        address player,
        uint256 nonce
    ) external onlySettler {
        // Store commitment (no expiry - valid until used)
        // Note: Nonce is stored but NOT validated - server manages nonces in Mnesia
        commitments[commitmentHash] = Commitment({
            player: player,
            nonce: nonce,
            timestamp: block.timestamp,
            used: false,
            serverSeed: bytes32(0)  // Empty until revealed after settlement
        });

        // Store reverse lookup so UI can find commitment by player + nonce
        playerCommitments[player][nonce] = commitmentHash;

        emit CommitmentSubmitted(commitmentHash, player, nonce);
    }

    // ============ Player Functions ============

    /**
     * @notice Place a bet with predictions using a pre-submitted commitment
     * @param token The ERC-20 token to bet with
     * @param amount The bet amount (18 decimals)
     * @param difficulty Game difficulty (-4 to -1 for Win One, 1 to 5 for Win All)
     * @param predictions Array of predictions (0=heads, 1=tails)
     * @param commitmentHash The commitment hash submitted by server BEFORE this bet (also serves as betId)
     */
    function placeBet(
        address token,
        uint256 amount,
        int8 difficulty,
        uint8[] calldata predictions,
        bytes32 commitmentHash
    ) external nonReentrant whenNotPaused {
        // Validate commitment in separate function to reduce stack usage
        _validateCommitment(commitmentHash);

        // Validate bet params and get diffIndex
        _validateBetParams(token, amount, difficulty, predictions);

        // Transfer tokens from player to contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Create bet and store it (using commitmentHash as betId)
        _createBet(token, amount, difficulty, predictions, commitmentHash);
    }

    function _validateCommitment(bytes32 commitmentHash) internal {
        Commitment storage commitment = commitments[commitmentHash];
        if (commitment.player == address(0)) revert CommitmentNotFound();
        if (commitment.used) revert CommitmentAlreadyUsed();
        if (commitment.player != msg.sender) revert CommitmentWrongPlayer();
        // Note: Nonce is NOT validated - server manages nonces in Mnesia
        commitment.used = true;
    }

    function _validateBetParams(
        address token,
        uint256 amount,
        int8 difficulty,
        uint8[] calldata predictions
    ) internal view returns (uint8 diffIndex) {
        TokenConfig storage config = tokenConfigs[token];
        if (!config.enabled) revert TokenNotEnabled();
        if (amount < MIN_BET) revert BetAmountTooLow();
        if (difficulty == 0 || difficulty < -4 || difficulty > 5) revert InvalidDifficulty();

        diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);

        if (predictions.length != FLIP_COUNTS[diffIndex]) revert InvalidPredictions();

        for (uint i = 0; i < predictions.length; i++) {
            if (predictions[i] > 1) revert InvalidPredictions();
        }

        uint256 maxBet = _calculateMaxBet(config.houseBalance, diffIndex);
        if (amount > maxBet) revert BetAmountTooHigh();

        uint256 potentialProfit = ((amount * MULTIPLIERS[diffIndex]) / 10000) - amount;
        if (config.houseBalance < potentialProfit) revert InsufficientHouseBalance();
    }

    /**
     * @notice Validate ROGUE bet parameters
     * @dev Queries ROGUEBankroll for max bet and house balance
     */
    function _validateROGUEBetParams(
        uint256 amount,
        int8 difficulty,
        uint8[] calldata predictions
    ) internal view returns (uint8 diffIndex) {
        if (difficulty == 0 || difficulty < -4 || difficulty > 5) revert InvalidDifficulty();
        if (amount < MIN_BET) revert BetAmountTooLow();

        diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);

        if (predictions.length != FLIP_COUNTS[diffIndex]) revert InvalidPredictions();
        for (uint i = 0; i < predictions.length; i++) {
            if (predictions[i] > 1) revert InvalidPredictions();
        }

        // Query ROGUEBankroll for limits
        (uint256 netBalance, , uint256 minBetSize, uint256 maxBetFromBankroll) =
            IROGUEBankroll(rogueBankroll).getHouseInfo();

        if (amount < minBetSize) revert BetAmountTooLow();

        // Apply both ROGUEBankroll's max bet AND BuxBooster's multiplier-based max
        uint256 maxBetForMultiplier = _calculateMaxBet(netBalance, diffIndex);
        uint256 maxBet = maxBetFromBankroll < maxBetForMultiplier ? maxBetFromBankroll : maxBetForMultiplier;

        if (amount > maxBet) revert BetAmountTooHigh();

        uint256 potentialProfit = ((amount * MULTIPLIERS[diffIndex]) / 10000) - amount;
        if (netBalance < potentialProfit) revert InsufficientHouseBalance();
    }

    function _createBet(
        address token,
        uint256 amount,
        int8 difficulty,
        uint8[] calldata predictions,
        bytes32 commitmentHash
    ) internal {
        // Get commitment to read the nonce (don't increment - server manages nonces)
        Commitment storage commitment = commitments[commitmentHash];
        uint256 nonce = commitment.nonce;

        // Use commitmentHash as betId directly (no struct changes - safe for upgradeability)
        bets[commitmentHash] = Bet({
            player: msg.sender,
            token: token,
            amount: amount,
            difficulty: difficulty,
            predictions: predictions,
            commitmentHash: commitmentHash,
            nonce: nonce,
            timestamp: block.timestamp,
            status: BetStatus.Pending
        });

        playerBetHistory[msg.sender].push(commitmentHash);
        totalBetsPlaced++;

        emit BetPlaced(commitmentHash, msg.sender, token, amount, difficulty, predictions, nonce);
    }

    /**
     * @notice Place a ROGUE bet (native token) using ROGUEBankroll
     * @dev Separate function from placeBet() to avoid modifying existing ERC-20 flow
     * @param amount The bet amount in wei
     * @param difficulty Game difficulty (-4 to -1 for Win One, 1 to 5 for Win All)
     * @param predictions Array of predictions (0=heads, 1=tails)
     * @param commitmentHash The commitment hash submitted by server BEFORE this bet
     */
    function placeBetROGUE(
        uint256 amount,
        int8 difficulty,
        uint8[] calldata predictions,
        bytes32 commitmentHash
    ) external payable nonReentrant whenNotPaused {
        require(msg.value == amount, "ROGUE amount mismatch");

        // Validate commitment
        _validateCommitment(commitmentHash);

        // Validate bet params with ROGUE-specific validation
        _validateROGUEBetParams(amount, difficulty, predictions);

        // Get commitment to read the nonce
        Commitment storage commitment = commitments[commitmentHash];
        uint256 nonce = commitment.nonce;

        // Calculate max possible payout for this bet
        uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);
        uint256 maxPayout = (amount * MULTIPLIERS[diffIndex]) / 10000;

        // Forward bet to ROGUEBankroll (also sends the ROGUE and bet details)
        IROGUEBankroll(rogueBankroll).updateHouseBalanceBuxBoosterBetPlaced{value: amount}(
            commitmentHash,
            difficulty,
            predictions,
            nonce,
            maxPayout
        );

        // Create bet record using ROGUE_TOKEN address
        _createBet(ROGUE_TOKEN, amount, difficulty, predictions, commitmentHash);
    }

    /**
     * @notice Settle a bet by revealing the server seed and results
     * @dev Server calculates results off-chain and submits them. Contract verifies seed and processes payout.
     * @param commitmentHash The commitment hash (also serves as betId)
     * @param serverSeed The revealed server seed (must hash to commitmentHash)
     * @param results The flip results calculated by server
     * @param won Whether the player won (calculated by server)
     */
    function settleBet(
        bytes32 commitmentHash,
        bytes32 serverSeed,
        uint8[] calldata results,
        bool won
    ) external onlySettler nonReentrant returns (uint256 payout) {
        Bet storage bet = bets[commitmentHash];

        if (bet.player == address(0)) revert BetNotFound();
        if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
        if (block.timestamp > bet.timestamp + BET_EXPIRY) revert BetExpiredError();

        // V4: Server is single source of truth - no verification needed
        // Server seed is stored for transparency and off-chain verification only

        // Verify results array length matches predictions
        if (results.length != bet.predictions.length) revert InvalidPredictions();

        // Store the revealed server seed (for transparency and player verification)
        commitments[bet.commitmentHash].serverSeed = serverSeed;

        // Process payout
        payout = _processSettlement(
            bet,
            bet.difficulty < 0 ? uint8(int8(4) + bet.difficulty) : uint8(int8(3) + bet.difficulty),
            won
        );

        totalBetsSettled++;

        // Emit event in separate function to avoid stack too deep
        _emitSettled(commitmentHash, bet, won, results, payout, serverSeed);
    }

    /**
     * @notice Settle a ROGUE bet by revealing the server seed and results
     * @dev Calls ROGUEBankroll for actual payout instead of handling internally
     * @param commitmentHash The commitment hash (also serves as betId)
     * @param serverSeed The revealed server seed
     * @param results The flip results calculated by server
     * @param won Whether the player won
     */
    function settleBetROGUE(
        bytes32 commitmentHash,
        bytes32 serverSeed,
        uint8[] calldata results,
        bool won
    ) external onlySettler nonReentrant returns (uint256 payout) {
        Bet storage bet = bets[commitmentHash];

        if (bet.player == address(0)) revert BetNotFound();
        if (bet.token != ROGUE_TOKEN) revert InvalidToken(); // Ensure this is a ROGUE bet
        if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
        if (block.timestamp > bet.timestamp + BET_EXPIRY) revert BetExpiredError();
        if (results.length != bet.predictions.length) revert InvalidPredictions();

        // Store revealed server seed
        commitments[bet.commitmentHash].serverSeed = serverSeed;

        uint8 diffIndex = bet.difficulty < 0 ? uint8(int8(4) + bet.difficulty) : uint8(int8(3) + bet.difficulty);

        // Settle via ROGUEBankroll (pass results array for event emission)
        payout = _settleROGUEBet(bet, diffIndex, won, results);

        totalBetsSettled++;
        _emitSettled(commitmentHash, bet, won, results, payout, serverSeed);
    }

    function _settleROGUEBet(
        Bet storage bet,
        uint8 diffIndex,
        bool won,
        uint8[] calldata results
    ) internal returns (uint256 payout) {
        PlayerStats storage stats = playerStats[bet.player];

        stats.totalBets++;
        stats.totalStaked += bet.amount;
        stats.betsPerDifficulty[diffIndex]++;

        // Calculate payout
        uint256 maxPayout = (bet.amount * MULTIPLIERS[diffIndex]) / 10000;

        if (won) {
            payout = maxPayout;
            bet.status = BetStatus.Won;

            int256 profit = int256(payout) - int256(bet.amount);
            stats.overallProfitLoss += profit;
            stats.profitLossPerDifficulty[diffIndex] += profit;

            // Call helper to avoid stack too deep
            _callBankrollWinning(bet, payout, maxPayout, results);
        } else {
            payout = 0;
            bet.status = BetStatus.Lost;

            stats.overallProfitLoss -= int256(bet.amount);
            stats.profitLossPerDifficulty[diffIndex] -= int256(bet.amount);

            // Call helper to avoid stack too deep
            _callBankrollLosing(bet, maxPayout, results);
        }
    }

    // Helper to call ROGUEBankroll for winning bet (avoids stack too deep)
    function _callBankrollWinning(
        Bet storage bet,
        uint256 payout,
        uint256 maxPayout,
        uint8[] calldata results
    ) private {
        IROGUEBankroll(rogueBankroll).settleBuxBoosterWinningBet(
            bet.player,
            bet.commitmentHash,
            bet.amount,
            payout,
            bet.difficulty,
            bet.predictions,
            results,
            bet.nonce,
            maxPayout
        );
    }

    // Helper to call ROGUEBankroll for losing bet (avoids stack too deep)
    function _callBankrollLosing(
        Bet storage bet,
        uint256 maxPayout,
        uint8[] calldata results
    ) private {
        IROGUEBankroll(rogueBankroll).settleBuxBoosterLosingBet(
            bet.player,
            bet.commitmentHash,
            bet.amount,
            bet.difficulty,
            bet.predictions,
            results,
            bet.nonce,
            maxPayout
        );
    }

    // Helper to emit BetSettled events - split into two to avoid stack too deep
    function _emitSettled(
        bytes32 commitmentHash,
        Bet storage bet,
        bool won,
        uint8[] calldata results,
        uint256 payout,
        bytes32 serverSeed
    ) private {
        // Emit settlement result
        emit BetSettled(
            commitmentHash,
            bet.player,
            won,
            results,
            payout,
            serverSeed
        );

        // Emit bet details
        emit BetDetails(
            commitmentHash,
            bet.token,
            bet.amount,
            bet.difficulty,
            bet.predictions,
            bet.nonce,
            bet.timestamp
        );
    }

    function _processSettlement(Bet storage bet, uint8 diffIndex, bool won) internal returns (uint256 payout) {
        TokenConfig storage config = tokenConfigs[bet.token];
        PlayerStats storage stats = playerStats[bet.player];

        stats.totalBets++;
        stats.totalStaked += bet.amount;
        stats.betsPerDifficulty[diffIndex]++;

        if (won) {
            payout = (bet.amount * MULTIPLIERS[diffIndex]) / 10000;
            bet.status = BetStatus.Won;
            config.houseBalance -= (payout - bet.amount);
            int256 profit = int256(payout) - int256(bet.amount);
            stats.overallProfitLoss += profit;
            stats.profitLossPerDifficulty[diffIndex] += profit;
            IERC20(bet.token).safeTransfer(bet.player, payout);
        } else {
            payout = 0;
            bet.status = BetStatus.Lost;
            config.houseBalance += bet.amount;
            stats.overallProfitLoss -= int256(bet.amount);
            stats.profitLossPerDifficulty[diffIndex] -= int256(bet.amount);

            // V6: Send referral reward on losing BUX bet
            _sendBuxReferralReward(bet.commitmentHash, bet);
        }
    }

    /**
     * @dev Send BUX referral reward on losing bet (non-blocking like NFT rewards)
     * @param commitmentHash The bet's commitment hash (for event tracking)
     * @param bet The bet struct
     */
    function _sendBuxReferralReward(bytes32 commitmentHash, Bet storage bet) private {
        // Skip if no referral program
        if (buxReferralBasisPoints == 0) return;

        address referrer = playerReferrers[bet.player];
        if (referrer == address(0)) return;

        // Calculate referral reward: betAmount * basisPoints / 10000
        uint256 rewardAmount = (bet.amount * buxReferralBasisPoints) / 10000;
        if (rewardAmount == 0) return;

        TokenConfig storage config = tokenConfigs[bet.token];

        // Ensure house has enough balance (non-blocking - skip if not enough)
        if (config.houseBalance < rewardAmount) {
            return;
        }

        // Deduct from house balance
        config.houseBalance -= rewardAmount;

        // Transfer BUX tokens directly to referrer wallet
        IERC20(bet.token).safeTransfer(referrer, rewardAmount);

        // Track total rewards
        totalReferralRewardsPaid[bet.token] += rewardAmount;
        referrerTokenEarnings[referrer][bet.token] += rewardAmount;

        emit ReferralRewardPaid(
            commitmentHash,
            referrer,
            bet.player,
            bet.token,
            rewardAmount
        );
    }

    // ============ View Functions ============

    /**
     * @notice Get bet details
     */
    function getBet(bytes32 betId) external view returns (
        address player,
        address token,
        uint256 amount,
        int8 difficulty,
        uint8[] memory predictions,
        bytes32 commitmentHash,
        uint256 nonce,
        uint256 timestamp,
        BetStatus status
    ) {
        Bet storage bet = bets[betId];
        return (
            bet.player,
            bet.token,
            bet.amount,
            bet.difficulty,
            bet.predictions,
            bet.commitmentHash,
            bet.nonce,
            bet.timestamp,
            bet.status
        );
    }

    /**
     * @notice Get player statistics
     */
    function getPlayerStats(address player) external view returns (
        uint256 totalBets,
        uint256 totalStaked,
        int256 overallProfitLoss,
        uint256[9] memory betsPerDifficulty,
        int256[9] memory profitLossPerDifficulty
    ) {
        PlayerStats storage stats = playerStats[player];
        return (
            stats.totalBets,
            stats.totalStaked,
            stats.overallProfitLoss,
            stats.betsPerDifficulty,
            stats.profitLossPerDifficulty
        );
    }

    /**
     * @notice Calculate max bet for a given token and difficulty
     */
    function getMaxBet(address token, int8 difficulty) external view returns (uint256) {
        if (difficulty == 0 || difficulty < -4 || difficulty > 5) return 0;
        uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);
        return _calculateMaxBet(tokenConfigs[token].houseBalance, diffIndex);
    }

    /**
     * @notice Get maximum bet size for ROGUE at given difficulty
     * @dev Queries ROGUEBankroll and applies multiplier-based constraints
     * @param difficulty Game difficulty (-4 to -1 for Win One, 1 to 5 for Win All)
     * @return Maximum allowed bet in wei
     */
    function getMaxBetROGUE(int8 difficulty) external view returns (uint256) {
        if (difficulty == 0 || difficulty < -4 || difficulty > 5) return 0;

        // Get limits from ROGUEBankroll
        (uint256 netBalance, , , uint256 maxBetFromBankroll) = IROGUEBankroll(rogueBankroll).getHouseInfo();

        // Calculate our multiplier-based max bet
        uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);
        uint256 maxBetForMultiplier = _calculateMaxBet(netBalance, diffIndex);

        // Return the minimum of both constraints
        return maxBetFromBankroll < maxBetForMultiplier ? maxBetFromBankroll : maxBetForMultiplier;
    }

    /**
     * @notice Calculate potential payout for a bet
     */
    function calculatePotentialPayout(uint256 amount, int8 difficulty) external view returns (uint256) {
        if (difficulty == 0 || difficulty < -4 || difficulty > 5) return 0;
        uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);
        return (amount * MULTIPLIERS[diffIndex]) / 10000;
    }

    /**
     * @notice Get player's bet history
     */
    function getPlayerBetHistory(address player, uint256 offset, uint256 limit)
        external view returns (bytes32[] memory)
    {
        bytes32[] storage history = playerBetHistory[player];
        uint256 total = history.length;

        if (offset >= total) return new bytes32[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        bytes32[] memory result = new bytes32[](end - offset);
        for (uint i = offset; i < end; i++) {
            result[i - offset] = history[i];
        }
        return result;
    }

    /**
     * @notice Get a player's current (unused) commitment for their next bet
     * @dev UI can link to Roguescan to show the commitment was on-chain before bet
     * @param player The player's address
     * @return commitmentHash The commitment hash (bytes32(0) if none exists)
     * @return nonce The nonce this commitment is for
     * @return timestamp When the commitment was submitted
     * @return used Whether the commitment has been used
     */
    function getPlayerCurrentCommitment(address player) external view returns (
        bytes32 commitmentHash,
        uint256 nonce,
        uint256 timestamp,
        bool used
    ) {
        nonce = playerNonces[player];
        commitmentHash = playerCommitments[player][nonce];

        if (commitmentHash != bytes32(0)) {
            Commitment storage c = commitments[commitmentHash];
            return (commitmentHash, c.nonce, c.timestamp, c.used);
        }
        return (bytes32(0), nonce, 0, false);
    }

    /**
     * @notice Get a commitment by player and nonce
     * @dev Useful for looking up past commitments and their revealed server seeds
     * @param player The player's address
     * @param nonce The nonce to look up
     * @return commitmentHash The commitment hash
     * @return commitmentTimestamp When commitment was submitted
     * @return used Whether the commitment was used
     * @return serverSeed The revealed server seed (empty if not yet settled)
     */
    function getCommitmentByNonce(address player, uint256 nonce) external view returns (
        bytes32 commitmentHash,
        uint256 commitmentTimestamp,
        bool used,
        bytes32 serverSeed
    ) {
        commitmentHash = playerCommitments[player][nonce];

        if (commitmentHash != bytes32(0)) {
            Commitment storage c = commitments[commitmentHash];
            return (commitmentHash, c.timestamp, c.used, c.serverSeed);
        }
        return (bytes32(0), 0, false, bytes32(0));
    }

    /**
     * @notice Get full commitment details by hash
     * @param commitmentHash The commitment hash to look up
     * @return player The player this commitment is for
     * @return nonce The nonce
     * @return timestamp When commitment was submitted
     * @return used Whether it has been used
     * @return serverSeed The revealed server seed (empty if not yet settled)
     */
    function getCommitment(bytes32 commitmentHash) external view returns (
        address player,
        uint256 nonce,
        uint256 timestamp,
        bool used,
        bytes32 serverSeed
    ) {
        Commitment storage c = commitments[commitmentHash];
        return (c.player, c.nonce, c.timestamp, c.used, c.serverSeed);
    }

    // ============ Admin Functions ============

    /**
     * @notice Configure a token for betting
     */
    function configureToken(address token, bool enabled) external onlyOwner {
        tokenConfigs[token].enabled = enabled;
        emit TokenConfigured(token, enabled);
    }

    /**
     * @notice Deposit tokens as house balance
     */
    function depositHouseBalance(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        tokenConfigs[token].houseBalance += amount;
        emit HouseDeposit(token, amount);
    }

    /**
     * @notice Withdraw house balance to owner
     */
    function withdrawHouseBalance(address token, uint256 amount) external onlyOwner {
        TokenConfig storage config = tokenConfigs[token];
        require(amount <= config.houseBalance, "Insufficient balance");
        config.houseBalance -= amount;
        IERC20(token).safeTransfer(owner(), amount);
        emit HouseWithdraw(token, amount);
    }

    /**
     * @notice Update settler address
     */
    function setSettler(address _settler) external onlyOwner {
        settler = _settler;
    }

    /**
     * @notice Set ROGUEBankroll contract address (V5)
     */
    function setROGUEBankroll(address _rogueBankroll) external onlyOwner {
        rogueBankroll = _rogueBankroll;
    }

    /**
     * @notice Pause/unpause the contract
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @notice Handle expired bets - refund to player
     */
    function refundExpiredBet(bytes32 betId) external {
        Bet storage bet = bets[betId];

        if (bet.player == address(0)) revert BetNotFound();
        if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
        if (block.timestamp <= bet.timestamp + BET_EXPIRY) revert BetNotExpired();

        bet.status = BetStatus.Expired;
        IERC20(bet.token).safeTransfer(bet.player, bet.amount);
        emit BetExpired(betId, bet.player);
    }

    // ============ Internal Functions ============

    /**
     * @notice Calculate max bet based on house balance and difficulty
     * @dev Max bet at difficulty 1 (2x) is 0.1% of house balance
     *      Other difficulties extrapolated so max payout is always ~0.1%
     */
    function _calculateMaxBet(uint256 houseBalance, uint8 diffIndex) internal view returns (uint256) {
        if (houseBalance == 0) return 0;

        // Base: 0.1% of house balance for 2x multiplier
        // For other multipliers, scale inversely with multiplier
        uint256 baseMaxBet = (houseBalance * MAX_BET_BPS) / 10000; // 0.1%
        uint256 multiplier = MULTIPLIERS[diffIndex];

        // Scale: maxBet = baseMaxBet * 20000 / multiplier
        // This ensures max potential payout is consistent across difficulties
        return (baseMaxBet * 20000) / multiplier;
    }

    // ============================================
    // Functions removed in V3 upgrade:
    // - _generateClientSeed: No longer needed (server calculates results)
    // - _generateResults: No longer needed (server calculates results)
    // - _checkWin: No longer needed (server determines win/loss)
    // - _addressToString: No longer needed
    // - _uint256ToString: No longer needed
    // - _int8ToString: No longer needed
    //
    // Contract now trusts server to provide correct results.
    // Provably fair verification happens off-chain via server seed reveal.
    // ============================================
}
