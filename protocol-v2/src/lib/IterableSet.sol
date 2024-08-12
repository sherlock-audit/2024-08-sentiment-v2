// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*//////////////////////////////////////////////////////////////
                            IterableSet
//////////////////////////////////////////////////////////////*/

/// @title IterableSet
/// @notice Iterable set library for address and uint256 types
library IterableSet {
    /*//////////////////////////////////////////////////////////////
                             Address Set
    //////////////////////////////////////////////////////////////*/

    /// @title AddressSet
    /// @notice Storage struct for iterable address set
    struct AddressSet {
        address[] elements; // list of elements in the set
        // idxOf indexing scheme:
        // idxOf[element] = index of key in self.elements + 1 OR in other words
        // idxOf[element] = one-indexed location of a particular element in self.elements
        // idxOf[element] = 0 denotes that an element is not present in the set
        mapping(address elem => uint256 idx) idxOf;
    }

    /// @notice Check if the set contains a given element
    function contains(AddressSet storage self, address elem) internal view returns (bool) {
        return self.idxOf[elem] > 0; // idxOf[element] = 0 denotes that element is not in the set
    }

    /// @notice Fetch element from set by index
    /// @dev Zero-indexed query to the elements array. Set does not preserve order after removals
    function getByIdx(AddressSet storage self, uint256 idx) internal view returns (address) {
        return self.elements[idx];
    }

    /// @notice Fetch all elements in the set
    /// @dev Set does not preserve order after removals
    function getElements(AddressSet storage self) internal view returns (address[] memory) {
        return self.elements;
    }

    /// @notice Fetch the number of elements in the set
    function length(AddressSet storage self) internal view returns (uint256) {
        return self.elements.length;
    }

    // insertion: the element is pushed to the end of self.elements and idxOf is updated accordingly

    /// @notice Insert an element into the set
    /// @dev No-op if element already exists
    function insert(AddressSet storage self, address elem) internal {
        if (self.idxOf[elem] != 0) return; // no-op if element is already in the set
        self.elements.push(elem);
        self.idxOf[elem] = self.elements.length;
    }

    // removal: replace it with the current last element, update idxOf and call pop()
    // if the element to be removed is the last element, simply update idxOf and call pop()

    /// @notice Remove element from set
    /// @dev No-op if element is not in the set
    function remove(AddressSet storage self, address elem) internal {
        if (self.idxOf[elem] == 0) return; // no-op if element is not in the set

        uint256 toRemoveIdx = self.idxOf[elem] - 1; // idx of element to be removed
        uint256 len = self.elements.length;

        // if element to be removed is not at the end, replace it with the last element
        if (toRemoveIdx != len - 1) {
            address lastElem = self.elements[len - 1];
            self.elements[toRemoveIdx] = lastElem;
            self.idxOf[lastElem] = toRemoveIdx + 1; // idxOf mapping is 1-indexed
        }

        self.idxOf[elem] = 0; // idxOf[elem] = 0 denotes that it is no longer in the set
        self.elements.pop(); // pop self.elements array effectively deleting elem
    }

    /*//////////////////////////////////////////////////////////////
                             Uint256 Set
    //////////////////////////////////////////////////////////////*/

    /// @title Uint256Set
    /// @notice Storage struct for iterable uint256 set
    struct Uint256Set {
        uint256[] elements; // list of elements in the set
        // idxOf indexing scheme:
        // idxOf[element] = index of key in self.elements + 1 OR in other words
        // idxOf[element] = one-indexed location of a particular element in self.elements
        // idxOf[element] = 0, if element is not present in the set
        mapping(uint256 elem => uint256 idx) idxOf;
    }

    /// @notice Check if the set contains a give element
    function contains(Uint256Set storage self, uint256 elem) internal view returns (bool) {
        return self.idxOf[elem] > 0; // idxOf[element] = 0 denotes that element is not in the set
    }

    /// @notice Fetch element from set by index
    /// @dev Zero-indexed query to the elements array. Set does not preserve order after removals
    function getByIdx(Uint256Set storage self, uint256 idx) internal view returns (uint256) {
        return self.elements[idx];
    }

    /// @notice Fetch all elements in the set
    /// @dev Set does not preserve order after removals
    function getElements(Uint256Set storage self) internal view returns (uint256[] memory) {
        return self.elements;
    }

    /// @notice Fetch the number of elements in the set
    function length(Uint256Set storage self) internal view returns (uint256) {
        return self.elements.length;
    }

    // insertion: the element is pushed to the end of self.elements and idxOf is updated accordingly

    /// @notice Insert an element into the set
    /// @dev No-op if element already exists
    function insert(Uint256Set storage self, uint256 elem) internal {
        if (self.idxOf[elem] != 0) return; // no-op if element is already in the set
        self.elements.push(elem);
        self.idxOf[elem] = self.elements.length;
    }

    // removal: replace it with the current last element, update idxOf and call pop()
    // if the element to be removed is the last element, simply update idxOf and call pop()

    /// @notice Remove element from set
    /// @dev No-op if element does not exist
    function remove(Uint256Set storage self, uint256 elem) internal {
        if (self.idxOf[elem] == 0) return; // no-op if element is not in the set

        uint256 toRemoveIdx = self.idxOf[elem] - 1; // idx of element to be removed
        uint256 len = self.elements.length;

        // if element to be removed is not at the end, replace it with the last element
        if (toRemoveIdx != len - 1) {
            uint256 lastElem = self.elements[len - 1];
            self.elements[toRemoveIdx] = lastElem;
            self.idxOf[lastElem] = toRemoveIdx + 1; // idxOf mapping is 1-indexed
        }

        self.idxOf[elem] = 0; // idxOf[elem] = 0 denotes that it is no longer in the set
        self.elements.pop(); // pop self.elements array effectively deleting elem
    }
}
