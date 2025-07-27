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

/*
 * `vm.createFork("rpc_url")` to create local forks of testnets like Sepolia and Arbitrum Sepolia. This allows tests to run against a snapshot of the real chain state.
 * `CCIPLocalSimulatorFork` from Chainlink Local, enables the simulation of CCIP message routing and execution between these local forks, effectively creating a local, two-chain (or multi-chain) test environment.
 */

/*
Contract Deployment order:
1. RebaseToken and RebaseTokenPool on Sepolia.

2. RebaseToken and RebaseTokenPool on Arbitrum Sepolia.

3. Vault on Sepolia.
 */

/*
CCIP Configuration: This includes:

1. Granting appropriate roles (e.g., minter/burner roles to the token pools or vault).

2. Registering the token pools with the CCIP routers on each chain.

3. Setting supported chains and other CCIP-specific parameters.
 */
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
        // vm.makePersistent to ensure that this single instance of CCIPLocalSimulatorFork is accessible with the same address and state on both the Sepolia and Arbitrum Sepolia forks.
        // This shared simulator is what will enable us to test message passing between them.
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

        // CCIP Configuration:
        /*
        First, the owner of the token (our EOA in this test setup) needs to nominate themselves (or another designated address) 
        as the pending administrator for the token. This is done by calling the registerAdminViaOwner(address token) function on the RegistryModuleOwnerCustom contract. 
        The address of this contract is available in the networkDetails.registryModuleOwnerCustomAddress field obtained earlier.
         */
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );

        /*
        After registering as a pending admin, the nominated address (our owner EOA) must finalize the process by accepting the admin role. 
        This is achieved by calling the acceptAdminRole(address localToken) function on the TokenAdminRegistry contract. 
        The address for this contract is found in networkDetails.tokenAdminRegistryAddress.
         */
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));

        // Link Tokens to Their Respective Pools
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaTokenPool)
        );

        vm.stopPrank();

        // ============================================================================================================================================================

        // Deploy on Arbitrum Sepolia
        vm.selectFork(arbSepoliaFork); // switch fork to Arbitrum Sepolia
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

        // CCIP Configuration:
        /*
        First, the owner of the token (our EOA in this test setup) needs to nominate themselves (or another designated address) 
        as the pending administrator for the token. This is done by calling the registerAdminViaOwner(address token) function on the RegistryModuleOwnerCustom contract. 
        The address of this contract is available in the networkDetails.registryModuleOwnerCustomAddress field obtained earlier.
         */
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );

        /*
        After registering as a pending admin, the nominated address (our owner EOA) must finalize the process by accepting the admin role. 
        This is achieved by calling the acceptAdminRole(address localToken) function on the TokenAdminRegistry contract. 
        The address for this contract is found in networkDetails.tokenAdminRegistryAddress.
         */
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        // Link Tokens to Their Respective Pools
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaTokenPool)
        );

        vm.stopPrank();
    }

    /*
    Before you can mint tokens and execute cross-chain transfers using Chainlink CCIP (Cross-Chain Interoperability Protocol) with a Burn & Mint token mechanism, 
    a critical prerequisite is the configuration of your deployed Token Pools. This configuration step establishes the necessary permissions and connections, 
    enabling the pools on different chains to interact seamlessly. 
     */
    /*
    When you configure a local token pool to add a remote chain via the chainsToAdd parameter, you are effectively "enabling" that remote chain for interaction. 
    This means the local pool (the one on which applyChainUpdates is being called) will be permitted to:

     * Receive tokens from the specified remote chain.

     * Send tokens to the specified remote chain.
     */

    /*
    Once your tokens (e.g., sepoliaToken, arbSepoliaToken) and token pools (e.g., sepoliaPool, arbSepoliaPool) are deployed on their respective chains, 
    you call the configureTokenPool helper function within your test's setUp function. This must be done for each direction of interaction.
     */

    /*
    Timing is Crucial: Pool configuration via applyChainUpdates must be performed after deploying your token pool contracts on all relevant chains but before 
    attempting any cross-chain minting or transfer operations.
     */

    /*
    Clarity in Direction: When configuring pools for bidirectional communication (e.g., Chain A <-> Chain B), ensure you call applyChainUpdates on Chain A's pool 
    (listing Chain B as remote) AND on Chain B's pool (listing Chain A as remote).
     */
    /// @notice main objective of this function is `applyChainUpdates`
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

        /*
        The primary purpose of applyChainUpdates is to update the chain-specific permissions and configurations for the token pool contract on which it is called. 
        Essentially, it tells a local pool which remote chains it is allowed to interact with.
         */
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

    /// @notice The idea of bridgeTokens function is taken from the contract under *Tutorial* https://docs.chain.link/ccip/tutorials/evm/transfer-tokens-from-contract
    /**
     * @notice The typical cross-chain transfer process, as implemented in this test, follows these steps:
     *
     * 1. Build the Message: Construct an EVM2AnyMessage struct containing details like the receiver's address, token transfer specifics, the fee token, and any extra arguments for CCIP.
     *
     * 2. Calculate Fees: Query the source chain's Router contract using getFee() to determine the cost of the CCIP transaction.
     *
     * 3. Fund Fees: In our local test setup, we'll use a helper function to mint LINK tokens (the designated fee token in this example) to the user.
     *
     * 4. Approve Fee Token: The user must approve the source chain's Router contract to spend the calculated LINK fee.
     *
     * 5. Approve Bridged Token: The user must also approve the source chain's Router to spend the amount of the token being bridged.
     *
     * 6. Send CCIP Message: Invoke ccipSend() on the source chain's Router, passing the destination chain selector and the prepared message.
     *
     * 7. Simulate Message Propagation: Utilize the CCIPLocalSimulatorFork to mimic the message's journey and processing on the destination chain, including fast-forwarding time to simulate network latency.
     *
     * 8. Verify Token Reception: Confirm that the tokens (and any associated data, like interest rates for a RebaseToken) are correctly credited to the receiver on the destination chain.
     */
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

        // Approve the actual token to be bridged
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
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork); // internally selects the remoteFork and processes the enqueued CCIP message.

        uint256 finalRemoteBalance = remoteToken.balanceOf(i_user);
        assertEq(finalRemoteBalance, initialRemoteBalance + amountToBridge);
    }

    /*
    Once your tokens (e.g., sepoliaToken, arbSepoliaToken) and token pools (e.g., sepoliaPool, arbSepoliaPool) are deployed on their respective chains, 
    you call the configureTokenPool helper function within your test's setUp function. This must be done for each direction of interaction.
     */
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

        /*
        When a function (like vault.deposit()) is payable and expects ETH, Foundry tests must explicitly send this value. 
        The syntax is: ContractType(payable(address(contractInstance))).functionName{value: amountToSend}(arguments);. This involves:

        1. Getting the address of the contract instance.

        2. Casting this address to payable.

        3. Casting this payable address back to the ContractType to access its functions.

        4. Appending {value: amountToSend} before the function arguments.
         */

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
