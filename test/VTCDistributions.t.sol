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
        usdt = new Token("USDT", "USDT", 18);
        // The contract owner is the deployer of the contract which is the test contract, not the caller
        vm.prank(contract_owner);
        rvtc = new RVTC(address(usdt), treasury, rendinex);

        // Mint USDT to contributors
        usdt.mint(first_contributor, 10_000 * 10 ** 6);
        usdt.mint(second_contributor, 8_000 * 10 ** 6);

        // Create license
        uint256 licenseGoal = 10_000 * 10 ** 6;
        vm.prank(contract_owner);
        rvtc.createLicense(licenseGoal);

        // Approve the RVTC contract to spend the tokens on behalf of the user
        vm.prank(user);
        usdt.approve(address(rvtc), type(uint256).max);

        vm.prank(first_contributor);
        usdt.approve(address(rvtc), 3_000 * 10 ** 6);
        vm.prank(first_contributor);
        rvtc.contributeToLicense(0, 3_000 * 10 ** 6);

        vm.prank(second_contributor);
        usdt.approve(address(rvtc), 7_000 * 10 ** 6);
        vm.prank(second_contributor);
        rvtc.contributeToLicense(0, 7_000 * 10 ** 6);

        (, , uint256[] memory updatedFundsRaised, ) = rvtc.getLicenses();
        assertEq(updatedFundsRaised[0], 10_000 * 10 ** 6);

        vm.prank(contract_owner);
        rvtc.finalizeLicense(0);

        // Repartition of tokens
        vm.prank(contract_owner);
        rvtc.distributeTokensForLicense(0, first_contributor, 300 * 10 ** 2);
        vm.prank(contract_owner);
        rvtc.distributeTokensForLicense(0, second_contributor, 700 * 10 ** 2);

        // Test balance of contributors
        uint256 balanceAfterMintFirstContributor = rvtc.balanceOf(
            first_contributor
        );
        assertEq(balanceAfterMintFirstContributor, 300 * 10 ** 2);
        uint256 balanceAfterMintSecondContributor = rvtc.balanceOf(
            second_contributor
        );
        assertEq(balanceAfterMintSecondContributor, 700 * 10 ** 2);

        (, , , bool[] memory fundingCompleted) = rvtc.getLicenses();
        assertTrue(fundingCompleted[0]);

        usdt.mint(contract_owner, 3_000 * 10 ** 6);
        vm.prank(contract_owner);
        usdt.approve(address(rvtc), 3_000 * 10 ** 6);
        vm.prank(contract_owner);
        rvtc.distributeProfits(1_000 * 10 ** 6);
    }

    function testWithdrawProfits() public {
        // There are 1000 tokens minted per license so the profit per token should be 1 usdt
        assertEq(rvtc.cumulativeProfitPerToken(), 1 * 10 ** 22);

        // The first contributor has 7000 usdt left so after withdrawing his 300 usdt he should have 7300 in total
        vm.prank(first_contributor);
        rvtc.withdrawProfits();
        uint256 balance = usdt.balanceOf(first_contributor);
        assertEq(balance, 7_300 * 10 ** 6);
    }

    function testFailWithdrawTwoTimes() public {
        vm.prank(first_contributor);
        rvtc.withdrawProfits();
        vm.prank(first_contributor);
        rvtc.withdrawProfits();
    }

    function testWithdrawWhenTransferBetweenDistributions() public {
        vm.prank(first_contributor);
        rvtc.transfer(first_purchaser, 200 * 10 ** 2);
        uint256 balance = usdt.balanceOf(first_contributor);
        assertEq(balance, 7_300 * 10 ** 6);
    }

    function testFailWithdrawBuyerAfterTransferBetweenDistributions() public {
        vm.prank(first_contributor);
        rvtc.transfer(first_purchaser, 200 * 10 ** 2);
        vm.prank(first_contributor);
        rvtc.withdrawProfits();
    }

    function testFailWithdrawSellerAfterTransfer() public {
        vm.prank(first_contributor);
        rvtc.transfer(first_purchaser, 200 * 10 ** 2);
        vm.prank(first_purchaser);
        rvtc.withdrawProfits();
    }

    function testFailWithdrawBuyerAfterTwoPurchases() public {
        vm.prank(first_contributor);
        rvtc.transfer(first_purchaser, 200 * 10 ** 2);
        vm.prank(second_contributor);
        rvtc.transfer(first_purchaser, 50 * 10 ** 2);
        uint256 balance = rvtc.balanceOf(first_purchaser);
        assertEq(balance, 250 * 10 ** 2);

        vm.prank(first_purchaser);
        rvtc.withdrawProfits();
    }

    function testBalancesAfterMultipleTransfers() public {
        vm.prank(first_contributor);
        rvtc.transfer(first_purchaser, 200 * 10 ** 2);
        uint256 balance_first = usdt.balanceOf(first_contributor);
        assertEq(balance_first, 7_300 * 10 ** 6);
        vm.prank(second_contributor);
        rvtc.transfer(first_purchaser, 50 * 10 ** 2);
        uint256 balance_second = usdt.balanceOf(second_contributor);
        assertEq(balance_second, 1_700 * 10 ** 6);
        uint256 balance_purchaser = usdt.balanceOf(first_purchaser);
        assertEq(balance_purchaser, 0);

        vm.prank(contract_owner);
        rvtc.distributeProfits(2_000 * 10 ** 6);
        /* As we have distributed 2000 usdt and there are 1000 license tokens the first contributor
        should add 200 usdt, the second contributor 1300 usdt and the first purchaser 500 usdt */

        vm.prank(first_contributor);
        rvtc.withdrawProfits();
        vm.prank(second_contributor);
        rvtc.withdrawProfits();
        vm.prank(first_purchaser);
        rvtc.withdrawProfits();
        balance_first = usdt.balanceOf(first_contributor);
        assertEq(balance_first, 7_500 * 10 ** 6);
        balance_second = usdt.balanceOf(second_contributor);
        assertEq(balance_second, 3_000 * 10 ** 6);
        balance_purchaser = usdt.balanceOf(first_purchaser);
        assertEq(balance_purchaser, 500 * 10 ** 6);
    }

    function testWithdrawSecondContributorRepurchase() public {
        // The first contributor sends 200 tokens to the first purchaser and the second contributor sends 50 tokens to the first purchaser
        vm.prank(first_contributor);
        rvtc.transfer(first_purchaser, 200 * 10 ** 2);
        vm.prank(second_contributor);
        rvtc.transfer(first_purchaser, 50 * 10 ** 2);

        // Second distribution, at this moment the first contributor has 100 tokens, the second contributor 650 and the first purchaser 250
        vm.prank(contract_owner);
        rvtc.distributeProfits(2_000 * 10 ** 6);

        vm.prank(first_purchaser);
        rvtc.transfer(first_contributor, 5 * 10 ** 2);

        uint256 balance = rvtc.balanceOf(second_contributor);
        assertEq(balance, 650 * 10 ** 2);
        balance = rvtc.balanceOf(first_purchaser);
        assertEq(balance, 245 * 10 ** 2);
        balance = rvtc.balanceOf(first_contributor);
        assertEq(balance, 105 * 10 ** 2);

        // The first contributor should have 1300 usdt from the first distribution including initial plus 200 usdt from second distribution
        uint256 usdt_balance = usdt.balanceOf(first_contributor);
        assertEq(usdt_balance, 7500 * 10 ** 6);
        // The second contributor had 700 usdt from first distribution, 1000 initial and 1300 from second distribution
        usdt_balance = usdt.balanceOf(second_contributor);
        assertEq(usdt_balance, 1700 * 10 ** 6);
        vm.prank(second_contributor);
        rvtc.withdrawProfits();
        usdt_balance = usdt.balanceOf(second_contributor);
        assertEq(usdt_balance, 3000 * 10 ** 6);
        // The first purchaser had 500 usdt from second distribution
        usdt_balance = usdt.balanceOf(first_purchaser);
        assertEq(usdt_balance, 500 * 10 ** 6);
    }
}
