// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {DeployMinimal} from "script/DeployMinimal.s.sol";

contract MinimalAccountTest is Test {
    HelperConfig helperConfig;
    MinimalAccount minimalAccount;

    function setUp() public {
        DeployMinimal deployMinimal = new DeployMinimal();
        (helperConfig, MinimalAccount) = deployMinimal.deployMinimalAccount();
    }
}
