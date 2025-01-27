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
    address public third_contributor = address(0x127);
    address public first_purchaser = address(0x126);
    address public treasury = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;
    address public rendinex = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;

    function setUp() public {
        usdt = new Token("USDT", "USDT", 18);
        // The contract owner is the deployer of the contract which is the test contract, not the caller
        vm.prank(contract_owner);
        rvtc = new RVTC(address(usdt), treasury, rendinex);

        // Mint USDT to contributors
        usdt.mint(first_contributor, 10_000 * 10 ** 6);
        usdt.mint(second_contributor, 8_000 * 10 ** 6);
        usdt.mint(third_contributor, 20_000 * 10 ** 6);

        // Create license
        uint256 licenseGoal = 10_000 * 10 ** 6;
        vm.prank(contract_owner);
        rvtc.createLicense(licenseGoal, licenseGoal);

        // Approve the RVTC contract to spend the tokens on behalf of the user
        vm.prank(user);
        usdt.approve(address(rvtc), type(uint256).max);

        vm.prank(first_contributor);
        usdt.approve(address(rvtc), 10_000 * 10 ** 6);
        vm.prank(first_contributor);
        rvtc.contributeToLicense(0, 3_000 * 10 ** 6);

        vm.prank(second_contributor);
        usdt.approve(address(rvtc), 8_000 * 10 ** 6);
        vm.prank(second_contributor);
        rvtc.contributeToLicense(0, 7_000 * 10 ** 6);

        vm.prank(contract_owner);
        rvtc.finalizeLicense(0);

        vm.prank(contract_owner);
        rvtc.distributeTokensForLicense(0, first_contributor, 300 * 10 ** 2);
        vm.prank(contract_owner);
        rvtc.distributeTokensForLicense(0, second_contributor, 700 * 10 ** 2);

        // Create second license
        uint256 secondLicenseGoal = 12_000 * 10 ** 6;
        vm.prank(contract_owner);
        rvtc.createLicense(secondLicenseGoal, secondLicenseGoal);

        vm.prank(third_contributor);
        usdt.approve(address(rvtc), 20_000 * 10 ** 6);
        vm.prank(third_contributor);
        rvtc.contributeToLicense(1, 10_000 * 10 ** 6);
        vm.prank(first_contributor);
        rvtc.contributeToLicense(1, 2_000 * 10 ** 6);

        vm.prank(contract_owner);
        rvtc.finalizeLicense(1);

        vm.prank(contract_owner);
        rvtc.distributeTokensForLicense(1, third_contributor, 833 * 10 ** 2);
        vm.prank(contract_owner);
        rvtc.distributeTokensForLicense(1, first_contributor, 167 * 10 ** 2);

        (,,, uint256[] memory updatedFundsRaised,) = rvtc.getLicenses();
        assertEq(updatedFundsRaised[0], 10_000 * 10 ** 6);
        assertEq(updatedFundsRaised[1], 12_000 * 10 ** 6);
    }

    function testSaleOfLicense() public {
        // Deposit tokens from contributors
        vm.prank(first_contributor);
        rvtc.depositTokens(300 * 10 ** 2);

        vm.prank(second_contributor);
        rvtc.depositTokens(300 * 10 ** 2);

        vm.prank(third_contributor);
        rvtc.depositTokens(500 * 10 ** 2);

        // Assert the total locked tokens after deposits
        uint256 totalLocked = rvtc.totalLockedTokens();
        uint256 expectedTotalLocked = 1000 * 10 ** 2;
        assertEq(totalLocked, expectedTotalLocked);

        // Finalize the sale
        vm.prank(contract_owner);
        rvtc.finalizeSale();

        // Check the final state after sale
        uint256 lockedTokensFirst = rvtc.lockedTokens(first_contributor);
        uint256 lockedTokensSecond = rvtc.lockedTokens(second_contributor);
        uint256 lockedTokensThird = rvtc.lockedTokens(third_contributor);

        // After sale is finalized, the locked tokens should be burned (i.e., 0)
        assertEq(lockedTokensFirst, 0);
        assertEq(lockedTokensSecond, 0);
        assertEq(lockedTokensThird, 0);

        // Check if the totalLockedTokens variable is reset
        uint256 totalLockedAfterSale = rvtc.totalLockedTokens();
        assertEq(totalLockedAfterSale, 0);

        // Check the number of licenses finalized, ensuring we incremented the counter correctly
        uint256 totalLicensesReturned = rvtc.totalLicensesReturned();
        assertEq(totalLicensesReturned, 1);

        // Ensure the balances of the contributors have been updated correctly
        uint256 balanceFirst = rvtc.balanceOf(first_contributor);
        uint256 balanceSecond = rvtc.balanceOf(second_contributor);
        uint256 balanceThird = rvtc.balanceOf(third_contributor);

        // Assuming the contract burns tokens upon finalizeSale
        assertEq(balanceFirst, 167 * 10 ** 2);
        assertEq(balanceSecond, 400 * 10 ** 2);
        assertEq(balanceThird, 433 * 10 ** 2);

        uint256 finalTotalSupply = rvtc.totalSupply();
        assertEq(finalTotalSupply, 1000 * 10 ** 2);
    }
}
