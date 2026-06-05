import 'dart:async';

import 'package:scratchql_creater/engine/runtime/runtime_broadcast_bus.dart';
import 'package:scratchql_creater/engine/runtime/runtime_models.dart';

class RuntimeScheduler {
  RuntimeScheduler({
    Duration tickDuration = const Duration(milliseconds: 16),
    RuntimeBroadcastBus? broadcastBus,
  })  : _tickDuration = tickDuration,
        _broadcastBus = broadcastBus ?? RuntimeBroadcastBus();

  final Duration _tickDuration;
  final RuntimeBroadcastBus _broadcastBus;
  final List<ScriptFrame> _pendingScripts = <ScriptFrame>[];
  final List<String> _clones = <String>[];
  final StreamController<RuntimeEvent> _events =
      StreamController<RuntimeEvent>.broadcast();

  Timer? _timer;

  Stream<RuntimeEvent> get events => _events.stream;
  Stream<String> get broadcasts => _broadcastBus.stream;
  bool get isRunning => _timer != null;
  List<String> get clones => List<String>.unmodifiable(_clones);

  void enqueue(ScriptFrame frame) => _pendingScripts.add(frame);

  void start() {
    if (isRunning) return;
    _timer = Timer.periodic(_tickDuration, (_) {
      unawaited(_tick());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void emitBroadcast(String topic) {
    _broadcastBus.emit(topic);
    _events.add(RuntimeEvent(type: RuntimeEventType.broadcast, payload: topic));
  }

  void createClone(String spriteId) {
    _clones.add(spriteId);
    _events.add(
      RuntimeEvent(type: RuntimeEventType.cloneCreated, payload: spriteId),
    );
  }

  Future<void> runSingleTickForTest() => _tick();

  void dispose() {
    stop();
    _broadcastBus.dispose();
    _events.close();
  }

  Future<void> _tick() async {
    _events.add(const RuntimeEvent(type: RuntimeEventType.tick, payload: null));

    final queue = List<ScriptFrame>.from(_pendingScripts);
    _pendingScripts.clear();

    for (final frame in queue) {
      final context = RuntimeContext(
        emit: _events.add,
        createClone: createClone,
      );
      await frame.entrypoint(context);
    }
  }
}
