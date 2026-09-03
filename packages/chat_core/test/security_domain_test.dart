import 'package:chat_core/chat_core.dart';
import 'package:test/test.dart';

void main() {
  test('security modes are explicit and exhaustive', () {
    expect(SecurityMode.values, [SecurityMode.trueE2ee]);
  });

  group('SecurityDomain', () {
    test('normalizes identifiers and compares by value', () {
      final first = SecurityDomain(
        id: '  personal:user-1  ',
        mode: SecurityMode.trueE2ee,
        policyVersion: '  v1  ',
      );
      final second = SecurityDomain(
        id: 'personal:user-1',
        mode: SecurityMode.trueE2ee,
        policyVersion: 'v1',
      );

      expect(first.id, 'personal:user-1');
      expect(first.policyVersion, 'v1');
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    for (final invalidId in ['', '   ', '\n\t']) {
      test('rejects blank id ${invalidId.hashCode}', () {
        expect(
          () => SecurityDomain(
            id: invalidId,
            mode: SecurityMode.trueE2ee,
            policyVersion: 'v1',
          ),
          throwsArgumentError,
        );
      });
    }

    for (final invalidVersion in ['', '   ', '\n\t']) {
      test('rejects blank policyVersion ${invalidVersion.hashCode}', () {
        expect(
          () => SecurityDomain(
            id: 'domain-1',
            mode: SecurityMode.trueE2ee,
            policyVersion: invalidVersion,
          ),
          throwsArgumentError,
        );
      });
    }
  });
}
