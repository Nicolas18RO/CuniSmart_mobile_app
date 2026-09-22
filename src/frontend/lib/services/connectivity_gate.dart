import 'dart:async';

/// Whether the device currently has a network path. Tests inject [FakeConnectivity].
abstract class ConnectivityGate {
  Future<bool> isOnline();

  Stream<bool> get onOnline;
}

class FakeConnectivity implements ConnectivityGate {
  FakeConnectivity({required this.online});

  bool online;
  final _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> get onOnline => _controller.stream;

  void setOnline(bool value) {
    online = value;
    _controller.add(value);
  }

  Future<void> close() => _controller.close();
}
