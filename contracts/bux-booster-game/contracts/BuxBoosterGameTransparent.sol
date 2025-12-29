// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BuxBoosterGameTransparent
 * @notice On-chain provably fair coin flip game (Transparent Proxy version)
 * @dev Uses OpenZeppelin's Transparent Proxy pattern instead of UUPS.
 *      Supports 9 difficulty levels (-4 to 5).
 *
 * GAME RULES:
 * - Win One Mode (difficulty -4 to -1): Player wins if ANY flip matches prediction
 * - Win All Mode (difficulty 1 to 5): Player must get ALL flips correct
 * - Multipliers include house edge
 * - Max bet = 0.1% of house balance, scaled by multiplier
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
}

// ============ ContextUpgradeable ============

abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {}

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
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }
        _status = ENTERED;
        _;
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
        _paused = false;
    }

    modifier whenNotPaused() {
        if (_paused) revert EnforcedPause();
        _;
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _pause() internal virtual {
        _paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal virtual {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

// ============================================================
// ===================== MAIN CONTRACT ========================
// ============================================================

contract BuxBoosterGameTransparent is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
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
        int8 difficulty;
        uint8[] predictions;
        bytes32 commitmentHash;
        uint256 nonce;
        uint256 timestamp;
        BetStatus status;
    }

    struct Commitment {
        address player;
        uint256 nonce;
        uint256 timestamp;
        bool used;
        bytes32 serverSeed;
    }

    enum BetStatus { Pending, Won, Lost, Expired }

    // ============ Constants ============

    uint8 constant MODE_WIN_ALL = 0;
    uint8 constant MODE_WIN_ONE = 1;
    uint256 public constant BET_EXPIRY = 1 hours;
    uint256 public constant MIN_BET = 1e18;
    uint256 public constant MAX_BET_BPS = 10;

    // ============ State Variables ============

    // Multipliers stored in state (initialized in initialize())
    uint32[9] public MULTIPLIERS;
    uint8[9] public FLIP_COUNTS;
    uint8[9] public GAME_MODES;

    mapping(address => TokenConfig) public tokenConfigs;
    mapping(bytes32 => Bet) public bets;
    mapping(address => uint256) public playerNonces;
    mapping(address => bytes32[]) public playerBetHistory;
    mapping(bytes32 => Commitment) public commitments;
    mapping(address => mapping(uint256 => bytes32)) public playerCommitments;

    address public settler;
    uint256 public totalBetsPlaced;
    uint256 public totalBetsSettled;

    // ============ Events ============

    event TokenConfigured(address indexed token, bool enabled);
    event CommitmentSubmitted(bytes32 indexed commitmentHash, address indexed player, uint256 nonce);
    event BetPlaced(bytes32 indexed betId, address indexed player, address indexed token, uint256 amount, int8 difficulty, uint8[] predictions, bytes32 commitmentHash, uint256 nonce);
    event BetSettled(bytes32 indexed betId, address indexed player, bool won, uint8[] results, uint256 payout, bytes32 serverSeed);
    event BetExpired(bytes32 indexed betId, address indexed player);
    event HouseDeposit(address indexed token, uint256 amount);
    event HouseWithdraw(address indexed token, uint256 amount);

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

    // ============ Modifiers ============

    modifier onlySettler() {
        if (msg.sender != settler && msg.sender != owner()) {
            revert UnauthorizedSettler();
        }
        _;
    }

    // ============ Constructor & Initializer ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();

        // Initialize multipliers
        MULTIPLIERS = [10200, 10500, 11300, 13200, 19800, 39600, 79200, 158400, 316800];
        FLIP_COUNTS = [5, 4, 3, 2, 1, 2, 3, 4, 5];
        GAME_MODES = [MODE_WIN_ONE, MODE_WIN_ONE, MODE_WIN_ONE, MODE_WIN_ONE, MODE_WIN_ALL, MODE_WIN_ALL, MODE_WIN_ALL, MODE_WIN_ALL, MODE_WIN_ALL];
    }

    // ============ Settler Functions ============

    function submitCommitment(bytes32 commitmentHash, address player, uint256 nonce) external onlySettler {
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

    // ============ Player Functions ============

    function placeBet(
        address token,
        uint256 amount,
        int8 difficulty,
        uint8[] calldata predictions,
        bytes32 commitmentHash
    ) external nonReentrant whenNotPaused returns (bytes32 betId) {
        // Validate commitment in separate function to reduce stack usage
        _validateCommitment(commitmentHash);

        // Validate bet params and get diffIndex
        uint8 diffIndex = _validateBetParams(token, amount, difficulty, predictions);

        // Transfer tokens
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Create bet and store it
        betId = _createBet(token, amount, difficulty, predictions, commitmentHash, diffIndex);
    }

    function _validateCommitment(bytes32 commitmentHash) internal {
        Commitment storage commitment = commitments[commitmentHash];
        if (commitment.player == address(0)) revert CommitmentNotFound();
        if (commitment.used) revert CommitmentAlreadyUsed();
        if (commitment.player != msg.sender) revert CommitmentWrongPlayer();
        if (commitment.nonce != playerNonces[msg.sender]) revert CommitmentWrongNonce();
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

    function _createBet(
        address token,
        uint256 amount,
        int8 difficulty,
        uint8[] calldata predictions,
        bytes32 commitmentHash,
        uint8 diffIndex
    ) internal returns (bytes32 betId) {
        uint256 nonce = playerNonces[msg.sender]++;
        betId = keccak256(abi.encodePacked(msg.sender, token, nonce, block.timestamp));

        bets[betId] = Bet({
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

        playerBetHistory[msg.sender].push(betId);
        totalBetsPlaced++;

        emit BetPlaced(betId, msg.sender, token, amount, difficulty, predictions, commitmentHash, nonce);
    }

    function settleBet(bytes32 betId, bytes32 serverSeed) external onlySettler nonReentrant returns (bool won, uint8[] memory results, uint256 payout) {
        Bet storage bet = bets[betId];

        if (bet.player == address(0)) revert BetNotFound();
        if (bet.status != BetStatus.Pending) revert BetAlreadySettled();
        if (block.timestamp > bet.timestamp + BET_EXPIRY) revert BetExpiredError();

        bytes32 computedHash = sha256(abi.encodePacked(serverSeed));
        if (computedHash != bet.commitmentHash) revert InvalidServerSeed();

        commitments[bet.commitmentHash].serverSeed = serverSeed;

        bytes32 clientSeed = _generateClientSeed(bet);
        bytes32 combinedSeed = sha256(abi.encodePacked(serverSeed, ":", clientSeed, ":", bet.nonce));

        results = _generateResults(combinedSeed, bet.predictions.length);

        uint8 diffIndex = bet.difficulty < 0 ? uint8(int8(4) + bet.difficulty) : uint8(int8(3) + bet.difficulty);

        won = _checkWin(bet.predictions, results, GAME_MODES[diffIndex]);

        TokenConfig storage config = tokenConfigs[bet.token];

        if (won) {
            payout = (bet.amount * MULTIPLIERS[diffIndex]) / 10000;
            bet.status = BetStatus.Won;
            uint256 profit = payout - bet.amount;
            config.houseBalance -= profit;
            IERC20(bet.token).safeTransfer(bet.player, payout);
        } else {
            payout = 0;
            bet.status = BetStatus.Lost;
            config.houseBalance += bet.amount;
        }

        totalBetsSettled++;
        emit BetSettled(betId, bet.player, won, results, payout, serverSeed);
    }

    // ============ View Functions ============

    function getMaxBet(address token, int8 difficulty) external view returns (uint256) {
        if (difficulty == 0 || difficulty < -4 || difficulty > 5) return 0;
        uint8 diffIndex = difficulty < 0 ? uint8(int8(4) + difficulty) : uint8(int8(3) + difficulty);
        return _calculateMaxBet(tokenConfigs[token].houseBalance, diffIndex);
    }

    function getPlayerCurrentCommitment(address player) external view returns (bytes32 commitmentHash, uint256 nonce, uint256 timestamp, bool used) {
        nonce = playerNonces[player];
        commitmentHash = playerCommitments[player][nonce];
        if (commitmentHash != bytes32(0)) {
            Commitment storage c = commitments[commitmentHash];
            return (commitmentHash, c.nonce, c.timestamp, c.used);
        }
        return (bytes32(0), nonce, 0, false);
    }

    // ============ Admin Functions ============

    function configureToken(address token, bool enabled) external onlyOwner {
        tokenConfigs[token].enabled = enabled;
        emit TokenConfigured(token, enabled);
    }

    function depositHouseBalance(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        tokenConfigs[token].houseBalance += amount;
        emit HouseDeposit(token, amount);
    }

    function withdrawHouseBalance(address token, uint256 amount) external onlyOwner {
        TokenConfig storage config = tokenConfigs[token];
        require(amount <= config.houseBalance, "Insufficient balance");
        config.houseBalance -= amount;
        IERC20(token).safeTransfer(owner(), amount);
        emit HouseWithdraw(token, amount);
    }

    function setSettler(address _settler) external onlyOwner {
        settler = _settler;
    }


    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

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

    function _calculateMaxBet(uint256 houseBalance, uint8 diffIndex) internal view returns (uint256) {
        if (houseBalance == 0) return 0;
        uint256 baseMaxBet = (houseBalance * MAX_BET_BPS) / 10000;
        uint256 multiplier = MULTIPLIERS[diffIndex];
        return (baseMaxBet * 20000) / multiplier;
    }

    function _generateClientSeed(Bet storage bet) internal view returns (bytes32) {
        // Use raw bytes instead of string conversion to reduce bytecode
        return sha256(abi.encodePacked(
            bet.player,
            bet.amount,
            bet.token,
            bet.difficulty,
            bet.predictions
        ));
    }

    function _generateResults(bytes32 combinedSeed, uint256 numFlips) internal pure returns (uint8[] memory) {
        uint8[] memory results = new uint8[](numFlips);
        for (uint i = 0; i < numFlips; i++) {
            results[i] = uint8(combinedSeed[i]) < 128 ? 0 : 1;
        }
        return results;
    }

    function _checkWin(uint8[] storage predictions, uint8[] memory results, uint8 mode) internal view returns (bool) {
        if (mode == MODE_WIN_ONE) {
            for (uint i = 0; i < predictions.length; i++) {
                if (predictions[i] == results[i]) return true;
            }
            return false;
        } else {
            for (uint i = 0; i < predictions.length; i++) {
                if (predictions[i] != results[i]) return false;
            }
            return true;
        }
    }
}
