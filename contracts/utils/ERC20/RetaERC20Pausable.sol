// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./RetaERC20.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/utils/Context.sol";
import "../../../lib/openzeppelin-contracts@4.3.2/contracts/security/Pausable.sol";

/**
 * @dev ERC20 token with pausable token transfers, minting and burning.
 *
 * Useful for scenarios such as preventing trades until the end of an evaluation
 * period, or having an emergency switch for freezing all token transfers in the
 * event of a large bug.
 */
abstract contract RetaERC20Pausable is ERC20, Pausable {
    /**
     * @dev See {ERC20-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - the contract must not be paused.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        require(!paused(), "RetaERC20Pausable: token transfer while paused");
    }
}
