// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MemeCoin.sol";
import "./MemeAssetRegistry.sol";
import "./security/AntiRugPull.sol";
import "./security/interfaces/IAntiRugPull.sol";

/**
 * @title MemeCoinFactory
 * @notice Factory contract for creating meme coins with deterministic addresses using CREATE2
 * @dev Uses CREATE2 opcode for predictable deployment addresses
 */
contract MemeCoinFactory {
    address public immutable antiRugPull;
    address public immutable assetRegistry;
    mapping(bytes32 => address) public getMemeCoin;
    address[] public allMemeCoins;
    
    event MemeCoinCreated(
        string name,
        string symbol,
        address indexed memeCoin,
        address indexed owner,
        uint256 totalSupply
    );

    constructor(address _antiRugPull, address _assetRegistry) {
        require(_antiRugPull != address(0), "Invalid AntiRugPull address");
        require(_assetRegistry != address(0), "Invalid AssetRegistry address");
        antiRugPull = _antiRugPull;
        assetRegistry = _assetRegistry;
    }

    /**
     * @notice Computes the address where a memecoin will be deployed
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param owner The initial owner of the token
     * @param salt Additional value to ensure uniqueness
     * @return The address where the memecoin would be deployed
     */
    function predictMemeCoinAddress(
        string memory name,
        string memory symbol,
        address owner,
        uint256 salt
    ) public view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                keccak256(abi.encodePacked(name, symbol, owner, salt)),
                keccak256(type(MemeCoin).creationCode)
            )
        );
        return address(uint160(uint256(hash)));
    }

    /**
     * @notice Creates a new memecoin with a deterministic address
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param owner The initial owner of the token
     * @param initialSupply The initial supply to mint
     * @param salt Additional value to ensure uniqueness
     * @return memeCoin The address of the deployed memecoin
     */
    function createMemeCoin(
        string memory name,
        string memory symbol,
        string memory imageUri,
        string memory description,
        address owner,
        uint256 initialSupply,
        uint256 salt
    ) external returns (address memeCoin) {
        bytes32 pendingHash;
        // Input validation
        require(owner != address(0), "Invalid owner address");
        require(initialSupply > 0, "Initial supply must be positive");
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        require(bytes(imageUri).length > 0, "Image URI cannot be empty");
        require(bytes(description).length > 0, "Description cannot be empty");
        
        // Generate salt and check uniqueness
        bytes32 saltHash = keccak256(abi.encodePacked(name, symbol, owner, salt));
        require(getMemeCoin[saltHash] == address(0), "MemeCoin already exists");

        // Security validations
      //  require(!IAntiRugPull(antiRugPull).isContractBlacklisted(msg.sender), "Caller blacklisted");
        require(initialSupply <= type(uint256).max / 100, "Initial supply too large");

        // Register metadata first to ensure uniqueness and get pending hash
        try MemeAssetRegistry(assetRegistry).registerAsset(
            address(0),
            name,
            symbol,
            imageUri,
            description
        ) returns (bytes32 _pendingHash) {
            pendingHash = _pendingHash;
        } catch Error(string memory reason) {
            revert(reason);
        } catch {
            revert("Failed to register metadata");
        }

        // Prepare creation bytecode with constructor arguments
        bytes memory bytecode = type(MemeCoin).creationCode;
        bytes memory encodedArgs = abi.encode(name, symbol, owner, antiRugPull);
        bytes memory combinedBytecode = bytes.concat(bytecode, encodedArgs);

        // Deploy contract
        assembly {
            memeCoin := create2(0, add(combinedBytecode, 32), mload(combinedBytecode), saltHash)
            if iszero(extcodesize(memeCoin)) {
                revert(0, 0)
            }
        }

        require(memeCoin != address(0), "Deployment failed");

        // Security validation first
      //  if (!IAntiRugPull(antiRugPull).validateDeployment(memeCoin)) {
       //     revert("Failed security validation");
       // }

        // Initialize token
        try MemeCoin(memeCoin).mint(owner, initialSupply) {
            // Store deployment info
            getMemeCoin[saltHash] = memeCoin;
            allMemeCoins.push(memeCoin);

            // Update metadata with actual address
            MemeAssetRegistry(assetRegistry).updateAssetAddress(memeCoin, pendingHash);
        } catch {
            revert("Initialization failed");
        }

        emit MemeCoinCreated(name, symbol, memeCoin, owner, initialSupply);
        return memeCoin;
    }

    /**
     * @notice Returns the total number of memecoins created
     */
    function allMemeCoinsLength() external view returns (uint256) {
        return allMemeCoins.length;
    }
}