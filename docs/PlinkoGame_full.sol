// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PlinkoGame
 * @notice Provably fair Plinko game with 9 configurations (3 row counts x 3 risk levels).
 * @dev UUPS Upgradeable contract using commit-reveal pattern.
 *      BUX settlement delegated to BUXBankroll (LP pool). ROGUE settlement delegated to ROGUEBankroll.
 *      PlinkoGame does NOT hold house funds for either token.
 *
 * GAME RULES:
 * - Ball drops through N-row peg board, bouncing left/right (50/50) at each peg
 * - Landing slot determines payout multiplier (0x to 1000x)
 * - 9 configs: 8/12/16 rows x Low/Medium/High risk
 *
 * PROVABLY FAIR:
 * - Server submits commitment hash BEFORE player bets
 * - Server calculates ball path off-chain using server seed
 * - Server reveals seed when settling (must match commitment)
 * - Players verify: SHA256(serverSeed) == commitmentHash, then replay path
 *
 * UPGRADEABILITY:
 * - Uses UUPS proxy pattern (EIP-1822)
 * - Only owner can authorize upgrades
 * - Storage layout: NEVER reorder, only add at END
 */

// ============================================================
// =============== FLATTENED DEPENDENCIES =====================
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

// ============ IBUXBankroll Interface ============

interface IBUXBankroll {
    function updateHouseBalancePlinkoBetPlaced(
        bytes32 commitmentHash,
        address player,
        uint256 wagerAmount,
        uint8 configIndex,
        uint256 nonce,
        uint256 maxPayout
    ) external returns (bool);

    function settlePlinkoWinningBet(
        address winner,
        bytes32 commitmentHash,
        uint256 betAmount,
        uint256 payout,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] calldata path,
        uint256 nonce,
        uint256 maxPayout
    ) external returns (bool);

    function settlePlinkoLosingBet(
        address player,
        bytes32 commitmentHash,
        uint256 wagerAmount,
        uint256 partialPayout,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] calldata path,
        uint256 nonce,
        uint256 maxPayout
    ) external returns (bool);

    function settlePlinkoPushBet(
        address player,
        bytes32 commitmentHash,
        uint256 betAmount,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] calldata path,
        uint256 nonce,
        uint256 maxPayout
    ) external returns (bool);

    function getMaxBet(uint8 configIndex, uint32 maxMultiplierBps) external view returns (uint256);

    function getHouseInfo() external view returns (
        uint256 totalBalance,
        uint256 liability,
        uint256 unsettledBets,
        uint256 netBalance,
        uint256 poolTokenSupply,
        uint256 poolTokenPrice
    );
}

// ============ IROGUEBankroll Interface ============

interface IROGUEBankroll {
    function updateHouseBalancePlinkoBetPlaced(
        bytes32 commitmentHash,
        uint8 configIndex,
        uint256 nonce,
        uint256 maxPayout
    ) external payable returns (bool);

    function settlePlinkoWinningBet(
        address winner,
        bytes32 commitmentHash,
        uint256 betAmount,
        uint256 payout,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] calldata path,
        uint256 nonce,
        uint256 maxPayout
    ) external returns (bool);

    function settlePlinkoLosingBet(
        address player,
        bytes32 commitmentHash,
        uint256 wagerAmount,
        uint256 partialPayout,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] calldata path,
        uint256 nonce,
        uint256 maxPayout
    ) external returns (bool);

    function getHouseInfo() external view returns (
        uint256 netBalance,
        uint256 totalBalance,
        uint256 minBetSize,
        uint256 maxBetSize
    );
}

// ============ Initializable ============

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

contract PlinkoGame is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    // ============ Structs ============

    struct TokenConfig {
        bool enabled;
        // No houseBalance — held by BUXBankroll/ROGUEBankroll
    }

    struct PlinkoBet {
        address player;
        address token;
        uint256 amount;
        uint8 configIndex;          // 0-8
        bytes32 commitmentHash;
        uint256 nonce;
        uint256 timestamp;
        BetStatus status;           // Pending, Won, Lost, Push, Expired
    }

    struct Commitment {
        address player;
        uint256 nonce;
        uint256 timestamp;
        bool used;
        bytes32 serverSeed;         // Revealed after settlement
    }

    struct PlinkoConfig {
        uint8 rows;                 // 8, 12, or 16
        uint8 riskLevel;            // 0=Low, 1=Medium, 2=High
        uint8 numPositions;         // rows + 1
        uint32 maxMultiplierBps;    // Highest multiplier in payout table (set by setPayoutTable)
    }

    enum BetStatus {
        Pending,
        Won,
        Lost,
        Push,
        Expired
    }

    // ============ Constants ============

    uint256 public constant BET_EXPIRY = 1 hours;
    uint256 public constant MIN_BET = 1e18;        // 1 token (18 decimals)
    uint256 public constant MAX_BET_BPS = 10;       // 0.1% of available bankroll liquidity
    uint256 public constant MULTIPLIER_DENOMINATOR = 10000;

    // ============ Custom Errors ============

    error TokenNotEnabled();
    error BetAmountTooLow();
    error BetAmountTooHigh();
    error InvalidConfigIndex();
    error BetNotFound();
    error BetAlreadySettled();
    error BetExpiredError();
    error InsufficientHouseBalance();
    error UnauthorizedSettler();
    error BetNotExpired();
    error CommitmentNotFound();
    error CommitmentAlreadyUsed();
    error CommitmentWrongPlayer();
    error InvalidToken();
    error InvalidPath();
    error InvalidLandingPosition();
    error PayoutTableNotSet();

    // ============ Events ============

    // Pre-game
    event CommitmentSubmitted(
        bytes32 indexed commitmentHash,
        address indexed player,
        uint256 nonce
    );

    // Bet placed
    event PlinkoBetPlaced(
        bytes32 indexed commitmentHash,
        address indexed player,
        address indexed token,
        uint256 amount,
        uint8 configIndex,
        uint8 rows,
        uint8 riskLevel,
        uint256 nonce
    );

    // PRIMARY settlement event
    event PlinkoBetSettled(
        bytes32 indexed commitmentHash,
        address indexed player,
        bool profited,
        uint8 landingPosition,
        uint32 payoutMultiplierBps,
        uint256 betAmount,
        uint256 payoutAmount,
        int256 profitLoss,
        bytes32 serverSeed
    );

    // Ball path details
    event PlinkoBallPath(
        bytes32 indexed commitmentHash,
        uint8 configIndex,
        uint8[] path,
        uint8 landingPosition,
        string configLabel
    );

    // Token and timing details (split to avoid stack-too-deep)
    event PlinkoBetDetails(
        bytes32 indexed commitmentHash,
        address indexed token,
        uint256 amount,
        uint8 configIndex,
        uint256 nonce,
        uint256 timestamp
    );

    event PlinkoBetExpired(bytes32 indexed betId, address indexed player);
    event TokenConfigured(address indexed token, bool enabled);
    event PayoutTableUpdated(uint8 indexed configIndex, uint8 rows, uint8 riskLevel);

    // ============ Storage Layout (UUPS — only add at END) ============

    PlinkoConfig[9] public plinkoConfigs;
    mapping(uint8 => uint32[]) public payoutTables;             // configIndex -> multiplier array
    mapping(bytes32 => PlinkoBet) public bets;
    mapping(address => uint256) public playerNonces;
    mapping(address => bytes32[]) public playerBetHistory;
    mapping(bytes32 => Commitment) public commitments;
    mapping(address => mapping(uint256 => bytes32)) public playerCommitments;
    address public settler;
    uint256 public totalBetsPlaced;
    uint256 public totalBetsSettled;
    address public rogueBankroll;                               // ROGUEBankroll contract
    address public buxBankroll;                                 // BUXBankroll LP contract
    address public buxToken;                                    // BUX ERC-20 address
    mapping(address => TokenConfig) public tokenConfigs;

    // ============ Modifiers ============

    modifier onlySettler() {
        if (msg.sender != settler && msg.sender != owner()) {
            revert UnauthorizedSettler();
        }
        _;
    }

    // ============ Constructor (UUPS) ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initialization ============

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        // Set up 9 configs (payout tables set via setPayoutTable after deployment)
        plinkoConfigs[0] = PlinkoConfig(8, 0, 9, 0);    // 8-Low
        plinkoConfigs[1] = PlinkoConfig(8, 1, 9, 0);    // 8-Medium
        plinkoConfigs[2] = PlinkoConfig(8, 2, 9, 0);    // 8-High
        plinkoConfigs[3] = PlinkoConfig(12, 0, 13, 0);   // 12-Low
        plinkoConfigs[4] = PlinkoConfig(12, 1, 13, 0);   // 12-Medium
        plinkoConfigs[5] = PlinkoConfig(12, 2, 13, 0);   // 12-High
        plinkoConfigs[6] = PlinkoConfig(16, 0, 17, 0);   // 16-Low
        plinkoConfigs[7] = PlinkoConfig(16, 1, 17, 0);   // 16-Medium
        plinkoConfigs[8] = PlinkoConfig(16, 2, 17, 0);   // 16-High
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Required to receive ROGUE refunds from ROGUEBankroll
    receive() external payable {}

    // ============ Settler Functions ============

    /**
     * @notice Submit a commitment hash BEFORE player places bet (provably fair)
     * @param commitmentHash SHA256 hash of server seed
     * @param player Player this commitment is for
     * @param nonce Expected nonce for this bet
     */
    function submitCommitment(
        bytes32 commitmentHash,
        address player,
        uint256 nonce
    ) external onlySettler {
        commitments[commitmentHash] = Commitment({
            player: player,
            nonce: nonce,
            timestamp: block.timestamp,
            used: false,
            serverSeed: bytes32(0)
        });

        playerCommitments[player][nonce] = commitmentHash;

        emit CommitmentSubmitted(commitmentHash, player, nonce);
    }

    // ============ Player Functions — BUX (ERC-20) ============

    /**
     * @notice Place a BUX bet on Plinko
     * @dev Transfers BUX from player directly to BUXBankroll, then notifies BUXBankroll.
     *      Player must approve BUXBankroll (not PlinkoGame) to spend BUX.
     * @param amount Bet amount in BUX (18 decimals)
     * @param configIndex Plinko config (0-8)
     * @param commitmentHash Pre-submitted commitment hash
     */
    function placeBet(
        uint256 amount,
        uint8 configIndex,
        bytes32 commitmentHash
    ) external nonReentrant whenNotPaused {
        // Validate commitment
        _validateCommitment(commitmentHash);

        // Validate config and bet params
        if (configIndex > 8) revert InvalidConfigIndex();
        if (payoutTables[configIndex].length == 0) revert PayoutTableNotSet();
        if (plinkoConfigs[configIndex].maxMultiplierBps == 0) revert PayoutTableNotSet();
        if (!tokenConfigs[buxToken].enabled) revert TokenNotEnabled();
        if (amount < MIN_BET) revert BetAmountTooLow();

        // Check max bet from BUXBankroll
        uint256 maxBet = IBUXBankroll(buxBankroll).getMaxBet(configIndex, plinkoConfigs[configIndex].maxMultiplierBps);
        if (amount > maxBet) revert BetAmountTooHigh();

        // Calculate max payout for liability tracking
        uint256 maxPayout = calculateMaxPayout(amount, configIndex);

        // Check bankroll has enough liquidity
        (, , , uint256 netBalance, , ) = IBUXBankroll(buxBankroll).getHouseInfo();
        if (netBalance < maxPayout) revert InsufficientHouseBalance();

        // Transfer BUX from player directly to BUXBankroll
        IERC20(buxToken).safeTransferFrom(msg.sender, buxBankroll, amount);

        // Notify BUXBankroll of bet placement (updates liability tracking)
        uint256 nonce = commitments[commitmentHash].nonce;
        IBUXBankroll(buxBankroll).updateHouseBalancePlinkoBetPlaced(
            commitmentHash, msg.sender, amount, configIndex, nonce, maxPayout
        );

        // Create bet record
        _createBet(buxToken, amount, configIndex, commitmentHash, nonce);
    }

    // ============ Player Functions — ROGUE (Native) ============

    /**
     * @notice Place a ROGUE (native token) bet on Plinko
     * @dev Sends ROGUE directly to ROGUEBankroll via msg.value.
     * @param amount Bet amount (must match msg.value)
     * @param configIndex Plinko config (0-8)
     * @param commitmentHash Pre-submitted commitment hash
     */
    function placeBetROGUE(
        uint256 amount,
        uint8 configIndex,
        bytes32 commitmentHash
    ) external payable nonReentrant whenNotPaused {
        require(msg.value == amount, "msg.value must match amount");

        // Validate commitment
        _validateCommitment(commitmentHash);

        // Validate config and bet params
        if (configIndex > 8) revert InvalidConfigIndex();
        if (payoutTables[configIndex].length == 0) revert PayoutTableNotSet();
        if (plinkoConfigs[configIndex].maxMultiplierBps == 0) revert PayoutTableNotSet();
        if (amount < MIN_BET) revert BetAmountTooLow();

        // Query ROGUEBankroll for limits
        (uint256 rogueNetBalance, , uint256 minBetSize, uint256 maxBetFromBankroll) =
            IROGUEBankroll(rogueBankroll).getHouseInfo();

        if (amount < minBetSize) revert BetAmountTooLow();
        if (amount > maxBetFromBankroll) revert BetAmountTooHigh();

        uint256 maxPayout = calculateMaxPayout(amount, configIndex);
        if (rogueNetBalance < maxPayout) revert InsufficientHouseBalance();

        // Send ROGUE to ROGUEBankroll and notify
        uint256 nonce = commitments[commitmentHash].nonce;
        IROGUEBankroll(rogueBankroll).updateHouseBalancePlinkoBetPlaced{value: amount}(
            commitmentHash, configIndex, nonce, maxPayout
        );

        // Create bet record (address(0) represents ROGUE)
        _createBet(address(0), amount, configIndex, commitmentHash, nonce);
    }

    // ============ Settlement — BUX ============

    /**
     * @notice Settle a BUX Plinko bet
     * @param commitmentHash Bet identifier
     * @param serverSeed Revealed server seed (SHA256 must match commitmentHash)
     * @param path Ball path array (0=left, 1=right at each peg)
     * @param landingPosition Final slot (0 to rows)
     */
    function settleBet(
        bytes32 commitmentHash,
        bytes32 serverSeed,
        uint8[] calldata path,
        uint8 landingPosition
    ) external onlySettler nonReentrant {
        PlinkoBet storage bet = bets[commitmentHash];
        if (bet.player == address(0)) revert BetNotFound();
        if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
        if (block.timestamp > bet.timestamp + BET_EXPIRY) revert BetExpiredError();
        if (bet.token != buxToken) revert InvalidToken();

        // Validate path
        _validatePath(path, landingPosition, bet.configIndex);

        // Calculate payout
        uint32 multiplierBps = payoutTables[bet.configIndex][landingPosition];
        uint256 payout = (bet.amount * uint256(multiplierBps)) / MULTIPLIER_DENOMINATOR;
        uint256 maxPayout = calculateMaxPayout(bet.amount, bet.configIndex);

        // Settle via BUXBankroll
        if (payout > bet.amount) {
            // WIN
            bet.status = BetStatus.Won;
            IBUXBankroll(buxBankroll).settlePlinkoWinningBet(
                bet.player, commitmentHash, bet.amount, payout,
                bet.configIndex, landingPosition, path,
                bet.nonce, maxPayout
            );
        } else if (payout < bet.amount) {
            // LOSS (partial payout if multiplier > 0)
            bet.status = BetStatus.Lost;
            IBUXBankroll(buxBankroll).settlePlinkoLosingBet(
                bet.player, commitmentHash, bet.amount, payout,
                bet.configIndex, landingPosition, path,
                bet.nonce, maxPayout
            );
        } else {
            // PUSH (payout == bet)
            bet.status = BetStatus.Push;
            IBUXBankroll(buxBankroll).settlePlinkoPushBet(
                bet.player, commitmentHash, bet.amount,
                bet.configIndex, landingPosition, path,
                bet.nonce, maxPayout
            );
        }

        // Reveal server seed
        commitments[commitmentHash].serverSeed = serverSeed;
        totalBetsSettled++;

        // Emit settlement events
        _emitSettlementEvents(
            commitmentHash, bet.player, bet.token, bet.amount,
            bet.configIndex, bet.nonce, bet.timestamp,
            payout, multiplierBps, landingPosition, path, serverSeed
        );
    }

    // ============ Settlement — ROGUE ============

    /**
     * @notice Settle a ROGUE Plinko bet
     * @param commitmentHash Bet identifier
     * @param serverSeed Revealed server seed
     * @param path Ball path array
     * @param landingPosition Final slot
     */
    function settleBetROGUE(
        bytes32 commitmentHash,
        bytes32 serverSeed,
        uint8[] calldata path,
        uint8 landingPosition
    ) external onlySettler nonReentrant {
        PlinkoBet storage bet = bets[commitmentHash];
        if (bet.player == address(0)) revert BetNotFound();
        if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
        if (block.timestamp > bet.timestamp + BET_EXPIRY) revert BetExpiredError();
        if (bet.token != address(0)) revert InvalidToken();

        // Validate path
        _validatePath(path, landingPosition, bet.configIndex);

        // Calculate payout
        uint32 multiplierBps = payoutTables[bet.configIndex][landingPosition];
        uint256 payout = (bet.amount * uint256(multiplierBps)) / MULTIPLIER_DENOMINATOR;
        uint256 maxPayout = calculateMaxPayout(bet.amount, bet.configIndex);

        // Settle via ROGUEBankroll
        if (payout > bet.amount) {
            // WIN
            bet.status = BetStatus.Won;
            IROGUEBankroll(rogueBankroll).settlePlinkoWinningBet(
                bet.player, commitmentHash, bet.amount, payout,
                bet.configIndex, landingPosition, path,
                bet.nonce, maxPayout
            );
        } else if (payout < bet.amount) {
            // LOSS
            bet.status = BetStatus.Lost;
            IROGUEBankroll(rogueBankroll).settlePlinkoLosingBet(
                bet.player, commitmentHash, bet.amount, payout,
                bet.configIndex, landingPosition, path,
                bet.nonce, maxPayout
            );
        } else {
            // PUSH — for ROGUE, bankroll handles similarly to loss with full return
            bet.status = BetStatus.Push;
            // ROGUEBankroll doesn't have a separate push function — use winning with payout == bet
            IROGUEBankroll(rogueBankroll).settlePlinkoWinningBet(
                bet.player, commitmentHash, bet.amount, payout,
                bet.configIndex, landingPosition, path,
                bet.nonce, maxPayout
            );
        }

        // Reveal server seed
        commitments[commitmentHash].serverSeed = serverSeed;
        totalBetsSettled++;

        // Emit settlement events
        _emitSettlementEvents(
            commitmentHash, bet.player, bet.token, bet.amount,
            bet.configIndex, bet.nonce, bet.timestamp,
            payout, multiplierBps, landingPosition, path, serverSeed
        );
    }

    // ============ Bet Expiry ============

    /**
     * @notice Refund an expired bet (anyone can call after BET_EXPIRY)
     * @dev For BUX: BUXBankroll settles as a push (returns wager).
     *      For ROGUE: ROGUEBankroll returns wager.
     * @param commitmentHash Bet identifier
     */
    function refundExpiredBet(bytes32 commitmentHash) external nonReentrant {
        PlinkoBet storage bet = bets[commitmentHash];
        if (bet.player == address(0)) revert BetNotFound();
        if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
        if (block.timestamp <= bet.timestamp + BET_EXPIRY) revert BetNotExpired();

        bet.status = BetStatus.Expired;

        uint256 maxPayout = calculateMaxPayout(bet.amount, bet.configIndex);

        // Refund as push (return exact bet amount)
        uint8[] memory emptyPath = new uint8[](0);

        if (bet.token == buxToken) {
            IBUXBankroll(buxBankroll).settlePlinkoPushBet(
                bet.player, commitmentHash, bet.amount,
                bet.configIndex, 0, emptyPath,
                bet.nonce, maxPayout
            );
        } else {
            // ROGUE: settle as winning with payout == bet (returns exact amount)
            IROGUEBankroll(rogueBankroll).settlePlinkoWinningBet(
                bet.player, commitmentHash, bet.amount, bet.amount,
                bet.configIndex, 0, emptyPath,
                bet.nonce, maxPayout
            );
        }

        totalBetsSettled++;

        emit PlinkoBetExpired(commitmentHash, bet.player);
    }

    // ============ Admin Functions ============

    /**
     * @notice Set payout table for a config. Auto-updates maxMultiplierBps.
     * @param configIndex Config index (0-8)
     * @param multipliers Array of payout multipliers in basis points
     */
    function setPayoutTable(uint8 configIndex, uint32[] calldata multipliers) external onlyOwner {
        if (configIndex > 8) revert InvalidConfigIndex();
        require(multipliers.length == plinkoConfigs[configIndex].numPositions, "Wrong array length");

        // Verify symmetric: multipliers[i] == multipliers[n-1-i]
        uint256 n = multipliers.length;
        for (uint256 i = 0; i < n / 2; i++) {
            require(multipliers[i] == multipliers[n - 1 - i], "Payout table must be symmetric");
        }

        // Store payout table
        delete payoutTables[configIndex];
        uint32 maxMult = 0;
        for (uint256 i = 0; i < multipliers.length; i++) {
            payoutTables[configIndex].push(multipliers[i]);
            if (multipliers[i] > maxMult) {
                maxMult = multipliers[i];
            }
        }

        // Auto-update maxMultiplierBps
        plinkoConfigs[configIndex].maxMultiplierBps = maxMult;

        emit PayoutTableUpdated(configIndex, plinkoConfigs[configIndex].rows, plinkoConfigs[configIndex].riskLevel);
    }

    /**
     * @notice Configure a token (enable/disable for betting)
     * @param token Token address (buxToken for BUX)
     * @param enabled Whether the token is enabled
     */
    function configureToken(address token, bool enabled) external onlyOwner {
        tokenConfigs[token] = TokenConfig({enabled: enabled});
        emit TokenConfigured(token, enabled);
    }

    function setSettler(address _settler) external onlyOwner {
        settler = _settler;
    }

    function setROGUEBankroll(address _rogueBankroll) external onlyOwner {
        rogueBankroll = _rogueBankroll;
    }

    function setBUXBankroll(address _buxBankroll) external onlyOwner {
        buxBankroll = _buxBankroll;
    }

    function setBUXToken(address _buxToken) external onlyOwner {
        buxToken = _buxToken;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============ View Functions ============

    /**
     * @notice Get a bet by commitment hash
     */
    function getBet(bytes32 commitmentHash) external view returns (PlinkoBet memory) {
        return bets[commitmentHash];
    }

    /**
     * @notice Get payout table for a config
     */
    function getPayoutTable(uint8 configIndex) external view returns (uint32[] memory) {
        return payoutTables[configIndex];
    }

    /**
     * @notice Get Plinko config
     */
    function getPlinkoConfig(uint8 configIndex) external view returns (PlinkoConfig memory) {
        return plinkoConfigs[configIndex];
    }

    /**
     * @notice Get commitment details
     */
    function getCommitment(bytes32 commitmentHash) external view returns (Commitment memory) {
        return commitments[commitmentHash];
    }

    /**
     * @notice Get max BUX bet for a config (queries BUXBankroll)
     */
    function getMaxBet(uint8 configIndex) external view returns (uint256) {
        if (configIndex > 8) revert InvalidConfigIndex();
        if (plinkoConfigs[configIndex].maxMultiplierBps == 0) return 0;
        return IBUXBankroll(buxBankroll).getMaxBet(configIndex, plinkoConfigs[configIndex].maxMultiplierBps);
    }

    /**
     * @notice Get max ROGUE bet for a config (queries ROGUEBankroll)
     */
    function getMaxBetROGUE(uint8 configIndex) external view returns (uint256) {
        if (configIndex > 8) revert InvalidConfigIndex();
        (, , , uint256 maxBetFromBankroll) = IROGUEBankroll(rogueBankroll).getHouseInfo();
        return maxBetFromBankroll;
    }

    /**
     * @notice Calculate maximum possible payout for a bet
     * @param amount Bet amount
     * @param configIndex Config index (0-8)
     * @return maxPayout Maximum payout (amount * maxMultiplier / 10000)
     */
    function calculateMaxPayout(uint256 amount, uint8 configIndex) public view returns (uint256) {
        return (amount * uint256(plinkoConfigs[configIndex].maxMultiplierBps)) / MULTIPLIER_DENOMINATOR;
    }

    /**
     * @notice Get player's bet history (paginated)
     * @param player Player address
     * @param offset Starting index
     * @param limit Max number of bets to return
     */
    function getPlayerBetHistory(
        address player,
        uint256 offset,
        uint256 limit
    ) external view returns (bytes32[] memory) {
        bytes32[] storage history = playerBetHistory[player];
        uint256 total = history.length;

        if (offset >= total) {
            return new bytes32[](0);
        }

        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 count = end - offset;

        bytes32[] memory result = new bytes32[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = history[offset + i];
        }
        return result;
    }

    // ============ Internal Functions ============

    function _validateCommitment(bytes32 commitmentHash) internal {
        Commitment storage commitment = commitments[commitmentHash];
        if (commitment.player == address(0)) revert CommitmentNotFound();
        if (commitment.used) revert CommitmentAlreadyUsed();
        if (commitment.player != msg.sender) revert CommitmentWrongPlayer();
        commitment.used = true;
    }

    function _validatePath(
        uint8[] calldata path,
        uint8 landingPosition,
        uint8 configIndex
    ) internal view {
        uint8 rows = plinkoConfigs[configIndex].rows;
        if (path.length != rows) revert InvalidPath();

        uint8 rightCount = 0;
        for (uint8 i = 0; i < path.length; i++) {
            if (path[i] != 0 && path[i] != 1) revert InvalidPath();
            if (path[i] == 1) rightCount++;
        }

        if (rightCount != landingPosition) revert InvalidLandingPosition();
        if (landingPosition >= plinkoConfigs[configIndex].numPositions) revert InvalidLandingPosition();
    }

    function _createBet(
        address token,
        uint256 amount,
        uint8 configIndex,
        bytes32 commitmentHash,
        uint256 nonce
    ) internal {
        bets[commitmentHash] = PlinkoBet({
            player: msg.sender,
            token: token,
            amount: amount,
            configIndex: configIndex,
            commitmentHash: commitmentHash,
            nonce: nonce,
            timestamp: block.timestamp,
            status: BetStatus.Pending
        });

        playerBetHistory[msg.sender].push(commitmentHash);
        totalBetsPlaced++;

        PlinkoConfig memory config = plinkoConfigs[configIndex];
        emit PlinkoBetPlaced(
            commitmentHash, msg.sender, token, amount,
            configIndex, config.rows, config.riskLevel, nonce
        );
    }

    /**
     * @dev Emit all settlement events. Split into helper to avoid stack-too-deep.
     */
    function _emitSettlementEvents(
        bytes32 commitmentHash,
        address player,
        address token,
        uint256 amount,
        uint8 configIndex,
        uint256 nonce,
        uint256 timestamp,
        uint256 payout,
        uint32 multiplierBps,
        uint8 landingPosition,
        uint8[] calldata path,
        bytes32 serverSeed
    ) internal {
        bool profited = payout > amount;
        int256 profitLoss = int256(payout) - int256(amount);

        emit PlinkoBetSettled(
            commitmentHash, player, profited,
            landingPosition, multiplierBps,
            amount, payout, profitLoss, serverSeed
        );

        string memory configLabel = _getConfigLabel(configIndex);
        emit PlinkoBallPath(
            commitmentHash, configIndex, path,
            landingPosition, configLabel
        );

        emit PlinkoBetDetails(
            commitmentHash, token, amount,
            configIndex, nonce, timestamp
        );
    }

    /**
     * @dev Returns human-readable config label for events
     */
    function _getConfigLabel(uint8 configIndex) internal pure returns (string memory) {
        if (configIndex == 0) return "8-Low";
        if (configIndex == 1) return "8-Medium";
        if (configIndex == 2) return "8-High";
        if (configIndex == 3) return "12-Low";
        if (configIndex == 4) return "12-Medium";
        if (configIndex == 5) return "12-High";
        if (configIndex == 6) return "16-Low";
        if (configIndex == 7) return "16-Medium";
        if (configIndex == 8) return "16-High";
        return "Unknown";
    }
}
