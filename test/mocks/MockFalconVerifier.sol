// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/security/interfaces/IFalconVerifier.sol";

contract MockFalconVerifier is IFalconVerifier {
    bool public shouldVerify = true;
    
    function verifySignature(
        bytes32 messageHash,
        bytes calldata signature,
        bytes32 publicKeyH,
        bytes32 publicKeyRho
    ) external view override returns (bool) {
        return shouldVerify;
    }
    
    function getFalconParameters() 
        external 
        pure 
        override 
        returns (uint256 n, uint256 q, uint256 sigma) 
    {
        return (1024, 12289, 1);
    }
    
    function setShouldVerify(bool _shouldVerify) external {
        shouldVerify = _shouldVerify;
    }
}