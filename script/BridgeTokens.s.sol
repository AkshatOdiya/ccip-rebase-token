// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

// A script designed to send tokens from a source chain to a destination chain using the CCIP router.

/*
Core Bridging logic:

1. Construct the CCIP Message: Create an EVM2AnyMessage struct containing all details for the cross-chain transfer.

2. Approve Token to Send: Grant the CCIP Router permission to spend the ERC20 tokens being bridged.

3. Calculate CCIP Fee: Query the CCIP Router to determine the fee required for the transaction.

4. Approve Fee Token: Grant the CCIP Router permission to spend the fee token (e.g., LINK).

5. Execute CCIP Send: Call the ccipSend function on the CCIP Router to initiate the transfer.
 */
contract BridgeTokenScript is Script {
    function run(
        address receiverAddress,
        uint64 destinationChainSelector,
        address tokenToSendAddress,
        uint256 amountToSend,
        address linkTokenAddress,
        address routerAddress
    ) public {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: tokenToSendAddress, amount: amountToSend});
        vm.startBroadcast();
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiverAddress),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkTokenAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });
        uint256 ccipFee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);

        // Approve the CCIP Router to spend the fee token (LINK)
        IERC20(linkTokenAddress).approve(routerAddress, ccipFee);

        // Approve the CCIP Router to spend the token being bridged
        IERC20(tokenToSendAddress).approve(routerAddress, amountToSend);

        // Call ccipSend on the router
        /*
        This function takes the destinationChainSelector and our fully prepared message. Although ccipSend is a payable function, 
        we are not sending any native currency (msg.value) with this call because we've specified linkTokenAddress as the feeToken in our message 
        and have approved the LINK tokens. If feeToken were address(0), we would need to send the ccipFee amount as msg.value.
         */
        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
