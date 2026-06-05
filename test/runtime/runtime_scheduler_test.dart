import 'package:flutter_test/flutter_test.dart';
import 'package:scratchql_creater/engine/runtime/runtime_models.dart';
import 'package:scratchql_creater/engine/runtime/runtime_scheduler.dart';

void main() {
  test('scheduler executes enqueued script and emits clone events', () async {
    final scheduler = RuntimeScheduler();
    var called = false;

    scheduler.enqueue(
      ScriptFrame(
        scriptId: 's1',
        entrypoint: (context) async {
          called = true;
          context.createClone('sprite-a');
        },
      ),
    );

    await scheduler.runSingleTickForTest();

    expect(called, isTrue);
    expect(scheduler.clones, contains('sprite-a'));
    scheduler.dispose();
  });

  test('broadcast creates runtime event', () async {
    final scheduler = RuntimeScheduler();
    RuntimeEvent? lastEvent;
    final sub = scheduler.events.listen((event) => lastEvent = event);

    scheduler.emitBroadcast('start');
    await Future<void>.delayed(const Duration(milliseconds: 1));

    expect(lastEvent?.type, RuntimeEventType.broadcast);
    expect(lastEvent?.payload, 'start');

    await sub.cancel();
    scheduler.dispose();
  });
}
