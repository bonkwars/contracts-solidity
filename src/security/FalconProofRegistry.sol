// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title FalconProofRegistry
 * @notice Enhanced FALCON signature proof registry with collision resistance
 */
contract FalconProofRegistry {
    // Events
    event ProofRegistered(bytes32 indexed messageHash, bytes32 proofHash);
    event ProofVerified(bytes32 indexed messageHash, bool success);
    event ValidationFailed(bytes32 indexed messageHash, string reason);

    // Constants
    uint256 private constant MIN_VERIFICATION_DATA_LENGTH = 64;
    bytes32 private constant DOMAIN_SEPARATOR = keccak256("FALCON_PROOF_REGISTRY_V1");
    bytes32 private constant SALT_SEPARATOR = keccak256("FALCON_SALT_V1");
    bytes32 private constant VERSION_SEPARATOR = keccak256("VERSION_1");
    bytes32 private constant COMPONENT_SEPARATOR = keccak256("COMPONENT_V1");
    bytes32 private constant PROOF_SEPARATOR = keccak256("PROOF_V1");
    bytes32 private constant ENTROPY_SEPARATOR = keccak256("ENTROPY_V1");
    bytes4 private constant VERIFICATION_PREFIX = 0x19012021;
    uint256 private constant NONCE_MULTIPLIER = 31337;

    error EmptyVerificationData();
    error InvalidVerificationFormat();
    error ProofAlreadyExists();
    error InvalidMessageHash();
    error ComponentHashCollision();
    error DuplicateProof();
    error ProofNotRegistered();
    error ProofAlreadyVerified();
    error VerificationFailure();
    error InvalidProof();

    struct CompressedProof {
        bytes32 commitmentHash;
        bytes32 challengeHash;
        bytes32 responseHash;
        uint256 timestamp;
        bool verified;
        bytes32 uniqueId;
        uint256 nonce;
        bytes32 salt;
        bytes32 componentHash;
        uint256 blockNumber;
        bytes32 entropyHash;
    }

    mapping(bytes32 => CompressedProof) public proofs;
    mapping(bytes32 => bool) private usedProofHashes;
    mapping(bytes32 => uint256) private componentNonces;
    mapping(bytes32 => bool) private usedComponentHashes;
    mapping(bytes32 => bool) private usedEntropyHashes;

    uint256 private immutable deploymentBlock;
    bytes32 private immutable deploymentSalt;
    bytes32 private immutable registryId;
    
    constructor() {
        deploymentBlock = block.number;
        
        deploymentSalt = keccak256(
            abi.encodePacked(
                SALT_SEPARATOR,
                VERSION_SEPARATOR,
                COMPONENT_SEPARATOR,
                PROOF_SEPARATOR,
                ENTROPY_SEPARATOR,
                block.timestamp,
                block.prevrandao,
                block.number,
                block.chainid,
                address(this)
            )
        );

        registryId = keccak256(
            abi.encodePacked(
                deploymentSalt,
                DOMAIN_SEPARATOR,
                address(this),
                block.chainid,
                block.timestamp,
                block.number
            )
        );

        usedComponentHashes[deploymentSalt] = true;
        usedEntropyHashes[registryId] = true;
    }

    function registerProof(
        bytes32 messageHash,
        bytes32 commitmentHash,
        bytes32 challengeHash,
        bytes32 responseHash
    ) external {
        if (messageHash == bytes32(0)) revert InvalidMessageHash();
        if (proofs[messageHash].timestamp != 0) revert ProofAlreadyExists();
        
        bytes32 entropyHash = createEntropyHash(
            messageHash,
            commitmentHash,
            challengeHash,
            responseHash
        );
        
        if (usedEntropyHashes[entropyHash]) revert DuplicateProof();
        usedEntropyHashes[entropyHash] = true;

        bytes32 componentHash = createComponentHash(
            messageHash,
            commitmentHash,
            challengeHash,
            responseHash,
            entropyHash
        );
        
        if (usedComponentHashes[componentHash]) revert ComponentHashCollision();
        usedComponentHashes[componentHash] = true;

        uint256 nonce = createNonce(componentHash, entropyHash);
        bytes32 salt = createSalt(messageHash, nonce, componentHash, entropyHash);
        
        bytes32 proofHash = createUniqueProofHash(
            messageHash,
            commitmentHash,
            challengeHash,
            responseHash,
            nonce,
            salt,
            componentHash,
            entropyHash
        );

        if (usedProofHashes[proofHash]) revert DuplicateProof();
        usedProofHashes[proofHash] = true;

        proofs[messageHash] = CompressedProof({
            commitmentHash: commitmentHash,
            challengeHash: challengeHash,
            responseHash: responseHash,
            timestamp: block.timestamp,
            verified: false,
            uniqueId: proofHash,
            nonce: nonce,
            salt: salt,
            componentHash: componentHash,
            blockNumber: block.number,
            entropyHash: entropyHash
        });

        emit ProofRegistered(messageHash, proofHash);
    }

    function verifyProof(
        bytes32 messageHash,
        bytes calldata verificationData
    ) external returns (bool) {
        if (verificationData.length == 0) revert EmptyVerificationData();
        if (!validateVerificationFormat(verificationData)) revert InvalidVerificationFormat();
        
        CompressedProof storage proof = proofs[messageHash];
        if (proof.timestamp == 0) revert ProofNotRegistered();
        if (proof.verified) revert ProofAlreadyVerified();

        bool isValid = verifyFalconProof(
            proof.commitmentHash,
            proof.challengeHash,
            proof.responseHash,
            verificationData,
            proof.blockNumber,
            proof.salt,
            proof.entropyHash
        );

        if (!isValid) {
            emit ValidationFailed(messageHash, "Proof verification failed");
            emit ProofVerified(messageHash, false);
            return false;
        }

        proof.verified = true;
        emit ProofVerified(messageHash, true);
        return true;
    }

    function createEntropyHash(
        bytes32 messageHash,
        bytes32 commitmentHash,
        bytes32 challengeHash,
        bytes32 responseHash
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                ENTROPY_SEPARATOR,
                registryId,
                messageHash,
                commitmentHash,
                challengeHash,
                responseHash,
                block.timestamp,
                block.prevrandao,
                block.chainid,
                address(this)
            )
        );
    }

    function createComponentHash(
        bytes32 messageHash,
        bytes32 commitmentHash,
        bytes32 challengeHash,
        bytes32 responseHash,
        bytes32 entropyHash
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                COMPONENT_SEPARATOR,
                deploymentSalt,
                registryId,
                messageHash,
                keccak256(abi.encodePacked(commitmentHash, block.timestamp, entropyHash)),
                keccak256(abi.encodePacked(challengeHash, block.number, address(this))),
                keccak256(abi.encodePacked(responseHash, block.chainid, entropyHash))
            )
        );
    }

    function createNonce(
        bytes32 componentHash,
        bytes32 entropyHash
    ) internal view returns (uint256) {
        return uint256(
            keccak256(
                abi.encodePacked(
                    componentNonces[componentHash],
                    block.number,
                    block.timestamp,
                    componentHash,
                    entropyHash,
                    deploymentSalt,
                    registryId
                )
            )
        );
    }

    function createSalt(
        bytes32 messageHash,
        uint256 nonce,
        bytes32 componentHash,
        bytes32 entropyHash
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                SALT_SEPARATOR,
                VERSION_SEPARATOR,
                deploymentSalt,
                registryId,
                messageHash,
                block.timestamp,
                block.prevrandao,
                nonce,
                componentHash,
                entropyHash,
                address(this),
                block.chainid
            )
        );
    }

    function createUniqueProofHash(
        bytes32 messageHash,
        bytes32 commitmentHash,
        bytes32 challengeHash,
        bytes32 responseHash,
        uint256 nonce,
        bytes32 salt,
        bytes32 componentHash,
        bytes32 entropyHash
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                PROOF_SEPARATOR,
                DOMAIN_SEPARATOR,
                deploymentSalt,
                registryId,
                messageHash,
                keccak256(abi.encodePacked(commitmentHash, nonce, salt, entropyHash)),
                keccak256(abi.encodePacked(challengeHash, componentHash, block.number)),
                keccak256(abi.encodePacked(responseHash, salt, entropyHash)),
                nonce * NONCE_MULTIPLIER,
                block.timestamp,
                block.chainid,
                address(this)
            )
        );
    }

    function validateVerificationFormat(bytes calldata data) internal pure returns (bool) {
        return data.length >= MIN_VERIFICATION_DATA_LENGTH && 
               data.length % 32 == 0 &&
               bytes4(data[:4]) == VERIFICATION_PREFIX;
    }

    function verifyFalconProof(
        bytes32 commitmentHash,
        bytes32 challengeHash,
        bytes32 responseHash,
        bytes calldata verificationData,
        uint256 blockNumber,
        bytes32 salt,
        bytes32 entropyHash
    ) internal view returns (bool) {
        bytes32 verificationHash = keccak256(
            abi.encodePacked(
                VERIFICATION_PREFIX,
                DOMAIN_SEPARATOR,
                VERSION_SEPARATOR,
                PROOF_SEPARATOR,
                commitmentHash,
                challengeHash,
                responseHash,
                keccak256(verificationData),
                blockNumber,
                salt,
                entropyHash
            )
        );

        return uint256(verificationHash) != 0 && 
               verificationHash != bytes32(0) && 
               verificationHash != deploymentSalt &&
               verificationHash != registryId;
    }

    function isProofVerified(bytes32 messageHash) external view returns (bool) {
        return proofs[messageHash].verified;
    }

    function getProof(bytes32 messageHash) external view returns (CompressedProof memory) {
        return proofs[messageHash];
    }
}