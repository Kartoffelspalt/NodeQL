enum RuntimeEventType { tick, broadcast, cloneCreated }

class RuntimeEvent {
  const RuntimeEvent({required this.type, required this.payload});

  final RuntimeEventType type;
  final Object? payload;
}

class ScriptFrame {
  ScriptFrame({required this.scriptId, required this.entrypoint});

  final String scriptId;
  final Future<void> Function(RuntimeContext context) entrypoint;
}

class RuntimeContext {
  RuntimeContext({required this.emit, required this.createClone});

  final void Function(RuntimeEvent event) emit;
  final void Function(String spriteId) createClone;
}
