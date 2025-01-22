// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title MemeAssetRegistry
 * @notice Registry contract for storing and managing meme coin asset metadata
 * @dev Prevents duplicate names, images, and descriptions for meme assets
 */
contract MemeAssetRegistry {
    struct MemeAsset {
        string name;
        string symbol;
        string imageUri;
        string description;
        bool exists;
    }

    // Mappings to track uniqueness and pending assets
    mapping(bytes32 => bool) private nameHashes;
    mapping(bytes32 => bool) private imageHashes;
    mapping(bytes32 => bool) private descriptionHashes;
    mapping(address => MemeAsset) public assets;
    mapping(bytes32 => MemeAsset) private pendingAssets;
    mapping(bytes32 => address) private pendingToFinal;
    address[] public registeredAssets;

    event AssetRegistered(
        address indexed tokenAddress,
        string name,
        string symbol,
        string imageUri,
        string description
    );

    /**
     * @notice Registers new meme asset metadata
     * @param tokenAddress The address of the meme token
     * @param name Name of the meme token
     * @param symbol Symbol of the meme token
     * @param imageUri URI of the meme image
     * @param description Description of the meme token
     */
    function registerAsset(
        address tokenAddress,
        string memory name,
        string memory symbol,
        string memory imageUri,
        string memory description
    ) external returns (bytes32) {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(bytes(symbol).length > 0, "Symbol cannot be empty");
        require(bytes(imageUri).length > 0, "Image URI cannot be empty");
        require(bytes(description).length > 0, "Description cannot be empty");
        
        bytes32 nameHash = keccak256(bytes(name));
        bytes32 imageHash = keccak256(bytes(imageUri));
        bytes32 descHash = keccak256(bytes(description));
        
        require(!nameHashes[nameHash], "Name already exists");
        require(!imageHashes[imageHash], "Image already exists");
        require(!descriptionHashes[descHash], "Description already exists");

        // Generate unique hash for pending asset
        bytes32 pendingHash = keccak256(abi.encodePacked(name, symbol, imageUri, description));
        
        // Store pending asset
        pendingAssets[pendingHash] = MemeAsset({
            name: name,
            symbol: symbol,
            imageUri: imageUri,
            description: description,
            exists: true
        });

        return pendingHash;
    }

    /**
     * @notice Checks if an asset name already exists
     * @param name Name to check
     * @return bool True if name exists
     */
    function isNameTaken(string memory name) external view returns (bool) {
        return nameHashes[keccak256(bytes(name))];
    }

    /**
     * @notice Checks if an image URI already exists
     * @param imageUri Image URI to check
     * @return bool True if image exists
     */
    function isImageTaken(string memory imageUri) external view returns (bool) {
        return imageHashes[keccak256(bytes(imageUri))];
    }

    /**
     * @notice Checks if a description already exists
     * @param description Description to check
     * @return bool True if description exists
     */
    function isDescriptionTaken(string memory description) external view returns (bool) {
        return descriptionHashes[keccak256(bytes(description))];
    }

    /**
     * @notice Gets asset data for a token address
     * @param tokenAddress Address of the token
     * @return MemeAsset Asset data struct
     */
    function getAsset(address tokenAddress) external view returns (MemeAsset memory) {
        require(assets[tokenAddress].exists, "Asset not found");
        return assets[tokenAddress];
    }

    /**
     * @notice Gets total number of registered assets
     * @return uint256 Number of registered assets
     */
    function getRegisteredAssetsCount() external view returns (uint256) {
        return registeredAssets.length;
    }

    function updateAssetAddress(address tokenAddress, bytes32 pendingHash) external {
        require(tokenAddress != address(0), "Invalid token address");
        require(!assets[tokenAddress].exists, "Asset already registered");
        require(pendingAssets[pendingHash].exists, "Pending asset not found");

        MemeAsset memory asset = pendingAssets[pendingHash];

        // Register hashes
        bytes32 nameHash = keccak256(bytes(asset.name));
        bytes32 imageHash = keccak256(bytes(asset.imageUri));
        bytes32 descHash = keccak256(bytes(asset.description));

        nameHashes[nameHash] = true;
        imageHashes[imageHash] = true;
        descriptionHashes[descHash] = true;

        // Store asset data
        assets[tokenAddress] = asset;
        registeredAssets.push(tokenAddress);
        
        // Clean up pending asset
        delete pendingAssets[pendingHash];
        
        emit AssetRegistered(
            tokenAddress,
            asset.name,
            asset.symbol,
            asset.imageUri,
            asset.description
        );
    }
}