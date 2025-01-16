// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Token} from "../src/BasicTokenERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import "../src/VTCContract.sol";

contract RVTCTest is Test {
    RVTC public rvtc;
    Token public usdt;

    address public contract_owner = address(0x121);
    address public user = address(0x123);
    address public first_contributor = address(0x124);
    address public treasury = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;
    address public rendinex = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;

    function setUp() public {
        usdt = new Token("USDT", "USDT", 18);
        // The contract owner is the deployer of the contract which is the test contract, not the caller
        vm.prank(contract_owner);
        rvtc = new RVTC(address(usdt), treasury, rendinex);

        // Mint USDT to contributors
        usdt.mint(first_contributor, 10_000 * 10 ** 6);

        // Create license
        uint256 licenseGoal = 10_000 * 10 ** 6;
        vm.prank(contract_owner);
        rvtc.createLicense(licenseGoal);

        // Approve the RVTC contract to spend the tokens on behalf of the user
        vm.prank(user);
        usdt.approve(address(rvtc), type(uint256).max);
    }

    // Test creation of license
    function testCreateLicense() public view {
        uint256 licenseGoal = 10_000 * 10 ** 6;

        // Get license data
        (
            uint256[] memory ids,
            uint256[] memory fundingGoals,
            uint256[] memory updatedFundsRaised,
            bool[] memory fundingCompleted
        ) = rvtc.getLicenses();

        assertEq(ids.length, 1);
        assertEq(ids[0], 0);
        assertEq(fundingGoals[0], licenseGoal);
        assertEq(updatedFundsRaised[0], 0);
        assertEq(fundingCompleted[0], false);
    }

    // Test reduction of funding
    function testReduceFundingGoal() public {
        uint256 reducedFunding = 3_000 * 10 ** 6;
        vm.prank(contract_owner);
        rvtc.reduceFundingGoal(0, reducedFunding);
        // Get license data
        (, uint256[] memory fundingGoals,,) = rvtc.getLicenses();
        assertEq(fundingGoals[0], reducedFunding);
    }

    /*
    function testContributeToLicense() public {
        vm.prank(owner);
        rvtc.createLicense(1000);

        vm.prank(user);
        usdtToken.approve(address(rvtc), 500);
        vm.prank(user);
        rvtc.contributeToLicense(0, 500);

        (uint256[] memory ids, , uint256[] memory fundsRaised, ) = rvtc
            .getLicenses();
        assertEq(fundsRaised[0], 500);
    }

    function testWithdrawContribution() public {
        vm.prank(owner);
        rvtc.createLicense(1000);

        vm.prank(user);
        usdtToken.approve(address(rvtc), 500);
        vm.prank(user);
        rvtc.contributeToLicense(0, 500);

        vm.prank(user);
        rvtc.withdrawContribution(0);

        (uint256[] memory ids, , uint256[] memory fundsRaised, ) = rvtc
            .getLicenses();
        assertEq(fundsRaised[0], 0);
    }

    function testMintLicense() public {
        vm.prank(owner);
        rvtc.mintLicense(1000);

        (uint256[] memory ids, , , ) = rvtc.getLicenses();
        assertEq(ids.length, 1);
    }

    function testFinalizeLicense() public {
        vm.prank(owner);
        rvtc.createLicense(1000);

        vm.prank(user);
        usdtToken.approve(address(rvtc), 1000);
        vm.prank(user);
        rvtc.contributeToLicense(0, 1000);

        vm.prank(owner);
        rvtc.finalizeLicense(0);

        (uint256[] memory ids, , , bool[] memory fundingCompleted) = rvtc
            .getLicenses();
        assertTrue(fundingCompleted[0]);
    }

    function testTotalLicensesMinted() public {
        vm.prank(owner);
        rvtc.createLicense(1000);

        vm.prank(user);
        usdtToken.approve(address(rvtc), 1000);
        vm.prank(user);
        rvtc.contributeToLicense(0, 1000);

        vm.prank(owner);
        rvtc.finalizeLicense(0);

        assertEq(rvtc.totalLicensesMinted(), 1);
    }

    function testDeployUSDTToken() public {
        uint256 licenseGoal = 10_000 * 10 ** 6; // 10,000 USDT
        uint256 contributionAmount = 1_000 * 10 ** 6; // 1,000 USDT

        // Create a license with a funding goal
        rvtc.createLicense(licenseGoal);

        // Get license data
        (, uint256[] memory fundingGoals, , ) = rvtc.getLicenses();

        // Verify the license's funding goal
        assertEq(fundingGoals[0], licenseGoal);

        // Contribute to the license from the user's account
        vm.prank(user); // Simulate the contribution from the user address
        rvtc.contributeToLicense(0, contributionAmount);

        // Get updated license data
        (, , uint256[] memory updatedFundsRaised, ) = rvtc.getLicenses();

        // Verify the funds raised
        assertEq(updatedFundsRaised[0], contributionAmount);
    }
    */
}
