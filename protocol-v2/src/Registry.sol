// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            Registry
//////////////////////////////////////////////////////////////*/

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Registry
contract Registry is Ownable {
    /// @notice Registry address for a given key hash updated
    event AddressSet(bytes32 indexed key, address addr);
    /// @notice Rate model address for a given key hash updated
    event RateModelSet(bytes32 indexed key, address addr);

    /// @notice Fetch module address for a given key hash
    mapping(bytes32 key => address addr) public addressFor;
    /// @notice Fetch rate model address for a given key hash
    mapping(bytes32 key => address rateModel) public rateModelFor;

    constructor() Ownable() { }

    /// @notice Update module address for a given key hash
    /// @param key Registry key hash
    /// @param addr Updated module address for the key hash
    function setAddress(bytes32 key, address addr) external onlyOwner {
        addressFor[key] = addr;
        emit AddressSet(key, addr);
    }

    /// @notice Update rate model address for a given key hash
    /// @param key Registry key hash
    /// @param rateModel Updated rate model address for the key hash
    function setRateModel(bytes32 key, address rateModel) external onlyOwner {
        rateModelFor[key] = rateModel;
        emit RateModelSet(key, rateModel);
    }
}
