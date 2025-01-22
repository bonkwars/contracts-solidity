// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../api/verifier.sol";

contract TestFalconVerifier {
    Groth16Verifier public verifier;

    constructor() {
        verifier = new Groth16Verifier();
    }

    function testVerification(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[18] memory input
    ) public view returns (bool) {
        return verifier.verifyProof(a, b, c, input);
    }
}