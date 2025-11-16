// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

/**
 * Complete Thirdweb AccountFactory for Remix deployment
 * This is a flattened version with all dependencies included
 */

// ============================================================================
// INTERFACES
// ============================================================================

interface IEntryPoint {
    function getNonce(address sender, uint192 key) external view returns (uint256 nonce);
    function balanceOf(address account) external view returns (uint256);
    function depositTo(address account) external payable;
}

interface IAccountExecute {
    function execute(address dest, uint256 value, bytes calldata func) external;
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external;
}

// ============================================================================
// LIBRARIES
// ============================================================================

library Clones {
    function clone(address implementation) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }

    function cloneDeterministic(address implementation, bytes32 salt) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, salt)
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }

    function predictDeterministicAddress(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3000000000000000000000000000000)
            let hash := keccak256(ptr, 0x37)
            ptr := mload(0x40)
            mstore(ptr, 0xff00000000000000000000000000000000000000000000000000000000000000)
            mstore(add(ptr, 0x01), shl(0x60, deployer))
            mstore(add(ptr, 0x15), salt)
            mstore(add(ptr, 0x35), hash)
            predicted := keccak256(ptr, 0x55)
        }
    }
}

// ============================================================================
// SIMPLE ACCOUNT IMPLEMENTATION
// ============================================================================

contract Account is IAccountExecute {
    address public owner;
    IEntryPoint private immutable _entryPoint;

    event AccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);

    modifier onlyOwnerOrEntryPoint() {
        require(
            msg.sender == owner || msg.sender == address(_entryPoint),
            "Account: not owner or entrypoint"
        );
        _;
    }

    constructor(IEntryPoint anEntryPoint, address) {
        _entryPoint = anEntryPoint;
    }

    function entryPoint() public view returns (IEntryPoint) {
        return _entryPoint;
    }

    function initialize(address _owner, bytes calldata) public {
        require(owner == address(0), "Already initialized");
        owner = _owner;
        emit AccountInitialized(_entryPoint, _owner);
    }

    function execute(address dest, uint256 value, bytes calldata func) external override onlyOwnerOrEntryPoint {
        _call(dest, value, func);
    }

    function executeBatch(
        address[] calldata dest,
        uint256[] calldata value,
        bytes[] calldata func
    ) external override onlyOwnerOrEntryPoint {
        require(dest.length == func.length && (value.length == 0 || value.length == func.length), "wrong array lengths");
        if (value.length == 0) {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], 0, func[i]);
            }
        } else {
            for (uint256 i = 0; i < dest.length; i++) {
                _call(dest[i], value[i], func[i]);
            }
        }
    }

    function _call(address target, uint256 value, bytes memory data) internal {
        (bool success, bytes memory result) = target.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    receive() external payable {}
}

// ============================================================================
// ACCOUNT FACTORY
// ============================================================================

contract AccountFactory {
    Account public immutable accountImplementation;
    IEntryPoint public immutable entrypoint;

    event AccountCreated(address indexed account, address indexed accountAdmin);

    constructor(IEntryPoint _entrypoint) {
        entrypoint = _entrypoint;
        accountImplementation = new Account(_entrypoint, address(this));
    }

    function createAccount(address _admin, bytes calldata _data) external returns (address) {
        address impl = address(accountImplementation);
        bytes32 salt = keccak256(abi.encode(_admin, _data));
        address account = Clones.cloneDeterministic(impl, salt);

        if (account.code.length > 0) {
            return account;
        }

        Account(payable(account)).initialize(_admin, _data);
        emit AccountCreated(account, _admin);

        return account;
    }

    function getAddress(address _admin, bytes calldata _data) external view returns (address) {
        bytes32 salt = keccak256(abi.encode(_admin, _data));
        return Clones.predictDeterministicAddress(
            address(accountImplementation),
            salt,
            address(this)
        );
    }

    function getAll() external view returns (address accountImpl, address entryPoint) {
        return (address(accountImplementation), address(entrypoint));
    }
}
