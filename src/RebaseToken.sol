// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author AkshatOdiya
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interest in rewards.
 * @notice The interest rate in the smart contract can only decrease.
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit.
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__NewInterestRateShouldBeLessThanThePreviousInterestRate(
        uint256 oldInterestRate, uint256 newInterestRate
    );

    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = 5e10;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_lastUpdatedTimeStamp;

    event InterestRateSet(uint256 indexed newInterestRate);

    //Initializes the token with standard parameters like name (e.g., "RebaseToken") and symbol (e.g., "RBT")
    constructor() ERC20("RebaseToken", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // As the interest rate can only decrease
        if (_newInterestRate > s_interestRate) {
            revert RebaseToken__NewInterestRateShouldBeLessThanThePreviousInterestRate(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    // to get the principle tokens minted to the user without any interest that has accrued since the last time user interacted with protocol
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /*
    The standard _mint and _burn functions (or their equivalents) will be augmented. 
    Before any transfer, minting, or burning operation that affects a user's balance, 
    a function like _mintAccruedInterest(address user) will be called. This function crystallizes 
    any pending accrued interest into the user's principal balance, 
    ensuring that all subsequent operations are based on their most up-to-date holdings.
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens, e.g., when they withdraw from a vault or for cross-chain transfers.
     * Handles burning the entire balance if _amount is type(uint256).max.
     * @param _from The user address from which to burn tokens.
     * @param _amount The amount of tokens to burn. Use type(uint256).max to burn all tokens.
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        /*
        A common convention in DeFi is to use type(uint256).max as an input _amount to signify an intent to interact 
        with the user's entire balance. This helps solve the "dust" problem: tiny, fractional amounts of tokens (often from 
        interest) that might accrue between the moment a user initiates a transaction (like a full withdrawal) and the 
        time it's actually executed on the blockchain due to network latency or block confirmation times.
         */
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    // calculate the balance for the user including the interest rate that has accumulated since the last update
    // i.e, (principle balance) + some interest that has accrued
    function balanceOf(address _user) public view override returns (uint256) {
        // get the current principle balance of the user(the number of tokens actually minted including the last interest minted)
        // multiply the principle balance by the interest rate
        // we need to use the super keywordas we are overriding the ERC20 contract funtion to tell our balancOf function to call the balanceOf of ERC20
        /*
        Divide by PRECISION_FACTOR beacuse balanceOf and _calculateUserAccumulatedInterestSinceLastUpdate will both give 18 decimal precision
        number so the total precision will become of 1e36, thats why divide it by PRECISION_FACTOR to get 18 decimal precision and get
        saved from possible integer overflow.
        */
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfers tokens from the caller to a recipient.
     * Accrued interest for both sender and recipient is minted before the transfer.
     * If the recipient is new, they inherit the sender's interest rate.
     * @param _recipient The address to transfer tokens to.
     * @param _amount The amount of tokens to transfer. Can be type(uint256).max to transfer full balance.
     * @return A boolean indicating whether the operation succeeded.
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        // this check is for, if msg.sender want to transfer all of their amount to recipient
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        // this check is for, if msg.sender want to transfer all of their amount to recipient
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice calculate the interest that has accumulated since the last update
     * @param _user The user to calculate the interest accumulated for
     * @return linearInterest The interest that has accumulated since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of the linear growth
        // the total amount with interest would be ((principle amount)+(principle amount * interest rate * time))
        // or it can be written like (principle amount*(1 + principle amount * interest rate * time))
        // or we can say that (principle amount * linear interest)
        // so OUR balanceOf will calculate (principle amount * linear interest)
        uint256 timeElapsed = block.timestamp - s_lastUpdatedTimeStamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    // Accrued interest is the interest that has been earned over time but not yet paid out or claimed.
    // CEI pattern
    /**
     * @notice Mint the accrued interest to the user since the last time they interacted with the protocol (e.g. burn, mint, transfer)
     * @param _user The user to mint the accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find their current balance of rebase tokens that have been minted to the user --> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // (2) calculate their current balance including any interest -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens to be minted to the user as interest ((2)-(1))
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // then we can call _mint to mint the interest
        s_lastUpdatedTimeStamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }

    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }
}
