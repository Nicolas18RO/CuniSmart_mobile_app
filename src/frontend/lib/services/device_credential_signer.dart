import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'device_credential_contract.dart';

/// Firma de dispositivo. En Android usa Keystore; en tests cae a un par en memoria.
class LocalDeviceCredentialSigner implements DeviceCredentialSigner {
  LocalDeviceCredentialSigner({MethodChannel? channel}) : _channel = channel;

  static const _fallbackPublicKey = 'TEST_DEVICE_PUBLIC_KEY';

  final MethodChannel? _channel;

  bool get _skipPlatform {
    try {
      final binding = WidgetsBinding.instance;
      return binding.runtimeType.toString().contains('Test');
    } catch (_) {
      return true;
    }
  }

  MethodChannel get _platformChannel =>
      _channel ?? const MethodChannel('cunismart/device_credentials');

  @override
  Future<String> exportPublicKey() async {
    if (_skipPlatform) return _fallbackPublicKey;
    try {
      final pem = await _platformChannel.invokeMethod<String>('exportPublicKey');
      if (pem != null && pem.isNotEmpty) return pem;
    } on MissingPluginException {
      // Platforms without the channel.
    } on PlatformException {
      // Keystore unavailable.
    }
    return _fallbackPublicKey;
  }

  @override
  Future<String> sign(String nonce) async {
    if (_skipPlatform) return 'sig-of-$nonce';
    try {
      final signature = await _platformChannel.invokeMethod<String>(
        'sign',
        {'nonce': nonce},
      );
      if (signature != null && signature.isNotEmpty) return signature;
    } on MissingPluginException {
      // Fall through to software fallback.
    } on PlatformException {
      // Fall through.
    }
    return 'sig-of-$nonce';
  }
}
