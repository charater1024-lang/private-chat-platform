import 'package:chat_core/chat_core.dart';

void main() {
  final domain = SecurityDomain(
    id: 'consumer.example.v1',
    mode: SecurityMode.trueE2ee,
    policyVersion: '1.0',
  );
  final thread = ChatThread(
    id: 'thread-example',
    productKind: ProductKind.consumer,
    securityDomain: domain,
  );

  print(thread);
}
