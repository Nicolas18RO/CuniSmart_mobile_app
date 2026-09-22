import 'package:connectivity_plus/connectivity_plus.dart';

import 'connectivity_gate.dart';

class ConnectivityPlusGate implements ConnectivityGate {
  ConnectivityPlusGate([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _hasNetwork(results);
  }

  @override
  Stream<bool> get onOnline =>
      _connectivity.onConnectivityChanged.map(_hasNetwork);

  bool _hasNetwork(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}
