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
    address public second_contributor = address(0x125);
    address public first_purchaser = address(0x126);
    address public treasury = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;
    address public rendinex = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;

    function setUp() public {
        usdt = new Token("USDT", "USDT", 6);
        // The contract owner is the deployer of the contract which is the test contract, not the caller
        vm.prank(contract_owner);
        rvtc = new RVTC(address(usdt), treasury, rendinex);

        // Mint USDT to contributors
        usdt.mint(first_contributor, 10_000 * 10 ** 6);
        usdt.mint(second_contributor, 8_000 * 10 ** 6);

        // Create license
        uint256 licenseGoal = 10_000 * 10 ** 6;
        vm.prank(contract_owner);
        rvtc.createLicense(licenseGoal, licenseGoal);

        // Approve the RVTC contract to spend the tokens on behalf of the user
        vm.prank(user);
        usdt.approve(address(rvtc), type(uint256).max);
    }

    // Test reduction of funding
    function testReduceFundingGoal() public {
        uint256 reducedFunding = 3_000 * 10 ** 6;
        vm.prank(contract_owner);
        rvtc.reduceFundingGoal(0, reducedFunding);
        // Get license data
        (,, uint256[] memory fundingGoals,,) = rvtc.getLicenses();
        assertEq(fundingGoals[0], reducedFunding);
    }

    // Test contribution to license
    function testContributeToLicense() public {
        vm.prank(contract_owner);
        rvtc.createLicense(10_000 * 10 ** 6, 10_000 * 10 ** 6);

        vm.prank(first_contributor);
        usdt.approve(address(rvtc), 3_000 * 10 ** 6);
        vm.prank(first_contributor);
        rvtc.contributeToLicense(0, 3_000 * 10 ** 6);

        (,,, uint256[] memory fundsRaised,) = rvtc.getLicenses();
        assertEq(fundsRaised[0], 3_000 * 10 ** 6);
        uint256 totalFundsToCollect = rvtc.totalFundsForLicenses();
        assertEq(totalFundsToCollect, 3_000 * 10 ** 6);
    }

    // Test collection of funds
    function testFundingCollection() public {
        // Ensure the owner of the contract has 0 usdt in the beginning
        uint256 balance = usdt.balanceOf(contract_owner);
        assertEq(balance, 0);

        vm.prank(first_contributor);
        usdt.approve(address(rvtc), 3_000 * 10 ** 6);
        vm.prank(first_contributor);
        rvtc.contributeToLicense(0, 3_000 * 10 ** 6);

        vm.prank(second_contributor);
        usdt.approve(address(rvtc), 4_000 * 10 ** 6);
        vm.prank(second_contributor);
        rvtc.contributeToLicense(0, 4_000 * 10 ** 6);

        (,,, uint256[] memory fundsRaised,) = rvtc.getLicenses();
        assertEq(fundsRaised[0], 7_000 * 10 ** 6);
        uint256 totalFundsToCollect = rvtc.totalFundsForLicenses();
        assertEq(totalFundsToCollect, 7_000 * 10 ** 6);

        vm.prank(contract_owner);
        rvtc.collectLicenseFunds(contract_owner);
        balance = usdt.balanceOf(contract_owner);
        assertEq(balance, 7_000 * 10 ** 6);

        totalFundsToCollect = rvtc.totalFundsForLicenses();
        assertEq(totalFundsToCollect, 0);
    }

    function testWithdrawContribution() public {
        vm.prank(first_contributor);
        usdt.approve(address(rvtc), 5_000 * 10 ** 6);
        vm.prank(first_contributor);
        rvtc.contributeToLicense(0, 5_000 * 10 ** 6);

        vm.prank(first_contributor);
        rvtc.withdrawContribution(0);

        (,,, uint256[] memory fundsRaised,) = rvtc.getLicenses();
        assertEq(fundsRaised[0], 0);
    }

    function testFinalizeLicense() public {
        vm.prank(first_contributor);
        usdt.approve(address(rvtc), 3_000 * 10 ** 6);
        vm.prank(first_contributor);
        rvtc.contributeToLicense(0, 3_000 * 10 ** 6);

        vm.prank(second_contributor);
        usdt.approve(address(rvtc), 7_000 * 10 ** 6);
        vm.prank(second_contributor);
        rvtc.contributeToLicense(0, 7_000 * 10 ** 6);

        (,,, uint256[] memory updatedFundsRaised,) = rvtc.getLicenses();
        assertEq(updatedFundsRaised[0], 10_000 * 10 ** 6);

        vm.prank(contract_owner);
        rvtc.finalizeLicense(0);

        (,,,, bool[] memory fundingCompleted) = rvtc.getLicenses();
        assertTrue(fundingCompleted[0]);
    }

    function testDistributeProfits() public {
        vm.prank(first_contributor);
        usdt.approve(address(rvtc), 3_000 * 10 ** 6);
        vm.prank(first_contributor);
        rvtc.contributeToLicense(0, 3_000 * 10 ** 6);

        vm.prank(second_contributor);
        usdt.approve(address(rvtc), 7_000 * 10 ** 6);
        vm.prank(second_contributor);
        rvtc.contributeToLicense(0, 7_000 * 10 ** 6);

        (,,, uint256[] memory updatedFundsRaised,) = rvtc.getLicenses();
        assertEq(updatedFundsRaised[0], 10_000 * 10 ** 6);
        vm.prank(contract_owner);
        rvtc.finalizeLicense(0);

        // Repartition of tokens
        vm.prank(contract_owner);
        rvtc.distributeTokensForLicense(0, first_contributor, 300 * 10 ** 2);
        vm.prank(contract_owner);
        rvtc.distributeTokensForLicense(0, second_contributor, 700 * 10 ** 2);

        // Test balance of contributors
        uint256 balanceAfterMintFirstContributor = rvtc.balanceOf(first_contributor);
        assertEq(balanceAfterMintFirstContributor, 300 * 10 ** 2);
        uint256 balanceAfterMintSecondContributor = rvtc.balanceOf(second_contributor);
        assertEq(balanceAfterMintSecondContributor, 700 * 10 ** 2);

        (,,,, bool[] memory fundingCompleted) = rvtc.getLicenses();
        assertTrue(fundingCompleted[0]);

        usdt.mint(contract_owner, 1_000 * 10 ** 6);
        vm.prank(contract_owner);
        usdt.approve(address(rvtc), 1_000 * 10 ** 6);
        vm.prank(contract_owner);
        rvtc.distributeProfits(1_000 * 10 ** 6);

        // There are 1000 tokens minted per license so the profit per token should be 1 usdt scaled
        assertEq(rvtc.cumulativeProfitPerToken(), 1 * 10 ** 22);

        // The first contributor has 7000 usdt left so after withdrawing his 300 usdt he should have 7300 in total
        vm.prank(first_contributor);
        rvtc.withdrawProfits();
        uint256 balance = usdt.balanceOf(first_contributor);
        assertEq(balance, 7_300 * 10 ** 6);
    }

    /*
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
