// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LaunchPool} from "./LaunchPool.sol";

/**
 * @title LaunchPad
 * @dev Contract for creating and managing LaunchPools.
 */
contract LaunchPad {
    address[] launchPools;

    /**
     * @dev The start time of the sale cannot be in the past.
     */
    error StartTimeInPast();

    /**
     * @dev The sale duration must be between 5 to 7 days.
     */
    error SaleDurationOutOfBounds();

    /**
     * @dev The total supply should not be less than 100.
     */
    error InsufficientTotalSupply();

    /**
     * @dev The creator supply should be at least 10% of the total supply.
     */
    error InsufficientCreatorSupply();

    /**
     * @dev The supply allocated to each whitelisted address should not exceed 20% of the total supply.
     */
    error WhitelistSupplyExceedsLimit();

    /**
     * @dev The combined supply of creator and whitelisted addresses should not exceed 50% of the total supply.
     */
    error AllocatedSupplyExceedsLimit();

    /**
     * @dev Creates a new LaunchPool contract.
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param maxSupply The maximum supply of the token.
     * @param creatorSupply The supply allocated to the creator.
     * @param saleStartTime The start time of the token sale.
     * @param saleDuration The duration of the token sale.
     * @param merkleRootForWhitelists The merkle root for the whitelists addresses.
     * @param ratios The ratios used in the sale.
     */
    function createLaunchPool(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint256 creatorSupply,
        uint256 saleStartTime,
        uint256 saleDuration,
        bytes32 merkleRootForWhitelists,
        uint256[5] memory ratios
    ) external {
        if (saleStartTime <= block.timestamp) {
            revert StartTimeInPast();
        }
        if (saleDuration < (86400 * 5) || saleDuration > (86400 * 7)) {
            revert SaleDurationOutOfBounds();
        }
        if (maxSupply < 100e18) {
            revert InsufficientTotalSupply();
        }
        if (creatorSupply < ((10 * maxSupply) / 100)) {
            revert InsufficientCreatorSupply();
        }

        uint256 allocatedSupply = creatorSupply;

        if (allocatedSupply > ((50 * maxSupply) / 100)) {
            revert AllocatedSupplyExceedsLimit();
        }

        LaunchPool pool = new LaunchPool(
            name,
            symbol,
            maxSupply,
            creatorSupply,
            allocatedSupply,
            saleStartTime,
            saleDuration,
            msg.sender,
            merkleRootForWhitelists,
            ratios
        );
        launchPools.push(address(pool));
    }

    /**
     * @dev Returns the address of a LaunchPool at a given index.
     * @param index The index of the LaunchPool in the array.
     * @return The address of the LaunchPool.
     */
    function getLaunchPoolAddress(uint256 index) public view returns (address) {
        return launchPools[index];
    }
}
