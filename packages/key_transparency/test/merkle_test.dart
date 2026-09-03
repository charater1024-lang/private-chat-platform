import 'package:key_transparency/key_transparency.dart';
import 'package:test/test.dart';

import 'test_fixtures.dart';

void main() {
  test('matches independently calculated domain-separated SHA-256 vectors', () {
    final tree3 = MerkleTree.fromCommitments(
      List<OpaqueKeyCommitment>.generate(3, fixtureCommitment),
    );
    final tree4 = MerkleTree.fromCommitments(
      List<OpaqueKeyCommitment>.generate(4, fixtureCommitment),
    );

    expect(
      MerkleHash.leaf(fixtureCommitment(0)).toHex(),
      '628b396ad10640a3d74b5d071b82b2ef'
      '478212aa8c29ec253eeeee90d3597478',
    );
    expect(
      tree3.root.toHex(),
      'cc27c684b3c9abda59c91d05dc4d15ad'
      '9b69c338713423d527272025a0f79db4',
    );
    expect(
      tree4.root.toHex(),
      '1cf155fb1b4185fd4e0bc59fdc25a19e'
      '23d5df81a522f2beb0bf6145d1add8bd',
    );
    expect(
      tree3.inclusionProof(0).auditPath.map((hash) => hash.toHex()),
      <String>[
        '7f4104a7f856070d45db950595e91c43'
            '8c7db6671bbed9ab627f5e2b1aeb998b',
        '3726cdb553749d4ec631fbd33ca1d0d5'
            '865f33726194c8363cf684871865100a',
      ],
    );
    expect(
      tree3.consistencyProof(2).auditPath.map((hash) => hash.toHex()),
      <String>[
        '3726cdb553749d4ec631fbd33ca1d0d5'
            '865f33726194c8363cf684871865100a',
      ],
    );
  });

  group('Merkle inclusion', () {
    test('every index verifies for balanced and uneven sizes', () {
      for (var size = 1; size <= 64; size++) {
        final commitments = List<OpaqueKeyCommitment>.generate(
          size,
          fixtureCommitment,
        );
        final tree = MerkleTree.fromCommitments(commitments);

        for (var index = 0; index < size; index++) {
          final proof = tree.inclusionProof(index);
          expect(
            proof.verifies(
              commitment: commitments[index],
              expectedRoot: tree.root,
            ),
            isTrue,
            reason: 'size=$size index=$index',
          );
        }
      }
    });

    test('rejects altered leaves, roots, indexes, and proof paths', () {
      final commitments = List<OpaqueKeyCommitment>.generate(
        7,
        fixtureCommitment,
      );
      final tree = MerkleTree.fromCommitments(commitments);
      final proof = tree.inclusionProof(3);

      expect(
        proof.verifies(
          commitment: fixtureCommitment(99),
          expectedRoot: tree.root,
        ),
        isFalse,
      );
      expect(
        proof.verifies(
          commitment: commitments[3],
          expectedRoot: fixtureDigest(99),
        ),
        isFalse,
      );
      final wrongIndex = MerkleInclusionProof(
        leafIndex: 2,
        treeSize: proof.treeSize,
        auditPath: proof.auditPath,
      );
      expect(
        wrongIndex.verifies(
          commitment: commitments[3],
          expectedRoot: tree.root,
        ),
        isFalse,
      );
      final tampered = MerkleInclusionProof(
        leafIndex: proof.leafIndex,
        treeSize: proof.treeSize,
        auditPath: <Sha256Digest>[
          fixtureDigest(88),
          ...proof.auditPath.skip(1),
        ],
      );
      expect(
        tampered.verifies(commitment: commitments[3], expectedRoot: tree.root),
        isFalse,
      );
      final extra = MerkleInclusionProof(
        leafIndex: proof.leafIndex,
        treeSize: proof.treeSize,
        auditPath: <Sha256Digest>[...proof.auditPath, fixtureDigest(77)],
      );
      expect(
        extra.verifies(commitment: commitments[3], expectedRoot: tree.root),
        isFalse,
      );
    });

    test('validates indexes and keeps proof paths immutable', () {
      final tree = MerkleTree.fromCommitments(<OpaqueKeyCommitment>[
        fixtureCommitment(1),
      ]);
      final proof = tree.inclusionProof(0);

      expect(() => tree.inclusionProof(-1), throwsRangeError);
      expect(() => tree.inclusionProof(1), throwsRangeError);
      expect(
        () => proof.auditPath.add(fixtureDigest(1)),
        throwsUnsupportedError,
      );
      expect(
        () => MerkleInclusionProof(
          leafIndex: 0,
          treeSize: 0,
          auditPath: const <Sha256Digest>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => MerkleInclusionProof(
          leafIndex: 0,
          treeSize: 1,
          auditPath: List<Sha256Digest>.filled(65, fixtureDigest(1)),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Merkle consistency', () {
    test('every prefix verifies for balanced and uneven trees', () {
      for (var currentSize = 0; currentSize <= 64; currentSize++) {
        final commitments = List<OpaqueKeyCommitment>.generate(
          currentSize,
          fixtureCommitment,
        );
        final currentTree = MerkleTree.fromCommitments(commitments);
        for (
          var previousSize = 0;
          previousSize <= currentSize;
          previousSize++
        ) {
          final previousTree = MerkleTree.fromCommitments(
            commitments.take(previousSize),
          );
          final proof = currentTree.consistencyProof(previousSize);
          expect(
            proof.verifies(
              previousRoot: previousTree.root,
              currentRoot: currentTree.root,
            ),
            isTrue,
            reason: 'previous=$previousSize current=$currentSize',
          );
        }
      }
    });

    test('rejects changed roots and proof nodes', () {
      final commitments = List<OpaqueKeyCommitment>.generate(
        13,
        fixtureCommitment,
      );
      final current = MerkleTree.fromCommitments(commitments);
      final previous = MerkleTree.fromCommitments(commitments.take(7));
      final proof = current.consistencyProof(7);

      expect(
        proof.verifies(
          previousRoot: fixtureDigest(100),
          currentRoot: current.root,
        ),
        isFalse,
      );
      expect(
        proof.verifies(
          previousRoot: previous.root,
          currentRoot: fixtureDigest(101),
        ),
        isFalse,
      );
      final tampered = MerkleConsistencyProof(
        previousTreeSize: 7,
        currentTreeSize: 13,
        auditPath: <Sha256Digest>[
          fixtureDigest(102),
          ...proof.auditPath.skip(1),
        ],
      );
      expect(
        tampered.verifies(
          previousRoot: previous.root,
          currentRoot: current.root,
        ),
        isFalse,
      );
    });

    test('enforces empty/equal tree proof semantics', () {
      final empty = MerkleTree.fromCommitments(const <OpaqueKeyCommitment>[]);
      final nonEmpty = MerkleTree.fromCommitments(<OpaqueKeyCommitment>[
        fixtureCommitment(1),
      ]);

      expect(
        nonEmpty
            .consistencyProof(0)
            .verifies(
              previousRoot: fixtureDigest(2),
              currentRoot: nonEmpty.root,
            ),
        isFalse,
      );
      expect(
        MerkleConsistencyProof(
          previousTreeSize: 1,
          currentTreeSize: 1,
          auditPath: <Sha256Digest>[fixtureDigest(3)],
        ).verifies(previousRoot: nonEmpty.root, currentRoot: nonEmpty.root),
        isFalse,
      );
      expect(
        empty
            .consistencyProof(0)
            .verifies(previousRoot: empty.root, currentRoot: empty.root),
        isTrue,
      );
    });

    test('validates size ranges and proof bounds', () {
      final tree = MerkleTree.fromCommitments(<OpaqueKeyCommitment>[
        fixtureCommitment(1),
      ]);

      expect(() => tree.consistencyProof(-1), throwsRangeError);
      expect(() => tree.consistencyProof(2), throwsRangeError);
      expect(
        () => MerkleConsistencyProof(
          previousTreeSize: 2,
          currentTreeSize: 1,
          auditPath: const <Sha256Digest>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => MerkleConsistencyProof(
          previousTreeSize: 1,
          currentTreeSize: 2,
          auditPath: List<Sha256Digest>.filled(65, fixtureDigest(1)),
        ),
        throwsArgumentError,
      );
    });
  });

  test('tree and proof diagnostics redact hashes', () {
    final tree = MerkleTree.fromCommitments(<OpaqueKeyCommitment>[
      fixtureCommitment(1),
      fixtureCommitment(2),
    ]);
    final inclusion = tree.inclusionProof(0);
    final consistency = tree.consistencyProof(1);

    expect(inclusion.toString(), contains('redacted'));
    expect(consistency.toString(), contains('redacted'));
    expect(inclusion.toString(), isNot(contains(tree.root.toHex())));
  });
}
