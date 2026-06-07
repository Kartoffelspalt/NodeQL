import 'dart:async';

class RuntimeBroadcastBus {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  Stream<String> get stream => _controller.stream;

  void emit(String topic) => _controller.add(topic);

  void dispose() => _controller.close();
}
