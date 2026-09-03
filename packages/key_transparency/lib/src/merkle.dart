import 'encoding.dart';
import 'sha256_digest.dart';

const String _leafDomain = 'key-transparency/rfc9162-leaf/v1';
const String _nodeDomain = 'key-transparency/rfc9162-node/v1';

/// RFC 9162-style Merkle hashing with explicit leaf/node domain separation.
///
/// RFC 9162 uses a single byte (`0x00` for leaves and `0x01` for nodes). This
/// package additionally binds both operations to this protocol before applying
/// the RFC byte, preventing cross-protocol reuse of a commitment digest.
abstract final class MerkleHash {
  static Sha256Digest emptyRoot() => sha256Of(const <int>[]);

  static Sha256Digest leaf(OpaqueKeyCommitment commitment) => sha256Of(<int>[
    ...domainBytes(_leafDomain),
    0x00,
    ...commitment.digest.bytes,
  ]);

  static Sha256Digest node(Sha256Digest left, Sha256Digest right) => sha256Of(
    <int>[...domainBytes(_nodeDomain), 0x01, ...left.bytes, ...right.bytes],
  );
}

/// An immutable append-only-log Merkle tree over opaque commitments.
final class MerkleTree {
  MerkleTree.fromCommitments(Iterable<OpaqueKeyCommitment> commitments)
    : _leafHashes = List<Sha256Digest>.unmodifiable(
        commitments.map(MerkleHash.leaf),
      );

  final List<Sha256Digest> _leafHashes;
  final Map<(int, int), Sha256Digest> _rangeCache =
      <(int, int), Sha256Digest>{};

  int get length => _leafHashes.length;

  Sha256Digest get root => _subtreeHash(0, length);

  MerkleInclusionProof inclusionProof(int leafIndex) {
    if (leafIndex < 0 || leafIndex >= length) {
      throw RangeError.index(leafIndex, _leafHashes, 'leafIndex');
    }
    final path = <Sha256Digest>[];
    _buildInclusionPath(leafIndex, 0, length, path);
    return MerkleInclusionProof(
      leafIndex: leafIndex,
      treeSize: length,
      auditPath: path,
    );
  }

  MerkleConsistencyProof consistencyProof(int previousTreeSize) {
    if (previousTreeSize < 0 || previousTreeSize > length) {
      throw RangeError.range(previousTreeSize, 0, length, 'previousTreeSize');
    }
    final path = <Sha256Digest>[];
    if (previousTreeSize != 0 && previousTreeSize != length) {
      _buildConsistencyPath(previousTreeSize, 0, length, true, path);
    }
    return MerkleConsistencyProof(
      previousTreeSize: previousTreeSize,
      currentTreeSize: length,
      auditPath: path,
    );
  }

  void _buildInclusionPath(
    int leafIndex,
    int start,
    int end,
    List<Sha256Digest> path,
  ) {
    final width = end - start;
    if (width == 1) {
      return;
    }
    final split = start + _largestPowerOfTwoLessThan(width);
    if (leafIndex < split) {
      _buildInclusionPath(leafIndex, start, split, path);
      path.add(_subtreeHash(split, end));
    } else {
      _buildInclusionPath(leafIndex, split, end, path);
      path.add(_subtreeHash(start, split));
    }
  }

  void _buildConsistencyPath(
    int previousTreeSize,
    int start,
    int end,
    bool includeOldRoot,
    List<Sha256Digest> path,
  ) {
    final width = end - start;
    if (previousTreeSize == width) {
      if (!includeOldRoot) {
        path.add(_subtreeHash(start, end));
      }
      return;
    }
    final leftWidth = _largestPowerOfTwoLessThan(width);
    final split = start + leftWidth;
    if (previousTreeSize <= leftWidth) {
      _buildConsistencyPath(
        previousTreeSize,
        start,
        split,
        includeOldRoot,
        path,
      );
      path.add(_subtreeHash(split, end));
    } else {
      _buildConsistencyPath(
        previousTreeSize - leftWidth,
        split,
        end,
        false,
        path,
      );
      path.add(_subtreeHash(start, split));
    }
  }

  Sha256Digest _subtreeHash(int start, int end) {
    final cacheKey = (start, end);
    final cached = _rangeCache[cacheKey];
    if (cached != null) {
      return cached;
    }
    final width = end - start;
    late final Sha256Digest result;
    if (width == 0) {
      result = MerkleHash.emptyRoot();
    } else if (width == 1) {
      result = _leafHashes[start];
    } else {
      final split = start + _largestPowerOfTwoLessThan(width);
      result = MerkleHash.node(
        _subtreeHash(start, split),
        _subtreeHash(split, end),
      );
    }
    _rangeCache[cacheKey] = result;
    return result;
  }
}

/// A compact proof that a commitment is included at one exact log position.
final class MerkleInclusionProof {
  MerkleInclusionProof({
    required this.leafIndex,
    required this.treeSize,
    required Iterable<Sha256Digest> auditPath,
  }) : auditPath = List<Sha256Digest>.unmodifiable(auditPath) {
    validatePortableInteger(treeSize, 'treeSize');
    if (treeSize == 0) {
      throw ArgumentError.value(treeSize, 'treeSize', 'must be greater than 0');
    }
    if (leafIndex < 0 || leafIndex >= treeSize) {
      throw RangeError.range(leafIndex, 0, treeSize - 1, 'leafIndex');
    }
    if (this.auditPath.length > 64) {
      throw ArgumentError.value(
        '<redacted>',
        'auditPath',
        'must contain at most 64 hashes',
      );
    }
  }

  final int leafIndex;
  final int treeSize;
  final List<Sha256Digest> auditPath;

  bool verifies({
    required OpaqueKeyCommitment commitment,
    required Sha256Digest expectedRoot,
  }) {
    var nodeIndex = leafIndex;
    var lastNode = treeSize - 1;
    var calculated = MerkleHash.leaf(commitment);

    for (final sibling in auditPath) {
      if (lastNode == 0) {
        return false;
      }
      if (nodeIndex.isOdd || nodeIndex == lastNode) {
        calculated = MerkleHash.node(sibling, calculated);
        if (nodeIndex.isEven) {
          while (nodeIndex != 0 && nodeIndex.isEven) {
            nodeIndex ~/= 2;
            lastNode ~/= 2;
          }
        }
      } else {
        calculated = MerkleHash.node(calculated, sibling);
      }
      nodeIndex ~/= 2;
      lastNode ~/= 2;
    }
    return lastNode == 0 && calculated == expectedRoot;
  }

  @override
  String toString() =>
      'MerkleInclusionProof(leafIndex: $leafIndex, treeSize: $treeSize, '
      'auditPath: <${auditPath.length} redacted hashes>)';
}

/// A compact proof that the earlier tree is a prefix of the later tree.
final class MerkleConsistencyProof {
  MerkleConsistencyProof({
    required this.previousTreeSize,
    required this.currentTreeSize,
    required Iterable<Sha256Digest> auditPath,
  }) : auditPath = List<Sha256Digest>.unmodifiable(auditPath) {
    validatePortableInteger(previousTreeSize, 'previousTreeSize');
    validatePortableInteger(currentTreeSize, 'currentTreeSize');
    if (previousTreeSize > currentTreeSize) {
      throw ArgumentError('previousTreeSize must not exceed currentTreeSize');
    }
    if (this.auditPath.length > 64) {
      throw ArgumentError.value(
        '<redacted>',
        'auditPath',
        'must contain at most 64 hashes',
      );
    }
  }

  final int previousTreeSize;
  final int currentTreeSize;
  final List<Sha256Digest> auditPath;

  bool verifies({
    required Sha256Digest previousRoot,
    required Sha256Digest currentRoot,
  }) {
    if (previousTreeSize == 0) {
      return auditPath.isEmpty &&
          previousRoot == MerkleHash.emptyRoot() &&
          (currentTreeSize != 0 || currentRoot == MerkleHash.emptyRoot());
    }
    if (previousTreeSize == currentTreeSize) {
      return auditPath.isEmpty && previousRoot == currentRoot;
    }
    if (auditPath.isEmpty) {
      return false;
    }

    var previousNode = previousTreeSize - 1;
    var currentNode = currentTreeSize - 1;
    while (previousNode.isOdd) {
      previousNode ~/= 2;
      currentNode ~/= 2;
    }

    var proofIndex = 0;
    late Sha256Digest previousCalculated;
    late Sha256Digest currentCalculated;
    if (_isPowerOfTwo(previousTreeSize)) {
      previousCalculated = previousRoot;
      currentCalculated = previousRoot;
    } else {
      previousCalculated = auditPath.first;
      currentCalculated = auditPath.first;
      proofIndex = 1;
    }

    for (; proofIndex < auditPath.length; proofIndex++) {
      if (currentNode == 0) {
        return false;
      }
      final sibling = auditPath[proofIndex];
      if (previousNode.isOdd || previousNode == currentNode) {
        previousCalculated = MerkleHash.node(sibling, previousCalculated);
        currentCalculated = MerkleHash.node(sibling, currentCalculated);
        if (previousNode.isEven) {
          while (previousNode != 0 && previousNode.isEven) {
            previousNode ~/= 2;
            currentNode ~/= 2;
          }
        }
      } else {
        currentCalculated = MerkleHash.node(currentCalculated, sibling);
      }
      previousNode ~/= 2;
      currentNode ~/= 2;
    }

    return currentNode == 0 &&
        previousCalculated == previousRoot &&
        currentCalculated == currentRoot;
  }

  @override
  String toString() =>
      'MerkleConsistencyProof(previousTreeSize: $previousTreeSize, '
      'currentTreeSize: $currentTreeSize, '
      'auditPath: <${auditPath.length} redacted hashes>)';
}

int _largestPowerOfTwoLessThan(int value) {
  assert(value > 1);
  var result = 1;
  while (result * 2 < value) {
    result *= 2;
  }
  return result;
}

bool _isPowerOfTwo(int value) => value > 0 && (value & (value - 1)) == 0;
