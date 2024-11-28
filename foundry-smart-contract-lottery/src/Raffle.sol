// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title A sample Raffle Contract
 * @author Annamalai Prabu
 * @notice This contract is for creating a simple raffle
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__SendMoreETHToEnterRaffle();
    error Raffle__NotEnoughTimePassed();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState); //we can now get back these parameters to debug more easily during errors

    /* Type Declarations */
    enum RaffleState {
        OPEN, //0 -> the raffle is open
        CALCULATING //1 -> we are calculating the winner
    } //we use this RaffleState to prevent any user from entering the raffle during the calculating winner phase

    /* State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;
    uint256 private immutable i_entranceFee;
    uint256 private immutable i_interval;
    // @dev The duration of the lottery in seconds
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    address payable[] private s_players; //payable address array
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);

    // What data structure should we use to keep track of all the players? the more you code, the more you'll be able to guess this -> here we'll use an address array
    // We must use the constructor of the inherited codebase in our constructor itself for the program to work
    constructor(
        uint256 _entranceFee,
        uint256 _interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = _entranceFee;
        i_interval = _interval;
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN; //same as RaffleState(0)

    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__SendMoreETHToEnterRaffle();
        }

        if(s_raffleState != RaffleState.OPEN){
            revert Raffle__RaffleNotOpen();
        }

        //the best version would be require(msg.value >= i_entranceFee, SendMoreETHToEnterRaffle()); But this only works in solidity ^0.8,26 and is slightly is less gas efficient than the prev used one here
        s_players.push(payable(msg.sender));
        //Events
        //1. Makes migration easier
        //2. Makes frontend indexing easier
        emit RaffleEntered(msg.sender);
    }

    //1. Get a random number
    //2. Use the random number to pick a player as winner
    //3. Be automatically called without any user intervention using Chainlink Automation (previously called Keepers)

    //When should the winner be picked?
    /**
     * @dev This is the function that the Chainlink nodes will call to see if the lottery is ready to have a winner picked
     * THe following should be true in order for upkeepNeeded to be true:
     * 1. The timeInterval has passed between raffle runs
     * 2. The raffle is open
     * 3. The contract has ETH (has players)
     * 4. Implicitly, your contract has LINK
     * @param - ignored
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return - ignored
     */

     function checkUpkeep(
        bytes memory /* checkData */ //this syntax means checkData is not used anywhere in this example
    )
        public
        view
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = (s_raffleState == RaffleState.OPEN);
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
    }



    function performUpkeep(bytes calldata /* performData */) external {
        // check to see if enough time has passed
        (bool upkeepNeeded,) = checkUpkeep("");

        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        if (block.timestamp - s_lastTimeStamp < i_interval) {
            revert Raffle__NotEnoughTimePassed();
        }

        // Get our random number from Chainlink VRF
        // 1. Request a random number
        // 2. Get the random number

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient.RandomWordsRequest({
            keyHash: i_keyHash, //gas price to work with the chainlink node
            subId: i_subscriptionId, // how we fund the oracle gas to work with chainlink vrf
            requestConfirmations: REQUEST_CONFIRMATIONS, //how many blocks should we wait for the chainlink vrf to give us a random number
            callbackGasLimit: i_callbackGasLimit, // the callback gas limit so that we accidentally don't spend too much gas on the callback
            numWords: NUM_WORDS, //here we specify the number of random words we want to get back
            extraArgs: VRFV2PlusClient._argsToBytes(
                // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
            )
        });

        s_vrfCoordinator.requestRandomWords(request);
    }

    //CEI: Checks, Events and Interactions Functions Design Pattern

    //abstract contracts can have 2 types of functions -> external and internal, the below function is ought to be implemented for this contract to work
    function fulfillRandomWords(uint256 /*requestId*/, uint256[] calldata randomWords) internal virtual override {

        //Checks (CEI) , in this particular function there are no Checks


        //Events (CEI) (Internal Contract State)
        //if we divide the random number by the number of players, we get the index of the player who won, we can use this index to pick a winner
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        
        s_raffleState = RaffleState.OPEN; //we are reopening the raffle here
        s_players = new address payable[](0); //we are resetting the players array here so that previous participants can't win anymore without entering the raffle once again
        s_lastTimeStamp = block.timestamp; // we are resetting the last timestamp here 
        emit WinnerPicked(s_recentWinner); //as this is internal and has nothing to do with interactions we move it from below to here

        //Interactions (CEI) (External Contract Interactions)
        (bool success, ) = recentWinner.call{value: address(this).balance}(""); //send the balance of the contract to the winner
        if(!success){
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getter Functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }
}
