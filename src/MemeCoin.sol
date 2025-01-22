// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {Owned} from "../lib/solmate/src/auth/Owned.sol";
import "./security/AntiBot.sol";
import "./security/AntiRugPull.sol";

contract MemeCoin is ERC20, Owned, AntiBot {
    AntiRugPull public antiRugPull;

    constructor(
        string memory name_,
        string memory symbol_,
        address initialOwner,
        address _antiRugPull
    ) ERC20(name_, symbol_, 18)  {
        antiRugPull = AntiRugPull(_antiRugPull);
    }

     function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Add this function to clear trading history
    function clearTradingHistory(address trader) external onlyOwner {
        UserTrading storage user = userTrading[trader];
        user.lastTradeTime = 0;
        user.dailyTxCount = 0;
        user.dayStartTime = 0;
        user.totalBought = 0;
        user.totalSold = 0;
    }


    function checkAndUpdateTrading(
        address account,
        uint256 amount,
        bool isBuy
    ) public pure override returns (uint256) {
        // Implement the logic for checking and updating trading
        // Return the penalty amount if any
        return 0;
    }

   function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
) internal virtual {
    // Only check sell restrictions when transferring to addresses that aren't the initial owner
    // and not when minting (from == address(0))
    if (from != address(0) && to != owner) {
        require(
            antiRugPull.checkAndUpdateSell(address(this), from, amount),
            "Sell restricted"
        );
    }

    // Check wallet size restrictions for receiving address
    if (to != address(0)) { // Not burning
        require(
            antiRugPull.checkAndUpdateBalance(
                address(this),
                to,
                amount,
                true
            ),
            "Balance would exceed max"
        );
    }
}

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _beforeTokenTransfer(msg.sender, to, amount);
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _beforeTokenTransfer(from, to, amount);
        return super.transferFrom(from, to, amount);
    }
}
