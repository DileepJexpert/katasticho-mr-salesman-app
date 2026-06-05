import 'package:flutter_test/flutter_test.dart';
import 'package:katasticho_field/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows Katasticho Field login screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    app.main();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Katasticho Field'), findsOneWidget);
    expect(find.text('Open demo field workspace'), findsOneWidget);
  });
}
