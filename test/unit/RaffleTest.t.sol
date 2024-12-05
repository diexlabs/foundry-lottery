// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { console } from "forge-std/Script.sol";
import { Test } from "forge-std/Test.sol";
import {Raffle} from "src/Raffle.sol";
import { DeployRaffle } from "script/DeployRaffle.s.sol";
import { HelperConfig } from "script/HelperConfig.s.sol";
import { Vm } from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    address public PLAYER = makeAddr('player');
    uint256 public constant STARTING_BALANCE = 10 ether;

     /** Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();

        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;
    }

    modifier raffleEntered {
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testRaffleInitializedInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }


    /** ENTER RAFFLE */

    function testRaffleReversWhenYouDontPayEnough() public {
        vm.prank(PLAYER);

        vm.expectRevert(Raffle.Raffle__SendMoreToEnterRaffle.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_BALANCE);
        // Act
        raffle.enterRaffle{value: entranceFee}();

        // Assert
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEnterRaffleEmitsEvent() public {
        // Arrange
        vm.prank(PLAYER);
        vm.deal(PLAYER, entranceFee);
        // Act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);

        // Assert
        raffle.enterRaffle{value: entranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);  // Best practice
        raffle.performUpkeep("");

        // Act
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();

        // Assert
    }

    /*////////////////////////////////////////////////////////////////////////////////////////
                            CHECK UPKEEP
    ////////////////////////////////////////////////////////////////////////////////////////*/

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);

    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public {
        // Arrange
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);  // Best practice
        raffle.performUpkeep("");

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    // Challenge
    // testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed
    // testCheckUpkeepReturnsTrueWhenParametersAreGood

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_BALANCE);
        raffle.enterRaffle{value: entranceFee}();

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        vm.deal(PLAYER, STARTING_BALANCE);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        // Act
        (bool upkeepNeeded,) = raffle.checkUpkeep("");

        // Assert
        assert(upkeepNeeded);
    }

    /*////////////////////////////////////////////////////////////////////////////////
                            PERFORM UPKEEP
    ////////////////////////////////////////////////////////////////////////////////*/

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public raffleEntered {

        // Act / Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        // Arrange
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        vm.deal(PLAYER, STARTING_BALANCE);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        uint256 currentBalance = entranceFee;
        uint256 numPlayers = 1;

        // Act
        vm.expectRevert(
            abi.encodeWithSelector(Raffle.Raffle__UpkeepNotNeed.selector, currentBalance, numPlayers, raffleState)
        );
        raffle.performUpkeep("");
    }

    // what if we need to get data from emitted events in our tests?
    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId() public raffleEntered {
        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];

        // Assert
        raffle.getRaffleState();
        assert(uint256(requestId) > 0);
    }

    /*/////////////////////////////////////////////////////////////////////////////////
                        FULFIL RANDOM WORDS
    /////////////////////////////////////////////////////////////////////////////////*/

    function testFulfilRandomWordsCanOnlyCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEntered {
        //Arrange / Act
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEntered {
        // Arrange
        uint256 additionalEntrants = 3;
        uint160 startingIndex = 1;
        address expectedWinner = address(1);

        for (uint160 index = startingIndex; index <= additionalEntrants; index++) {
            address player = address(index);
            hoax(player, 1 ether);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 startingTimestamp = raffle.getLastTimestamp();
        uint256 winnerStartingBalance = expectedWinner.balance;

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 requestId = logs[1].topics[1];
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endTimestamp = raffle.getLastTimestamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assertEq(recentWinner, expectedWinner);
        assertEq(uint256(raffleState), 0);
        assertEq(winnerBalance, winnerStartingBalance + prize);
        assert(endTimestamp > startingTimestamp);
    }

}