// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:readyremake/main.dart';

void main() {
  testWidgets('Login screen renders', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const CivicConnectApp());

    // Verify that the login screen shows the expected text.
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Log in to your Civic Connect account to keep your neighborhood better.'), findsOneWidget);

    // Verify that the button to sign in exists.
    expect(find.text('Sign In'), findsOneWidget);
  });
}
