// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AirdropPrizePool
 * @notice Holds USDT prizes on Arbitrum One for airdrop winners
 * @dev UUPS Upgradeable proxy. Admin sets prizes per round and sends USDT to winners.
 *      All dependencies flattened for easier verification on Arbiscan.
 *
 * LIFECYCLE:
 * 1. Owner funds the pool: fundPrizePool(amount)
 * 2. Owner sets 33 prizes: setPrize(roundId, winnerIndex, winner, amount)
 * 3. Owner sends each prize: sendPrize(roundId, winnerIndex)
 * 4. Anyone can verify: getPrize(roundId, winnerIndex)
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
// =============== AIRDROP PRIZE POOL CONTRACT ================
// ============================================================

contract AirdropPrizePool is Initializable, ContextUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    uint256 public constant NUM_WINNERS = 33;

    // ============ Core State ============
    IERC20 public usdt;
    uint256 public roundId;

    // ============ Prize Tracking ============
    struct Prize {
        address winner;
        uint256 amount;
        bool claimed;
        bytes32 txRef;
    }

    // roundId => winnerIndex => Prize
    mapping(uint256 => mapping(uint256 => Prize)) internal _prizes;

    // ============ Events ============
    event PrizePoolFunded(uint256 roundId, uint256 amount);
    event PrizeSet(uint256 roundId, uint256 winnerIndex, address winner, uint256 amount);
    event PrizeSent(uint256 roundId, uint256 winnerIndex, address winner, uint256 amount);
    event UsdtWithdrawn(uint256 amount);
    event NewRoundStarted(uint256 roundId);

    // ============ Initializer ============

    function initialize(address _usdt) initializer public {
        require(_usdt != address(0), "Invalid USDT address");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        usdt = IERC20(_usdt);
        roundId = 1;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Admin: Funding ============

    function fundPrizePool(uint256 amount) external onlyOwner {
        require(amount > 0, "Zero amount");
        usdt.safeTransferFrom(msg.sender, address(this), amount);
        emit PrizePoolFunded(roundId, amount);
    }

    // ============ Admin: Prize Configuration ============

    function setPrize(uint256 _roundId, uint256 winnerIndex, address winner, uint256 amount) external onlyOwner {
        require(winnerIndex < NUM_WINNERS, "Invalid winner index");
        require(winner != address(0), "Invalid winner address");
        require(amount > 0, "Zero prize amount");

        _prizes[_roundId][winnerIndex] = Prize({
            winner: winner,
            amount: amount,
            claimed: false,
            txRef: bytes32(0)
        });

        emit PrizeSet(_roundId, winnerIndex, winner, amount);
    }

    // ============ Admin: Prize Distribution ============

    function sendPrize(uint256 _roundId, uint256 winnerIndex) external onlyOwner {
        require(winnerIndex < NUM_WINNERS, "Invalid winner index");

        Prize storage prize = _prizes[_roundId][winnerIndex];
        require(prize.winner != address(0), "Prize not set");
        require(!prize.claimed, "Already claimed");
        require(usdt.balanceOf(address(this)) >= prize.amount, "Insufficient USDT balance");

        prize.claimed = true;
        usdt.safeTransfer(prize.winner, prize.amount);

        emit PrizeSent(_roundId, winnerIndex, prize.winner, prize.amount);
    }

    // ============ Admin: Round Management ============

    function startNewRound() external onlyOwner {
        roundId++;
        emit NewRoundStarted(roundId);
    }

    // ============ Admin: Withdrawal ============

    function withdrawUsdt(uint256 amount) external onlyOwner {
        require(amount > 0, "Zero amount");
        require(usdt.balanceOf(address(this)) >= amount, "Insufficient balance");
        usdt.safeTransfer(msg.sender, amount);
        emit UsdtWithdrawn(amount);
    }

    // ============ View Functions ============

    function getPrize(uint256 _roundId, uint256 winnerIndex) external view returns (Prize memory) {
        require(winnerIndex < NUM_WINNERS, "Invalid winner index");
        return _prizes[_roundId][winnerIndex];
    }

    function getRoundPrizeTotal(uint256 _roundId) external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < NUM_WINNERS; i++) {
            total += _prizes[_roundId][i].amount;
        }
        return total;
    }

    function getPoolBalance() external view returns (uint256) {
        return usdt.balanceOf(address(this));
    }
}
