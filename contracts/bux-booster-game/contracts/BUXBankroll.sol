// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title BUXBankroll
 * @notice ERC-20 LP token bankroll that holds all BUX house funds for Plinko (and future BUX games).
 * @dev UUPS Upgradeable contract. Users deposit BUX to receive LP-BUX tokens and share in house
 *      profit/loss. Authorized game contracts call settlement functions to pay winners from the pool.
 *
 * LP PRICING:
 * - Deposit: uses effectiveBalance = totalBalance - unsettledBets (fair pricing, ignoring in-flight bets)
 * - Withdrawal: uses netBalance = totalBalance - liability (safety, reserving worst-case payouts)
 * - After all bets settle, both converge to totalBalance.
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

// ============ IERC20Upgradeable (for LP token) ============

interface IERC20Upgradeable {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

// ============ IERC20MetadataUpgradeable ============

interface IERC20MetadataUpgradeable is IERC20Upgradeable {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

// ============ ERC20Upgradeable ============

contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    function __ERC20_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal onlyInitializing {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner_ = _msgSender();
        _transfer(owner_, to, amount);
        return true;
    }

    function allowance(address owner_, address spender) public view virtual override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner_ = _msgSender();
        _approve(owner_, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner_ = _msgSender();
        _approve(owner_, spender, allowance(owner_, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner_ = _msgSender();
        uint256 currentAllowance = allowance(owner_, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner_, spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal virtual {
        require(owner_ != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _spendAllowance(address owner_, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner_, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner_, spender, currentAllowance - amount);
            }
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
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

contract BUXBankroll is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ERC20Upgradeable
{
    using SafeERC20 for IERC20;

    // ============ Structs ============

    struct HouseBalance {
        uint256 totalBalance;       // Total BUX held (deposits + bet wagers)
        uint256 liability;          // Outstanding max payouts for active bets
        uint256 unsettledBets;      // Sum of wager amounts for unsettled bets
        uint256 netBalance;         // totalBalance - liability (available for new bets/withdrawals)
        uint256 poolTokenSupply;    // Cached LP-BUX totalSupply()
        uint256 poolTokenPrice;     // Cached LP price (18 decimals precision)
    }

    struct PlinkoPlayerStats {
        uint256 totalBets;
        uint256 wins;
        uint256 losses;
        uint256 pushes;
        uint256 totalWagered;
        uint256 totalWinnings;
        uint256 totalLosses;
    }

    struct PlinkoAccounting {
        uint256 totalBets;
        uint256 totalWins;
        uint256 totalLosses;
        uint256 totalPushes;
        uint256 totalVolumeWagered;
        uint256 totalPayouts;
        int256 totalHouseProfit;
        uint256 largestWin;
        uint256 largestBet;
    }

    // ============ Constants ============

    uint256 public constant MAX_BET_BPS = 10;  // 0.1% of net balance
    uint256 public constant MULTIPLIER_DENOMINATOR = 10000;

    // ============ Custom Errors ============

    error UnauthorizedGame();
    error InsufficientBalance();
    error InsufficientLiquidity();
    error ZeroAmount();
    error ZeroAddress();
    error TransferFailed();

    // ============ Events ============

    // LP Token
    event BUXDeposited(address indexed depositor, uint256 amountBUX, uint256 amountLP);
    event BUXWithdrawn(address indexed withdrawer, uint256 amountBUX, uint256 amountLP);
    event PoolPriceUpdated(uint256 newPrice, uint256 totalBalance, uint256 totalSupply, uint256 timestamp);

    // Plinko Game
    event PlinkoBetPlaced(
        address indexed player,
        bytes32 indexed commitmentHash,
        uint256 amount,
        uint8 configIndex,
        uint256 nonce,
        uint256 timestamp
    );
    event PlinkoWinningPayout(
        address indexed winner,
        bytes32 indexed commitmentHash,
        uint256 betAmount,
        uint256 payout,
        uint256 profit
    );
    event PlinkoWinDetails(
        bytes32 indexed commitmentHash,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] path,
        uint256 nonce
    );
    event PlinkoLosingBet(
        address indexed player,
        bytes32 indexed commitmentHash,
        uint256 wagerAmount,
        uint256 partialPayout
    );
    event PlinkoLossDetails(
        bytes32 indexed commitmentHash,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] path,
        uint256 nonce
    );
    event PlinkoPayoutFailed(
        address indexed winner,
        bytes32 indexed commitmentHash,
        uint256 payout
    );

    // Referrals
    event ReferralRewardPaid(
        bytes32 indexed commitmentHash,
        address indexed referrer,
        address indexed player,
        uint256 amount
    );
    event ReferrerSet(address indexed player, address indexed referrer);

    // Admin
    event GameAuthorized(address indexed game, bool authorized);
    event MaxBetDivisorChanged(uint256 oldDivisor, uint256 newDivisor);
    event ReferralBasisPointsChanged(uint256 previousBasisPoints, uint256 newBasisPoints);
    event ReferralAdminChanged(address indexed previousAdmin, address indexed newAdmin);

    // ============ Storage Layout (UUPS — only add at END) ============
    // Inherited: _initialized (uint64), _initializing (bool), _owner (address),
    //            _status (uint256 reentrancy), _paused (bool)
    // Inherited ERC20: _balances, _allowances, _totalSupply, _name, _symbol

    address public buxToken;                                        // BUX ERC-20 contract address
    HouseBalance public houseBalance;                               // Pool accounting
    uint256 public maximumBetSizeDivisor;                           // Default 1000 (0.1%)

    // Game authorization
    address public plinkoGame;                                      // Authorized Plinko contract
    // address public buxBoosterGame;                               // Future: authorize BuxBooster

    // Plinko stats
    mapping(address => PlinkoPlayerStats) public plinkoPlayerStats;
    PlinkoAccounting public plinkoAccounting;
    mapping(address => uint256[9]) public plinkoBetsPerConfig;
    mapping(address => int256[9]) public plinkoPnLPerConfig;

    // Referral system (shared across all games)
    uint256 public referralBasisPoints;                             // e.g. 20 = 0.2%
    mapping(address => address) public playerReferrers;
    uint256 public totalReferralRewardsPaid;
    mapping(address => uint256) public referrerTotalEarnings;
    address public referralAdmin;

    // Price history (for chart snapshots)
    uint256 public lastPriceSnapshotTime;

    // ============ Modifiers ============

    modifier onlyPlinko() {
        if (msg.sender != plinkoGame) {
            revert UnauthorizedGame();
        }
        _;
    }

    // ============ Constructor (UUPS) ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initialization ============

    function initialize(address _buxToken) public initializer {
        if (_buxToken == address(0)) {
            revert ZeroAddress();
        }

        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        __ERC20_init("BUX Bankroll", "LP-BUX");

        buxToken = _buxToken;
        maximumBetSizeDivisor = 1000;       // 0.1% max bet
        houseBalance.poolTokenPrice = 1e18; // Initial 1:1
        referralBasisPoints = 20;            // 0.2% referral rate on losing bets
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ LP Token Functions (Public) ============

    /**
     * @notice Deposit BUX and receive LP-BUX tokens. Caller must approve BUXBankroll first.
     * @dev Uses effectiveBalance (totalBalance - unsettledBets) for LP pricing to avoid
     *      dilution from unrealized bets.
     * @param amount Amount of BUX to deposit
     */
    function depositBUX(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 lpMinted;
        uint256 supply = totalSupply();

        if (supply == 0) {
            lpMinted = amount;  // 1:1 for first deposit
        } else {
            // Use (totalBalance - unsettledBets) as the "real" pool value for LP pricing.
            // unsettledBets are wager amounts that haven't been settled yet — they inflate
            // totalBalance but aren't realized profit/loss.
            uint256 effectiveBalance = houseBalance.totalBalance - houseBalance.unsettledBets;
            if (effectiveBalance == 0) {
                lpMinted = amount;  // Edge case: all balance is unsettled
            } else {
                lpMinted = (amount * supply) / effectiveBalance;
            }
        }

        // Transfer BUX from depositor to this contract
        IERC20(buxToken).safeTransferFrom(msg.sender, address(this), amount);

        // Mint LP tokens to depositor
        _mint(msg.sender, lpMinted);

        // Update house balance
        houseBalance.totalBalance += amount;
        _recalculateHouseBalance();

        emit BUXDeposited(msg.sender, amount, lpMinted);
        emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);
    }

    /**
     * @notice Withdraw BUX by burning LP-BUX tokens.
     * @dev Uses netBalance (totalBalance - liability) to ensure withdrawals
     *      cannot drain funds needed for outstanding bet payouts.
     * @param lpAmount Amount of LP-BUX to burn
     */
    function withdrawBUX(uint256 lpAmount) external nonReentrant whenNotPaused {
        if (lpAmount == 0) {
            revert ZeroAmount();
        }
        if (balanceOf(msg.sender) < lpAmount) {
            revert InsufficientBalance();
        }

        uint256 supply = totalSupply();
        // Withdrawable amount based on net balance (respects outstanding liabilities)
        uint256 buxOut = (lpAmount * houseBalance.netBalance) / supply;
        if (buxOut > houseBalance.netBalance) {
            revert InsufficientLiquidity();
        }

        // Burn LP tokens first (checks-effects-interactions)
        _burn(msg.sender, lpAmount);

        // Transfer BUX to withdrawer
        IERC20(buxToken).safeTransfer(msg.sender, buxOut);

        // Update house balance
        houseBalance.totalBalance -= buxOut;
        _recalculateHouseBalance();

        emit BUXWithdrawn(msg.sender, buxOut, lpAmount);
        emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);
    }

    // ============ Game Integration — Plinko (onlyPlinko) ============

    /**
     * @notice Called by PlinkoGame when player places a BUX bet.
     *         BUX is transferred from player to BUXBankroll by PlinkoGame before calling this.
     * @param commitmentHash Bet identifier
     * @param player Player address
     * @param wagerAmount Amount of BUX wagered
     * @param configIndex Plinko config (0-8)
     * @param nonce Player's nonce
     * @param maxPayout Maximum possible payout based on max multiplier
     * @return success True if update succeeded
     */
    function updateHouseBalancePlinkoBetPlaced(
        bytes32 commitmentHash,
        address player,
        uint256 wagerAmount,
        uint8 configIndex,
        uint256 nonce,
        uint256 maxPayout
    ) external onlyPlinko returns (bool) {
        houseBalance.totalBalance += wagerAmount;
        houseBalance.liability += maxPayout;
        houseBalance.unsettledBets += wagerAmount;
        _recalculateHouseBalance();

        emit PlinkoBetPlaced(player, commitmentHash, wagerAmount, configIndex, nonce, block.timestamp);
        return true;
    }

    /**
     * @notice Settle a winning Plinko bet. Sends payout to winner.
     * @param winner Player who won
     * @param commitmentHash Bet identifier
     * @param betAmount Original wager
     * @param payout Total payout (betAmount + profit)
     * @param configIndex Plinko config (0-8)
     * @param landingPosition Slot ball landed in
     * @param path Ball path array
     * @param nonce Player's nonce
     * @param maxPayout Max possible payout (for liability release)
     * @return success True if settlement succeeded
     */
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
    ) external onlyPlinko nonReentrant returns (bool) {
        uint256 profit = payout - betAmount;

        // Transfer payout to winner
        IERC20(buxToken).safeTransfer(winner, payout);

        // Update house balance
        houseBalance.totalBalance -= payout;
        houseBalance.liability -= maxPayout;
        houseBalance.unsettledBets -= betAmount;
        _recalculateHouseBalance();

        // Update stats
        _updatePlinkoStatsWin(winner, betAmount, profit, configIndex);

        emit PlinkoWinningPayout(winner, commitmentHash, betAmount, payout, profit);
        emit PlinkoWinDetails(commitmentHash, configIndex, landingPosition, path, nonce);
        emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);

        return true;
    }

    /**
     * @notice Settle a losing Plinko bet. House keeps BUX. Sends partial payout if multiplier > 0.
     * @param player Player who lost
     * @param commitmentHash Bet identifier
     * @param wagerAmount Original wager
     * @param partialPayout Amount to return (0 for 0x multiplier, or partial for < 1x)
     * @param configIndex Plinko config (0-8)
     * @param landingPosition Slot ball landed in
     * @param path Ball path array
     * @param nonce Player's nonce
     * @param maxPayout Max possible payout (for liability release)
     * @return success True if settlement succeeded
     */
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
    ) external onlyPlinko nonReentrant returns (bool) {
        // Send partial payout if > 0 (e.g. 0.3x on a loss)
        if (partialPayout > 0) {
            IERC20(buxToken).safeTransfer(player, partialPayout);
            houseBalance.totalBalance -= partialPayout;
        }

        // Release liability
        houseBalance.liability -= maxPayout;
        houseBalance.unsettledBets -= wagerAmount;
        _recalculateHouseBalance();

        // Update stats
        uint256 lossAmount = wagerAmount - partialPayout;
        _updatePlinkoStatsLoss(player, wagerAmount, lossAmount, configIndex);

        // Referral reward on loss portion (non-blocking)
        if (lossAmount > 0) {
            _sendReferralReward(commitmentHash, player, lossAmount);
        }

        emit PlinkoLosingBet(player, commitmentHash, wagerAmount, partialPayout);
        emit PlinkoLossDetails(commitmentHash, configIndex, landingPosition, path, nonce);
        emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);

        return true;
    }

    /**
     * @notice Settle a push (payout == bet). Return exact amount, no house movement.
     * @param player Player
     * @param commitmentHash Bet identifier
     * @param betAmount Original wager (returned exactly)
     * @param configIndex Plinko config (0-8)
     * @param landingPosition Slot ball landed in
     * @param path Ball path array
     * @param nonce Player's nonce
     * @param maxPayout Max possible payout (for liability release)
     * @return success True if settlement succeeded
     */
    function settlePlinkoPushBet(
        address player,
        bytes32 commitmentHash,
        uint256 betAmount,
        uint8 configIndex,
        uint8 landingPosition,
        uint8[] calldata path,
        uint256 nonce,
        uint256 maxPayout
    ) external onlyPlinko nonReentrant returns (bool) {
        // Return exact bet amount
        IERC20(buxToken).safeTransfer(player, betAmount);

        // Update house balance
        houseBalance.totalBalance -= betAmount;
        houseBalance.liability -= maxPayout;
        houseBalance.unsettledBets -= betAmount;
        _recalculateHouseBalance();

        // Update stats (push)
        plinkoPlayerStats[player].totalBets++;
        plinkoPlayerStats[player].pushes++;
        plinkoPlayerStats[player].totalWagered += betAmount;
        plinkoBetsPerConfig[player][configIndex]++;
        plinkoAccounting.totalBets++;
        plinkoAccounting.totalPushes++;
        plinkoAccounting.totalVolumeWagered += betAmount;

        emit PoolPriceUpdated(houseBalance.poolTokenPrice, houseBalance.totalBalance, totalSupply(), block.timestamp);

        return true;
    }

    // ============ View Functions ============

    /**
     * @notice Get comprehensive house balance info
     */
    function getHouseInfo() external view returns (
        uint256 totalBalance_,
        uint256 liability_,
        uint256 unsettledBets_,
        uint256 netBalance_,
        uint256 poolTokenSupply_,
        uint256 poolTokenPrice_
    ) {
        return (
            houseBalance.totalBalance,
            houseBalance.liability,
            houseBalance.unsettledBets,
            houseBalance.netBalance,
            houseBalance.poolTokenSupply,
            houseBalance.poolTokenPrice
        );
    }

    /**
     * @notice Get current LP-BUX price (18 decimals, 1e18 = 1:1)
     */
    function getLPPrice() external view returns (uint256) {
        return houseBalance.poolTokenPrice;
    }

    /**
     * @notice Get max allowed BUX bet for a given Plinko config
     * @param configIndex Plinko config (0-8) — unused here but kept for interface consistency
     * @param maxMultiplierBps Highest multiplier in the config's payout table
     * @return maxBet Maximum BUX bet amount
     */
    function getMaxBet(uint8 configIndex, uint32 maxMultiplierBps) external view returns (uint256) {
        // Suppress unused parameter warning
        configIndex;
        if (houseBalance.netBalance == 0 || maxMultiplierBps == 0) {
            return 0;
        }
        // baseMaxBet = 0.1% of net balance
        uint256 baseMaxBet = (houseBalance.netBalance * MAX_BET_BPS) / 10000;
        // Scale down by multiplier: higher multiplier = smaller max bet
        // 20000 is 2x in basis points (bet + winnings). For a 5.6x multiplier (56000 bps),
        // maxBet = baseMaxBet * 20000 / 56000
        return (baseMaxBet * 20000) / uint256(maxMultiplierBps);
    }

    /**
     * @notice Get Plinko global accounting
     */
    function getPlinkoAccounting() external view returns (
        uint256 totalBets_,
        uint256 totalWins_,
        uint256 totalLosses_,
        uint256 totalPushes_,
        uint256 totalVolumeWagered_,
        uint256 totalPayouts_,
        int256 totalHouseProfit_,
        uint256 largestWin_,
        uint256 largestBet_,
        uint256 winRate,
        int256 houseEdge
    ) {
        PlinkoAccounting storage acc = plinkoAccounting;

        totalBets_ = acc.totalBets;
        totalWins_ = acc.totalWins;
        totalLosses_ = acc.totalLosses;
        totalPushes_ = acc.totalPushes;
        totalVolumeWagered_ = acc.totalVolumeWagered;
        totalPayouts_ = acc.totalPayouts;
        totalHouseProfit_ = acc.totalHouseProfit;
        largestWin_ = acc.largestWin;
        largestBet_ = acc.largestBet;

        if (acc.totalBets > 0) {
            winRate = (acc.totalWins * 10000) / acc.totalBets;
        }

        if (acc.totalVolumeWagered > 0) {
            houseEdge = (acc.totalHouseProfit * 10000) / int256(acc.totalVolumeWagered);
        }
    }

    /**
     * @notice Get full Plinko player stats including per-config breakdown
     * @param player Player address to query
     */
    function getPlinkoPlayerStats(address player) external view returns (
        uint256 totalBets_,
        uint256 wins_,
        uint256 losses_,
        uint256 pushes_,
        uint256 totalWagered_,
        uint256 totalWinnings_,
        uint256 totalLosses_,
        uint256[9] memory betsPerConfig,
        int256[9] memory pnlPerConfig
    ) {
        PlinkoPlayerStats storage stats = plinkoPlayerStats[player];

        totalBets_ = stats.totalBets;
        wins_ = stats.wins;
        losses_ = stats.losses;
        pushes_ = stats.pushes;
        totalWagered_ = stats.totalWagered;
        totalWinnings_ = stats.totalWinnings;
        totalLosses_ = stats.totalLosses;
        betsPerConfig = plinkoBetsPerConfig[player];
        pnlPerConfig = plinkoPnLPerConfig[player];
    }

    /**
     * @notice Get per-config bet counts for a player
     */
    function getPlinkoBetsPerConfig(address player) external view returns (uint256[9] memory) {
        return plinkoBetsPerConfig[player];
    }

    /**
     * @notice Get per-config P/L for a player (signed)
     */
    function getPlinkoPnLPerConfig(address player) external view returns (int256[9] memory) {
        return plinkoPnLPerConfig[player];
    }

    // ============ Admin Functions ============

    /**
     * @notice Set the authorized Plinko game contract
     * @param _plinkoGame Address of PlinkoGame proxy
     */
    function setPlinkoGame(address _plinkoGame) external onlyOwner {
        emit GameAuthorized(_plinkoGame, true);
        plinkoGame = _plinkoGame;
    }

    /**
     * @notice Set the maximum bet size divisor
     * @dev Divisor of 1000 means max bet = 0.1% of net balance
     * @param _divisor New divisor value (must be > 0)
     */
    function setMaxBetDivisor(uint256 _divisor) external onlyOwner {
        require(_divisor > 0, "Divisor must be > 0");
        emit MaxBetDivisorChanged(maximumBetSizeDivisor, _divisor);
        maximumBetSizeDivisor = _divisor;
    }

    /**
     * @notice Set referral reward rate in basis points
     * @param _bps New basis points (max 1000 = 10%)
     */
    function setReferralBasisPoints(uint256 _bps) external onlyOwner {
        require(_bps <= 1000, "Basis points cannot exceed 10%");
        emit ReferralBasisPointsChanged(referralBasisPoints, _bps);
        referralBasisPoints = _bps;
    }

    /**
     * @notice Set the referral admin address
     * @param _admin New admin address (e.g., BuxMinter service wallet)
     */
    function setReferralAdmin(address _admin) external onlyOwner {
        emit ReferralAdminChanged(referralAdmin, _admin);
        referralAdmin = _admin;
    }

    /**
     * @notice Set a player's referrer (can only be set once)
     * @param player Player's smart wallet address
     * @param referrer Referrer's smart wallet address
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
     * @notice Batch set multiple player referrers
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
            if (
                playerReferrers[players[i]] == address(0) &&
                referrers[i] != address(0) &&
                players[i] != referrers[i]
            ) {
                playerReferrers[players[i]] = referrers[i];
                emit ReferrerSet(players[i], referrers[i]);
            }
        }
    }

    /**
     * @notice Emergency withdraw BUX from pool (owner only, for emergencies)
     * @param amount Amount of BUX to withdraw
     */
    function emergencyWithdrawBUX(uint256 amount) external onlyOwner {
        IERC20(buxToken).safeTransfer(msg.sender, amount);
        houseBalance.totalBalance -= amount;
        _recalculateHouseBalance();
    }

    /**
     * @notice Pause deposits and withdrawals
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause deposits and withdrawals
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Accept native token (ROGUE) sent to this contract. Not expected, but safe to include.
    receive() external payable {}

    // ============ Internal Functions ============

    /**
     * @dev Recalculate derived house balance fields after any change.
     *      netBalance = totalBalance - liability
     *      poolTokenPrice = (totalBalance - unsettledBets) * 1e18 / supply
     */
    function _recalculateHouseBalance() internal {
        houseBalance.netBalance = houseBalance.totalBalance - houseBalance.liability;
        houseBalance.poolTokenSupply = totalSupply();
        if (houseBalance.poolTokenSupply > 0) {
            houseBalance.poolTokenPrice =
                ((houseBalance.totalBalance - houseBalance.unsettledBets) * 1e18) / houseBalance.poolTokenSupply;
        } else {
            houseBalance.poolTokenPrice = 1e18;  // Default 1:1 when no supply
        }
    }

    /**
     * @dev Send referral reward from pool on losing bets. Non-blocking — settlement
     *      never fails due to referral transfer issues.
     * @param commitmentHash Bet identifier for event tracking
     * @param player Player who lost
     * @param lossAmount Loss amount (wagerAmount - partialPayout)
     */
    function _sendReferralReward(
        bytes32 commitmentHash,
        address player,
        uint256 lossAmount
    ) internal {
        if (referralBasisPoints == 0) return;
        address referrer = playerReferrers[player];
        if (referrer == address(0)) return;

        uint256 rewardAmount = (lossAmount * referralBasisPoints) / 10000;
        if (rewardAmount == 0) return;

        // Non-blocking: try-catch so settlement never fails due to referral
        try IERC20(buxToken).transfer(referrer, rewardAmount) returns (bool success) {
            if (success) {
                houseBalance.totalBalance -= rewardAmount;
                _recalculateHouseBalance();
                totalReferralRewardsPaid += rewardAmount;
                referrerTotalEarnings[referrer] += rewardAmount;
                emit ReferralRewardPaid(commitmentHash, referrer, player, rewardAmount);
            }
        } catch {
            // Silently skip — don't block settlement
        }
    }

    /**
     * @dev Update Plinko stats for a winning bet
     */
    function _updatePlinkoStatsWin(
        address player,
        uint256 betAmount,
        uint256 profit,
        uint8 configIndex
    ) internal {
        plinkoPlayerStats[player].totalBets++;
        plinkoPlayerStats[player].wins++;
        plinkoPlayerStats[player].totalWagered += betAmount;
        plinkoPlayerStats[player].totalWinnings += profit;
        plinkoBetsPerConfig[player][configIndex]++;
        plinkoPnLPerConfig[player][configIndex] += int256(profit);

        plinkoAccounting.totalBets++;
        plinkoAccounting.totalWins++;
        plinkoAccounting.totalVolumeWagered += betAmount;
        plinkoAccounting.totalPayouts += betAmount + profit;
        plinkoAccounting.totalHouseProfit -= int256(profit);
        if (profit > plinkoAccounting.largestWin) plinkoAccounting.largestWin = profit;
        if (betAmount > plinkoAccounting.largestBet) plinkoAccounting.largestBet = betAmount;
    }

    /**
     * @dev Update Plinko stats for a losing bet
     */
    function _updatePlinkoStatsLoss(
        address player,
        uint256 betAmount,
        uint256 lossAmount,
        uint8 configIndex
    ) internal {
        plinkoPlayerStats[player].totalBets++;
        plinkoPlayerStats[player].losses++;
        plinkoPlayerStats[player].totalWagered += betAmount;
        plinkoPlayerStats[player].totalLosses += lossAmount;
        plinkoBetsPerConfig[player][configIndex]++;
        plinkoPnLPerConfig[player][configIndex] -= int256(lossAmount);

        plinkoAccounting.totalBets++;
        plinkoAccounting.totalLosses++;
        plinkoAccounting.totalVolumeWagered += betAmount;
        if (betAmount > lossAmount) {
            plinkoAccounting.totalPayouts += betAmount - lossAmount;
        }
        plinkoAccounting.totalHouseProfit += int256(lossAmount);
        if (betAmount > plinkoAccounting.largestBet) plinkoAccounting.largestBet = betAmount;
    }

    // ============ Referral View Functions ============

    /**
     * @notice Get a player's referrer
     */
    function getPlayerReferrer(address player) external view returns (address) {
        return playerReferrers[player];
    }

    /**
     * @notice Get total referral rewards paid all-time
     */
    function getTotalReferralRewardsPaid() external view returns (uint256) {
        return totalReferralRewardsPaid;
    }

    /**
     * @notice Get total earnings for a specific referrer
     */
    function getReferrerTotalEarnings(address referrer) external view returns (uint256) {
        return referrerTotalEarnings[referrer];
    }
}
