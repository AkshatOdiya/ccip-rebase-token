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
 
#### What It Does?

1. Sets necessary permissions for the `RebaseTokenPool` contract, often involving CCIP-specific roles.

2. Assigns CCIP roles and configures permissions for inter-chain communication.

3. Deploys the core contracts (`RebaseToken`, `RebaseTokenPool`, `Vault`) to a source chain (e.g., Sepolia) using `script/Deployer.s.sol`.

4. Parses the deployment output to extract the addresses of the newly deployed contracts.

5. Deploys the `Vault` (and potentially `RebaseToken` and `RebaseTokenPool` if not already deployed as part of a unified script) on the destination chain (e.g., zkSync Sepolia).

6. Configures the RebaseTokenPool on the source chain (Sepolia) using `script/ConfigurePool.s.sol`, linking it to the destination chain by setting remote chain selectors, token addresses on the destination chain, and CCIP rate limits.

7. Simulates user interaction by depositing funds (e.g., ETH) into the `Vault` on Sepolia, thereby minting rebase tokens.

8. Includes a pause or wait period to allow some interest to accrue on the rebase tokens.

9. Configures the `RebaseTokenPool` on the destination chain (zkSync Sepolia), establishing the reciprocal CCIP linkage.

10. Initiates a cross-chain transfer of the rebase tokens from Sepolia to zkSync Sepolia using `script/BridgeTokens.s.sol`.

11. Performs balance checks on both chains before and after the bridge operation to verify the successful transfer and correct accounting.

### Example Use Case:

1. **Deployment**: Deploy the `RebaseToken`, `RebaseTokenPool`, and `Vault` smart contracts onto the Sepolia testnet.

2. **Cross-Chain Deployment**: Deploy the corresponding smart contracts (or at least the `RebaseTokenPool` and potentially a `RebaseToken` representation) onto a second testnet, such as zkSync Sepolia.

3. **CCIP Configuration**: Configure Chainlink CCIP lanes between the deployed `RebaseTokenPool` contracts on Sepolia and zkSync Sepolia, enabling them to communicate and transfer tokens.

4. **Acquire Rebase Tokens**: Interact with the `Vault` contract on Sepolia by depositing ETH, thereby receiving an initial balance of rebase tokens.

5. **Interest Accrual**: Observe as the rebase token balance in the Sepolia wallet increases over time, reflecting the accrued interest as per the token's rebase mechanism.

6. **Cross-Chain Transfer**: Execute the `BridgeTokens.s.sol` Foundry script (or the overarching `bridgeToZkSync.sh` bash script). This script will:

    * Instruct the `RebaseTokenPool` on Sepolia to burn a specified amount of the user's rebase tokens.

    * Initiate a CCIP message to the `RebaseTokenPool` on zkSync Sepolia.

    * Upon successful CCIP message relay, the `RebaseTokenPool` on zkSync Sepolia will mint an equivalent amount of rebase tokens to the user's address on that chain.

7. **Verification**: The user can then verify their new rebase token balance on zkSync Sepolia and the correspondingly reduced (or zeroed, if all tokens were bridged) balance on Sepolia.

---

## What Are Rebase Tokens? Defining Elastic Supply in Crypto

A rebase token is a cryptocurrency engineered with an elastic supply. This means its total circulating supply algorithmically adjusts rather than remaining fixed. These adjustments, commonly referred to as "rebases," are triggered by specific protocols or algorithms. The primary purpose of a rebase mechanism is to either reflect changes in the token's underlying value or to distribute accrued rewards, such as interest, directly to token holders by modifying their balances.


### Key Differentiators: Rebase Tokens vs. Standard Cryptocurrencies
The fundamental distinction between rebase tokens and conventional cryptocurrencies lies in how they respond to changes in value or accumulated rewards.

* Standard Tokens: With a standard cryptocurrency, the total supply generally remains constant (barring events like burns or new minting governed by different rules). When demand increases or the protocol accrues value, the price per token typically adjusts upwards. Conversely, negative factors tend to decrease the price.

* Rebase Tokens: In contrast, rebase tokens are designed so that their total supply expands or contracts. When a protocol aims to distribute rewards or adjust to value changes, instead of the token's market price fluctuating significantly, the quantity of tokens each holder possesses changes. The price per token aims to remain more stable or target a specific peg, while the supply absorbs the value changes.

This "elastic supply" mechanism means your individual token balance can increase or decrease without any direct action on your part.

### Exploring the Types of Rebase Tokens
Rebase tokens can be broadly categorized based on their primary objective:

1. **Rewards Rebase Tokens:** These tokens are commonly found in decentralized finance (DeFi) protocols, particularly in lending and borrowing platforms. Their supply increases to distribute earnings, such as interest, directly to token holders. As the protocol generates revenue, it's reflected as an increase in the number of tokens held by users.

2. **Value Stability Rebase Tokens:** This category includes tokens designed to maintain a stable value relative to an underlying asset or currency (e.g., USD). Often associated with algorithmic stablecoins, these tokens adjust their supply to help maintain their price peg. If the token's market price deviates from its target, a rebase can occur: increasing supply if the price is too high (to bring it down) or decreasing supply if the price is too low (to push it up).

### How Rebase Mechanisms Work: A Practical Example of a Positive Rebase
To understand the impact of a rebase, let's consider a hypothetical scenario involving a positive rebase, typically seen with rewards distribution:

Imagine you hold 1,000 tokens of a specific rebase cryptocurrency. The protocol associated with this token decides to distribute 10% interest to all holders via a positive rebase.

* **Before Rebase:** Your balance is 1,000 tokens.

* **Rebase Event:** The protocol executes a +10% rebase.

* **After Rebase:** Your wallet balance automatically updates to 1,100 tokens (1,000 tokens + 10% of 1,000 tokens).

Crucially, while your token quantity increases, your *proportional ownership of the total token supply remains unchanged*. This is because every token holder experiences the same percentage increase in their balance. If the total supply increased by 10%, and your holdings also increased by 10%, your share of the network is preserved. The same logic applies in reverse for negative rebases, where everyone's balance would decrease proportionally.

### Real-World Application: Aave's aTokens Explained
One of the most prominent examples of rewards rebase tokens in action is Aave's aTokens. Aave is a leading decentralized lending and borrowing protocol.

Here’s how aTokens function within the Aave ecosystem:

1. **Depositing Assets:** When you deposit an asset like USDC or DAI into the Aave protocol, you are essentially lending your cryptocurrency to the platform's liquidity pool.

2. **Receiving aTokens:** In return for your deposit, Aave issues you a corresponding amount of aTokens (e.g., aUSDC for USDC deposits, aDAI for DAI deposits). These aTokens represent your claim on the underlying deposited assets plus any accrued interest.

3. **Accruing Interest via Rebase:** The aTokens you hold are rebase tokens. As your deposited assets generate interest from borrowers within the Aave protocol, your balance of aTokens automatically increases over time. This increase directly reflects the interest earned.

4. **Redemption**: You can redeem your aTokens at any time to withdraw your original principal deposit plus the accumulated interest, which is represented by the increased quantity of your aTokens.

This mechanism provides a seamless way for users to earn passive income, with their interest earnings visibly accumulating as an increase in their aToken balance.

### Deep Dive: The Smart Contract Behind Aave's aTokens

The magic of rebase tokens like Aave's aTokens is executed through smart contracts. To understand how your balance dynamically updates, we can look at the AToken.sol smart contract, publicly available on GitHub (e.g., at `github.com/aave-protocol/contracts/blob/master/contracts/tokenization/AToken.sol`).

A key function in ERC-20 token contracts is `balanceOf(address _user)`, which returns the token balance of a specified address. For standard tokens, this function typically retrieves a stored value. However, for rebase tokens like aTokens, the `balanceOf` function is more dynamic. It doesn't just fetch a static number; it calculates the user's current balance, including any accrued interest, at the moment the function is called.

Within Aave's `AToken.sol` contract, the `balanceOf` function incorporates logic to compute the user's principal balance plus the interest earned up to that point. It often involves internal functions like `calculateSimulatedBalanceInternal` (or similar, depending on the contract version and specific implementation details), which is crucial for dynamically calculating the balance including interest. This function effectively determines the "scaled balance" by factoring in the accumulated interest.

### Aave's aTokens in Action: A Numerical Illustration
Let's solidify the concept of Aave's aTokens with a simple numerical example:

* **Scenario**: You deposit 1,000 USDC into the Aave protocol.

* **Action**: In return, you receive 1,000 aUSDC (assuming a 1:1 initial minting ratio).

* **Interest Rate**: Let's assume the variable annual percentage rate (APR) for USDC lending averages out to 5% over one year.

* **Result After One Year:** Due to the rebase mechanism of aUSDC, your balance will have grown to reflect the earned interest. After one year at a 5% APR, your aUSDC balance would automatically increase to approximately 1,050 aUSDC.

When you decide to withdraw, you would redeem your 1,050 aUSDC and receive back 1,050 USDC (your original 1,000 USDC deposit plus 50 USDC in interest). The rebase token seamlessly handled the interest accrual by increasing your token quantity.

### The Significance of Rebase Tokens in DeFi and Beyond
Rebase tokens, with their elastic supply mechanism, play a crucial role in various corners of the Web3 ecosystem, particularly within Decentralized Finance (DeFi). Understanding how they function is vital for anyone interacting with:

* **Lending and Borrowing Protocols:** As seen with Aave's aTokens, they provide an intuitive way to represent and distribute interest earnings.

* **Algorithmic Stablecoins:** Some stablecoins use rebasing to help maintain their price peg to a target asset.

* **Yield Farming and Staking:** Certain protocols might use rebase mechanics to distribute rewards.

---

## Core Design of the Single-Chain Rebase Token
### Protocol Overview

The fundamental idea is to create a system where users can deposit an underlying asset (for example, ETH or a stablecoin like WETH) into a central smart contract, which we'll refer to as the `Vault`. In exchange for their deposit, users receive `rebase tokens`. These `rebase tokens` are special; they represent the user's proportional share of the total underlying assets held within the `Vault`, including any interest or rewards that accrue over time.

### Understanding Rebase Token Mechanics
The defining characteristic of a rebase token is how its supply adjusts, directly impacting a holder's balance.

* **Dynamic Balances:** The `balanceOf(address user)` function, a standard ERC20 view function, will be designed to return a dynamic value. This means that when a user queries their balance, it will appear to increase over time, reflecting their share of accrued interest or rewards. In our specific implementation, this increase will be calculated linearly with time.

* `balanceOf` `is a View Function (Gas Efficiency)`: It's crucial to understand that the `balanceOf` function shows the user's current theoretical balance, including dynamically calculated interest. However, calling `balanceOf` itself does not execute a state-changing transaction on the blockchain. It doesn't mint new tokens with every call, as that would incur gas costs for simply viewing a balance. This design is critical for gas efficiency.

* `State Update on Interaction`: The actual minting of the accrued interest (i.e., updating the user's on-chain token amount) will occur strategically before a user performs any state-changing action with their tokens. These actions include:

    * Depositing more underlying assets (minting more rebase tokens).

    * Withdrawing/redeeming their underlying assets (burning rebase tokens).

    * Transferring their rebase tokens to another address.

    * (In the future) Bridging their tokens to another chain.

The mechanism works as follows: When a user initiates one of these actions, the contract will first check the time elapsed since their last interaction. It then calculates the interest accrued to that user during this period, based on their specific interest rate (more on this below). These newly calculated interest tokens are then minted to the user's recorded balance on-chain. Only after this balance update does the contract proceed to execute the user's original requested action (e.g., transfer, burn) with their now up-to-date balance.

### The Interest Rate Model: Rewarding Early Adopters
Our interest rate mechanism is designed to incentivize early participation in the protocol.

* **Global Interest Rate**: The protocol will feature a `global interest rate`. This rate, potentially managed by an `owner` or a governance mechanism, determines the base rate at which interest accrues for the entire protocol at any given moment.

* **Decreasing Global Rate (Key Feature)**: A critical design choice is that this `global interest rate` can only decrease over time. It cannot be increased by the owner once set or lowered.

* **User-Specific Interest Rate Snapshot:** When a user makes their first deposit into the `Vault`, the `Rebase Token` contract takes a snapshot of the current `global interest rate`. This snapshot becomes the user's individual, fixed interest rate for that specific deposit.

* **Incentivizing Early Adopters:** This design directly rewards early users. Because the global interest rate can only decrease, users who deposit earlier effectively lock in a higher interest rate for their initial capital compared to users who deposit later, when the global rate might have been reduced.

* **Handling Subsequent Deposits:** If an existing user makes additional deposits at a later time, those new deposits would likely accrue interest based on the (potentially lower) g`lobal interest rate` prevailing at the time of the new deposit. The exact mechanics for handling multiple deposits from the same user and their associated rates will be detailed during contract implementation.

* **Conceptual Source of Yield:** While the underlying assets in the `Vault` could theoretically be deployed in various DeFi strategies (e.g., staking, lending, liquidity provision) to generate yield, for this initial version, the "interest" is primarily a function of the rebase mechanism itself, designed to increase token adoption by directly rewarding token holders with more tokens.

### Illustrating the Interest Rate Flow
Let's visualize how this interest rate mechanism plays out for different users at different times:

1. **Initial User Deposit (User 1):**

    * `User 1` deposits ETH into the `Vault Contract`.

    * The `Vault Contract` communicates with the `Rebase Token` contract.

    * Let's assume the `Rebase Token` contract currently has its globalInterestRate set to 0.05 (or 5%).

    * The `Rebase Token` contract records that `User 1's Interest Rate` is 0.05. This rate is now locked in for User 1's initial deposit.

    * The `Vault Contract` mints and sends the corresponding amount of rebase tokens to `User 1`.

2. **Owner Adjusts Global Rate:**

   * Sometime later, an `Owner` (or governance) interacts with the `Rebase Token` contract.

   * The `Owner` decides to decrease the `globalInterestRate`, for example, from 0.05 down to 0.04 (4%).

3. **New User Deposit (User 2):**
   * Now, `User 2` decides to deposit ETH into the Vault Contract.

   * The `Vault Contract` again communicates with the Rebase Token contract.

   * The `Rebase Token` contract's globalInterestRate is now 0.04.

   * The `Rebase Token` contract records that `User 2's Interest` Rate is 0.04. This is User 2's locked-in rate.

   * The `Vault Contract` mints and sends rebase tokens to User 2.

4. **Outcome and Further Rate Adjustments:**

   * As time progresses, `User 1` will continue to accrue interest based on their higher, locked-in rate of 0.05.

   * `User 2`, having deposited later, will accrue interest based on their lower, locked-in rate of 0.04. This clearly demonstrates the early adopter incentive.

   * If the `Owner` were to decrease the `globalInterestRate` again, say to 0.02, it would not affect the already locked-in rates for `User 1` (still 0.05) or `User 2` (still 0.04). Any new depositors after this change would receive the 0.02 rate.

   ---
   
>**_!IMPORTANT_**  
> We use low-level `.call{value: ...}("")`. Avoid using `.transfer()` or `.send()` as they have fixed gas stipends that can cause issues if the recipient is a contract with a fallback function that requires more gas.

* Using `bound(variable, min, max)` is more effective than `vm.assume` for setting input boundaries as it guides the fuzzer, as `vm.assume` can make many fuzz runs irrelevant(those values would be just skipped from test).