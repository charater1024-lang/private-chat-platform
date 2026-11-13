// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.38;

/// @notice Privacy-minimal checkpoint anchor for an independently verified
/// key-transparency log.
/// @dev Calldata is exactly one 32-byte aggregate checkpoint digest. The
/// contract has no owner, stores no account identifier, key, signature,
/// message, file or user metadata, and accepts no value.
contract KeyTransparencyAnchor {
    error InvalidAnchorCalldata();
    error ZeroAnchorDigest();

    // Private on purpose: a generated public getter would accept ABI selector
    // calldata in addition to the one permitted 32-byte anchoring payload.
    mapping(bytes32 digest => uint256 blockNumber) private _firstAnchoredAtBlock;

    // Anonymous avoids a Keccak event-signature topic. The single topic is the
    // digest itself, which makes strict receipt verification unambiguous.
    event CheckpointAnchored(bytes32 indexed digest) anonymous;

    fallback(bytes calldata input) external returns (bytes memory) {
        if (input.length != 32) revert InvalidAnchorCalldata();
        bytes32 digest;
        assembly ("memory-safe") {
            digest := calldataload(input.offset)
        }
        if (digest == bytes32(0)) revert ZeroAnchorDigest();

        // Idempotent anchoring prevents a public-mempool observer from
        // front-running the same digest merely to make the wallet transaction
        // revert. Every successful call emits a receipt-verifiable event.
        if (_firstAnchoredAtBlock[digest] == 0) {
            _firstAnchoredAtBlock[digest] = block.number;
        }
        emit CheckpointAnchored(digest);
        return new bytes(0);
    }
}
