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

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // we need to pass the token address to the constructor
    // create a deposit function that mints token to the user equal to the amount of ETH user deposits
    // create a redeem function that burns tokens from the user and sends the user ETH
    // create a way to add rewards to the vault
    error Vault__TransferFailed();

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed _user, uint256 indexed _amount);
    event Redeem(address indexed _user, uint256 indexed _amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /**
     * @notice allows users to deposit ETH into the vault and mint rebase token in return
     */
    receive() external payable {}

    function deposit() external payable {
        // we need to use the amount of eth the user has sent to mint tokens to the user
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice  Allows a user to burn their RebaseTokens and receive a corresponding amount of ETH.
     * @param _amount the amount of eth to redeem correspondingly burning the rebase token
     * @dev Follows Checks-Effects-Interactions pattern. Uses low-level .call for ETH transfer.
     */
    function redeem(uint256 _amount) external {
        // 1. burn the tokens from user
        i_rebaseToken.burn(msg.sender, _amount);
        // 2. we need to send the user ETH
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__TransferFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}
