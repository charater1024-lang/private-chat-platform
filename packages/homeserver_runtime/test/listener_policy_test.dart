import 'dart:convert';
import 'dart:io';

import 'package:homeserver_runtime/homeserver_runtime.dart';
import 'package:test/test.dart';

void main() {
  final credential = PrivateReverseProxyCredential.base64Url(
    base64Url
        .encode(List<int>.generate(32, (index) => index))
        .replaceAll('=', ''),
  );

  test('defaults to loopback and rejects public or wildcard binds', () {
    final loopback = HomeserverListenerPolicy.loopback();
    expect(loopback.isLoopbackOnly, isTrue);
    expect(loopback.bindAddress, InternetAddress.loopbackIPv4);

    for (final address in <String>['0.0.0.0', '203.0.113.9', '::']) {
      expect(
        () => HomeserverListenerPolicy.privateReverseProxy(
          bindAddress: InternetAddress(address),
          trustedProxyAddresses: <InternetAddress>[InternetAddress('10.0.0.2')],
          allowedHosts: const <String>['chat.example.test'],
          proxyCredential: credential,
        ),
        throwsArgumentError,
      );
    }
  });

  test('private mode requires exact same-family proxies and exact hosts', () {
    final policy = HomeserverListenerPolicy.privateReverseProxy(
      bindAddress: InternetAddress('10.0.0.10'),
      trustedProxyAddresses: <InternetAddress>[InternetAddress('10.0.0.2')],
      allowedHosts: const <String>['chat.example.test'],
      proxyCredential: credential,
    );
    expect(policy.isLoopbackOnly, isFalse);
    expect(policy.acceptsDirectPeer(InternetAddress('10.0.0.2')), isTrue);
    expect(policy.acceptsDirectPeer(InternetAddress('10.0.0.3')), isFalse);
    expect(policy.acceptsHost('chat.example.test', 8080), isTrue);
    expect(policy.acceptsHost('evil.example.test', 8080), isFalse);

    expect(
      () => HomeserverListenerPolicy.privateReverseProxy(
        bindAddress: InternetAddress('10.0.0.10'),
        trustedProxyAddresses: <InternetAddress>[
          InternetAddress('2001:db8::1'),
        ],
        allowedHosts: const <String>['chat.example.test'],
        proxyCredential: credential,
      ),
      throwsArgumentError,
    );
    expect(
      () => HomeserverListenerPolicy.privateReverseProxy(
        bindAddress: InternetAddress('10.0.0.10'),
        trustedProxyAddresses: <InternetAddress>[InternetAddress('10.0.0.2')],
        allowedHosts: const <String>['*.example.test'],
        proxyCredential: credential,
      ),
      throwsArgumentError,
    );
  });

  test('proxy credential comparison rejects truncation and substitution', () {
    final encoded = base64Url
        .encode(List<int>.generate(32, (index) => index))
        .replaceAll('=', '');
    expect(
      credential.acceptsAuthorizationHeader('PrivateProxy $encoded'),
      isTrue,
    );
    expect(
      credential.acceptsAuthorizationHeader('PrivateProxy ${encoded}x'),
      isFalse,
    );
    expect(credential.acceptsAuthorizationHeader('Bearer $encoded'), isFalse);
  });
}
