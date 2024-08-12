// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test, console2 } from "forge-std/Test.sol";
import { IterableSet } from "src/lib/IterableSet.sol";

contract IterableSetTest is Test {
    IterableSet.AddressSet addressSet;
    IterableSet.Uint256Set uint256Set;

    using IterableSet for IterableSet.AddressSet;
    using IterableSet for IterableSet.Uint256Set;

    mapping(address => bool) includedAddr;
    mapping(uint256 => bool) includedUint;

    function testFuzzAddressSet(address[] memory els, bool unique) public {
        if (unique) els = _uniquifyAddr(els);

        for (uint256 i = 0; i < els.length; i++) {
            addressSet.insert(els[i]);
        }
        for (uint256 i = 0; i < els.length; i++) {
            assertTrue(addressSet.contains(els[i]));
        }
        if (unique) {
            assert(addressSet.length() == els.length);
            assert(keccak256(abi.encode(addressSet.getElements())) == keccak256(abi.encode(els)));

            for (uint256 i = 0; i < els.length; ++i) {
                assertEq(addressSet.getByIdx(i), els[i]);
            }
        }

        for (uint256 i = 0; i < els.length; i++) {
            addressSet.remove(els[i]);
        }
        for (uint256 i = 0; i < els.length; i++) {
            assertFalse(addressSet.contains(els[i]));
        }

        assert(addressSet.length() == 0);
    }

    function testFuzzUintSet(uint256[] memory els, bool unique) public {
        if (unique) els = _uniquifyUint(els);

        for (uint256 i = 0; i < els.length; i++) {
            uint256Set.insert(els[i]);
        }
        for (uint256 i = 0; i < els.length; i++) {
            assertTrue(uint256Set.contains(els[i]));
        }
        if (unique) {
            assert(uint256Set.length() == els.length);
            assert(keccak256(abi.encode(uint256Set.getElements())) == keccak256(abi.encode(els)));

            for (uint256 i = 0; i < els.length; ++i) {
                assertEq(uint256Set.getByIdx(i), els[i]);
            }
        }

        for (uint256 i = 0; i < els.length; i++) {
            uint256Set.remove(els[i]);
        }
        for (uint256 i = 0; i < els.length; i++) {
            assertFalse(uint256Set.contains(els[i]));
        }

        assert(uint256Set.length() == 0);
    }

    function _uniquifyAddr(address[] memory els) internal returns (address[] memory) {
        address[] memory unique_els = new address[](els.length);
        uint256 counter = 0;
        for (uint256 i = 0; i < els.length; i++) {
            if (includedAddr[els[i]]) continue;
            unique_els[counter] = els[i];
            includedAddr[els[i]] = true;
            counter++;
        }
        assembly {
            mstore(unique_els, counter)
        }
        return unique_els;
    }

    function _uniquifyUint(uint256[] memory els) internal returns (uint256[] memory) {
        uint256[] memory unique_els = new uint256[](els.length);
        uint256 counter = 0;
        for (uint256 i = 0; i < els.length; i++) {
            if (includedUint[els[i]]) continue;
            unique_els[counter] = els[i];
            includedUint[els[i]] = true;
            counter++;
        }
        assembly {
            mstore(unique_els, counter)
        }
        return unique_els;
    }
}
