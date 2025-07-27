// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

/*
This contract follows: https://docs.chain.link/ccip/tutorials/evm/cross-chain-tokens/register-from-eoa-burn-mint-foundry
Enable your tokens in CCIP (Burn & Mint): Register from an EOA using Foundry
 */

/*
i_token Variable: Remember that i_token is a state variable inherited from the TokenPool base contract. 
It stores the IERC20 address of the token this pool manages. You must cast it to your custom token interface 
(e.g., IRebaseToken(address(i_token))) to call specific functions like getUserInterestRate, burn, or your custom mint
 */

/*
CCIP Security Features: The _validateLockOrBurn and _validateReleaseOrMint functions from the base TokenPool contract are critical. 
They incorporate essential security checks, including RMN validation and adherence to configured rate limits, safeguarding the token transfer process.
 */
contract RebaseTokenPool is TokenPool {
    /*
    The `TokenPool` base constructor requires:

    `_token`: The address of the rebase token this pool will manage.

    `_allowlist`: An array of addresses permitted to send tokens through this pool.

    `_rnmProxy`: The address of the CCIP Risk Management Network (RMN) proxy.

    `_router`: The address of the CCIP router contract.
     */
    constructor(IERC20 token, address[] memory allowlist, address rmnProxy, address router)
        TokenPool(token, allowlist, rmnProxy, router)
    {}

    /// @notice burns the tokens on the source chain
    /*
    When tokens are sent from the source chain, this function is called. 
    It burns the specified amount of rebase tokens on the source chain and then constructs 
    and dispatches a CCIP message to the destination chain, instructing it to mint an equivalent amount.
     */
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        external
        virtual
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        // `_validateLockOrBurn(lockOrBurnIn)`: This is an internal function inherited from TokenPool. It performs crucial security and configuration checks (e.g., RMN validation, rate limits) before proceeding.
        _validateLockOrBurn(lockOrBurnIn);

        // Burn the tokens on the source chain. This returns their userAccumulatedInterest before the tokens were burned (in case all tokens were burned, we don't want to send 0 cross-chain)
        // The originalSender is the EOA or contract that initiated the CCIP transfer. The interest rate is fetched for this originalSender
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);

        //uint256 currentInterestRate = IRebaseToken(address(i_token)).getInterestRate();
        // the tokens are burned from the pool contract's balance (address(this)). This is because the CCIP router first transfers the user's tokens to this pool contract before lockOrBurn is executed.
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        // Prepare the output data for CCIP
        // encode a function call to pass the caller's info to the destination pool and update it
        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /// @notice Mints the tokens on the source chain
    /*
    On the destination chain, this function is triggered upon receiving a valid CCIP message from the source chain's pool. 
    It then mints the appropriate amount of rebase tokens to the recipient
     */
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        external
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn);
        address receiver = releaseOrMintIn.receiver;
        (uint256 userInterestRate) = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        // Mint rebasing tokens to the receiver on the destination chain
        // This will also mint any interest that has accrued since the last time the user's balance was updated.
        // Tokens are minted directly to the receiver specified in the CCIP message.
        IRebaseToken(address(i_token)).mint(receiver, releaseOrMintIn.amount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.amount});
    }
}
