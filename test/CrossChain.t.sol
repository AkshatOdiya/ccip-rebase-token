// SPDX-License-Identifier: MIT
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
    address[] public allowlist = new address[](0);

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    CCIPLocalSimulatorFork public ccipLocalSimulatorFork;

    address immutable i_owner = makeAddr("owner");
    address immutable i_user = makeAddr("user");
    uint256 constant SEND_VALUE = 1e5;

    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;

    Vault vault;

    RebaseTokenPool sepoliaTokenPool;
    RebaseTokenPool arbSepoliaTokenPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    /* for setUp(), steps are followed according to this
    https://docs.chain.link/ccip/tutorials/evm/cross-chain-tokens/register-from-eoa-burn-mint-foundry#tutorial
     */
    function setUp() public {
        string memory sepolia = vm.envString("ETHEREUM_SEPOLIA_RPC_URL");
        string memory arb_sepolia = vm.envString("ARBITRUM_SEPOLIA_RPC_URL");
        sepoliaFork = vm.createSelectFork(sepolia);
        arbSepoliaFork = vm.createFork(arb_sepolia);

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Deploy on Sepolia
        vm.startPrank(i_owner);

        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        vm.deal(address(vault), 1e18);

        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        sepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            allowlist,
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        sepoliaToken.grantMintAndBurnRole(address(sepoliaTokenPool));
        sepoliaToken.grantMintAndBurnRole(address(vault));

        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );

        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaTokenPool)
        );

        vm.stopPrank();

        // Deploy on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork);
        vm.startPrank(i_owner);

        arbSepoliaToken = new RebaseToken();
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        arbSepoliaTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            allowlist,
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

        vm.stopPrank();
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        address remotePoolAddress,
        address remoteTokenAddress,
        uint64 remoteChainSelector
    ) public {
        vm.selectFork(fork);

        TokenPool.ChainUpdate;
        bytes memory encodedRemotePoolAddress = abi.encode(remotePoolAddress);
        TokenPool.ChainUpdate[] memory chains = new TokenPool.ChainUpdate[](1);

        chains[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: encodedRemotePoolAddress,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        vm.prank(i_owner);
        TokenPool(localPool).applyChainUpdates(chains);
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
        vm.startPrank(i_user);

        Client.EVMTokenAmount[] memory tokenToSendDetails = new Client.EVMTokenAmount[](1);
        tokenToSendDetails[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(i_user),
            data: "",
            tokenAmounts: tokenToSendDetails,
            extraArgs: "",
            feeToken: localNetworkDetails.linkAddress // Fee to be paid in link
        });

        vm.stopPrank();

        // It is like vm.deal and we are doing things using chainlink local
        ccipLocalSimulatorFork.requestLinkFromFaucet(
            i_user, IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message)
        );

        vm.startPrank(i_user);

        // approve the Router to transfer LINK tokens on contract's behalf. It will spend the fees in LINK
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message) // getFee: Get the fee required to send the message
        );

        uint256 balanceBeforeBridge = localToken.balanceOf(i_user);

        // Send the message through the router
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);

        uint256 balanceAfterBridge = localToken.balanceOf(i_user);
        assertEq(balanceAfterBridge, balanceBeforeBridge - amountToBridge);

        vm.stopPrank();

        // now go to the other chain
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 900);
        uint256 initialRemoteBalance = remoteToken.balanceOf(i_user);

        vm.selectFork(localFork);
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        uint256 finalRemoteBalance = remoteToken.balanceOf(i_user);
        assertEq(finalRemoteBalance, initialRemoteBalance + amountToBridge);
    }

    function testBridgeAllTokens() public {
        configureTokenPool(
            sepoliaFork,
            address(sepoliaTokenPool),
            address(arbSepoliaTokenPool),
            address(arbSepoliaToken),
            arbSepoliaNetworkDetails.chainSelector
        );

        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaTokenPool),
            address(sepoliaTokenPool),
            address(sepoliaToken),
            sepoliaNetworkDetails.chainSelector
        );

        vm.selectFork(sepoliaFork);
        vm.deal(i_user, SEND_VALUE);
        vm.startPrank(i_user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        vm.stopPrank();

        bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );

        vm.selectFork(arbSepoliaFork);
        vm.warp(block.timestamp + 3600);
        uint256 destBalance = arbSepoliaToken.balanceOf(i_user);

        bridgeTokens(
            destBalance,
            arbSepoliaFork,
            sepoliaFork,
            arbSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            arbSepoliaToken,
            sepoliaToken
        );
    }
}
