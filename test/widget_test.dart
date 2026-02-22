import 'package:audit_app/core/app.dart';
import 'package:audit_app/features/auth/splash_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AuditApp renders SplashPage', (WidgetTester tester) async {
    await tester.pumpWidget(const AuditApp());

    expect(find.byType(SplashPage), findsOneWidget);
  });
}
