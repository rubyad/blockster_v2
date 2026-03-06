// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AirdropVaultV3
 * @notice On-chain airdrop vault for BUX token redemptions (V3)
 * @dev UUPS Upgradeable proxy. All dependencies flattened for RogueScan verification.
 *
 * V3 CHANGES:
 * - drawWinners() simplified: just stores server seed + marks drawn (no on-chain computation)
 * - New setWinner() lets server push winner data after off-chain draw
 * - Removed SHA256 verification from drawWinners (Elixir handles provably fair logic)
 *
 * LIFECYCLE:
 * 1. Owner calls startRound(commitmentHash, endTime)
 * 2. Users call deposit(externalWallet, amount)
 * 3. Owner calls closeAirdrop() — stops deposits, captures block hash
 * 4. Owner calls drawWinners(serverSeed) — reveals seed, marks drawn
 * 5. Owner calls setWinner() for each winner (computed off-chain)
 * 6. Anyone calls getWinnerInfoForRound() or verifyFairnessForRound() to verify
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
// =============== AIRDROP VAULT V3 CONTRACT ==================
// ============================================================

contract AirdropVaultV3 is Initializable, ContextUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ============ Constants ============
    uint256 public constant NUM_WINNERS = 33;

    // ============ Core State ============
    IERC20 public buxToken;
    uint256 public roundId;

    // ============ V1/V2 State (preserved for storage layout) ============

    struct Deposit {
        address blocksterWallet;
        address externalWallet;
        uint256 startPosition;
        uint256 endPosition;
        uint256 amount;
    }

    // V1/V2 Winner struct — kept for storage layout compatibility, no longer written to
    struct Winner {
        uint256 randomNumber;
        address blocksterWallet;
        address externalWallet;
        uint256 depositIndex;
        uint256 depositAmount;
        uint256 depositStart;
        uint256 depositEnd;
    }

    struct RoundState {
        bytes32 commitmentHash;
        bytes32 revealedServerSeed;
        bytes32 blockHashAtClose;
        uint256 closeBlockNumber;
        uint256 airdropEndTime;
        bool isOpen;
        bool isDrawn;
        uint256 totalEntries;
    }

    mapping(uint256 => RoundState) internal _rounds;
    mapping(uint256 => Deposit[]) internal _deposits;
    mapping(uint256 => mapping(address => uint256)) internal _totalDeposited;
    mapping(uint256 => Winner[]) internal _winners; // V1/V2 legacy, unused in V3

    // ============ V3 State (appended after V2 slots) ============

    struct WinnerV3 {
        uint256 randomNumber;
        address blocksterWallet;
        address externalWallet;
        uint256 buxRedeemed;
        uint256 blockStart;
        uint256 blockEnd;
    }

    // roundId => prizePosition (0-indexed) => winner data
    mapping(uint256 => mapping(uint256 => WinnerV3)) internal _winnersV3;
    mapping(uint256 => uint256) internal _winnerCountV3;

    // ============ Events ============
    event RoundStarted(uint256 roundId, bytes32 commitmentHash, uint256 endTime);
    event BuxDeposited(uint256 roundId, address indexed blocksterWallet, address indexed externalWallet, uint256 amount, uint256 startPosition, uint256 endPosition);
    event AirdropClosed(uint256 roundId, uint256 totalEntries, bytes32 blockHashAtClose);
    event AirdropDrawn(uint256 roundId, bytes32 serverSeed, bytes32 blockHash, uint256 totalEntries);
    event WinnerSet(uint256 roundId, uint256 prizePosition, address blocksterWallet, address externalWallet, uint256 randomNumber);
    event BuxWithdrawn(uint256 roundId, uint256 amount);

    // ============ Initializer ============

    function initialize(address _buxToken) initializer public {
        require(_buxToken != address(0), "Invalid token address");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        buxToken = IERC20(_buxToken);
    }

    function initializeV2() reinitializer(2) public {
        // No new state to initialize
    }

    function initializeV3() reinitializer(3) public {
        // No new state to initialize — V3 mappings start empty
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Version ============

    function version() external pure returns (string memory) {
        return "v3";
    }

    // ============ Current Round View Helpers ============

    function commitmentHash() external view returns (bytes32) {
        return _rounds[roundId].commitmentHash;
    }

    function revealedServerSeed() external view returns (bytes32) {
        return _rounds[roundId].revealedServerSeed;
    }

    function blockHashAtClose() external view returns (bytes32) {
        return _rounds[roundId].blockHashAtClose;
    }

    function closeBlockNumber() external view returns (uint256) {
        return _rounds[roundId].closeBlockNumber;
    }

    function airdropEndTime() external view returns (uint256) {
        return _rounds[roundId].airdropEndTime;
    }

    function isOpen() external view returns (bool) {
        return _rounds[roundId].isOpen;
    }

    function isDrawn() external view returns (bool) {
        return _rounds[roundId].isDrawn;
    }

    function totalEntries() external view returns (uint256) {
        return _rounds[roundId].totalEntries;
    }

    // ============ Admin Functions ============

    function startRound(bytes32 _commitmentHash, uint256 _endTime) external onlyOwner {
        require(_commitmentHash != bytes32(0), "Zero commitment hash");
        require(_endTime > block.timestamp, "End time must be in future");

        if (roundId > 0) {
            RoundState storage prev = _rounds[roundId];
            require(!prev.isOpen, "Previous round still open");
        }

        roundId++;

        RoundState storage round = _rounds[roundId];
        round.commitmentHash = _commitmentHash;
        round.airdropEndTime = _endTime;
        round.isOpen = true;

        emit RoundStarted(roundId, _commitmentHash, _endTime);
    }

    function closeAirdrop() external onlyOwner {
        RoundState storage round = _rounds[roundId];
        require(round.isOpen, "Round not open");

        round.isOpen = false;
        round.closeBlockNumber = block.number;
        round.blockHashAtClose = blockhash(block.number - 1);

        emit AirdropClosed(roundId, round.totalEntries, round.blockHashAtClose);
    }

    /// @notice Reveal server seed and mark round as drawn. No on-chain winner computation.
    function drawWinners(bytes32 _serverSeed) external onlyOwner {
        RoundState storage round = _rounds[roundId];
        require(!round.isOpen, "Must close first");
        require(!round.isDrawn, "Already drawn");

        round.revealedServerSeed = _serverSeed;
        round.isDrawn = true;

        emit AirdropDrawn(roundId, _serverSeed, round.blockHashAtClose, round.totalEntries);
    }

    /// @notice Push a single winner (computed off-chain) to the contract.
    function setWinner(
        uint256 _roundId,
        uint256 prizePosition,
        uint256 randomNumber,
        address blocksterWallet,
        address externalWallet,
        uint256 buxRedeemed,
        uint256 blockStart,
        uint256 blockEnd
    ) external onlyOwner {
        RoundState storage round = _rounds[_roundId];
        require(round.isDrawn, "Not drawn yet");
        require(prizePosition >= 1 && prizePosition <= NUM_WINNERS, "Invalid position");

        _winnersV3[_roundId][prizePosition - 1] = WinnerV3({
            randomNumber: randomNumber,
            blocksterWallet: blocksterWallet,
            externalWallet: externalWallet,
            buxRedeemed: buxRedeemed,
            blockStart: blockStart,
            blockEnd: blockEnd
        });

        if (prizePosition > _winnerCountV3[_roundId]) {
            _winnerCountV3[_roundId] = prizePosition;
        }

        emit WinnerSet(_roundId, prizePosition, blocksterWallet, externalWallet, randomNumber);
    }

    function withdrawBux(uint256 _roundId) external onlyOwner {
        require(_roundId > 0 && _roundId <= roundId, "Invalid round");
        RoundState storage round = _rounds[_roundId];
        require(round.isDrawn, "Round not drawn yet");

        uint256 balance = buxToken.balanceOf(address(this));
        require(balance > 0, "No BUX to withdraw");

        buxToken.safeTransfer(msg.sender, balance);

        emit BuxWithdrawn(_roundId, balance);
    }

    // ============ Deposit Functions ============

    function depositFor(
        address blocksterWallet,
        address externalWallet,
        uint256 amount
    ) external onlyOwner {
        RoundState storage round = _rounds[roundId];
        require(round.isOpen, "Round not open");
        require(amount > 0, "Zero amount");
        require(blocksterWallet != address(0), "Invalid blockster wallet");
        require(externalWallet != address(0), "Invalid external wallet");

        buxToken.safeTransferFrom(blocksterWallet, address(this), amount);

        uint256 startPosition = round.totalEntries + 1;
        uint256 endPosition = round.totalEntries + amount;
        round.totalEntries = endPosition;

        _deposits[roundId].push(Deposit({
            blocksterWallet: blocksterWallet,
            externalWallet: externalWallet,
            startPosition: startPosition,
            endPosition: endPosition,
            amount: amount
        }));

        _totalDeposited[roundId][blocksterWallet] += amount;

        emit BuxDeposited(roundId, blocksterWallet, externalWallet, amount, startPosition, endPosition);
    }

    function deposit(
        address externalWallet,
        uint256 amount
    ) external {
        RoundState storage round = _rounds[roundId];
        require(round.isOpen, "Round not open");
        require(amount > 0, "Zero amount");
        require(externalWallet != address(0), "Invalid external wallet");

        address blocksterWallet = _msgSender();

        buxToken.safeTransferFrom(blocksterWallet, address(this), amount);

        uint256 startPosition = round.totalEntries + 1;
        uint256 endPosition = round.totalEntries + amount;
        round.totalEntries = endPosition;

        _deposits[roundId].push(Deposit({
            blocksterWallet: blocksterWallet,
            externalWallet: externalWallet,
            startPosition: startPosition,
            endPosition: endPosition,
            amount: amount
        }));

        _totalDeposited[roundId][blocksterWallet] += amount;

        emit BuxDeposited(roundId, blocksterWallet, externalWallet, amount, startPosition, endPosition);
    }

    // ============ Public View Functions ============

    function getDeposit(uint256 index) external view returns (Deposit memory) {
        return getDepositForRound(roundId, index);
    }

    function getDepositForRound(uint256 _roundId, uint256 index) public view returns (Deposit memory) {
        require(index < _deposits[_roundId].length, "Index out of bounds");
        return _deposits[_roundId][index];
    }

    function getDepositCount() external view returns (uint256) {
        return _deposits[roundId].length;
    }

    function getDepositCountForRound(uint256 _roundId) external view returns (uint256) {
        return _deposits[_roundId].length;
    }

    function totalDeposited(address wallet) external view returns (uint256) {
        return _totalDeposited[roundId][wallet];
    }

    function totalDepositedForRound(uint256 _roundId, address wallet) external view returns (uint256) {
        return _totalDeposited[_roundId][wallet];
    }

    function getWalletForPosition(uint256 position) external view returns (address blocksterWallet, address externalWallet) {
        return getWalletForPositionInRound(roundId, position);
    }

    function getWalletForPositionInRound(uint256 _roundId, uint256 position) public view returns (address blocksterWallet, address externalWallet) {
        RoundState storage round = _rounds[_roundId];
        require(position >= 1 && position <= round.totalEntries, "Position out of range");

        uint256 idx = _findDepositIndex(_roundId, position);
        Deposit storage dep = _deposits[_roundId][idx];
        return (dep.blocksterWallet, dep.externalWallet);
    }

    function getUserDeposits(address blocksterWallet) external view returns (Deposit[] memory) {
        return getUserDepositsForRound(roundId, blocksterWallet);
    }

    function getUserDepositsForRound(uint256 _roundId, address blocksterWallet) public view returns (Deposit[] memory) {
        Deposit[] storage deps = _deposits[_roundId];
        uint256 count = 0;
        for (uint256 i = 0; i < deps.length; i++) {
            if (deps[i].blocksterWallet == blocksterWallet) {
                count++;
            }
        }

        Deposit[] memory result = new Deposit[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < deps.length; i++) {
            if (deps[i].blocksterWallet == blocksterWallet) {
                result[idx] = deps[i];
                idx++;
            }
        }
        return result;
    }

    function verifyFairness() external view returns (bytes32 commitment, bytes32 seed, bytes32 blockHash, uint256 entries) {
        return verifyFairnessForRound(roundId);
    }

    function verifyFairnessForRound(uint256 _roundId) public view returns (bytes32 commitment, bytes32 seed, bytes32 blockHash, uint256 entries) {
        RoundState storage round = _rounds[_roundId];
        return (round.commitmentHash, round.revealedServerSeed, round.blockHashAtClose, round.totalEntries);
    }

    // ============ Winner View Functions (1-indexed) ============

    function getWinnerInfo(uint256 prizePosition) external view returns (
        address blocksterWallet,
        address externalWallet,
        uint256 buxRedeemed,
        uint256 blockStart,
        uint256 blockEnd,
        uint256 randomNumber
    ) {
        return getWinnerInfoForRound(roundId, prizePosition);
    }

    function getWinnerInfoForRound(uint256 _roundId, uint256 prizePosition) public view returns (
        address blocksterWallet,
        address externalWallet,
        uint256 buxRedeemed,
        uint256 blockStart,
        uint256 blockEnd,
        uint256 randomNumber
    ) {
        RoundState storage round = _rounds[_roundId];
        require(round.isDrawn, "Airdrop not drawn yet");
        require(prizePosition >= 1 && prizePosition <= NUM_WINNERS, "Invalid prize position");

        WinnerV3 storage w = _winnersV3[_roundId][prizePosition - 1];
        require(w.blocksterWallet != address(0), "Winner not set yet");

        return (w.blocksterWallet, w.externalWallet, w.buxRedeemed, w.blockStart, w.blockEnd, w.randomNumber);
    }

    function getWinnerCount(uint256 _roundId) external view returns (uint256) {
        return _winnerCountV3[_roundId];
    }

    function getRoundState(uint256 _roundId) external view returns (
        bytes32 commitment,
        bytes32 seed,
        bytes32 blockHash,
        uint256 endTime,
        bool open,
        bool drawn,
        uint256 entries
    ) {
        RoundState storage round = _rounds[_roundId];
        return (
            round.commitmentHash,
            round.revealedServerSeed,
            round.blockHashAtClose,
            round.airdropEndTime,
            round.isOpen,
            round.isDrawn,
            round.totalEntries
        );
    }

    // ============ Internal: Binary Search ============

    function _findDepositIndex(uint256 _roundId, uint256 position) internal view returns (uint256) {
        Deposit[] storage deps = _deposits[_roundId];
        uint256 low = 0;
        uint256 high = deps.length - 1;

        while (low <= high) {
            uint256 mid = (low + high) / 2;
            if (position < deps[mid].startPosition) {
                if (mid == 0) break;
                high = mid - 1;
            } else if (position > deps[mid].endPosition) {
                low = mid + 1;
            } else {
                return mid;
            }
        }
        revert("Position not found");
    }
}
