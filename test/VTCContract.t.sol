// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Token} from "../src/BasicTokenERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import "../src/VTCContract.sol";

contract RVTCTest is Test {
    RVTC public rvtc;
    Token public usdt;

    address public user = address(0x123);
    address public treasury = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;
    address public rendinex = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;

    function setUp() public {
        usdt = new Token("USDT", "USDT", 18);
        rvtc = new RVTC(address(usdt), treasury, rendinex);
        // Mint 100,000 USDT to test address
        usdt.mint(user, 10_000 * 10 ** 18);

        // Approve the RVTC contract to spend the tokens on behalf of the user
        vm.prank(user); // "vm.prank" simulates transactions from another address
        usdt.approve(address(rvtc), type(uint256).max);
    }

    function testDeployUSDTToken() public {
        uint256 licenseGoal = 10_000 * 10 ** 18; // 10,000 USDT
        uint256 contributionAmount = 1_000 * 10 ** 18; // 1,000 USDT

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
}
