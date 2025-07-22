Everything is in README.md

# Building Cross-Chain Rebase Tokens with Foundry and Chainlink CCIP

This Repo contains a rebase token capable of operating and being transferred across multiple blockchains.

## Core Concepts:

* **Rebase Token:** At its heart, a rebase token is a type of cryptocurrency where the total supply adjusts algorithmically. This adjustment is distributed proportionally among all token holders. Consequently, a user's token balance changes not due to direct transfers in or out of their wallet, but because the effective quantity or "value" represented by each token unit shifts with the supply. In our specific implementation, this rebase mechanism will be tied to an interest rate, causing user balances to appear to grow over time as interest accrues.

* **Cross-Chain Functionality:** This refers to the capability of our rebase token and its associated logic to operate across different, independent blockchains. The core challenge here is enabling the token, or at least its value representation, to move from a source chain to a destination chain seamlessly.

* **Chainlink CCIP (Cross-Chain Interoperability Protocol):**  CCIP is the pivotal technology enabling our token's cross-chain capabilities. It provides a secure and reliable way for smart contracts on one blockchain to send messages and transfer tokens to smart contracts on another blockchain.

* **Burn-and-Mint Mechanism (for CCIP token transfers):** To maintain a consistent total circulating supply across all integrated chains (barring changes from the rebase mechanism itself), we employ a burn-and-mint strategy. When tokens are transferred from a source chain to a destination chain:

1. Tokens are "burned" (irrevocably destroyed) on the source chain.

2. An equivalent amount of new tokens is "minted" (created) on the destination chain.

* **Foundry**: Our development environment of choice is Foundry, a powerful and fast smart contract development toolkit written in Rust. We'll use Foundry for writing, testing (including complex scenarios like fuzzing and fork testing), and deploying our Solidity smart contracts.

* **Linear Interest:** The rebase token in this project will accrue interest based on a straightforward linear model. The interest earned will be a product of the user's specific interest rate and the time elapsed since their last balance update or interaction

* **Fork Testing:** A crucial testing methodology we'll utilize is fork testing. This involves creating a local, isolated copy (a "fork") of an actual blockchain (e.g., Sepolia testnet, Arbitrum Sepolia testnet) at a specific block height. This allows us to test our smart contracts' interactions with existing, deployed contracts and protocols in a highly realistic environment without incurring real gas costs or requiring deployment to a live testnet for every iteration.

* **Local CCIP Simulation:** To streamline development and testing of cross-chain interactions, we will use tools like Chainlink Local's CCIPLocalSimulatorFork. This enables us to simulate CCIP message passing and token transfers entirely locally, which is invaluable for debugging and verifying logic before engaging with public testnets.


### Objectives:

* The fundamentals and practical application of Chainlink CCIP.

* How to enable an existing token for CCIP compatibility.

* Techniques for creating custom tokens specifically designed for CCIP, going beyond standard ERC20s.

* The design and implementation of a rebase token.

* Advanced Solidity and Foundry concepts, including:

  * Effective use of the super keyword for inheriting and extending contract functionality.

  * Sophisticated testing strategies.

  * Understanding and mitigating issues related to "token dust" (minute, economically insignificant token balances).

  * Handling precision and truncation challenges inherent in financial calculations, especially critical for rebase mechanisms.

  * Practical application of fork testing.

  * The use of nested structs for organizing complex data.

* The mechanics of bridging tokens between different blockchains.

* The intricacies of cross-chain transfers.

## Main Architecture:

### Main

`RebaseToken.sol:` The Heart of Our Interest-Bearing Token.  
This contract defines the core logic for our rebase token.  
**Purpose**: To implement an ERC20-like token whose balances effectively increase over time due to an accrued interest mechanism.

`RebaseTokenPool.sol:` Enabling Cross-Chain Transfers with CCIP  
This contract is responsible for managing the cross-chain movement of our rebase token using Chainlink CCIP. It will likely inherit from or extensively utilize Chainlink's Pool.sol contract or similar CCIP-specific base contracts.  
**Purpose**: To facilitate the burn-and-mint mechanism for transferring the rebase token between different blockchains via CCIP.

`Vault.sol:` Interacting with the Rebase Token  
The Vault.sol contract serves as an interface for users to acquire or redeem rebase tokens using a base asset (e.g., ETH).  
**Purpose:** To allow users to deposit a base asset (like ETH) and receive rebase tokens in return, and conversely, to redeem their rebase tokens for the underlying base asset.

### Scripts

`Deployer.s.sol:` This script handles the deployment of the `RebaseToken`, `RebaseTokenPool`, and `Vault` contracts to the target blockchain.   

`ConfigurePool.s.sol:` After deployment, this script is used to configure the CCIP settings on the `RebaseTokenPool` contracts on each chain. This includes setting parameters like supported remote chains (using their chain selectors), addresses of token contracts on other chains, and rate limits for CCIP transfers.  

`BridgeTokens.s.sol:` This script provides a convenient way to initiate a cross-chain token transfer, automating the calls to the `RebaseTokenPool` for locking/burning and CCIP message dispatch.  

`Interactions.s.sol:` This script would likely contain functions for other general interactions with the deployed contracts, such as depositing into the vault or checking balances.  

### Tests

`RebaseToken.t.sol` Contains unit and fuzz tests specifically for the RebaseToken.sol contract.  

> **_CheatCode_Alert!_**  
>`assertApproxEqAbs` allows us to verify that calculated values are within an acceptable tolerance (delta) of expected values, rather than insisting on exact equality (assertEq) which might lead to spurious test failures.

`CrossChain.t.sol` Contains fork tests designed to validate the end-to-end cross-chain functionality.   

> **_CheatCode_Alert!_**  
>`vm.createFork("rpc_url")` to create local forks of testnets like Sepolia and Arbitrum Sepolia. This allows tests to run against a snapshot of the real chain state.

### Automating Deployment and Cross-Chain Operations: The `bridgeToZkSync.sh` Script  
To streamline the entire process from deployment to a live cross-chain transfer, a bash script like `bridgeToZkSync.sh` is invaluable.  

**Purpose**: This script automates a complex sequence of operations involving contract deployments, configurations, and interactions across multiple chains (e.g., Sepolia and zkSync Sepolia).
 