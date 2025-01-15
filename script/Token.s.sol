pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {RVTC} from "../src/VTCContract.sol";

contract TokenScript is Script {
    function setUp() public {}

    function run() public {
        uint privateKey = vm.envUint("DEV_PRIVATE_KEY");
        // address account = vm.addr(privateKey);

        // Convert the strings to address type
        address usdtToken = 0x63F68920562Dd306657B9c735F7ECfF07Ce7D032;
        address treasury = 0x2c7504D9D37aECda0b4629af3090DF76c747F798;
        address rendinex = 0x2c7504D9D37aECda0b4629af3090DF76c747F798;

        vm.startBroadcast(privateKey);
        RVTC rvtc = new RVTC(usdtToken, treasury, rendinex);
        uint256 fundingGoal = 1000 * 1e18;
        rvtc.createLicense(fundingGoal);
        vm.stopBroadcast();
    }
}