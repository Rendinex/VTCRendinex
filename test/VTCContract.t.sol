// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import "../src/VTCContract.sol";

contract RVTCTest is Test {
    RVTC public rvtc;

    address public usdtToken = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;
    address public treasury = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;
    address public rendinex = 0x4838B106FCe9647Bdf1E7877BF73cE8B0BAD5f97;

    function setUp() public {
        rvtc = new RVTC(usdtToken, treasury, rendinex);
    }

    function test_fee() public view {
        assertEq(rvtc.feePercent(), 10);
    }
}
