// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title NFTRewarder
 * @notice Revenue sharing contract for High Rollers NFTs from ROGUE betting
 * @dev UUPS Upgradeable contract for distributing ROGUE betting profits to NFT holders.
 *
 * REVENUE MODEL:
 * - ROGUEBankroll sends 20 BPS (0.2%) of each losing bet to this contract
 * - Rewards distributed proportionally based on NFT multipliers (30-100x)
 * - NFT ownership tracked via server-synced registry (cross-chain from Arbitrum)
 *
 * ACCESS CONTROL:
 * - Owner (multisig): upgrade contract, set admin, set rogueBankroll
 * - Admin (server wallet): register NFTs, update ownership, execute withdrawals
 * - ROGUEBankroll: send rewards via receiveReward()
 *
 * NFT MULTIPLIERS (High Rollers):
 * - Index 0: Penelope Fatale (100x)
 * - Index 1: Mia Siren (90x)
 * - Index 2: Cleo Enchante (80x)
 * - Index 3: Sophia Spark (70x)
 * - Index 4: Luna Mirage (60x)
 * - Index 5: Aurora Seductra (50x)
 * - Index 6: Scarlett Ember (40x)
 * - Index 7: Vivienne Allure (30x)
 *
 * UPGRADEABILITY:
 * - Uses UUPS proxy pattern (EIP-1822)
 * - Only owner can authorize upgrades
 * - State is preserved across upgrades
 */

// ============================================================
// =============== FLATTENED DEPENDENCIES =====================
// ============================================================
// The following interfaces and base contracts are included
// directly for easier verification on block explorers.
// Uses UPGRADEABLE versions for proxy compatibility.
// ============================================================

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

contract NFTRewarder is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {

    // ============ Structs ============

    struct NFTMetadata {
        uint8 hostessIndex;     // 0-7 (determines multiplier)
        bool registered;        // Has this tokenId been registered
        address owner;          // Current owner (synced from Arbitrum by server)
    }

    // ============ Constants ============

    // Multipliers per hostess type (index 0-7)
    // Penelope=100, Mia=90, Cleo=80, Sophia=70, Luna=60, Aurora=50, Scarlett=40, Vivienne=30
    // Note: Can't use constant arrays in Solidity, so we use a pure function instead
    function _getMultiplier(uint8 hostessIndex) internal pure returns (uint8) {
        if (hostessIndex == 0) return 100;  // Penelope Fatale
        if (hostessIndex == 1) return 90;   // Mia Siren
        if (hostessIndex == 2) return 80;   // Cleo Enchante
        if (hostessIndex == 3) return 70;   // Sophia Spark
        if (hostessIndex == 4) return 60;   // Luna Mirage
        if (hostessIndex == 5) return 50;   // Aurora Seductra
        if (hostessIndex == 6) return 40;   // Scarlett Ember
        if (hostessIndex == 7) return 30;   // Vivienne Allure
        revert InvalidHostessIndex();
    }

    // ============ State Variables ============

    // Access Control
    address public admin;           // Server wallet for daily operations
    address public rogueBankroll;   // Authorized to send rewards

    // NFT Registry
    mapping(uint256 => NFTMetadata) public nftMetadata;  // tokenId => NFTMetadata
    uint256 public totalRegisteredNFTs;
    uint256 public totalMultiplierPoints;     // Sum of all registered NFT multipliers

    // Owner → TokenIds mapping (for batch view functions)
    mapping(address => uint256[]) public ownerTokenIds;  // owner => array of tokenIds
    mapping(uint256 => uint256) private tokenIdToOwnerIndex;  // tokenId => index in ownerTokenIds array

    // Reward Tracking (MasterChef-style)
    uint256 public totalRewardsReceived;       // All-time rewards received
    uint256 public totalRewardsDistributed;    // All-time rewards claimed
    uint256 public rewardsPerMultiplierPoint;  // Accumulated rewards per point (scaled by 1e18)

    // Per-NFT reward tracking
    mapping(uint256 => uint256) public nftRewardDebt;      // tokenId => already-accounted-for rewards
    mapping(uint256 => uint256) public nftClaimedRewards;  // tokenId => total claimed by this NFT

    // Per-User tracking (by recipient address)
    mapping(address => uint256) public userTotalClaimed;

    // ============ Events ============

    event RewardReceived(bytes32 indexed betId, uint256 amount, uint256 timestamp);
    event RewardClaimed(address indexed user, uint256 amount, uint256[] tokenIds);
    event NFTRegistered(uint256 indexed tokenId, address indexed owner, uint8 hostessIndex);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event RogueBankrollChanged(address indexed previousBankroll, address indexed newBankroll);
    event OwnershipUpdated(uint256 indexed tokenId, address indexed oldOwner, address indexed newOwner);

    // ============ Errors ============

    error NotAdmin();
    error NotRogueBankroll();
    error InvalidAddress();
    error InvalidHostessIndex();
    error AlreadyRegistered();
    error NFTNotRegistered();
    error NoRewardsToClaim();
    error NoNFTsRegistered();
    error TransferFailed();
    error LengthMismatch();

    // ============ Modifiers ============

    modifier onlyAdmin() {
        if (msg.sender != admin && msg.sender != owner()) {
            revert NotAdmin();
        }
        _;
    }

    modifier onlyRogueBankroll() {
        if (msg.sender != rogueBankroll) {
            revert NotRogueBankroll();
        }
        _;
    }

    // ============ Initialization ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract (replaces constructor for upgradeable contracts)
     * @dev Admin and rogueBankroll are set via setAdmin() and setRogueBankroll() after deployment
     */
    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        // Admin and rogueBankroll are set via setAdmin() and setRogueBankroll() after deployment
    }

    /**
     * @notice Required by UUPS - only owner can upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // ============ Owner-Only Functions ============

    /**
     * @notice Set new admin address (owner only)
     * @param _admin New admin address
     */
    function setAdmin(address _admin) external onlyOwner {
        if (_admin == address(0)) revert InvalidAddress();
        emit AdminChanged(admin, _admin);
        admin = _admin;
    }

    /**
     * @notice Set ROGUEBankroll address (owner only)
     * @param _rogueBankroll New ROGUEBankroll address
     */
    function setRogueBankroll(address _rogueBankroll) external onlyOwner {
        if (_rogueBankroll == address(0)) revert InvalidAddress();
        emit RogueBankrollChanged(rogueBankroll, _rogueBankroll);
        rogueBankroll = _rogueBankroll;
    }

    // ============ Reward Receiving (Called by ROGUEBankroll) ============

    /**
     * @notice Receive ROGUE rewards from ROGUEBankroll when a BuxBooster bet is lost
     * @dev Only callable by authorized ROGUEBankroll contract
     * @param betId The commitment hash of the losing bet (for event tracking)
     */
    function receiveReward(bytes32 betId) external payable onlyRogueBankroll {
        if (msg.value == 0) revert NoRewardsToClaim();
        if (totalMultiplierPoints == 0) revert NoNFTsRegistered();

        // Update global reward tracking
        totalRewardsReceived += msg.value;

        // Update rewards per multiplier point (scaled by 1e18 for precision)
        rewardsPerMultiplierPoint += (msg.value * 1e18) / totalMultiplierPoints;

        // Emit event with timestamp - server uses this for 24h tracking
        emit RewardReceived(betId, msg.value, block.timestamp);
    }

    // ============ Reward Calculation ============

    /**
     * @notice Calculate pending rewards for a specific NFT
     * @param tokenId The NFT token ID
     * @return Pending unclaimed rewards in wei
     */
    function pendingReward(uint256 tokenId) public view returns (uint256) {
        NFTMetadata storage nft = nftMetadata[tokenId];
        if (!nft.registered) return 0;

        uint256 multiplier = _getMultiplier(nft.hostessIndex);
        uint256 accumulatedReward = (multiplier * rewardsPerMultiplierPoint) / 1e18;

        return accumulatedReward - nftRewardDebt[tokenId];
    }

    // ============ NFT Registration (Admin Only) ============

    /**
     * @notice Register NFT with metadata and owner. Only needs to be done once per NFT.
     * @dev Hostess index determines multiplier and never changes after mint
     * @param tokenId The NFT token ID
     * @param hostessIndex 0-7 index into MULTIPLIERS array
     * @param _owner Current owner address (from Arbitrum contract)
     */
    function registerNFT(uint256 tokenId, uint8 hostessIndex, address _owner) external onlyAdmin {
        if (hostessIndex >= 8) revert InvalidHostessIndex();
        if (nftMetadata[tokenId].registered) revert AlreadyRegistered();

        nftMetadata[tokenId] = NFTMetadata({
            hostessIndex: hostessIndex,
            registered: true,
            owner: _owner
        });

        // Add to owner's token array
        if (_owner != address(0)) {
            tokenIdToOwnerIndex[tokenId] = ownerTokenIds[_owner].length;
            ownerTokenIds[_owner].push(tokenId);
        }

        uint256 multiplier = _getMultiplier(hostessIndex);
        totalMultiplierPoints += multiplier;
        totalRegisteredNFTs++;

        // Set initial reward debt so newly registered NFT doesn't claim past rewards
        nftRewardDebt[tokenId] = (multiplier * rewardsPerMultiplierPoint) / 1e18;

        emit NFTRegistered(tokenId, _owner, hostessIndex);
    }

    /**
     * @notice Batch register multiple NFTs with metadata and owners in a single transaction
     * @dev CRITICAL: All existing NFTs MUST be registered BEFORE enabling rewards
     *      in ROGUEBankroll. Otherwise totalMultiplierPoints will be wrong.
     *
     * Recommended batch size: 100-200 NFTs per transaction to avoid gas limits
     *
     * @param tokenIds Array of NFT token IDs
     * @param hostessIndices Array of hostess indices (0-7)
     * @param owners Array of current owner addresses (from Arbitrum contract)
     */
    function batchRegisterNFTs(
        uint256[] calldata tokenIds,
        uint8[] calldata hostessIndices,
        address[] calldata owners
    ) external onlyAdmin {
        if (tokenIds.length != hostessIndices.length) revert LengthMismatch();
        if (tokenIds.length != owners.length) revert LengthMismatch();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            // Skip already registered (allows idempotent batch calls)
            if (nftMetadata[tokenIds[i]].registered) continue;

            uint8 hostessIndex = hostessIndices[i];
            if (hostessIndex >= 8) revert InvalidHostessIndex();

            address _owner = owners[i];

            nftMetadata[tokenIds[i]] = NFTMetadata({
                hostessIndex: hostessIndex,
                registered: true,
                owner: _owner
            });

            // Add to owner's token array
            if (_owner != address(0)) {
                tokenIdToOwnerIndex[tokenIds[i]] = ownerTokenIds[_owner].length;
                ownerTokenIds[_owner].push(tokenIds[i]);
            }

            uint256 multiplier = _getMultiplier(hostessIndex);
            totalMultiplierPoints += multiplier;
            totalRegisteredNFTs++;
            nftRewardDebt[tokenIds[i]] = (multiplier * rewardsPerMultiplierPoint) / 1e18;

            emit NFTRegistered(tokenIds[i], _owner, hostessIndex);
        }
    }

    // ============ Ownership Management (Admin Only) ============

    /**
     * @notice Update ownership of an NFT (called by server when transfer detected on Arbitrum)
     * @dev Maintains ownerTokenIds arrays for efficient batch queries
     * @param tokenId The NFT token ID
     * @param newOwner The new owner address
     */
    function updateOwnership(uint256 tokenId, address newOwner) external onlyAdmin {
        NFTMetadata storage nft = nftMetadata[tokenId];
        if (!nft.registered) revert NFTNotRegistered();

        address oldOwner = nft.owner;
        if (oldOwner == newOwner) return;  // No change

        // Remove from old owner's array (if not zero address)
        if (oldOwner != address(0)) {
            _removeFromOwnerArray(oldOwner, tokenId);
        }

        // Add to new owner's array
        if (newOwner != address(0)) {
            tokenIdToOwnerIndex[tokenId] = ownerTokenIds[newOwner].length;
            ownerTokenIds[newOwner].push(tokenId);
        }

        // Update NFT metadata
        nft.owner = newOwner;

        emit OwnershipUpdated(tokenId, oldOwner, newOwner);
    }

    /**
     * @notice Batch update ownership for multiple NFTs
     * @dev Gas efficient for full syncs
     */
    function batchUpdateOwnership(
        uint256[] calldata tokenIds,
        address[] calldata newOwners
    ) external onlyAdmin {
        if (tokenIds.length != newOwners.length) revert LengthMismatch();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            NFTMetadata storage nft = nftMetadata[tokenIds[i]];
            if (!nft.registered) continue;

            address oldOwner = nft.owner;
            address newOwner = newOwners[i];

            if (oldOwner == newOwner) continue;

            // Remove from old owner's array
            if (oldOwner != address(0)) {
                _removeFromOwnerArray(oldOwner, tokenIds[i]);
            }

            // Add to new owner's array
            if (newOwner != address(0)) {
                tokenIdToOwnerIndex[tokenIds[i]] = ownerTokenIds[newOwner].length;
                ownerTokenIds[newOwner].push(tokenIds[i]);
            }

            // Update NFT metadata
            nft.owner = newOwner;

            emit OwnershipUpdated(tokenIds[i], oldOwner, newOwner);
        }
    }

    /**
     * @dev Remove tokenId from owner's array using swap-and-pop
     */
    function _removeFromOwnerArray(address _owner, uint256 tokenId) private {
        uint256[] storage tokens = ownerTokenIds[_owner];
        uint256 index = tokenIdToOwnerIndex[tokenId];
        uint256 lastIndex = tokens.length - 1;

        if (index != lastIndex) {
            // Swap with last element
            uint256 lastTokenId = tokens[lastIndex];
            tokens[index] = lastTokenId;
            tokenIdToOwnerIndex[lastTokenId] = index;
        }

        // Remove last element
        tokens.pop();
    }

    // ============ Hostess Index Fix (Owner Only - One-time fix for misregistered NFTs) ============

    /**
     * @notice Fix hostess index for misregistered NFTs (owner only)
     * @dev This should only be used to correct data entry errors during initial registration.
     *      Updates totalMultiplierPoints accordingly.
     * @param tokenId The NFT token ID
     * @param correctHostessIndex The correct hostess index (0-7)
     */
    function fixHostessIndex(uint256 tokenId, uint8 correctHostessIndex) external onlyOwner {
        if (correctHostessIndex >= 8) revert InvalidHostessIndex();

        NFTMetadata storage nft = nftMetadata[tokenId];
        if (!nft.registered) revert NFTNotRegistered();

        uint8 oldHostessIndex = nft.hostessIndex;
        if (oldHostessIndex == correctHostessIndex) return;  // No change

        // Calculate multiplier difference
        uint256 oldMultiplier = _getMultiplier(oldHostessIndex);
        uint256 newMultiplier = _getMultiplier(correctHostessIndex);

        // Update totalMultiplierPoints
        totalMultiplierPoints = totalMultiplierPoints - oldMultiplier + newMultiplier;

        // Update hostess index
        nft.hostessIndex = correctHostessIndex;

        // Note: We don't update rewardDebt here since no rewards have been distributed yet
        // If rewards had been distributed, we'd need to handle the debt adjustment
    }

    /**
     * @notice Batch fix hostess indices for multiple NFTs
     * @param tokenIds Array of token IDs to fix
     * @param correctHostessIndices Array of correct hostess indices
     */
    function batchFixHostessIndex(
        uint256[] calldata tokenIds,
        uint8[] calldata correctHostessIndices
    ) external onlyOwner {
        if (tokenIds.length != correctHostessIndices.length) revert LengthMismatch();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            uint8 correctHostessIndex = correctHostessIndices[i];

            if (correctHostessIndex >= 8) revert InvalidHostessIndex();

            NFTMetadata storage nft = nftMetadata[tokenId];
            if (!nft.registered) continue;

            uint8 oldHostessIndex = nft.hostessIndex;
            if (oldHostessIndex == correctHostessIndex) continue;

            uint256 oldMultiplier = _getMultiplier(oldHostessIndex);
            uint256 newMultiplier = _getMultiplier(correctHostessIndex);

            totalMultiplierPoints = totalMultiplierPoints - oldMultiplier + newMultiplier;
            nft.hostessIndex = correctHostessIndex;
        }
    }

    // ============ Withdrawal (Admin Only - Server Verified) ============

    /**
     * @notice Withdraw rewards to a specific address (called by server after ownership verification)
     * @dev Only callable by admin. Server verifies ownership via OwnerSyncService before calling.
     * @param tokenIds Array of token IDs to claim for
     * @param recipient Address to send ROGUE to (the verified NFT owner)
     * @return amount Total ROGUE withdrawn
     */
    function withdrawTo(
        uint256[] calldata tokenIds,
        address recipient
    ) external onlyAdmin nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) revert InvalidAddress();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (!nftMetadata[tokenId].registered) revert NFTNotRegistered();

            uint256 pending = pendingReward(tokenId);
            if (pending > 0) {
                // Update reward debt
                uint8 hostessIndex = nftMetadata[tokenId].hostessIndex;
                uint256 multiplier = _getMultiplier(hostessIndex);
                nftRewardDebt[tokenId] = (multiplier * rewardsPerMultiplierPoint) / 1e18;

                // Track claimed amounts
                nftClaimedRewards[tokenId] += pending;
                amount += pending;
            }
        }

        if (amount == 0) revert NoRewardsToClaim();

        userTotalClaimed[recipient] += amount;
        totalRewardsDistributed += amount;

        // Transfer ROGUE to recipient
        (bool sent,) = payable(recipient).call{value: amount}("");
        if (!sent) revert TransferFailed();

        emit RewardClaimed(recipient, amount, tokenIds);
    }

    // ============ View Functions ============

    /**
     * @notice Get all token IDs owned by an address
     * @param _owner The wallet address
     * @return Array of token IDs
     */
    function getOwnerTokenIds(address _owner) external view returns (uint256[] memory) {
        return ownerTokenIds[_owner];
    }

    /**
     * @notice Get aggregated earnings for a wallet (all their NFTs combined)
     * @param _owner The wallet address
     * @return totalPending Total unclaimed rewards across all NFTs
     * @return totalClaimed Total ever claimed by this wallet
     * @return tokenIds Array of owned token IDs
     */
    function getOwnerEarnings(address _owner) external view returns (
        uint256 totalPending,
        uint256 totalClaimed,
        uint256[] memory tokenIds
    ) {
        tokenIds = ownerTokenIds[_owner];
        totalClaimed = userTotalClaimed[_owner];

        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalPending += pendingReward(tokenIds[i]);
        }

        return (totalPending, totalClaimed, tokenIds);
    }

    /**
     * @notice Get detailed earnings for multiple token IDs
     * @param tokenIds Array of token IDs to query
     * @return pending Array of pending rewards (same order as input)
     * @return claimed Array of claimed rewards (same order as input)
     * @return multipliers Array of multipliers (same order as input)
     */
    function getTokenEarnings(uint256[] calldata tokenIds) external view returns (
        uint256[] memory pending,
        uint256[] memory claimed,
        uint8[] memory multipliers
    ) {
        pending = new uint256[](tokenIds.length);
        claimed = new uint256[](tokenIds.length);
        multipliers = new uint8[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            NFTMetadata storage nft = nftMetadata[tokenId];

            if (nft.registered) {
                pending[i] = pendingReward(tokenId);
                claimed[i] = nftClaimedRewards[tokenId];
                multipliers[i] = _getMultiplier(nft.hostessIndex);
            }
        }

        return (pending, claimed, multipliers);
    }

    /**
     * @notice Get earnings data for a specific NFT (on-chain data only)
     * @param tokenId The NFT token ID
     * @return totalEarned All-time earnings for this NFT
     * @return pendingAmount Unclaimed rewards
     * @return hostessIndex The hostess type (for off-chain multiplier lookup)
     */
    function getNFTEarnings(uint256 tokenId) external view returns (
        uint256 totalEarned,
        uint256 pendingAmount,
        uint8 hostessIndex
    ) {
        NFTMetadata storage nft = nftMetadata[tokenId];
        if (!nft.registered) revert NFTNotRegistered();

        pendingAmount = pendingReward(tokenId);
        totalEarned = nftClaimedRewards[tokenId] + pendingAmount;
        hostessIndex = nft.hostessIndex;
    }

    /**
     * @notice Get earnings for multiple NFTs in a single call (for batch sync)
     * @param tokenIds Array of token IDs to query
     * @return totalEarned Array of total earned amounts
     * @return pendingAmounts Array of pending amounts
     * @return hostessIndices Array of hostess indices
     */
    function getBatchNFTEarnings(uint256[] calldata tokenIds) external view returns (
        uint256[] memory totalEarned,
        uint256[] memory pendingAmounts,
        uint8[] memory hostessIndices
    ) {
        totalEarned = new uint256[](tokenIds.length);
        pendingAmounts = new uint256[](tokenIds.length);
        hostessIndices = new uint8[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            NFTMetadata storage nft = nftMetadata[tokenId];

            if (!nft.registered) continue;

            uint256 pending = pendingReward(tokenId);

            totalEarned[i] = nftClaimedRewards[tokenId] + pending;
            pendingAmounts[i] = pending;
            hostessIndices[i] = nft.hostessIndex;
        }
    }

    /**
     * @notice Get global statistics for display
     * @return totalRewards All-time rewards received
     * @return totalDistributed All-time rewards claimed
     * @return totalPending Current contract balance (unclaimed)
     * @return registeredNFTs Number of registered NFTs
     * @return totalPoints Sum of all multiplier points
     */
    function getGlobalStats() external view returns (
        uint256 totalRewards,
        uint256 totalDistributed,
        uint256 totalPending,
        uint256 registeredNFTs,
        uint256 totalPoints
    ) {
        totalRewards = totalRewardsReceived;
        totalDistributed = totalRewardsDistributed;
        totalPending = address(this).balance;
        registeredNFTs = totalRegisteredNFTs;
        totalPoints = totalMultiplierPoints;
    }

    /**
     * @notice Get NFT metadata
     * @param tokenId The NFT token ID
     * @return hostessIndex The hostess type (0-7)
     * @return registered Whether the NFT is registered
     * @return _owner Current owner address
     * @return multiplier The multiplier for this NFT type
     */
    function getNFTMetadata(uint256 tokenId) external view returns (
        uint8 hostessIndex,
        bool registered,
        address _owner,
        uint8 multiplier
    ) {
        NFTMetadata storage nft = nftMetadata[tokenId];
        hostessIndex = nft.hostessIndex;
        registered = nft.registered;
        _owner = nft.owner;
        multiplier = nft.registered ? _getMultiplier(nft.hostessIndex) : 0;
    }

    /**
     * @notice Get multiplier for a hostess index
     * @param hostessIndex 0-7
     * @return The multiplier value (30-100)
     */
    function getMultiplier(uint8 hostessIndex) external pure returns (uint8) {
        return _getMultiplier(hostessIndex);
    }

    /**
     * @notice Allow contract to receive ROGUE directly (for testing/manual deposits)
     */
    receive() external payable {
        // Accept direct ROGUE transfers but don't update rewards
        // Use receiveReward() for proper reward distribution
    }
}
