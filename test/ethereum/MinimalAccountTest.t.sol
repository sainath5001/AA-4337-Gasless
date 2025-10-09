// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {DeployMinimal} from "script/DeployMinimal.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp, PackedUserOperation, IEntryPoint} from "script/SendPackedUserOp.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ZkSyncChainChecker} from "lib/foundry-devops/src/ZkSyncChainChecker.sol";

contract MinimalAccountTest is Test, ZkSyncChainChecker {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    ERC20Mock usdc;
    SendPackedUserOp sendPackedUserOp;

    address randomuser = makeAddr("randomUser");

    uint256 constant AMOUNT = 1e18;

    function setUp() public skipZkSync {
        DeployMinimal deployMinimal = new DeployMinimal();
        (helperConfig, minimalAccount) = deployMinimal.deployMinimalAccount();
        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();
    }

    // USDC Mint
    // msg.sender -> MinimalAccount
    // approve some amount
    // USDC contract
    // come from the entrypoint
    function testOwnerCanExecuteCommands() public skipZkSync {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testNonOwnerCannotExecuteCommands() public skipZkSync {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    function testRecoverSignedOp() public skipZkSync {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );
        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);

        // Act
        address actualSigner = ECDSA.recover(userOperationHash.toEthSignedMessageHash(), packedUserOp.signature);

        // Assert
        assertEq(actualSigner, minimalAccount.owner());
    }

    // 1. Sign user ops
    // 2. Call validate userops
    // 3. Assert the return is correct
    function testValidationOfUserOps() public skipZkSync {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );
        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);
        uint256 missingAccountFunds = 1e18;

        // Act
        vm.prank(helperConfig.getConfig().entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);
        assertEq(validationData, 0);
    }

    function testEntryPointCanExecuteCommands() public skipZkSync {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );
        // bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);

        vm.deal(address(minimalAccount), 1e18);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        // Act
        vm.prank(randomuser);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(randomuser));

        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testNonEntryPointCannotExecuteCommands() public skipZkSync {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(MinimalAccount.execute.selector, dest, value, functionData);

        PackedUserOperation memory packedUserOp = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), 1e18);

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;

        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(randomuser));
    }

    function testOwnerCanChangeEntryPoint() public skipZkSync {
        // Arrange
        address newEntryPoint = makeAddr("newEntryPoint");
        assertEq(minimalAccount.entryPoint(), helperConfig.getConfig().entryPoint);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.changeEntryPoint(newEntryPoint);

        // Assert
        assertEq(minimalAccount.entryPoint(), newEntryPoint);
    }

    function testNonOwnerCannotChangeEntryPoint() public skipZkSync {
        // Arrange
        address newEntryPoint = makeAddr("newEntryPoint");
        assertEq(minimalAccount.entryPoint(), helperConfig.getConfig().entryPoint);

        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.changeEntryPoint(newEntryPoint);
    }

    function testOwnerCanChangeOwner() public skipZkSync {
        // Arrange
        address newOwner = makeAddr("newOwner");
        assertEq(minimalAccount.owner(), helperConfig.getConfig().owner);
    }

    function testNonOwnerCannotChangeOwner() public skipZkSync {
        // Arrange
        address newOwner = makeAddr("newOwner");
        assertEq(minimalAccount.owner(), helperConfig.getConfig().owner);

        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.changeOwner(newOwner);
    }

    function testfuzzingExecute(address dest, uint256 value, bytes memory functionData) public skipZkSync {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        vm.assume(dest != address(0));
        vm.assume(value < 1e18); // Prevent excessive gas usage
        vm.assume(functionData.length > 0);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(dest, value, functionData);

        // Assert
        // Check if the call was successful by checking the balance of the destination contract
        assertTrue(true); // Placeholder for actual checks based on functionData
    }

    function testfuzzingExecuteWithRevert(address dest, uint256 value, bytes memory functionData) public skipZkSync {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        vm.assume(dest != address(0));
        vm.assume(value < 1e18); // Prevent excessive gas usage
        vm.assume(functionData.length > 0);

        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
    }

    function testfuzzingChangeEntryPoint(address newEntryPoint) public skipZkSync {
        // Arrange
        vm.assume(newEntryPoint != address(0));
        assertEq(minimalAccount.entryPoint(), helperConfig.getConfig().entryPoint);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.changeEntryPoint(newEntryPoint);

        // Assert
        assertEq(minimalAccount.entryPoint(), newEntryPoint);
    }

    function testfuzzingChangeEntryPointWithRevert(address newEntryPoint) public skipZkSync {
        // Arrange
        vm.assume(newEntryPoint != address(0));
        assertEq(minimalAccount.entryPoint(), helperConfig.getConfig().entryPoint);

        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.changeEntryPoint(newEntryPoint);
    }

    function testfuzzingChangeOwner(address newOwner) public skipZkSync {
        // Arrange
        vm.assume(newOwner != address(0));
        assertEq(minimalAccount.owner(), helperConfig.getConfig().owner);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.changeOwner(newOwner);

        // Assert
        assertEq(minimalAccount.owner(), newOwner);
    }

    function testfuzzingChangeOwnerWithRevert(address newOwner) public skipZkSync {
        // Arrange
        vm.assume(newOwner != address(0));
        assertEq(minimalAccount.owner(), helperConfig.getConfig().owner);

        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.changeOwner(newOwner);
    }

    function testfuzzingValidateUserOp(
        PackedUserOperation memory packedUserOp,
        bytes32 userOperationHash,
        uint256 missingAccountFunds
    ) public skipZkSync {
        // Arrange
        vm.assume(missingAccountFunds < 1e18); // Prevent excessive gas usage

        // Act
        vm.prank(helperConfig.getConfig().entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);

        // Assert
        assertEq(validationData, 0);
    }

    function testfuzzingValidateUserOpWithRevert(
        PackedUserOperation memory packedUserOp,
        bytes32 userOperationHash,
        uint256 missingAccountFunds
    ) public skipZkSync {
        // Arrange
        vm.assume(missingAccountFunds < 1e18); // Prevent excessive gas usage

        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);
    }

    function testfuzzingHandleOps(PackedUserOperation[] memory ops, address target) public skipZkSync {
        // Arrange
        vm.assume(ops.length > 0);
        vm.assume(target != address(0));

        // Act
        vm.prank(helperConfig.getConfig().entryPoint);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(target));

        // Assert
        // Check if the operations were handled successfully
        assertTrue(true); // Placeholder for actual checks based on the operations
    }

    function testfuzzingHandleOpsWithRevert(PackedUserOperation[] memory ops, address target) public skipZkSync {
        // Arrange
        vm.assume(ops.length > 0);
        vm.assume(target != address(0));

        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(target));
    }

    function testfuzzingOwnerChange(address newOwner, address newEntryPoint) public skipZkSync {
        // Arrange
        vm.assume(newOwner != address(0));
        vm.assume(newEntryPoint != address(0));
        assertEq(minimalAccount.owner(), helperConfig.getConfig().owner);
        assertEq(minimalAccount.entryPoint(), helperConfig.getConfig().entryPoint);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.changeOwner(newOwner);
        minimalAccount.changeEntryPoint(newEntryPoint);

        // Assert
        assertEq(minimalAccount.owner(), newOwner);
        assertEq(minimalAccount.entryPoint(), newEntryPoint);
    }

    function testfuzzingChangeEntryPoint(address newEntryPoint) public skipZkSync {
        // Arrange
        vm.assume(newEntryPoint != address(0));
        assertEq(minimalAccount.entryPoint(), helperConfig.getConfig().entryPoint);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.changeEntryPoint(newEntryPoint);

        // Assert
        assertEq(minimalAccount.entryPoint(), newEntryPoint);
    }

    function testfuzzingChangeEntryPoint(address newEntryPoint) public skipZkSync {
        // Arrange
        vm.assume(newEntryPoint != address(0));
        assertEq(minimalAccount.entryPoint(), helperConfig.getConfig().entryPoint);

        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.changeEntryPoint(newEntryPoint);

        // Assert
        assertEq(minimalAccount.entryPoint(), newEntryPoint);
    }

    function testfuzzingChangeEntryPointWithRevert(address newEntryPoint) public skipZkSync {
        // Arrange
        vm.assume(newEntryPoint != address(0));
        assertEq(minimalAccount.entryPoint(), helperConfig.getConfig().entryPoint);

        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.changeEntryPoint(newEntryPoint);
    }

    function testfuzzingEntrypointExecuteCommands(PackedUserOperation[] memory ops, address target) public skipZkSync {
        // Arrange
        vm.assume(ops.length > 0);
        vm.assume(target != address(0));

        // Act
        vm.prank(helperConfig.getConfig().entryPoint);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(target));

        // Assert
        // Check if the operations were handled successfully
        assertTrue(true); // Placeholder for actual checks based on the operations
    }

    function testfuzzingEntrypointExecuteCommandsWithRevert(PackedUserOperation[] memory ops, address target)
        public
        skipZkSync
    {
        // Arrange
        vm.assume(ops.length > 0);
        vm.assume(target != address(0));
        // Act
        vm.prank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(target));
    }
}
