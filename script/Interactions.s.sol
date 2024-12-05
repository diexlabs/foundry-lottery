// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Script, console } from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";
import { LinkToken } from "test/mocks/LinkToken.sol";
import { CodeConstants } from "script/HelperConfig.s.sol";
import { DevOpsTools } from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {

    function createSubscriptionUsingConfig() public returns (uint256, address) {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCordinator = helperConfig.getConfig().vrfCoordinator;
        (uint256 subId, ) = createSubscription(vrfCordinator);
        return (subId, vrfCordinator);
    }

    function createSubscription(address vrfCordinator) public returns (uint256, address) {
        console.log("creating subscription on chain ID, ", block.chainid);
        vm.startBroadcast();
        uint256 subscriptionId = VRFCoordinatorV2_5Mock(vrfCordinator).createSubscription();
        vm.stopBroadcast();

        console.log("your subscription Id is: ", subscriptionId);

        return (subscriptionId, vrfCordinator);
    }

    function run() public {
        createSubscriptionUsingConfig();
    }

}


contract FundSubscription is Script, CodeConstants {
    uint256 public constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        address vrfCoordinator = helperConfig.getConfig().vrfCoordinator;
        uint256 subscriptionId = helperConfig.getConfig().subscriptionId;
        address linkToken = helperConfig.getConfig().link;
        fundSubscription(vrfCoordinator, subscriptionId, linkToken);
    }

    function fundSubscription(address vrfCordinator, uint256 subscriptionId, address linkToken) public {
        console.log('funding subscription: ', subscriptionId);
        console.log("with vrf Coordinator: ", vrfCordinator);
        console.log("on Chain Id: ", block.chainid);

        if (block.chainid == LOCAL_CHAIN_ID) {
            vm.startBroadcast();
            VRFCoordinatorV2_5Mock(vrfCordinator).fundSubscription(subscriptionId, FUND_AMOUNT * 100);
            vm.stopBroadcast();
        }
        else {
            vm.startBroadcast();
            LinkToken(linkToken).transferAndCall(vrfCordinator, FUND_AMOUNT * 100, abi.encode(subscriptionId));
            vm.stopBroadcast();
        }


    }

    function run() public {}
}


contract AddConsumer is Script {

    function addConsumerUsingConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        uint256 subId = helperConfig.getConfig().subscriptionId;
        address vrf = helperConfig.getConfig().vrfCoordinator;

        addConsumer(mostRecentlyDeployed, vrf, subId);
    }

    function addConsumer(address contractToAddVrf, address vrf, uint256 subId) public {
        vm.startBroadcast();
        VRFCoordinatorV2_5Mock(vrf).addConsumer(subId, contractToAddVrf);
        vm.stopBroadcast();
    }

    function run() external {
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
        addConsumerUsingConfig(mostRecentlyDeployed);
    }
}