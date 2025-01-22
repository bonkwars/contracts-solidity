// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IFalconVerifier
 * @author Degen4Life Team
 * @notice Interface for Falcon signature verification
 * @dev Defines the standard interface for verifying Falcon post-quantum signatures
 * @custom:security-contact security@memeswap.exchange
 */
interface IFalconVerifier {
    /**
     * @notice Verifies a Falcon signature
     * @param messageHash Hash of the message that was signed
     * @param signature Falcon signature bytes
     * @param publicKeyH First component of the public key
     * @param publicKeyRho Second component of the public key
     * @return True if signature is valid
     */
    function verifySignature(
        bytes32 messageHash,
        bytes calldata signature,
        bytes32 publicKeyH,
        bytes32 publicKeyRho
    ) external view returns (bool);

    /**
     * @notice Gets the Falcon parameters used by this implementation
     * @return n Falcon parameter N (degree of polynomials)
     * @return q Modulus q
     * @return sigma Standard deviation σ
     */
    function getFalconParameters()
        external
        view
        returns (uint256 n, uint256 q, uint256 sigma);
}
