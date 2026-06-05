import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scratchql_creater/core/app/scratchql_app.dart';

void main() {
  testWidgets('renders localized workspace shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ScratchQlApp()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ScratchQL Creator'), findsOneWidget);
  });
}
