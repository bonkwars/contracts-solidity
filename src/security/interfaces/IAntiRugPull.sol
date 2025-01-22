// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAntiRugPull {
    function isContractBlacklisted(address account) external view returns (bool);
    function validateDeployment(address token) external returns (bool);
}