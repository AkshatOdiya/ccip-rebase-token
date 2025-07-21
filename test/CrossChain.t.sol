// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
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
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    uint256 sepoliaFork;
    uint256 arbSepoliaFork;
    address immutable i_owner = makeAddr("owner");
    address immutable i_user = makeAddr("user");

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;
    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;
    RebaseTokenPool sepoliaTokenPool;
    RebaseTokenPool arbSepoliaTokenPool;
    Vault vault;
    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    function setUp() public {
        string memory sepolia = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory arb_sepolia = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        sepoliaFork = vm.createSelectFork(sepolia);
        arbSepoliaFork = vm.createFork(arb_sepolia);
        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // 1. Deploy and configure on sepolia
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(i_owner);
        sepoliaToken = new RebaseToken();
        sepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaTokenPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaTokenPool)
        );
        configureTokenPool(
            sepoliaFork, // Local chain: Sepolia
            address(sepoliaTokenPool), // Local pool: Sepolia's TokenPool
            arbSepoliaNetworkDetails.chainSelector, // Remote chain selector: Arbitrum Sepolia's
            address(arbSepoliaTokenPool), // Remote pool address: Arbitrum Sepolia's TokenPool
            address(arbSepoliaToken) // Remote token address: Arbitrum Sepolia's Token
        );

        vm.stopPrank();

        // 2. Deploy and consifure on arbitrum sepolia
        vm.selectFork(arbSepoliaFork); // we need to select fork as used vm.createFork not vm.createSelectFork
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(i_owner);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaTokenPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaTokenPool)
        );
        configureTokenPool(
            arbSepoliaFork, // Local chain: Arbitrum Sepolia
            address(arbSepoliaTokenPool), // Local pool: Arbitrum Sepolia's TokenPool
            sepoliaNetworkDetails.chainSelector, // Remote chain selector: Sepolia's
            address(sepoliaTokenPool), // Remote pool address: Sepolia's TokenPool
            address(sepoliaToken) // Remote token address: Sepolia's Token
        );
        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        vm.selectFork(fork);
        vm.prank(i_owner);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: abi.encode(remotePoolAddresses),
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});
        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        // address(linkToken) means fees are paid in LINK
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(i_user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });

        // Get the fee required to send the message
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);

        // It is like vm.deal and we doing things using chainlink local
        ccipLocalSimulatorFork.requestLinkFromFaucet(i_user, fee);

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        vm.prank(i_user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);

        uint256 localBalanceBefore = localToken.balanceOf(i_user);

        // approve the Router to spend tokens on contract's behalf. It will spend the amount of the given token
        vm.prank(i_user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        // Send the message through the router
        vm.prank(i_user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        uint256 localBalanceAfter = localToken.balanceOf(i_user);

        assertEq(localBalanceAfter, localBalanceBefore - amountToBridge);
        uint256 localUserInterestRate = localToken.getUserInterestRate(i_user);

        // now go to the other chain
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(i_user);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork); // this line won't matter as we have already selected the fork, but for surity we can do this
        uint256 remoteBalanceAfter = remoteToken.balanceOf(i_user);
        assertEq(remoteBalanceAfter, amountToBridge + remoteBalanceBefore);
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(i_user);
        assertEq(remoteUserInterestRate, localUserInterestRate);
    }
}
