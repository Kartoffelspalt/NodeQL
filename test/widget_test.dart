import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nodeql/core/app/nodeql_app.dart';

void main() {
  testWidgets('renders localized workspace shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: NodeQlApp()));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('NodeQL'), findsOneWidget);
  });
}
